/**
 * PasskeyRegisterHook — Phoenix LiveView hook for passkey registration.
 *
 * Reads `registration_token` and `username` from the element's data attributes,
 * then drives the full WebAuthn registration ceremony:
 *
 *   1. POST /api/v1/auth/invites/complete  → passkey_register_token
 *   2. POST /api/v1/auth/passkeys/register/challenge → WebAuthn options
 *   3. navigator.credentials.create(options)
 *   4. POST /api/v1/auth/passkeys/register  → success
 *   5. pushEvent("register-success") → LiveView redirects to login
 *
 * On any failure pushEvent("register-error", { code, message }) so the LiveView
 * can surface a user-visible error.
 *
 * Retry logic
 * -----------
 * Steps 1 and 2 are expensive and consume server-side resources. When the user
 * cancels the biometric prompt (NotAllowedError) and taps the button again, we
 * skip as many already-completed steps as possible:
 *
 *   Priority 1 — hasFreshHandle:
 *     this._challengeHandle, this._challengeExpiresAt, and this._cachedPublicKey
 *     are set after Step 2. If the handle has not expired, skip Steps 1 and 2
 *     and jump directly to Step 3 using the cached values.
 *
 *   Priority 2 — this._passkeyRegisterToken:
 *     Set after Step 1. If present (but no fresh challenge), skip Step 1 only
 *     and re-run Step 2 to get a fresh challenge.
 *
 *   Priority 3 — no cache:
 *     Full flow from Step 1.
 *
 * State is cleared on fatal errors (NotSupportedError) and on success.
 * State is preserved on recoverable errors (NotAllowedError, AbortError, network).
 */

import { bufferToBase64url, base64urlToBuffer, getCsrfToken, friendlyWebAuthnError } from "./webauthn_helpers.js";

// ── Debug configuration ────────────────────────────────────────────────────────

const DEBUG = document.documentElement.dataset.debug === "true";

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

const PasskeyRegisterHook = {
  mounted() {
    DEBUG && console.log("[PasskeyRegister] Hook mounted", { el: this.el.id });

    this._csrfToken = getCsrfToken();
    this._hydrateRetryStateFromDataset();
    this._clickHandler = () => this.startRegistration();
    this.el.addEventListener("click", this._clickHandler);
  },

  updated() {
    this._hydrateRetryStateFromDataset();
  },

  destroyed() {
    this.el.removeEventListener("click", this._clickHandler);
    this._clearRetryState();
  },

  /**
   * Clears all cached retry state. Call on fatal errors and on success.
   */
  _clearRetryState() {
    this._passkeyRegisterToken = null;
    this._challengeHandle = null;
    this._challengeExpiresAt = null;
    this._cachedPublicKey = null;
  },

  _hydrateRetryStateFromDataset() {
    const passkeyRegisterToken = this.el.dataset.passkeyRegisterToken;

    if (passkeyRegisterToken) {
      this._passkeyRegisterToken = passkeyRegisterToken;
    }
  },

  async startRegistration() {
    const registrationToken = this.el.dataset.registrationToken;
    const username = this.el.dataset.username;

    if (
      typeof navigator === "undefined" ||
      typeof navigator.credentials === "undefined" ||
      typeof navigator.credentials.create !== "function"
    ) {
      this._clearRetryState();
      this.pushEvent("register-error", {
        code: "unsupported",
        message: friendlyWebAuthnError({ name: "NotSupportedError" }),
      });
      return;
    }

    if (!registrationToken) {
      DEBUG && console.error("[PasskeyRegister] Missing registration_token on element");
      this.pushEvent("register-error", {
        code: "missing_registration_token",
        message: this._friendlyServerError("missing_registration_token"),
      });
      return;
    }

    if (!username) {
      DEBUG && console.error("[PasskeyRegister] Missing username on element");
      this.pushEvent("register-error", {
        code: "network",
        message: friendlyWebAuthnError(null),
      });
      return;
    }

    // -------------------------------------------------------------------------
    // Determine which steps to skip based on cached retry state.
    //
    // Priority order (most skips first):
    //   1. Fresh challenge_handle + cached decoded options → skip Steps 1 and 2
    //   2. Cached passkeyRegisterToken → skip Step 1 only
    //   3. No cache → full flow
    // -------------------------------------------------------------------------
    const now = new Date();
    const handleExpiry = this._challengeExpiresAt ? new Date(this._challengeExpiresAt) : null;
    const hasFreshHandle =
      this._challengeHandle &&
      this._cachedPublicKey &&
      handleExpiry &&
      handleExpiry > now;

    try {
      let challengeHandle;
      let publicKeyOptions;

      if (hasFreshHandle) {
        // -----------------------------------------------------------------------
        // Fast path: reuse cached challenge_handle and decoded public key options.
        // Skips Steps 1 and 2 entirely — the invite token is not re-consumed.
        // -----------------------------------------------------------------------
        DEBUG && console.log("[PasskeyRegister] Reusing cached challenge_handle, skipping Steps 1+2");
        challengeHandle = this._challengeHandle;
        publicKeyOptions = this._cachedPublicKey;
      } else {
        // -----------------------------------------------------------------------
        // Step 1: Complete invite registration — exchange registration_token +
        //         username for a passkey_register_token.
        //         Skipped if we already have a cached token from a prior attempt.
        // -----------------------------------------------------------------------
        let passkeyRegisterToken;

        if (this._passkeyRegisterToken) {
          DEBUG && console.log("[PasskeyRegister] Reusing cached passkey_register_token, skipping Step 1");
          passkeyRegisterToken = this._passkeyRegisterToken;
        } else {
          const completeRes = await fetch("/api/v1/auth/invites/complete", {
            method: "POST",
            credentials: "include",
            headers: {
              "Content-Type": "application/json",
              "x-csrf-token": this._csrfToken,
            },
            body: JSON.stringify({
              registration_token: registrationToken,
              username: username,
            }),
          });

          if (!completeRes.ok) {
            const body = await completeRes.json().catch(() => ({}));
            const code = body?.error?.code || "invite_completion_failed";
            DEBUG && console.error("[PasskeyRegister] complete_invite failed", code);
            this.pushEvent("register-error", {
              code: code,
              message: this._friendlyServerError(code),
            });
            return;
          }

          const completeData = await completeRes.json();
          passkeyRegisterToken = completeData.passkey_register_token;

          if (!passkeyRegisterToken) {
            DEBUG && console.error("[PasskeyRegister] No passkey_register_token in response");
            this.pushEvent("register-error", {
              code: "passkey_registration_failed",
              message: this._friendlyServerError("passkey_registration_failed"),
            });
            return;
          }

          // Cache the token so subsequent retries skip Step 1.
          this._passkeyRegisterToken = passkeyRegisterToken;
          this.pushEvent("step1-complete", { passkey_register_token: passkeyRegisterToken });
        }

        // -----------------------------------------------------------------------
        // Step 2: Fetch WebAuthn registration challenge.
        // -----------------------------------------------------------------------
        const challengeRes = await fetch(
          "/api/v1/auth/passkeys/register/challenge",
          {
            method: "POST",
            credentials: "include",
            headers: {
              "Content-Type": "application/json",
              "x-csrf-token": this._csrfToken,
            },
            body: JSON.stringify({ register_token: passkeyRegisterToken }),
          },
        );

        if (!challengeRes.ok) {
          const body = await challengeRes.json().catch(() => ({}));
          const code = body?.error?.code || "challenge_failed";
          DEBUG && console.error("[PasskeyRegister] challenge request failed", code);
          this.pushEvent("register-error", {
            code: code,
            message: this._friendlyServerError(code),
          });
          return;
        }

        const challengeData = await challengeRes.json();
        challengeHandle = challengeData.challenge_handle;
        publicKeyOptions = this.decodeCreationOptions(challengeData.public_key_options);

        // Cache challenge_handle, decoded options, and expiry so the next retry
        // can skip Steps 1 and 2 entirely.
        this._challengeHandle = challengeHandle;
        this._challengeExpiresAt = challengeData.expires_at || null;
        this._cachedPublicKey = publicKeyOptions;
        DEBUG && console.log("[PasskeyRegister] Cached challenge_handle for retry", {
          expiresAt: this._challengeExpiresAt,
        });
      }

      // -----------------------------------------------------------------------
      // Step 3: Call navigator.credentials.create with decoded options.
      // -----------------------------------------------------------------------
      let credential;
      try {
        credential = await navigator.credentials.create({
          publicKey: publicKeyOptions,
        });
      } catch (err) {
        DEBUG && console.error("[PasskeyRegister] navigator.credentials.create failed", err);
        const name = err?.name || "";

        if (name === "NotSupportedError") {
          this._clearRetryState();
        }

        const errorCodeMap = {
          NotAllowedError: "cancelled",
          AbortError: "aborted",
          NotSupportedError: "unsupported",
          InvalidStateError: "already_registered",
        };
        const code = errorCodeMap[name] ?? "network";
        this.pushEvent("register-error", { code: code, message: friendlyWebAuthnError(err) });
        return;
      }

      // -----------------------------------------------------------------------
      // Step 4: POST credential to the registration endpoint.
      // -----------------------------------------------------------------------
      const registerRes = await fetch("/api/v1/auth/passkeys/register", {
        method: "POST",
        credentials: "include",
        headers: {
          "Content-Type": "application/json",
          "x-csrf-token": this._csrfToken,
        },
        body: JSON.stringify({ ...this.encodeCredential(credential), challenge_handle: challengeHandle }),
      });

      if (!registerRes.ok) {
        const body = await registerRes.json().catch(() => ({}));
        const code = body?.error?.code || "passkey_registration_failed";
        DEBUG && console.error("[PasskeyRegister] passkey register failed", code);
        this.pushEvent("register-error", {
          code: code,
          message: this._friendlyServerError(code),
        });
        return;
      }

      // -----------------------------------------------------------------------
      // Step 5: Success — tell the LiveView to redirect and clear retry state.
      // -----------------------------------------------------------------------
      DEBUG && console.log("[PasskeyRegister] Registration complete");
      this._clearRetryState();
      this.pushEvent("register-success", {});
    } catch (err) {
      DEBUG && console.error("[PasskeyRegister] Unexpected error during registration", err);
      this.pushEvent("register-error", {
        code: "network",
        message: friendlyWebAuthnError(err),
      });
    }
  },

  /**
   * Maps server-returned error codes to user-friendly messages.
   * @param {string} code
   * @returns {string}
   */
  _friendlyServerError(code) {
    const map = {
      expired: "This invite has expired. Ask for a new one.",
      used: "This invite has already been used.",
      invalid: "This invite link is not valid.",
      rate_limited: "Too many attempts. Please wait a moment.",
      invalid_challenge: "The setup session expired. Please reload the page.",
      passkey_registration_failed: "Passkey setup failed. Please try again.",
      missing_registration_token: "Session expired. Please start the invite flow again.",
      invite_completion_failed: "Registration failed. Please try again.",
      challenge_failed: "Could not start passkey creation. Please try again.",
      username_taken: "That name is already taken. Go back and choose a different one.",
    };
    return map[code] || "Something went wrong. Please try again.";
  },

  /**
   * Converts server-sent challenge options into the shape expected by
   * navigator.credentials.create. Binary fields are base64url-encoded on
   * the server and must be decoded to ArrayBuffer here.
   *
   * @param {object} opts  Raw JSON from the challenge endpoint
   * @returns {PublicKeyCredentialCreationOptions}
   */
  decodeCreationOptions(opts) {
    return {
      ...opts,
      challenge: base64urlToBuffer(opts.challenge),
      user: {
        ...opts.user,
        id: base64urlToBuffer(opts.user.id),
      },
      excludeCredentials: (opts.excludeCredentials || []).map((cred) => ({
        ...cred,
        id: base64urlToBuffer(cred.id),
      })),
    };
  },

  /**
   * Encodes the PublicKeyCredential returned by navigator.credentials.create
   * into a plain-JSON-serialisable object for transport to the server.
   *
   * @param {PublicKeyCredential} credential
   * @returns {object}
   */
  encodeCredential(credential) {
    const response = credential.response;

    // Send flat fields matching the server's register_passkey/1 expectations.
    // The login hook (assertion) uses the same flat convention.
    return {
      credential_id: bufferToBase64url(credential.rawId),
      client_data_json: bufferToBase64url(response.clientDataJSON),
      attestation_object: bufferToBase64url(response.attestationObject),
    };
  },

};

export default PasskeyRegisterHook;
