# Famichat NOW

**Last Updated**: 2026-02-25

## One-line reality

Famichat has a solid backend messaging foundation and now has a secure, test-validated CLI broadcast verification workflow, but it is not production-ready for real family usage yet.

## What works today

1. Real-time channel infrastructure is in place with authenticated joins and telemetry.
2. Core chat domain flows exist for direct/self/group messaging and conversation membership checks.
3. Story 7.4.2 is implemented:
   - Canonical secure endpoint: `POST /api/test/broadcast`
   - Compatibility alias: `POST /api/test/test_events` (deprecated path)
   - Auth + membership authorization enforced
   - Contract outcomes covered (`200/401/403/422`) with no-broadcast guarantees on non-200
4. Accounts/auth foundation is in place (token/session/device/passkey flows), enabling authenticated API and channel behavior.

## What is still not done

1. No true E2EE yet: messages are still effectively plaintext from a product-trust perspective.
2. Client integration documentation and end-to-end operator workflow are still fragmented.
3. Repo-wide lint/static-analysis gates still have baseline debt outside 7.4.2 scope.
4. Sprint follow-through remains on role/auth edge-case testing and end-to-end notification verification.

## What this means for the product

1. Good state for backend engineering validation and controlled internal drills.
2. Not yet a trust-ready family messaging product for broad dogfooding or release.
3. Main remaining risk is privacy/security posture (encryption gap), not basic transport mechanics.

## Top 3 next tasks (highest ROI)

1. Close auth/role edge-case test gaps (channel authorization + group privilege boundary conditions).
2. Start E2EE implementation track (MLS/OpenMLS path) to remove plaintext-risk as the top product blocker.
3. Triage repo-wide lint/static baseline debt and capture a current coverage snapshot.
