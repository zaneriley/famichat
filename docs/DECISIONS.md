# Decisions Log

Resolved decisions and explicitly rejected items. Reference document — answers "is this settled?" and "why did we say no?"

---

## Resolved decisions

- [x] Decide: commit to local-first persistent storage as SPA default before scaffold — DECIDED: persistent IndexedDB with encryption-at-rest; ephemeral makes search/previews/offline impossible → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P0-dogfood | agent:consensus
- [x] Decide: should self_service_enabled default to true for dogfood? — RESOLVED: yes; rate limit raised to 10/IP/hr; button demoted to text link → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: rate limit threshold behind NAT (3/hr may collide for same-household devices) — RESOLVED: raise to 10/IP/hr → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: accept double-biometric (register then sign-in) or auto-authenticate? — RESOLVED: auto-authenticate; 5/8 consensus angles agreed, user confirmed → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: Japanese translations for new gettext strings — RESOLVED: P0 blocking; user decision: must-have for Japanese-speaking spouse → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: clean up 66 pre-existing test failures as prerequisite or separate workstream? — RESOLVED: separate workstream; 3 mechanical root causes, zero hidden bugs → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: is unauthenticated POST /api/v1/auth/passkeys/assert/challenge intentional? — RESOLVED: yes, WebAuthn discoverable credential spec; add rate limiting → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: extend invite link TTL beyond 10 minutes for L1 dogfood? — RESOLVED: 72 hours; user decision; SPEC.md updated → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: is photo sharing required for 2-week dogfood? — RESOLVED: no; punt to next cycle; tracked as P2-debt → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: add "thinking of you" one-tap message? — RESOLVED: no; user decision: that's just a poke/like → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: reduce refresh token TTL from 30 to 7 days? — DEFERRED to L2: 30 days correct for dogfood; 7-day TTL adds auth friction with no security gain (revocation is device-level, not TTL-level) → .tmp/2026-03-10-ideation/09-rate-limiting-nat.md | agent:consensus
- [x] Decide: deployment strategy for L1 dogfood — RESOLVED: homelab + Docker Compose + Cloudflare Tunnel; dogfoods operator self-hosting experience; captures friction for future documentation | agent:consensus
- [x] Decide: remove `cache: disabled: true` entirely from prod.exs, not decouple rate limiting — RESOLVED: `Famichat.Cache` is only backing auth rate limiting, so preserving the dead flag adds coupling without user value → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | agent:consensus
- [x] Decide: should `./run setup` prompt for optional customizations or keep minimal? — RESOLVED: no new surface; warm errors in runtime.exs only for L1; wizard/check-config deferred to P2 → .tmp/2026-03-11-config-ux/round-1/consensus.md | agent:consensus
- [x] Decide: encrypt message bodies at rest in IndexedDB — DECIDED: AES-256-GCM, same wrapping key infra as MLS state → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | agent:consensus
- [x] Decide: cold-start key access model — DECIDED: instant open (persistent CryptoKey); optional passkey/biometric as wishlist → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | agent:consensus
- [x] Decide: server-side ciphertext retention — DECIDED: short (30 days / all-device ACK); local store is canonical → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | agent:consensus
- [x] Decide: recovery phrase model — DECIDED: 12-word phrase for L3; social recovery (1-2 family members) as wishlist for L4+ → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | agent:consensus
- [x] Decide: move `Famichat.Chat.Family` schema to `Famichat.Accounts`? — RESOLVED: no; Family stays in Chat for L1; adding Accounts→Chat dep creates a cycle; FamilyContext cross-boundary reach is documented and accepted → .tmp/2026-03-20-boundary-enforcement/round-1/consensus.md | agent:boundary-consensus
- [x] Decide: enforce `Famichat.Auth` facade or accept direct sub-module access? — RESOLVED: accept direct sub-module access; facade has zero callers; 8 Auth sub-boundaries work as independent top-level boundaries → .tmp/2026-03-20-boundary-enforcement/round-1/consensus.md | agent:boundary-consensus

## Cut / Won't do

- [-] Bounded context refactor (Onboarding → Chat.create_family) — harmless violation in throwaway code; SPA will replace | agent:consensus
- [-] LiveView deduplication (merge FamilyNewLive into FamilySetupLive) — zero user value; throwaway code per SPEC | agent:consensus
- [-] PasskeyCeremony helper extraction — duplication is real but code is throwaway | agent:consensus
- [-] Doc updates (guardrails, lexicon, SPEC deep update) — deferred until post-dogfood stabilization | agent:consensus
- [-] QR pairing UI — invite link sufficient for L1 | spec-review
- [-] "Thinking of you" one-tap message button — user decision: that's just a poke/like; clutters minimal interface | agent:consensus
- [-] Static /help page — user decision: the operator IS the help desk; no self-service recovery page needed at L1 | agent:consensus
- [-] Letters at L1 — consensus: defer entirely; validate daily text use first; revisit at L2+ | agent:consensus

