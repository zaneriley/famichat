/**
 * Shared WebAuthn helpers used by both passkey hook files.
 *
 * Exported individually so each hook only imports what it needs.
 */

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
 * @param {Error|null|undefined} err
 * @returns {string}
 */
export function friendlyWebAuthnError(err) {
  if (!err) return "Something went wrong. Please try again.";
  const name = err.name || "";
  if (name === "NotAllowedError") return "Passkey setup was cancelled or timed out. Tap the button to try again.";
  if (name === "NotSupportedError") return "Your browser doesn't support passkeys. Try Safari, Chrome, or Edge.";
  if (name === "AbortError") return "Passkey setup was interrupted. Please try again.";
  if (name === "InvalidStateError") return "A passkey is already set up on this device.";
  return "Passkey setup failed. Please try again.";
}
