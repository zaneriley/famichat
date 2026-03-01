# E2EE Architecture Decision Matrix (One-Page Reference)

**Date**: 2026-03-01
**Status**: Ready for decision
**Recommendation**: **Path C.1 (SPA + iframe bridge)** ✅

---

## Quick Comparison

|  | **A** (WASM+iframe) | **B** (Native) | **C.1** (SPA) ✅ | **D** (Operator trust) |
|---|---|---|---|---|
| **Real E2EE?** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Multi-device works?** | ❌ **Broken** | ✅ Yes (3 wk) | ✅ Yes (w/ recovery key) | N/A |
| **Timeline** | 6–10 wk | 12–16 wk | **6–8 wk** | 2–4 wk |
| **Team can do it now?** | ✅ JS | ❌ Needs iOS/Android | ✅ JS | ✅ Ops |
| **NIF salvage** | 40% | 0% | **70%** | 100% |
| **Server can decrypt?** | No | No | **No** | ❌ **Yes** |
| **UX on web** | OK (iframe) | None (6mo+) | **Excellent** | OK (unchanged) |
| **UX on mobile** | Web only | **Excellent** | Responsive web | Web only |
| **Risk level** | Medium | High | **Low** | Low (but wrong premise) |

---

## The Recommendation

### Path C.1: SPA + iframe Bridge

**Why it wins**:
1. **Fastest real E2EE**: 6–8 weeks (vs. 12–16 for native, 2–4 for false security).
2. **Salvages 70% of NIF**: Error handling, snapshot MAC, validation utils, all Track A hardening stays.
3. **Current team executes**: JavaScript developers. No hiring.
4. **Staged rollout**: Keep LiveView nav, replace message area with encrypted iframe SPA. Low risk.
5. **Multi-device works**: Recovery key (12-word phrase) is proven pattern.
6. **True E2EE**: Server is genuinely a relay; can't decrypt.

### Why Not the Others

| Path | Why Not | Fallback |
|------|---------|----------|
| **A** | Multi-device breaks (siloed keys per browser). User can't read old messages on new device. Deal-breaker for families. | Use in Q2 as complementary web UI if you build B. |
| **B** | 12+ weeks, requires iOS/Android engineers. Good long-term, but too slow for Q1. | Plan this for Q3 2026 as second client after C is live. |
| **D** | Not real E2EE. Server still decrypts everything. Just security theater. Only viable if you reframe product as "encrypted at rest" (not E2EE). | Use only if stakeholders explicitly don't want client-side keys (unlikely). |

---

## Implementation Roadmap (8 Weeks)

| Week | Phase | Deliverable | Status |
|------|-------|-------------|--------|
| **1–2** | Foundation | React SPA scaffold + openmls-wasm spike + iframe bridge | POC working |
| **2–3** | Single conversation | Encrypt/decrypt for direct msgs; 2-user test | E2E working |
| **3–5** | Groups + multi-device | Group msgs + device enrollment (each device is MLS member) | Multi-device test passing |
| **5–6** | Recovery key ceremony | 12-word recovery key generation & input flow | Key recovery working |
| **6–8** | Testing & hardening | Load tests, WASM optimization, WebSocket sync, offline queue | Production-ready |

**Go-live gate**: Phase 4 (recovery key) works reliably. No shipping without multi-device tested.

---

## Key Management: "Wife Gets a New Phone"

1. **Original device**: Wife logs in → app generates 12-word recovery key → she writes it down (one-time).
2. **New device**: Wife logs in with passkey → "Have a recovery key?" → enters phrase → app derives per-device key.
3. **Server**: Adds new device to group as new MLS member.
4. **Result**: New device can decrypt all future messages immediately.
5. **Old messages**: Stay on old device (user accepts "history loss" like WhatsApp). Or implement re-encryption in Q2 (~2 weeks).

**Acceptable for family use.** One-time recovery key save; subsequent onboarding is smooth.

---

## NIF Code Fate

**Not a sunk cost.** 70% reusable:

| Lines | Status | Examples |
|-------|--------|----------|
| **1,700 KEEP** | No changes | ErrorCode enum, snapshot MAC (N5), validation utilities, all Track A hardening |
| **1,000 DELETE** | Group state ops | GROUP_SESSIONS DashMap, stage/merge/commit functions, ConversationSecurityLifecycle |
| **300 REFACTOR** | Small changes | MessageService (remove encrypt call), Crypto.MLS adapter (remove 6 functions) |

**Result**: Smaller, faster NIF (1,700 lines) focused on validation + audit logging. Zero regression in hardening (all Track A tests stay).

---

## What You Tell Stakeholders

### Now
*"Messages are encrypted at rest and in transit. The server can decrypt them (it holds the keys). Appropriate for self-hosted family use with a trusted admin, but not true E2EE."*

### After Path C (End Q1)
*"Messages are encrypted on your device before leaving. The server stores ciphertext it can't decrypt. True end-to-end encryption (E2EE)."*

### After Path B (Q3, optional)
*"iOS and Android apps use device-specific keys in Keychain/EncryptedSharedPrefs. Web users have browser-based E2EE. All devices share encrypted backend; multi-device sync works seamlessly."*

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| **WASM cold start is slow** | Pre-load on first login; cache in service worker. Target <2s. |
| **Keys in localStorage can be XSS'd** | Strict CSP (no-eval, no-unsafe-inline). Keys encrypted with passkey-derived salt. |
| **Recovery key is lost by user** | Build "recovery contacts" in Q3: user designates trusted family member for key recovery. |
| **openmls-wasm doesn't exist** | Fork OpenMLS, add WASM bindings (~1 week). OpenMLS is active; PRs welcome. |
| **Multi-device keys get out of sync** | Each device is independent MLS member; no shared key to sync. Client-side only. |

---

## Immediate Next Steps (This Week)

1. **Verify openmls-wasm is viable**: Does it exist? Does it compile? Bundle size?
2. **If not**: Can we fork OpenMLS and add WASM bindings? (1-week spike)
3. **Approve Path C.1** as the decision.
4. **Start Phase 1** (React SPA scaffold) by end of week.
5. **Decision checkpoint** on openmls-wasm viability: can we commit to 6–8 week timeline?

---

## Full Documentation

- **Deep analysis**: `docs/E2EE_ARCHITECTURE_OPTIONS.md` (41 KB; all options, tradeoffs, multi-device strategies)
- **Executive summary**: `docs/E2EE_ARCHITECTURE_SUMMARY.md` (6 KB; decision rationale, timeline, risks)
- **NIF refactoring plan**: `docs/NIF_SALVAGE_PLAN.md` (20 KB; what stays, what deletes, migration checklist)
- **This document**: One-page decision matrix (you are here)

---

## Decision

**Recommended**: Path C.1 (SPA + iframe bridge)
**Timeline**: 6–8 weeks to real E2EE
**Team**: JavaScript developers; no mobile hiring needed
**Next step**: Approve; start Phase 1 spike immediately
**Checkpoint**: End of this week (openmls-wasm viability)

---

**Ready to ship real E2EE by end of March 2026.** 🎯
