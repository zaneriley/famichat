# Security Defaults

How Famichat handles production security without requiring operator configuration.

## Philosophy

Security defaults should be correct out of the box. An operator who sets `URL_HOST`, `URL_SCHEME`, and `SECRET_KEY_BASE` — the minimum to run — gets a production-hardened instance. No security checklist, no "don't forget to also set X."

Dev and production diverge at compile time, not at runtime. The operator doesn't toggle security on; it's structurally absent in dev and structurally present in production. This means there's nothing to forget.

## Session cookie

The `Secure` flag is set unconditionally — both dev and production.

This works because the [W3C Secure Contexts spec](https://w3c.github.io/webappsec-secure-contexts/) treats `localhost` as a "potentially trustworthy origin." Browsers accept `Secure`-flagged cookies over plain HTTP on localhost. The flag only blocks transmission over non-localhost HTTP, which is the exact scenario it's designed to prevent.

**What the operator controls:** Nothing. This is always on.

## Content Security Policy (CSP)

CSP restricts which origins the browser trusts for scripts, styles, connections, and other resources. Famichat builds the CSP dynamically from the endpoint's `url` config (scheme, host, port).

### Dev vs production

| Directive area | Dev | Production |
|---|---|---|
| Allowed hosts | Configured host + `localhost` + `0.0.0.0` + any `CSP_ADDITIONAL_HOSTS` | Configured host + any `CSP_ADDITIONAL_HOSTS` |
| WebSocket (`connect-src`) | Specific WSS URL + bare `ws:` and `wss:` protocols (allows LiveReload, HMR) | Specific WSS URL only |
| Scripts (`script-src`) | `'unsafe-inline'` + `'unsafe-eval'` (required by dev tooling) | No inline scripts, no eval |

These gates are compile-time (`@env == :dev`). They don't exist in the production binary — not disabled, absent.

**What the operator controls:**
- `CSP_ADDITIONAL_HOSTS` (optional) — comma-separated list of extra allowed origins, for CDNs or asset hosts. Most operators won't need this.

### Why not a nonce-based CSP?

Phoenix LiveView injects inline scripts for its WebSocket bootstrap. A strict nonce-based policy would require patching LiveView's rendering pipeline. The current policy is the tightest that works with stock Phoenix.

## WebSocket origin checking

Phoenix checks the `Origin` header on WebSocket upgrade requests to prevent cross-site WebSocket hijacking. In production, Famichat auto-derives the allowed origin from the endpoint's existing `url` config:

```
check_origin: ["https://your-domain.example:443"]
```

This is constructed at runtime from `URL_SCHEME`, `URL_HOST`, and `URL_PORT` — values the operator already provides. Non-standard ports (anything other than 80/443) are included automatically.

In dev, origin checking is disabled (`check_origin: false` in `dev.exs`) so that connections from any local address work without friction.

**What the operator controls:** Nothing beyond the URL variables they already set. The origin allowlist is derived, not configured separately.

### Reverse proxy compatibility

Origin checking works correctly behind Cloudflare Tunnel, Caddy, Nginx, and other reverse proxies. The browser sets the `Origin` header to the public-facing URL (what the user sees in the address bar), and Phoenix compares it against the configured public URL. The proxy's internal forwarding doesn't affect this.

## LiveDashboard request logger

The `Phoenix.LiveDashboard.RequestLogger` plug parses a query parameter on every request to enable request logging. This is a development convenience — it has no purpose in production and adds unnecessary request processing.

In Famichat, this plug is inside the `code_reloading?` compile-time guard, so it doesn't exist in the production binary.

**What the operator controls:** Nothing. This is structurally absent in production.

## Summary of operator-facing configuration

| Setting | Required? | Default |
|---|---|---|
| `URL_HOST` | Yes | — |
| `URL_SCHEME` | No | `https` |
| `URL_PORT` | No | `443` |
| `SECRET_KEY_BASE` | Yes | — |
| `CSP_ADDITIONAL_HOSTS` | No | empty |

Everything else described on this page is automatic.
