/**
 * PasskeyLoginHook — Phoenix LiveView hook for WebAuthn assertion (login).
 *
 * Flow:
 * 1. On button click, push "passkey-loading" to LiveView
 * 2. POST /api/v1/auth/passkeys/assert/challenge (with CSRF token)
 * 3. Decode challenge options, call navigator.credentials.get(options)
 * 4. POST /api/v1/auth/passkeys/assert with the credential
 * 5. On success: pushEvent("passkey-result", { token: data.access_token })
 * 6. On error:  pushEvent("passkey-error",  { code: "ErrorName", message: "..." })
 */

import { bufferToBase64url, base64urlToBuffer, getCsrfToken, withWebAuthnTimeout } from "./webauthn_helpers.js";

// ── Debug configuration ────────────────────────────────────────────────────────

const DEBUG = document.documentElement.dataset.debug === "true";

// ── Hook ───────────────────────────────────────────────────────────────────────

const PasskeyLoginHook = {
  mounted() {
    DEBUG && console.log("[PasskeyLogin] Hook mounted", { el: this.el.id });

    this.el.addEventListener("click", () => this._startFlow());
  },

  destroyed() {
    // Nothing to clean up — the click listener is on `this.el` which is gone.
  },

  // ── Error helpers ──────────────────────────────────────────────────────────

  /**
   * Returns a structured { code, message } for a WebAuthn browser error.
   * The code is the raw DOMException name (e.g. "NotAllowedError") so the
   * Elixir side can normalize it. The message is a fallback for logging.
   */
  _errorPayload(err) {
    const code = err?.name || "UnknownError";
    return { code, message: err?.message || "unknown" };
  },

  /**
   * Returns a structured { code, message } for a server-side error.
   */
  _serverErrorPayload(code) {
    return { code: code || "server_error", message: code || "server_error" };
  },

  // ── Main flow ──────────────────────────────────────────────────────────────

  async _startFlow() {
    // Guard: WebAuthn requires a secure context (HTTPS or localhost)
    if (
      typeof navigator === "undefined" ||
      typeof navigator.credentials === "undefined" ||
      typeof navigator.credentials.get !== "function"
    ) {
      this.pushEvent("passkey-error", {
        code: "NotSupportedError",
        message: "WebAuthn API not available",
      });
      return;
    }

    this.pushEvent("passkey-loading", {});

    try {
      // Step 1: obtain an assertion challenge from the server
      const challengeResponse = await this._fetchAssertionChallenge();
      if (!challengeResponse.ok) {
        const body = await challengeResponse.json().catch(() => ({}));
        const code = body?.error?.code ?? "challenge_failed";
        this.pushEvent("passkey-error", this._serverErrorPayload(code));
        return;
      }

      const challengeData = await challengeResponse.json();

      // The server wraps options under the "public_key_options" key.
      const publicKeyOptions = challengeData.public_key_options;
      const challengeHandle = challengeData.challenge_handle;

      if (!publicKeyOptions || !challengeHandle) {
        this.pushEvent("passkey-error", this._serverErrorPayload("challenge_failed"));
        return;
      }

      // Step 2: decode binary fields for the WebAuthn API
      const getOptions = {
        publicKey: {
          ...publicKeyOptions,
          // challenge must be an ArrayBuffer
          challenge: base64urlToBuffer(publicKeyOptions.challenge),
          // allowCredentials[].id must be ArrayBuffer
          allowCredentials: (publicKeyOptions.allowCredentials ?? []).map(
            (cred) => ({
              ...cred,
              id: base64urlToBuffer(cred.id),
            }),
          ),
        },
      };

      // Step 3: ask the browser / authenticator for a credential assertion
      let credential;
      try {
        credential = await withWebAuthnTimeout(navigator.credentials.get(getOptions));
      } catch (err) {
        this.pushEvent("passkey-error", this._errorPayload(err));
        return;
      }

      if (!credential) {
        this.pushEvent("passkey-error", {
          code: "UnknownError",
          message: "navigator.credentials.get returned null",
        });
        return;
      }

      // Step 4: encode binary fields back to base64url for JSON transport
      const assertionPayload = {
        credential_id: bufferToBase64url(credential.rawId),
        challenge_handle: challengeHandle,
        authenticator_data: bufferToBase64url(
          credential.response.authenticatorData,
        ),
        client_data_json: bufferToBase64url(credential.response.clientDataJSON),
        signature: bufferToBase64url(credential.response.signature),
      };

      // Include userHandle for discoverable credential flow — the authenticator
      // returns the user.id set during registration so the server can identify
      // who is logging in without a prior username lookup.
      if (credential.response.userHandle) {
        assertionPayload.user_handle = bufferToBase64url(
          credential.response.userHandle,
        );
      }

      // Step 5: verify the assertion on the server
      const assertResponse = await this._postAssert(assertionPayload);
      if (!assertResponse.ok) {
        const body = await assertResponse.json().catch(() => ({}));
        const code = body?.error?.code ?? "assert_failed";
        this.pushEvent("passkey-error", this._serverErrorPayload(code));
        return;
      }

      const sessionData = await assertResponse.json();
      const token = sessionData.access_token;

      if (!token) {
        this.pushEvent("passkey-error", this._serverErrorPayload("assert_failed"));
        return;
      }

      // Step 6: notify the LiveView — it will navigate to HomeLive
      this.pushEvent("passkey-result", { token });
    } catch (err) {
      DEBUG && console.error("[PasskeyLogin] Error during flow:", err);
      this.pushEvent("passkey-error", this._errorPayload(err));
    }
  },

  // ── API calls ──────────────────────────────────────────────────────────────

  _fetchAssertionChallenge() {
    return fetch("/api/v1/auth/passkeys/assert/challenge", {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        "x-csrf-token": getCsrfToken(),
      },
      // The server accepts an optional identifier; omit for device-resident keys.
      body: JSON.stringify({}),
    });
  },

  _postAssert(payload) {
    return fetch("/api/v1/auth/passkeys/assert", {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        "x-csrf-token": getCsrfToken(),
      },
      body: JSON.stringify(payload),
    });
  },
};

export default PasskeyLoginHook;
