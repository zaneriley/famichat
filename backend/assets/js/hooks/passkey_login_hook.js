/**
 * PasskeyLoginHook — Phoenix LiveView hook for WebAuthn assertion (login).
 *
 * Flow:
 * 1. On button click, push "passkey-loading" to LiveView
 * 2. POST /api/v1/auth/passkeys/assert/challenge (with CSRF token)
 * 3. Decode challenge options, call navigator.credentials.get(options)
 * 4. POST /api/v1/auth/passkeys/assert with the credential
 * 5. On success: pushEvent("passkey-result", { token: data.access_token })
 * 6. On error:  pushEvent("passkey-error",  { message: "..." })
 */

// ── Debug configuration ────────────────────────────────────────────────────────

const DEBUG = document.documentElement.dataset.debug === "true";

// ── Base64url helpers ──────────────────────────────────────────────────────────

/**
 * Convert an ArrayBuffer (or Uint8Array) to a base64url string without padding.
 */
function bufferToBase64url(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

/**
 * Convert a base64url string (with or without padding) to an ArrayBuffer.
 */
function base64urlToBuffer(base64url) {
  // Normalise: base64url → base64 with padding
  const padded =
    base64url.replace(/-/g, "+").replace(/_/g, "/") +
    "===".slice((base64url.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// ── CSRF helper ────────────────────────────────────────────────────────────────

function getCsrfToken() {
  return (
    document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ||
    ""
  );
}

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

  _friendlyError(err) {
    if (!err) return "Something went wrong. Please try again.";
    const name = err.name || "";
    const msg = err.message || "";
    if (name === "NotAllowedError" || msg.includes("not allowed") || msg.includes("timed out")) {
      return "Sign-in was cancelled or timed out. Tap the button and follow your device's prompt.";
    }
    if (name === "SecurityError") {
      return "Sign-in requires a secure connection (HTTPS). Please check your URL.";
    }
    if (name === "NotSupportedError") {
      return "Your browser doesn't support passkeys. Try Safari, Chrome, or Edge on a modern device.";
    }
    if (name === "AbortError") {
      return "Sign-in was interrupted. Please try again.";
    }
    if (name === "InvalidStateError") {
      return "No passkey found for this device. Ask for an invite to set one up.";
    }
    return "Sign-in failed. Please try again.";
  },

  _friendlyServerError(code) {
    const map = {
      invalid_credentials: "We couldn't verify your passkey. Please try again.",
      invalid_challenge: "The sign-in session expired. Tap the button to start again.",
      rate_limited: "Too many attempts. Please wait a moment and try again.",
      challenge_failed: "Couldn't start sign-in. Please try again.",
    };
    return map[code] || "Sign-in failed. Please try again.";
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
        message:
          "Your browser doesn't support passkeys. Try Safari, Chrome, or Edge on a modern device.",
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
        this.pushEvent("passkey-error", {
          message: this._friendlyServerError(code),
        });
        return;
      }

      const challengeData = await challengeResponse.json();

      // The server wraps options under the "public_key_options" key.
      const publicKeyOptions = challengeData.public_key_options;
      const challengeHandle = challengeData.challenge_handle;

      if (!publicKeyOptions || !challengeHandle) {
        this.pushEvent("passkey-error", {
          message: this._friendlyServerError("challenge_failed"),
        });
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
        credential = await navigator.credentials.get(getOptions);
      } catch (err) {
        this.pushEvent("passkey-error", {
          message: this._friendlyError(err),
        });
        return;
      }

      if (!credential) {
        this.pushEvent("passkey-error", {
          message: "Sign-in failed. Please try again.",
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
        this.pushEvent("passkey-error", {
          message: this._friendlyServerError(code),
        });
        return;
      }

      const sessionData = await assertResponse.json();
      const token = sessionData.access_token;

      if (!token) {
        this.pushEvent("passkey-error", {
          message: "Sign-in failed. Please try again.",
        });
        return;
      }

      // Step 6: notify the LiveView — it will navigate to HomeLive
      this.pushEvent("passkey-result", { token });
    } catch (err) {
      DEBUG && console.error("[PasskeyLogin] Error during flow:", err);
      this.pushEvent("passkey-error", {
        message: this._friendlyError(err),
      });
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
