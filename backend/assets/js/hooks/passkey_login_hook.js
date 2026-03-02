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
    console.log("[PasskeyLogin] Hook mounted", { el: this.el.id });

    this.el.addEventListener("click", () => this._startFlow());
  },

  destroyed() {
    // Nothing to clean up — the click listener is on `this.el` which is gone.
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
          "Your browser does not support passkeys. Please use a modern browser over HTTPS.",
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
        throw new Error(`Could not start sign-in (${code}).`);
      }

      const challengeData = await challengeResponse.json();

      // The server wraps options under the "public_key_options" key.
      const publicKeyOptions = challengeData.public_key_options;
      const challengeHandle = challengeData.challenge_handle;

      if (!publicKeyOptions || !challengeHandle) {
        throw new Error(
          "Invalid challenge response from server: missing public_key_options or challenge_handle.",
        );
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
        if (err.name === "NotAllowedError") {
          throw new Error("Sign-in was cancelled or timed out. Please try again.");
        }
        throw new Error(`Passkey error: ${err.message}`);
      }

      if (!credential) {
        throw new Error("No credential returned by the browser.");
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

      // Step 5: verify the assertion on the server
      const assertResponse = await this._postAssert(assertionPayload);
      if (!assertResponse.ok) {
        const body = await assertResponse.json().catch(() => ({}));
        const code = body?.error?.code ?? "assert_failed";

        if (code === "invalid_credentials" || code === "invalid_challenge") {
          throw new Error("Passkey verification failed. Please try again.");
        }
        if (code === "rate_limited") {
          throw new Error("Too many attempts. Please wait and try again.");
        }
        throw new Error(`Sign-in failed (${code}).`);
      }

      const sessionData = await assertResponse.json();
      const token = sessionData.access_token;

      if (!token) {
        throw new Error("Server did not return an access token.");
      }

      // Step 6: notify the LiveView — it will navigate to HomeLive
      this.pushEvent("passkey-result", { token });
    } catch (err) {
      console.error("[PasskeyLogin] Error during flow:", err);
      this.pushEvent("passkey-error", {
        message: err.message || "An unexpected error occurred. Please try again.",
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
