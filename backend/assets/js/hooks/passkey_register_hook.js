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
 * On any failure pushEvent("register-error", { message }) so the LiveView can
 * surface a user-visible error.
 */

// ---------------------------------------------------------------------------
// Base64url helpers — same algorithm as the assert hook would use
// ---------------------------------------------------------------------------

/**
 * Encodes an ArrayBuffer to a base64url string (no padding).
 * @param {ArrayBuffer} buffer
 * @returns {string}
 */
function bufferToBase64url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

/**
 * Decodes a base64url string (with or without padding) to a Uint8Array.
 * @param {string} b64url
 * @returns {Uint8Array}
 */
function base64urlToBuffer(b64url) {
  // Restore standard base64 padding
  const padded = b64url.replace(/-/g, "+").replace(/_/g, "/");
  const padding = (4 - (padded.length % 4)) % 4;
  const b64 = padded + "=".repeat(padding);
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// ── CSRF helper ─────────────────────────────────────────────────────────────

function getCsrfToken() {
  return (
    document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ||
    ""
  );
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

const PasskeyRegisterHook = {
  mounted() {
    console.log("[PasskeyRegister] Hook mounted", { el: this.el.id });

    this.el.addEventListener("click", () => this.startRegistration());
  },

  async startRegistration() {
    const registrationToken = this.el.dataset.registrationToken;
    const username = this.el.dataset.username;

    if (!registrationToken) {
      console.error("[PasskeyRegister] Missing registration_token on element");
      this.pushEvent("register-error", {
        message: this._friendlyServerError("missing_registration_token"),
      });
      return;
    }

    if (!username) {
      console.error("[PasskeyRegister] Missing username on element");
      this.pushEvent("register-error", {
        message: this._friendlyError(null),
      });
      return;
    }

    try {
      // -----------------------------------------------------------------------
      // Step 1: Complete invite registration — exchange registration_token +
      //         username for a passkey_register_token.
      // -----------------------------------------------------------------------
      const completeRes = await fetch("/api/v1/auth/invites/complete", {
        method: "POST",
        credentials: "include",
        headers: {
          "Content-Type": "application/json",
          "x-csrf-token": getCsrfToken(),
        },
        body: JSON.stringify({
          registration_token: registrationToken,
          username: username,
        }),
      });

      if (!completeRes.ok) {
        const body = await completeRes.json().catch(() => ({}));
        const code = body?.error?.code || "invite_completion_failed";
        console.error("[PasskeyRegister] complete_invite failed", code);
        this.pushEvent("register-error", {
          message: this._friendlyServerError(code),
        });
        return;
      }

      const completeData = await completeRes.json();
      const passkeyRegisterToken = completeData.passkey_register_token;

      if (!passkeyRegisterToken) {
        console.error("[PasskeyRegister] No passkey_register_token in response");
        this.pushEvent("register-error", {
          message: this._friendlyServerError("passkey_registration_failed"),
        });
        return;
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
            "x-csrf-token": getCsrfToken(),
          },
          body: JSON.stringify({ register_token: passkeyRegisterToken }),
        },
      );

      if (!challengeRes.ok) {
        const body = await challengeRes.json().catch(() => ({}));
        const code = body?.error?.code || "challenge_failed";
        console.error("[PasskeyRegister] challenge request failed", code);
        this.pushEvent("register-error", {
          message: this._friendlyServerError(code),
        });
        return;
      }

      const challengeData = await challengeRes.json();

      // -----------------------------------------------------------------------
      // Step 3: Call navigator.credentials.create with decoded options.
      // -----------------------------------------------------------------------
      const publicKeyOptions = this.decodeCreationOptions(challengeData);

      let credential;
      try {
        credential = await navigator.credentials.create({
          publicKey: publicKeyOptions,
        });
      } catch (err) {
        console.error("[PasskeyRegister] navigator.credentials.create failed", err);
        this.pushEvent("register-error", { message: this._friendlyError(err) });
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
          "x-csrf-token": getCsrfToken(),
        },
        body: JSON.stringify(this.encodeCredential(credential)),
      });

      if (!registerRes.ok) {
        const body = await registerRes.json().catch(() => ({}));
        const code = body?.error?.code || "passkey_registration_failed";
        console.error("[PasskeyRegister] passkey register failed", code);
        this.pushEvent("register-error", {
          message: this._friendlyServerError(code),
        });
        return;
      }

      // -----------------------------------------------------------------------
      // Step 5: Success — tell the LiveView to redirect.
      // -----------------------------------------------------------------------
      console.log("[PasskeyRegister] Registration complete");
      this.pushEvent("register-success", {});
    } catch (err) {
      console.error("[PasskeyRegister] Unexpected error during registration", err);
      this.pushEvent("register-error", {
        message: this._friendlyError(err),
      });
    }
  },

  /**
   * Maps browser WebAuthn errors to user-friendly messages.
   * @param {Error|null|undefined} err
   * @returns {string}
   */
  _friendlyError(err) {
    if (!err) return "Something went wrong. Please try again.";
    const name = err.name || "";
    if (name === "NotAllowedError") return "Passkey setup was cancelled or timed out. Tap the button to try again.";
    if (name === "NotSupportedError") return "Your browser doesn't support passkeys. Try Safari, Chrome, or Edge.";
    if (name === "AbortError") return "Passkey setup was interrupted. Please try again.";
    if (name === "InvalidStateError") return "A passkey is already set up on this device.";
    return "Passkey setup failed. Please try again.";
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

    return {
      id: credential.id,
      raw_id: bufferToBase64url(credential.rawId),
      type: credential.type,
      response: {
        client_data_json: bufferToBase64url(response.clientDataJSON),
        attestation_object: bufferToBase64url(response.attestationObject),
      },
    };
  },

};

export default PasskeyRegisterHook;
