/**
 * Shared WebAuthn helpers used by passkey hook files.
 *
 * Exported individually so each hook only imports what it needs.
 */

// ── Timeout helper ────────────────────────────────────────────────────────────

/**
 * Default safety-net timeout for WebAuthn credential operations (ms).
 *
 * The server-provided `publicKey.timeout` is the primary mechanism — browsers
 * respect it and reject with NotAllowedError when it fires. This outer timeout
 * is a backstop for buggy browsers or authenticators that silently hang.
 *
 * 2 minutes is generous: the WebAuthn spec allows authenticators up to 60s, and
 * most OS prompts auto-dismiss well before that. We double it to avoid
 * false-positives on slow hardware keys.
 */
const WEBAUTHN_TIMEOUT_MS = 120_000;

/**
 * Races a WebAuthn promise against a timeout. If the timeout fires first, the
 * returned promise rejects with a DOMException("NotAllowedError") so callers
 * see the same error shape as a user-cancelled prompt.
 *
 * @param {Promise} promise  The navigator.credentials.get/create call
 * @param {number}  [ms]     Timeout in milliseconds (default: WEBAUTHN_TIMEOUT_MS)
 * @returns {Promise}
 */
export function withWebAuthnTimeout(promise, ms = WEBAUTHN_TIMEOUT_MS) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new DOMException("The operation timed out.", "NotAllowedError"));
    }, ms);
  });

  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Encodes an ArrayBuffer to a base64url string (no padding).
 * Uses spread instead of char-by-char concat to avoid O(n²) allocation.
 * Chunks the input to avoid stack overflow for very large buffers (>65535 bytes).
 *
 * @param {ArrayBuffer} buffer
 * @returns {string}
 */
export function bufferToBase64url(buffer) {
  const bytes = new Uint8Array(buffer);
  // chunk to avoid stack overflow for very large buffers (>65535 bytes)
  const CHUNK = 0x8000;
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

/**
 * Decodes a base64url string (with or without padding) to a Uint8Array.
 *
 * @param {string} b64url
 * @returns {Uint8Array}
 */
export function base64urlToBuffer(b64url) {
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

/**
 * Returns the CSRF token from the meta tag.
 *
 * @returns {string}
 */
export function getCsrfToken() {
  return (
    document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
  );
}

/**
 * Maps a WebAuthn browser error to a user-friendly message.
 *
 * These messages follow brand voice: soft openers ("Something went wrong..."),
 * casual actions ("Try again" not "Please retry"), describe what happens
 * rather than naming the technology.
 *
 * @param {Error|null|undefined} err
 * @returns {string}
 */
export function friendlyWebAuthnError(err) {
  if (!err) return "Something went wrong. Try again.";
  const name = err.name || "";
  if (name === "NotAllowedError") return "Passkey setup was cancelled or timed out. Tap the button to try again.";
  if (name === "NotSupportedError") return "Your browser doesn't support passkeys. Try Safari, Chrome, or Edge.";
  if (name === "AbortError") return "Passkey setup was interrupted. Try again.";
  if (name === "InvalidStateError") return "A passkey is already set up on this device.";
  if (name === "SecurityError") return "Something went wrong connecting securely. Try a different browser or check your URL.";
  return "Something went wrong with passkey setup. Try again.";
}
