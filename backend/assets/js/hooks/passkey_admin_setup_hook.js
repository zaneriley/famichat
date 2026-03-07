/**
 * PasskeyAdminSetupHook — Phoenix LiveView hook for admin passkey registration.
 *
 * Like PasskeyRegisterHook but SKIPS step 1 (complete_invite). The passkey
 * register token is provided directly via the element's data-passkey-register-token
 * attribute, set by the LiveView after bootstrap_admin succeeds.
 *
 *   1. Read data-passkey-register-token from the element
 *   2. POST /api/v1/auth/passkeys/register/challenge → WebAuthn options
 *   3. navigator.credentials.create(options)
 *   4. POST /api/v1/auth/passkeys/register → success
 *   5. pushEvent("register-success") → LiveView advances to next step
 *
 * On any failure: pushEvent("register-error", { code, message })
 *
 * Retry logic
 * -----------
 * When the user cancels the biometric prompt (NotAllowedError) and taps the
 * button again, we skip Step 2 if a fresh challenge_handle is cached:
 *
 *   hasFreshHandle: this._challengeHandle, this._challengeExpiresAt, and
 *     this._cachedPublicKey are all set after Step 2. If the handle has not
 *     expired, jump directly to Step 3 using the cached values.
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

const PasskeyAdminSetupHook = {
  mounted() {
    DEBUG && console.log("[PasskeyAdminSetup] Hook mounted", { el: this.el.id });

    this._csrfToken = getCsrfToken();
    this._clickHandler = () => this.startRegistration();
    this.el.addEventListener("click", this._clickHandler);
  },

  destroyed() {
    this.el.removeEventListener("click", this._clickHandler);
    this._clearRetryState();
  },

  /**
   * Clears all cached retry state. Call on fatal errors and on success.
   */
  _clearRetryState() {
    this._challengeHandle = null;
    this._challengeExpiresAt = null;
    this._cachedPublicKey = null;
  },

  async startRegistration() {
    const passkeyRegisterToken = this.el.dataset.passkeyRegisterToken;

    if (!passkeyRegisterToken) {
      DEBUG && console.error("[PasskeyAdminSetup] Missing data-passkey-register-token on element");
      this.pushEvent("register-error", {
        code: "missing_registration_token",
        message: this._friendlyServerError("missing_registration_token"),
      });
      return;
    }

    // -------------------------------------------------------------------------
    // Determine whether to skip Step 2 based on cached retry state.
    //
    // If a fresh challenge_handle is cached (from a previous attempt in this
    // hook's lifetime), skip the challenge fetch entirely and jump to Step 3.
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
        // Skips Step 2 — no additional server round-trip needed.
        // -----------------------------------------------------------------------
        DEBUG && console.log("[PasskeyAdminSetup] Reusing cached challenge_handle, skipping Step 2");
        challengeHandle = this._challengeHandle;
        publicKeyOptions = this._cachedPublicKey;
      } else {
        // -----------------------------------------------------------------------
        // Step 2: Fetch WebAuthn registration challenge using the passkey register
        //         token directly (no invite completion step needed for admin setup).
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
          DEBUG && console.error("[PasskeyAdminSetup] challenge request failed", code);
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
        // can skip Step 2 entirely.
        this._challengeHandle = challengeHandle;
        this._challengeExpiresAt = challengeData.expires_at || null;
        this._cachedPublicKey = publicKeyOptions;
        DEBUG && console.log("[PasskeyAdminSetup] Cached challenge_handle for retry", {
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
        DEBUG && console.error("[PasskeyAdminSetup] navigator.credentials.create failed", err);
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
        DEBUG && console.error("[PasskeyAdminSetup] passkey register failed", code);
        this.pushEvent("register-error", {
          code: code,
          message: this._friendlyServerError(code),
        });
        return;
      }

      // -----------------------------------------------------------------------
      // Step 5: Success — tell the LiveView to advance to issue_invite step
      //         and clear retry state.
      // -----------------------------------------------------------------------
      DEBUG && console.log("[PasskeyAdminSetup] Registration complete");
      this._clearRetryState();
      this.pushEvent("register-success", {});
    } catch (err) {
      DEBUG && console.error("[PasskeyAdminSetup] Unexpected error during registration", err);
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
      expired: "This setup session has expired. Please reload the page and start again.",
      used: "This setup token has already been used. Please reload the page.",
      invalid: "This setup token is not valid. Please reload the page.",
      invalid_token: "Session expired. Please reload the page and start again.",
      rate_limited: "Too many attempts. Please wait a moment.",
      invalid_challenge: "The setup session expired. Please reload the page.",
      passkey_registration_failed: "Passkey setup failed. Please try again.",
      missing_registration_token: "Session expired. Please reload the page and start again.",
      challenge_failed: "Could not start passkey creation. Please try again.",
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

export default PasskeyAdminSetupHook;
