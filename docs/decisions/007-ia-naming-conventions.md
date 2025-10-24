here’s a concise, copy‑pastable **ia lexicon + style guide** you can drop into `/docs/ia-lexicon.md`. it encodes the decisions we’ve been making so other engineers can replicate them.

---

## core domain nouns

| concept                        | prefer                     | avoid / deprecated              | definition                                                     | write owner (context) | schema module (data boundary)                                   | id field         | notes                                                           |
| ------------------------------ | -------------------------- | ------------------------------- | -------------------------------------------------------------- | --------------------- | --------------------------------------------------------------- | ---------------- | --------------------------------------------------------------- |
| household (governance unit)    | **household**              | family (as governance unit)     | the permission boundary for invites, roles, and recovery scope | `Auth.Households`     | `Accounts.HouseholdMembership` (`@source "family_memberships"`) | `household_id`   | ui copy may still say “family”; internal code uses “household”. |
| membership                     | **household_membership**   | family_membership (module name) | user ↔ household link with role                                | `Auth.Households`     | `Accounts.HouseholdMembership`                                  | `id`             | export helper apis from `Auth.Households`.                      |
| user identity                  | **user**                   | account (as a person)           | person using the app                                           | `Auth.Identity`       | `Accounts.User`                                                 | `user_id`        | identity owns writes to user; others read.                      |
| device                         | **user_device**            | device                          | client device state (refresh, trust, revocation)               | `Auth.Sessions`       | `Accounts.UserDevice`                                           | `device_id`      | sessions owns writes.                                           |
| passkey                        | **passkey**                | authenticator                   | stored webauthn credential                                     | `Auth.Passkeys`       | `Accounts.Passkey`                                              | `passkey.id`     | passkeys owns writes (sign_count, disable).                     |
| webauthn challenge             | **challenge** (namespaced) | (none)                          | single‑use challenge for registration/assertion                | `Auth.Passkeys`       | `Auth.Passkeys.Challenge`                                       | `challenge.id`   | context‑local schema (not shared).                              |
| token (ledgered/signed/secret) | **token**                  | user_token helpers              | auth tokens across kinds and storage classes                   | `Auth.Tokens`         | `Accounts.UserToken`                                            | `user_tokens.id` | only `Auth.Tokens.Storage` writes.                              |
| invite                         | **invite**                 | (none)                          | onboarding invitation to a household                           | `Auth.Onboarding`     | `Accounts.UserToken` (kind=`invite`)                            | token id         | onboarding orchestrates via token kinds.                        |
| pairing                        | **pairing**                | pair                            | device pairing flow linked to invites                          | `Auth.Onboarding`     | `Accounts.UserToken` (kinds map below)                          | token id         | two kinds: qr, admin code.                                      |
| session                        | **session**                | login                           | access+refresh lifecycle bound to device                       | `Auth.Sessions`       | `Accounts.UserDevice` + tokens                                  | n/a              | access is signed, refresh is device secret.                     |

---

## verbs and contracts

use a closed set of verbs per capability.

| capability        | verbs                                                                                                                                    | applies to                | return type                                        | error type         | don’t do                                                  |            |                            |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | -------------------------------------------------- | ------------------ | --------------------------------------------------------- | ---------- | -------------------------- |
| tokens (ledgered) | **issue → fetch → consume**                                                                                                              | ledgered kinds            | `%Auth.IssuedToken{}` (issue), `UserToken` (fetch) | `Auth.Errors.t/0`  | don’t call repo on `UserToken` directly.                  |            |                            |
| tokens (signed)   | **sign → verify**                                                                                                                        | access, challenge handles | signed token (string)                              | `{:error, :expired | :invalid                                                  | :missing}` | don’t use `fetch/consume`. |
| sessions          | **start_session → refresh_session → revoke_device → verify_access_token → require_reauth?**                                              | per device                | map with tokens (public), booleans                 | `Auth.Errors.t/0`  | don’t mix “remember” and “trust” terms; see naming rules. |            |                            |
| passkeys          | **issue_registration_challenge → issue_assertion_challenge → fetch_*_challenge → consume_challenge → register_passkey → assert_passkey** | webauthn                  | map with `public_key_options`                      | `Auth.Errors.t/0`  | don’t return mixed key casing at top level.               |            |                            |
| onboarding        | **issue_invite → accept_invite → issue_pairing → redeem_pairing → complete_registration**                                                | household onboarding      | typed maps                                         | `Auth.Errors.t/0`  | don’t alternate accept/redeem names arbitrarily.          |            |                            |
| households        | **add_member → member_role**                                                                                                             | governance                | role or membership                                 | `Auth.Errors.t/0`  | don’t write `HouseholdMembership` outside this context.   |            |                            |

---

## naming rules (modules, files, and fields)

* **contexts (behavior)**: `Famichat.Auth.<Context>` (e.g., `Auth.Sessions`, `Auth.Passkeys`, `Auth.Tokens`, `Auth.Households`, `Auth.Onboarding`, `Auth.Identity`).
* **data boundary (schemas only)**: `Famichat.Accounts.<Schema>` stored in `lib/famichat/accounts/` one file per schema (no extra `schemas/` directory).
* **owners**: add “write owner” in the schema module doc. e.g., “Write owner: `Auth.Sessions`.”
* **device helpers**: `Auth.Sessions.DeviceStore` (not `Device`) to signal persistence responsibility.
* **policies & storage**: `Auth.Tokens.Policy` (policy), `Auth.Tokens.Storage` (adapter).
* **runtime/adapters**: prefer `auth/runtime/*` over `auth/infra/*` (e.g., `Auth.Runtime.RateLimit`).
* **snake case for internal map keys**; only spec‑mandated blobs (e.g., WebAuthn’s `publicKey`) keep original casing under a snake‑case wrapper key `public_key_options`.

---

## canonical token kinds

use these atoms in code; map to legacy `user_tokens.kind` strings centrally.

| canonical kind (code)   | legacy db string        | audience (atom) | storage       |
| ----------------------- | ----------------------- | --------------- | ------------- |
| `:invite`               | `"invite"`              | `:invitee`      | ledgered      |
| `:invite_registration`  | `"invite_registration"` | `:invitee`      | signed        |
| `:pairing_qr`           | `"pair_qr"`             | `:device`       | ledgered      |
| `:pairing_admin_code`   | `"pair_admin_code"`     | `:device`       | ledgered      |
| `:passkey_registration` | `"passkey_reg"`         | `:user`         | ledgered      |
| `:passkey_assertion`    | `"passkey_assert"`      | `:user`         | ledgered      |
| `:magic_link`           | `"magic_link"`          | `:user`         | ledgered      |
| `:otp`                  | `"otp"`                 | `:user`         | ledgered      |
| `:recovery`             | `"recovery"`            | `:admin`        | ledgered      |
| `:access`               | n/a (signed)            | `:device`       | signed        |
| `:session_refresh`      | `"device_refresh"`      | `:device`       | device_secret |

**policy shapes**

* `audience`: atom in policy; convert to string only at write time.
* `subject_strategy`: **atoms only**: `:none | :user_id | :device_id | :email_sha256`.

---

## sessions and device naming

* boolean option: **`:remember_device?`** (not `:remember`).
* db field stays **`trusted_until`**; docs call it “trust window”.
* helper module: **`Auth.Sessions.DeviceStore`**; public context stays `Auth.Sessions`.
* rotation module: **`Auth.Sessions.RefreshRotation`**.

---

## households vocabulary

* use **household** for governance scope across code, tokens, telemetry, and payloads (`household_id`).
* keep table name `family_memberships`; expose schema as `Accounts.HouseholdMembership @source "family_memberships"`.
* provide compatibility alias: `defmodule Accounts.FamilyMembership, do: alias Accounts.HouseholdMembership`.

---

## telemetry and rate limiting

**telemetry**

* root: `[:famichat, :auth, <context>, <action>]`
* examples:

  * `[:famichat, :auth, :tokens, :issued]`
  * `[:famichat, :auth, :sessions, :refresh]`
  * `[:famichat, :auth, :passkeys, :challenge_issued]`

**rate limit buckets**

* module: `Auth.RateLimit` (mechanism) and `Auth.RateLimit.Buckets` (enum).
* naming pattern: `verb.object` (lowercase, dot‑separated).
* standard buckets:

  * `invite.issue`, `invite.accept`
  * `pairing.redeem`, `pairing.reissue`
  * `passkey.assertion`, `passkey.registration`
  * `session.refresh`
  * `magic_link.issue`, `otp.issue`

---

## error taxonomy

* public type: **`Auth.Errors.t()`** only.
* atoms: `:invalid | :expired | :used | :revoked | :trust_required | :trust_expired | :reuse_detected`.
* tuples: `{:rate_limited, seconds}` | `{:forbidden, reason_atom}` | `{:validation_failed, Ecto.Changeset.t()}`.
* don’t place errors under `Accounts.*` (data boundary).

---

## return shape and casing rules

* **public maps** use snake_case keys: `challenge`, `challenge_handle`, `expires_at`, `public_key_options`.
* **spec blobs** (e.g., WebAuthn `publicKey`) keep original casing but are nested under `*_options` snake‑case keys.
* **issued token** struct: `%Auth.IssuedToken{kind, class, raw, record?, hash?, issued_at, expires_at, audience?}` (no duplicate fields vs policy).

---

## mece checklist (before adding a new module or table)

1. **is this a shared table?** put the schema in `Accounts.*`.
   if single‑context, place it under that context’s namespace.
2. **who writes?** add “write owner” to the schema docs and expose writes only through that context.
3. **does a verb already exist?** reuse verbs from the verbs table.
4. **does telemetry fit the root?** conform to `[:famichat, :auth, <context>, <action>]`.
5. **does the new name collide with existing nouns?** prefer the canonical dictionary above.

---

## compatibility patterns

* for renames, add one release of aliases with `@deprecated` messages.
* keep legacy db strings for token kinds; map canonicals ↔ strings in `Auth.Tokens.Policy`.
* don’t rename database columns for copyedits; use module names and docs to encode the domain.

---

## quick examples (before → after)

**module names**

* `Auth.Authenticators` → `Auth.Passkeys`
* `Auth.Infra.Tokens` → `Auth.Tokens.Storage`
* `Auth.TokenPolicy` → `Auth.Tokens.Policy`
* `Auth.Sessions.Device` → `Auth.Sessions.DeviceStore`

**token issuance**

```elixir
# before
{:ok, %Auth.Tokens.Issue{raw: r}} = Auth.Tokens.issue(:passkey_reg, %{"user_id" => uid})

# after
{:ok, %Auth.IssuedToken{raw: r}}  = Auth.Tokens.issue(:passkey_registration, %{"user_id" => uid})
```

**webauthn response**

```elixir
%{
  challenge: "...",
  challenge_handle: "...",
  expires_at: dt,
  public_key_options: %{ "challenge" => "...", "rp" => %{...} }
}
```

**telemetry**

```elixir
:telemetry.execute([:famichat, :auth, :sessions, :refresh], %{count: 1}, %{device_id: d})
```

**rate limiting**

```elixir
Auth.RateLimit.check(:'session.refresh', device_id, limit: 6, per: 3600)
```