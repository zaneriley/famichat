Below is a single, comprehensive, copy‑pastable document you can drop into your repo (e.g., `/docs/auth-ia-ddd-refactor.md`). It consolidates the IA, DDD decisions, naming, APIs, and the step‑by‑step plan so any engineer (or LLM) can implement and verify the changes end‑to‑end.

---

# Famichat auth IA and DDD refactor — authoritative guide

**Status**: Approved design
**Audience**: Backend engineers, reviewers, LLMs assisting implementation
**Applies to**: `lib/famichat/{accounts,auth}/**` and related docs/tests/telemetry

---

## 1) Executive summary

We are finishing the auth refactor by:

* Converting **Accounts** into a **schema‑only data boundary** (no business logic).
* Exposing **Auth** as the **single façade and behavior boundary** (sessions, tokens, passkeys, onboarding, households).
* Unifying naming, telemetry, rate limiting, and error taxonomy to be MECE, DDD‑aligned, and easy to navigate.

We avoid risky migrations. We do not rename database tables or columns. We deliver in small, verifiable PRs with compile‑time boundary enforcement, greps as gates, and contract tests.

---

## 2) Goals and non‑goals

**Goals**

* New engineers can find the right module in one guess.
* Schema ownership is explicit; only one context writes each table.
* Public verbs, token kinds, and payload shapes are consistent.
* Telemetry and throttling use a single vocabulary and root.

**Non‑goals**

* No database renames or table reshapes.
* No big‑bang refactor; all changes are incremental and reversible.

---

## 3) Domain dictionary (canonical lexicon)

> Put this in `/docs/ia-lexicon.md` and keep it in sync.

| concept                     | prefer                     | deprecated                    | definition                                             | write owner (context) | schema module (data boundary)                                   | id field         | notes                                                 |
| --------------------------- | -------------------------- | ----------------------------- | ------------------------------------------------------ | --------------------- | --------------------------------------------------------------- | ---------------- | ----------------------------------------------------- |
| household (governance unit) | **household**              | family (as governance)        | Permission boundary for invites, roles, recovery scope | `Auth.Households`     | `Accounts.HouseholdMembership` (`@source "family_memberships"`) | `household_id`   | UI may still say “family”; internals use “household”. |
| membership                  | **household_membership**   | family_membership (module)    | User ↔ household with role                             | `Auth.Households`     | `Accounts.HouseholdMembership`                                  | `id`             | Add alias `Accounts.FamilyMembership` for compat.     |
| user identity               | **user**                   | account (as a person)         | A person using the app                                 | `Auth.Identity`       | `Accounts.User`                                                 | `user_id`        | Identity owns writes; others read only.               |
| device                      | **user_device**            | device                        | Client device state (refresh, trust, revocation); trust_state distinguishes `:pending \| :active \| :revoked`; pending devices get read-only access until a household admin approves (Path A for non-admin members) or are immediately active when added via QR from an existing trusted device (Path B). | `Auth.Sessions`       | `Accounts.UserDevice`                                           | `device_id`      | Sessions owns writes. See §8.1 for device-add authorization model.                                 |
| passkey                     | **passkey**                | authenticator                 | Stored WebAuthn credential                             | `Auth.Passkeys`       | `Accounts.Passkey`                                              | `passkey.id`     | Passkeys owns writes (sign_count/disable).            |
| webauthn challenge          | **challenge** (namespaced) | —                             | Single‑use registration/assertion challenge            | `Auth.Passkeys`       | `Auth.Passkeys.Challenge`                                       | `challenge.id`   | Context‑local schema (not shared).                    |
| token                       | **token**                  | user_token helpers (publicly) | Auth tokens across kinds/storage                       | `Auth.Tokens`         | `Accounts.UserToken`                                            | `user_tokens.id` | Only `Auth.Tokens.Storage` writes.                    |
| invite                      | **invite**                 | —                             | Onboarding invitation to a household                   | `Auth.Onboarding`     | `Accounts.UserToken` kind=`invite`                              | token id         | Kinds below.                                          |
| pairing                     | **pairing**                | pair                          | Device pairing tied to invites                         | `Auth.Onboarding`     | `Accounts.UserToken`                                            | token id         | `pair_qr` and `pair_admin_code`.                     |
| session                     | **session**                | login                         | Access + refresh lifecycle per device                  | `Auth.Sessions`       | `Accounts.UserDevice` + tokens                                  | —                | Access is signed, refresh is device‑secret.           |

---

## 4) Target architecture

```
lib/famichat/
├── accounts/                    # Data boundary (schemas only)
│   ├── user.ex                  # Accounts.User           (write owner: Auth.Identity)
│   ├── passkey.ex               # Accounts.Passkey        (write owner: Auth.Passkeys)
│   ├── user_token.ex            # Accounts.UserToken      (write owner: Auth.Tokens)
│   ├── user_device.ex           # Accounts.UserDevice     (write owner: Auth.Sessions)
│   ├── household_membership.ex  # Accounts.HouseholdMembership @source "family_memberships"
│   ├── username.ex              # Username utilities (consumed by Identity)
│   └── types/encrypted_binary.ex
│
└── auth/                        # Behavior boundaries (public surface via Famichat.Auth)
    ├── auth.ex                  # Famichat.Auth façade (public API)
    ├── tokens/
    │   ├── tokens.ex            # Auth.Tokens (issue/fetch/consume/sign/verify)
    │   ├── policy.ex            # Auth.Tokens.Policy     (policy per kind)
    │   └── storage.ex           # Auth.Tokens.Storage    (adapters, writes UserToken)
    ├── sessions/
    │   ├── sessions.ex          # Auth.Sessions (public)
    │   ├── device_store.ex      # Auth.Sessions.DeviceStore (writes UserDevice)
    │   └── refresh_rotation.ex  # Auth.Sessions.RefreshRotation
    ├── passkeys/
    │   ├── passkeys.ex          # Auth.Passkeys (public)
    │   └── challenge.ex         # Auth.Passkeys.Challenge (context-local schema)
    ├── households/
    │   └── households.ex        # Auth.Households (add_member, member_role)
    ├── onboarding/
    │   └── onboarding.ex        # Auth.Onboarding (invite/pairing orchestration)
    └── runtime/
        ├── rate_limit.ex        # Auth.RateLimit (mechanism)
        ├── buckets.ex           # Auth.RateLimit.Buckets (enum)
        └── instrumentation.ex   # Auth.Runtime.Instrumentation (spans)
```

**Boundary rules**

* `Famichat.Accounts`: exports only schema modules and pure types. No behavior.
* Each `Auth.<Context>` declares `deps: [Famichat.Accounts, Famichat.Repo, Famichat.Auth.Runtime]`.
* Only the designated owner context writes its schema (see lexicon). All other contexts read only.

---

## 5) The façade

Public callers should import only:

```elixir
Famichat.Auth
```

Keep a deprecated `Famichat.Accounts` façade delegating to `Famichat.Auth` for one release.

**Public surface (illustrative; keep your current arities):**

* Sessions:

  * `start_session(user, device_info, opts \\ [remember_device?: false]) :: {:ok, map} | {:error, Auth.Errors.t()}`
  * `refresh_session(device_id, refresh) :: {:ok, map} | {:error, Auth.Errors.t()}`
  * `revoke_device(user_id, device_id) :: {:ok, :revoked} | {:error, Auth.Errors.t()}`
  * `verify_access_token(token) :: {:ok, %{user_id: uuid, device_id: bin}} | {:error, Auth.Errors.t()}`
  * `require_reauth?(user_id, device_id, action_atom) :: boolean`
* Passkeys:

  * `issue_registration_challenge(user) :: {:ok, challenge_map} | {:error, Auth.Errors.t()}`
  * `issue_assertion_challenge(user) :: {:ok, challenge_map} | {:error, Auth.Errors.t()}`
  * `fetch_registration_challenge(handle) :: {:ok, Challenge.t} | {:error, Auth.Errors.t()}`
  * `fetch_assertion_challenge(handle) :: {:ok, Challenge.t} | {:error, Auth.Errors.t()}`
  * `consume_challenge(challenge) :: {:ok, Challenge.t} | {:error, Auth.Errors.t()}`
  * `register_passkey(attrs) :: {:ok, Accounts.Passkey.t} | {:error, Auth.Errors.t()}`
  * `assert_passkey(attrs) :: {:ok, %{user: Accounts.User.t, passkey: Accounts.Passkey.t}} | {:error, Auth.Errors.t()}`
* Tokens:

  * `issue(kind, payload, opts \\ []) :: {:ok, %Auth.IssuedToken{}} | {:error, Auth.Errors.t()}`
  * `fetch(kind, raw, opts \\ []) :: {:ok, Accounts.UserToken.t} | {:error, Auth.Errors.t()}`
  * `consume(user_token) :: {:ok, Accounts.UserToken.t} | {:error, Ecto.Changeset.t()}`
  * `sign(kind, payload, opts \\ []) :: token_string`
  * `verify(kind, token, opts \\ []) :: {:ok, payload} | {:error, :expired | :invalid | :missing}`
* Onboarding:

  * `issue_invite/3`, `accept_invite/1`, `issue_pairing/1`, `redeem_pairing/1`, `complete_registration/2`
* Households:

  * `add_member/3`, `member_role/2`

---

## 6) Naming conventions

* **Use “household”** for governance scope across code, telemetry, tokens, and payloads (`household_id`).
  Keep DB table `family_memberships` and expose schema as `Accounts.HouseholdMembership @source "family_memberships"`. Provide alias `Accounts.FamilyMembership`.
* **Modules and files mirror each other** (no `schemas/` subfolder inside `accounts`).
* **Public maps use snake_case keys**. Spec blobs (e.g., WebAuthn `publicKey`) live under a snake‑case wrapper key: `public_key_options`.
* **Booleans read as questions**: `:remember_device?` (not `:remember`).
* **Policies and adapters**: `Auth.Tokens.Policy`, `Auth.Tokens.Storage`.
* **Sessions store**: `Auth.Sessions.DeviceStore` (not just `Device`).

---

## 7) Token system

### 7.1 Canonical kinds (code) ↔ legacy DB strings

Map canonicals in **one place** (policy) without DB changes:

| canonical kind (code)   | legacy db string        | audience (atom) | storage       |
| ----------------------- | ----------------------- | --------------- | ------------- |
| `:invite`               | `"invite"`              | `:invitee`      | ledgered      |
| `:invite_registration`  | `"invite_registration"` | `:invitee`      | signed        |
| `:pair_qr`              | `"pair_qr"`             | `:device`       | ledgered      |
| `:pair_admin_code`      | `"pair_admin_code"`     | `:device`       | ledgered      |
| `:passkey_registration` | `"passkey_reg"`         | `:user`         | ledgered      |
| `:passkey_assertion`    | `"passkey_assert"`      | `:user`         | ledgered      |
| `:magic_link`           | `"magic_link"`          | `:user`         | ledgered      |
| `:otp`                  | `"otp"`                 | `:user`         | ledgered      |
| `:recovery`             | `"recovery"`            | `:admin`        | ledgered      |
| `:access`               | n/a (signed)            | `:device`       | signed        |
| `:session_refresh`      | `"device_refresh"`      | `:device`       | device_secret |

### 7.2 Policy and storage contracts

* `Auth.Tokens.Policy` returns canonical atoms:

  * `audience :: atom` (convert to string only when writing DB rows).
  * `subject_strategy :: :none | :user_id | :device_id | :email_sha256` (atoms only).
* `Auth.Tokens.Storage` is the only code that writes `Accounts.UserToken`.
* Issuance API returns `%Auth.IssuedToken{kind, class, raw, hash?, record?, audience?, issued_at, expires_at}`.

### 7.3 Verbs and rules

* Ledgered kinds: **issue → fetch → consume**.
* Signed kinds: **sign → verify** (no fetch/consume).
* Subject id telemetry: emit `:subject_id_present` or `:missing_subject_id` under the unified root (see §10).

---

## 8) Sessions and device trust

* `Auth.Sessions.DeviceStore` writes `Accounts.UserDevice`.
* `Auth.Sessions.RefreshRotation` implements refresh reuse detection and revocation.
* Options:

  * `remember_device? :: boolean` (hint for granting a trust window).
* DB shape unchanged (`trusted_until`, `refresh_token_hash`, `previous_token_hash`, etc.).
* Telemetry unified under `[:famichat, :auth, :sessions, <action>]`.

### 8.1 Device-add authorization model (decided 2026-03-01)

Two paths exist for adding a new device. **Path B is the higher-trust path.**

**Path A — Passkey login**

Approval is gated on household role:
- Household admin or adult member: immediately approved (self-approving).
- Non-admin member (teen, child): device enters a **pending** state with read-only access until a household admin approves.
- Grandparent / low-tech user: passkey sync (iCloud/Google) is seamless; falls back to magic link + OTP with a passive household-admin notification.

The pending state must be persisted on `Accounts.UserDevice` (e.g., a `trust_state` field distinguishing `:pending | :active | :revoked`). This is a **known gap** — the schema and authorization enforcement have not yet been built (see `docs/NOW.md`).

**Path B — QR / existing device approval**

The user scans a QR code generated by an already-trusted device they physically possess. This proves current possession of a prior trusted device, which is a stronger signal than passkey alone.
- Immediately approved for any role; no pending state; no admin review required.
- Use cases: platform switch (iOS → Android), lost passkey, or any scenario where the user still holds a trusted device.
- Implemented via the existing `pair_qr` / `pair_admin_code` token kinds in `Auth.Onboarding`.

**Revocation**

- Any neighborhood admin or household admin may revoke a device.
- Revocation kills the active session immediately and triggers MLS group removal from all conversations.
- UX: tombstone message per affected conversation ("Zane removed iPhone 12 from this conversation").
- Past messages retain MLS forward secrecy; the revoked device cannot decrypt future messages.

**Trust hierarchy**

```
Neighborhood admin  →  revoke any device on the instance
Household admin     →  manage family members' devices; approve pending additions
Adult member        →  manage own devices (self-approving on Path A)
Non-admin member    →  add via Path A (pending) or Path B (immediate, requires existing device)
```

---

## 9) Passkeys and WebAuthn

* Context is `Auth.Passkeys`.
* Schema is `Auth.Passkeys.Challenge` (table unchanged: `webauthn_challenges`).
* Verbs: `issue_*_challenge → fetch_*_challenge → consume_challenge`.
* Response shape:

```elixir
%{
  challenge: "...",                  # base64url
  challenge_handle: "...",           # signed opaque token
  expires_at: ~U[...Z],
  public_key_options: %{             # original WebAuthn blob (spec casing)
    "challenge" => "...",
    "rp" => %{...},
    ...
  }
}
```

---

## 10) Telemetry and rate limiting

### 10.1 Telemetry

Single root: `[:famichat, :auth, <context>, <action>]`

Examples:

* `[:famichat, :auth, :tokens, :issued]`
* `[:famichat, :auth, :passkeys, :challenge_issued | :challenge_consumed | :challenge_invalid]`
* `[:famichat, :auth, :sessions, :start | :refresh | :refresh_reuse_detected | :revoke]`

### 10.2 Rate limiting

* Mechanism: `Auth.RateLimit`.
* Buckets enum: `Auth.RateLimit.Buckets` with **`verb.object`** names:

  * `invite.issue`, `invite.accept`
  * `pairing.redeem`, `pairing.reissue`
  * `passkey.registration`, `passkey.assertion`
  * `session.refresh`
  * `magic_link.issue`, `otp.issue`

---

## 11) Error taxonomy

Public type: `Auth.Errors.t()`

* Atoms: `:invalid | :expired | :used | :revoked | :trust_required | :trust_expired | :reuse_detected`
* Tuples: `{:rate_limited, seconds}` | `{:forbidden, reason_atom}` | `{:validation_failed, Ecto.Changeset.t()}`

Errors live under `Famichat.Auth.Errors` (not in `Accounts`).

---

## 12) Return shape rules

* **Public** maps use **snake_case** keys.
* **Spec** payloads (e.g., WebAuthn `publicKey`) keep spec casing and live under snake‑case wrapper keys (e.g., `public_key_options`).

---

## 13) Compatibility and aliasing

* `Famichat.Accounts` façade remains for one release, marked `@deprecated`, delegating to `Famichat.Auth`.
* `Accounts.FamilyMembership` becomes an alias to `Accounts.HouseholdMembership`.
* Deprecated compatibility shims have now been removed (`Auth.Infra.*`, `Auth.TokenPolicy`, `Auth.Sessions.Device`, `Auth.Sessions.RotationPolicy`). Only `Auth.Authenticators` remains temporarily as a pass-through to `Auth.Passkeys` while external callers finish migrating.

---

## 14) Implementation plan (discrete, verifiable phases)

We run two tracks that interleave safely: **Track A (structure)** and **Track B (IA naming).**
Each phase is a small PR with explicit acceptance checks and rollbacks.

### Track A — Accounts → schema‑only boundary

**A1. Boundary hardening (no behavior change)**

* Add `use Boundary` to `Famichat.Accounts`; export only schema modules and pure types.
* Ensure every `Auth.*` module declares `deps: [Famichat.Accounts, Famichat.Repo, Famichat.Auth.Runtime]`.
* Move files so path mirrors modules (`accounts/*.ex`, one file per schema).
  **Acceptance**: Boundary CI fails illegal writes; editor navigation mirrors modules.
  **Rollback**: Revert boundary configs.

**A2. Tokens inversion (remove `Accounts.Token`)**

* Implement `Auth.Tokens.Storage` that writes `Accounts.UserToken` directly (copy hashing/changeset logic from `Accounts.Token`).
* Replace calls to `Accounts.Token.*` with `Auth.Tokens.Storage.*`.
* Keep `Accounts.Token` as a deprecated shim delegating to `Auth.Tokens.Storage` for one release.
  **Status**: ✅ Completed — shim removed Oct 2025 (grep shows zero references).
  **Rollback**: Point shim back.

**A3. Façade routes to Auth**

* `Famichat.Accounts` façade delegates to `Auth` contexts directly for sessions/tokens/passkey challenges.
  **Status**: ✅ Completed — façade is now a deprecated thin delegate (Oct 2025).
* Mark any legacy delegates `@deprecated`.
  **Acceptance**: Grep shows zero calls to `Accounts.Legacy` for the migrated parts.
  **Rollback**: Repoint delegates.

**A4. Delete leftovers**

* Remove `accounts/legacy.ex` once unused.
* Move rate limiter mechanism under `Auth.Runtime.RateLimit`; delete `Accounts.RateLimiter`.
* Ensure every schema has a “write owner” note in its `@moduledoc`.
  **Acceptance**: Grep has no references to deleted modules; boundary CI passes.
  **Rollback**: Restore from tag.

### Track B — IA lexicon and DX naming

**B1. Introduce new façade and context wrappers**

* Add `Famichat.Auth` façade.
* Add thin wrapper modules (aliases + `@deprecated`): `Auth.Passkeys`, `Auth.Tokens.Policy`, `Auth.Tokens.Storage`, `Auth.Sessions.DeviceStore`, `Auth.Sessions.RefreshRotation`.
  **Acceptance**: New names compile; old names still work with deprecation warnings.
  **Rollback**: Remove wrappers.

**B2. Household lexicon cut (no DB migration)**

* Add `Accounts.HouseholdMembership @source "family_memberships"`.
* Add alias module `Accounts.FamilyMembership`.
* Update `Auth.Households` to use the new schema module.
  **Acceptance**: Tests pass; writes happen through `Households`.
  **Rollback**: Revert alias and schema module.

**B3. Passkeys rename and response shape**

* Move functionality into `Auth.Passkeys`; keep `Auth.Authenticators` as a deprecated alias.
* Return `public_key_options` wrapper around the WebAuthn blob.
* Rename schema to `Auth.Passkeys.Challenge` (module name only).
  **Acceptance**: Controller tests expect `public_key_options`; telemetry root uses `:passkeys`.
  **Rollback**: Reintroduce old module and shape.

**B4. Tokens vocabulary normalization**

* `%Auth.Tokens.Issue{}` → `%Auth.IssuedToken{}` (keep `Auth.Tokens.Issue` as a deprecated type alias for one release).
* `audience` strictly atom in policy; convert at write time only.
* `subject_strategy` strictly atoms.
* Canonicalize kinds and mapping in `Auth.Tokens.Policy`.
  **Acceptance**: Property tests for issuance/consumption still pass with mixed historical rows.
  **Rollback**: Keep mapping table; revert struct rename if needed.

**B5. Telemetry and rate limiting unification**

* All emits under `[:famichat, :auth, <context>, <action>]`.
* Replace buckets with `Auth.RateLimit.Buckets` names.
* Remove `Auth.RateLimit`.
  **Acceptance**: No occurrences of `[:auth_sessions` in grep; dashboards updated.
  **Rollback**: Provide temporary dual‑emit for one release.

**B6. Façade and errors finalization**

* Document `Famichat.Auth` as the only public façade.
* Move error type to `Auth.Errors`; keep `Accounts.Errors` as a type alias temporarily.
* Update `/docs/ia-lexicon.md` and schema docs.
  **Acceptance**: External callers import `Famichat.Auth`; no new references to `Famichat.Accounts` façade.
  **Rollback**: Keep aliases longer.

**B7. Recovery scopes and audit log**

* Extend `Auth.Recovery.issue_recovery/3` to accept scoped requests (`:target_user`, `:household`, `:global`), defaulting to `:target_user` when the `:recovery_scopes_v1` flag is disabled.
* Embed `scope` and optional `household_id` in recovery token payloads; legacy tokens without those keys continue to redeem as `:target_user`.
* Implement scoped containment in `redeem_recovery/1`, calling new helpers (`Sessions.revoke_all_for_user/1`, `Sessions.revoke_all_for_household/2`, passkey disable loops) and marking every affected user as enrollment-required.
* Introduce `auth_audit_logs` table + `Auth.Runtime.Audit.record/2` that stores `{event, actor_id, subject_id, household_id, scope, metadata}` with indexes for review; write a row for both issue and redeem.
* Telemetry under `[:famichat, :auth, :recovery, action]` must include `scope`/`household_id` without leaking secrets; alert if `:global` scope fires while `:recovery_global_allowed` is off.
  **Acceptance**: Flags gate the behaviour (disabled -> legacy flow, enabled -> scoped). Authorization tests pass, audit rows exist per affected user, telemetry metadata passes the “no raw token/code/email” grep.
  **Rollback**: Disable `:recovery_scopes_v1` to return to the original behaviour; audit table and helpers remain for future use.

---

## 15) Verification matrix (CI gates)

Add these greps to CI as explicit gates per phase:

* **A2**: `grep -R "Famichat.Accounts.Token" lib/` → empty (except the shim file).
* **A3**: `grep -R "Famichat.Accounts.Legacy" lib/` → empty.
* **B3**: `grep -R "Auth\.Authenticators" lib/ | grep -v alias` → empty.
* **B5**: `grep -R "\[:auth_sessions" lib/` → empty.
* **B6**: `grep -R "defmodule Famichat\.Accounts do" lib/` → present but contains only `@deprecated` delegates to `Famichat.Auth`.

Boundary checks:

* `mix compile` under `mix_boundary` must fail if a non‑owner context modifies a schema it doesn’t own.

Contract tests:

* Façade tests pin request/response shapes (snake_case keys, `public_key_options` wrapper, `%Auth.IssuedToken{}` struct fields).
* Property tests for token issuance/consumption with canonical kinds + legacy strings exercised.

---

## 16) Sample code snippets (drop‑in)

**16.1 Household membership schema (no migration)**

```elixir
defmodule Famichat.Accounts.HouseholdMembership do
  @moduledoc """
  Links a user to a household with a specific role.

  Write owner: `Famichat.Auth.Households`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Phoenix.Param, key: :id}
  @source "family_memberships"
  schema @source do
    belongs_to :family, Famichat.Chat.Family, foreign_key: :family_id
    belongs_to :user,   Famichat.Accounts.User
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(m, attrs) do
    m
    |> cast(attrs, [:family_id, :user_id, :role])
    |> validate_required([:family_id, :user_id, :role])
    |> unique_constraint(:membership_uniqueness,
      name: :family_memberships_family_id_user_id_index
    )
  end
end

defmodule Famichat.Accounts.FamilyMembership do
  @moduledoc "deprecated alias; use `Famichat.Accounts.HouseholdMembership`"
  @deprecated "use Famichat.Accounts.HouseholdMembership"
  defdelegate __info__(key), to: Famichat.Accounts.HouseholdMembership
end
```

**16.2 Tokens policy kind mapping (canonical ↔ legacy)**

```elixir
defmodule Famichat.Auth.Tokens.Policy do
  @canonical_to_legacy %{
    invite:                "invite",
    invite_registration:   "invite_registration",
    pair_qr:               "pair_qr",
    pair_admin_code:       "pair_admin_code",
    passkey_registration:  "passkey_reg",
    passkey_assertion:     "passkey_assert",
    magic_link:            "magic_link",
    otp:                   "otp",
    recovery:              "recovery",
    access:                nil,
    session_refresh:       "device_refresh"
  }

  def legacy_kind_string(:access), do: nil
  def legacy_kind_string(kind),    do: Map.fetch!(@canonical_to_legacy, kind)
end
```

**16.3 Passkeys challenge response shape**

```elixir
%{
  "challenge" => b64_chal, # returned to legacy callers if needed
  "challenge_handle" => handle,
  "expires_at" => expires_at,
  "public_key_options" => public_key_blob,
  challenge: b64_chal,     # snake_case for new callers
  challenge_handle: handle,
  expires_at: expires_at,
  public_key_options: public_key_blob
}
```

**16.4 Telemetry emits (unified root)**

```elixir
:telemetry.execute([:famichat, :auth, :sessions, :refresh], %{count: 1}, %{device_id: device_id})
:telemetry.execute([:famichat, :auth, :passkeys, :challenge_issued], %{count: 1}, %{user_id: user.id})
:telemetry.execute([:famichat, :auth, :tokens, :issued], %{count: 1}, %{kind: kind, class: class})
```

**16.5 Rate limit buckets**

```elixir
defmodule Famichat.Auth.RateLimit.Buckets do
  @type t ::
          :'invite.issue'
          | :'invite.accept'
          | :'pairing.redeem'
          | :'pairing.reissue'
          | :'passkey.registration'
          | :'passkey.assertion'
          | :'session.refresh'
          | :'magic_link.issue'
          | :'otp.issue'
end
```

---

## 17) Testing guidance

* **Boundary tests**: Create illegal cross‑calls and assert compile‑time failures in CI.
* **Property tests**:

  * Token issuance/consumption: for each canonical kind, assert TTL ≤ max, audience set, subject id strategy honored.
  * Refresh rotation: after n rotations, only last and previous hashes are acceptable; reuse triggers revocation and emits correct telemetry.
* **Contract tests**:

  * Façade shape tests for each public call (snake_case keys, `public_key_options` wrapper).
  * Passkeys challenge fetch/consume semantics (`:invalid_challenge`, `:expired`, `:already_used`).
* **Telemetry tests**: Assert exactly one event per action at the new root; no legacy roots emitted.
* **Rate limit tests**: Buckets use `verb.object` names; verify throttling returns `{:rate_limited, seconds}`.

---

## 18) Observability and dashboards

* Update dashboards to consume `[:famichat, :auth, ...]` only.
* Token issuance graphs by canonical `kind`.
* Passkeys challenge invalid rate alert (possible replay/desync).
* Session refresh reuse rate alert.

---

## 19) Developer migration guide

* Import `Famichat.Auth` instead of `Famichat.Accounts` in new code.
* Use `:remember_device?` instead of `:remember`.
* Expect `public_key_options` under `Auth.Passkeys` challenge responses.
* Refer to `Accounts.HouseholdMembership` in code; `FamilyMembership` is an alias for now.

---

## 20) Rollback plan

Every phase is self‑contained and reversible:

* Wrappers and aliases let us revert module moves by deleting wrapper files.
* Boundary enforcement can be relaxed temporarily by reverting `use Boundary` config changes.
* Telemetry can dual‑emit during a release if needed.
* The token kind mapping lives solely in `Auth.Tokens.Policy`; reverting the mapping is a one‑file change.

---

## 21) Definition of done

* `Famichat.Auth` is the documented façade; `Famichat.Accounts` façade is deprecated.
* `Accounts` contains schemas and pure types only; every schema `@moduledoc` declares “write owner”.
* All token issuance flows run through `Auth.Tokens` and write via `Auth.Tokens.Storage`.
* `Auth.Passkeys` owns WebAuthn; responses use `public_key_options`.
* Telemetry root unified; rate limit buckets standardized.
* CI contains greps and boundary checks; contract tests and property tests pass.
* Old names exist only as deprecated aliases for one release.

---

## 22) Rationale (why these choices)

* **Household** is the precise governance unit for invites, roles, and recovery. Using it yields MECE boundaries and future‑proofs multi‑home and caregiver scenarios without schema churn.
* **Schema‑only Accounts** keeps a single source of truth for data while enabling clear write ownership.
* **Canonical token kinds and unified telemetry** remove ambiguity and lower cognitive load for everyday work and incident response.

---

This document is the single source of truth for the auth IA and DDD refactor. If any future change deviates from these rules, update this doc and the lexicon first, then code.
