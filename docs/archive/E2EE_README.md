# E2EE Architecture Analysis — Complete Documentation

**Date**: 2026-03-01
**Status**: Ready for stakeholder decision
**Audience**: Technical leadership, product stakeholders, implementation team leads

---

## Overview

Famichat currently violates end-to-end encryption (E2EE) semantics: MLS private keys are held server-side in a Rust NIF, and the server decrypts all messages to render them in LiveView. This analysis evaluates 4 realistic paths to fix this, given the team's constraints.

**Bottom line**: Recommend **Path C.1 (SPA + iframe bridge)** for immediate execution. Achieves true E2EE in 6–8 weeks, salvages 70% of the hardened Rust NIF, fits the current team's JavaScript skill set, and enables multi-device sync via recovery key.

---

## Document Guide

### 1. **E2EE_DECISION_MATRIX.md** (Start here — 1 page)

**Purpose**: One-page quick reference for decision-makers.

**Contains**:
- Comparison table of all 4 paths (timeline, E2EE, multi-device, team fit, NIF salvage).
- Why Path C.1 wins.
- Why not the others.
- 8-week implementation roadmap (summary).
- Key management story ("wife gets a new phone").
- NIF salvage overview.
- Immediate next steps.

**Read time**: 5 minutes
**Best for**: Stakeholders, managers, decision-makers

---

### 2. **E2EE_ARCHITECTURE_SUMMARY.md** (Executives — 6 KB)

**Purpose**: Executive summary for leadership approvals.

**Contains**:
- The problem (server can decrypt everything).
- The solution (client-side MLS keys).
- Why Path C.1 wins (fastest, salvages code, team can do it).
- What happens to the Rust NIF (70% reusable).
- 8-week roadmap with phases.
- Risk & mitigation table.
- What you tell users now vs. Q1 2026.

**Read time**: 10 minutes
**Best for**: CTO, product lead, stakeholders approving the decision

---

### 3. **E2EE_ARCHITECTURE_OPTIONS.md** (Deep analysis — 41 KB)

**Purpose**: Comprehensive analysis of all 4 paths. This is the authoritative reference.

**Contains**:
- Executive summary (problem, solution, recommendation).
- Current state (2,700 lines of hardened NIF, proven test suite, multi-device complexity).
- Architectural constraints (self-hosted, family use, OpenMLS is the direction, NIF is hardened).
- **Path A** (LiveView + WASM in iframe): Why multi-device breaks.
- **Path B** (Native iOS/Android): Why it's too slow for Q1; viable Q3.
- **Path C** (SPA + REST API): How it works, stages, tradeoffs, recovery key ceremony.
- **Path C.1 specifically** (iframe bridge): Minimizes rewrite risk.
- **Path D** (Operator trust + HSM): Why it's security theater (server still decrypts).
- Detailed comparison table (timeline, NIF salvage, team fit, security, UX).
- **Implementation roadmap** (5 phases, 8 weeks).
- Critical design decisions (localStorage vs IndexedDB, recovery key vs cloud backup, message search, ciphertext format, WebSocket sync).
- Honest NIF sunk-cost analysis.
- Appendix: OpenMLS WASM viability check.

**Read time**: 30–45 minutes (or 10 if you skim headings)
**Best for**: Technical leads, architects, engineers making detailed trade-offs

---

### 4. **NIF_SALVAGE_PLAN.md** (Implementation guide — 20 KB)

**Purpose**: Detailed refactoring plan for the Rust NIF and Elixir lifecycle code.

**Contains**:
- Current state (2,723 lines, Track A hardening, tests).
- **Tier 1: Keep** (~1,700 lines): Error codes, snapshot MAC, validation utilities (no changes needed).
- **Tier 2: Delete** (~1,000 lines): GROUP_SESSIONS DashMap, stage/merge/commit ops, ConversationSecurityLifecycle, persistent state store.
- **Tier 3: Refactor** (~300 lines): MessageService, Crypto.MLS adapter (small, safe changes).
- **Tier 4: Expand** (~300 lines): New server-side validation functions, audit logging (optional).
- Code reuse metrics (70% salvage).
- Migration checklist (6 phases, weeks 1–8).
- Risk mitigation (what could break, how to detect).
- Future extensions (zero-knowledge proofs, key rotation).

**Read time**: 20 minutes
**Best for**: Engineers executing the refactoring, ensuring zero regression in hardening

---

## How to Use This Document Set

### If You're Approving the Decision (Next 24 Hours)
1. Read **E2EE_DECISION_MATRIX.md** (5 min).
2. Read **E2EE_ARCHITECTURE_SUMMARY.md** (10 min).
3. Ask clarifying questions (see "Next Steps" below).
4. Approve Path C.1 or request deeper analysis.

### If You're Implementing (Next 8 Weeks)
1. Read **E2EE_ARCHITECTURE_SUMMARY.md** (orientation; 10 min).
2. Read **E2EE_ARCHITECTURE_OPTIONS.md** sections on Path C.1 (detailed design; 20 min).
3. Read **NIF_SALVAGE_PLAN.md** (refactoring guide; 20 min).
4. Use **NIF_SALVAGE_PLAN.md** migration checklist as your sprint board.
5. Reference **E2EE_ARCHITECTURE_OPTIONS.md** implementation roadmap (Phases 1–5).

### If You're Reviewing (Later)
1. Use **E2EE_DECISION_MATRIX.md** to understand why Path C.1 was chosen.
2. Use **NIF_SALVAGE_PLAN.md** to understand what code was deleted and why.
3. Use **E2EE_ARCHITECTURE_OPTIONS.md** Appendix to understand what questions were asked about openmls-wasm viability.

---

## Key Findings (TL;DR)

### The Problem
- MLS keys are server-side (in Rust NIF DashMap).
- Server decrypts all messages to render LiveView.
- A compromised server (or bad-faith admin) can read all family conversations retroactively.
- Current system is "encrypted at rest + TLS in transit" — not E2EE.

### The Solution
- Move MLS key generation and encryption to the client (browser).
- Server becomes a relay: stores encrypted blobs it cannot decrypt.
- Client decrypts messages locally.
- This is true E2EE.

### Why Path C.1
1. **Fastest E2EE**: 6–8 weeks (vs. 12–16 for native, false security for operator trust).
2. **70% NIF salvage**: Error handling, snapshot MAC (N5), validation, all Track A hardening stays. Only delete group state ops (~1,000 lines).
3. **Team can execute now**: JavaScript developers. No hiring.
4. **Staged rollout**: Keep LiveView nav (using existing framework), replace message area with encrypted iframe SPA. Low risk of breaking the entire app.
5. **Multi-device works**: Recovery key (12-word phrase) is a proven pattern (Signal, Wire).
6. **Server is genuinely a relay**: Can't decrypt anything. Not security theater.

### Timeline
- **Week 1–2**: Foundation (React scaffold, openmls-wasm spike, iframe bridge).
- **Week 2–3**: Single conversation PoC (direct messages working).
- **Week 3–5**: Groups + multi-device enrollment.
- **Week 5–6**: Recovery key ceremony (user enters 12-word phrase on new device).
- **Week 6–8**: Testing, performance, hardening, production readiness.

### Multi-Device Key Management
- **Original device**: User logs in → app generates recovery key (12-word phrase) → user saves it.
- **New device**: User logs in with passkey → enters recovery key → app derives per-device MLS key.
- **Server**: Adds new device to group as new MLS member.
- **Result**: New device can decrypt future messages immediately. Old messages stay on old device (acceptable; users understand this pattern).

### NIF Code Fate
- **Keep**: ~1,700 lines (error handling, snapshot MAC, validation, hardening).
- **Delete**: ~1,000 lines (group state ops, ConversationSecurityLifecycle, persistent state store).
- **Refactor**: ~300 lines (MessageService, Crypto.MLS adapter).
- **Add**: ~300 lines (server-side validation, optional audit logging).
- **Result**: Smaller (1,700 lines), faster (no group state serialization), cleaner NIF.

---

## What You Tell Stakeholders

### Current State (Before Path C)
*"Messages are encrypted at rest (Cloak vault) and in transit (TLS). The server can decrypt them because it holds the keys. This is appropriate for self-hosted family use with a trusted admin, but it's not end-to-end encrypted (E2EE)."*

### After Path C (End Q1 2026)
*"Messages are encrypted on your device before they leave your phone or computer. The server stores ciphertext and acts as a relay; it cannot decrypt your messages. This is true end-to-end encryption (E2EE)."*

### Optional: After Path B (Q3 2026)
*"iOS and Android users have native apps with true E2EE; keys are stored in device Keychain/EncryptedSharedPrefs. Web users continue to use the browser SPA with client-side encryption. All platforms share the same encrypted backend; multi-device sync works seamlessly across all devices."*

---

## Immediate Next Steps (This Week)

1. **Read documents** (start with decision matrix; 5 min).
2. **Ask clarifying questions** (see below).
3. **Verify openmls-wasm viability**:
   - Does OpenMLS have an official WASM build / wasm-bindgen bindings?
   - If not, can we fork and add WASM support (~1 week effort)?
   - What's the bundle size (target: <2 MB gzipped)?
4. **Approve Path C.1** as the architectural direction.
5. **Assign implementation lead** for Phase 1 (React SPA scaffold).
6. **Start Phase 1 spike** by end of week.
7. **Decision checkpoint** (end of Phase 1): Confirm openmls-wasm is viable; commit to 6–8 week timeline.

---

## Common Questions

### Q: Can we use Path D (operator attestation) instead?
**A**: Path D is not real E2EE. The server still decrypts everything. It only works if you reframe the product as "encrypted at rest + audit trail" (not E2EE). For families, E2EE is a core value; users expect the server can't read their messages. Recommend Path C.

### Q: Why not Path B (native apps) immediately?
**A**: Path B requires 12–16 weeks and iOS/Android engineers. Path C achieves real E2EE in 6–8 weeks with your current JavaScript team. Plan Path B for Q3 2026 as a second client *after* the browser E2EE is live and proven.

### Q: What if openmls-wasm doesn't exist?
**A**: We fork OpenMLS and add WASM bindings ourselves (~1 week effort). OpenMLS is active and maintained; they accept PRs. Worst case, you compile openmls to WASM via wasm-bindgen yourself. This is a known, manageable task.

### Q: Will users lose their message history on new devices?
**A**: By default, yes (like WhatsApp). Old messages stay on old device; new device starts fresh post-join. Optional: implement re-encryption ceremony in Q2 (~2 weeks) so new devices can access old messages via server re-encryption to new device's key.

### Q: What about offline messages?
**A**: Implement client-side queue: if user goes offline, messages are queued locally and synced when online. This is standard mobile pattern; included in Phase 5 testing.

### Q: Is the 70% NIF salvage rate realistic?
**A**: Yes. Error handling, snapshot MAC, validation utilities are independent and reusable. Group state ops (1,000 lines) are tightly coupled to server-side MLS; they get deleted. But they're not wasted — they validated the architecture. See NIF_SALVAGE_PLAN.md for line-by-line breakdown.

### Q: What if server security is breached? Can attackers read old messages?
**A**: **Before Path C** (server holds keys): Yes, all messages are readable (forward secrecy broken).
**After Path C** (client holds keys): No, server doesn't have keys, so attackers can't decrypt. MLS provides forward secrecy (old message keys are deleted after use). A 2-day-old message key doesn't exist on server or client; it can't be decrypted even if attackers steal the database.

### Q: Can the admin force-decrypt if they have database access?
**A**: **Before Path C** (server NIF holds keys in memory): Yes, admin can modify NIF code or attach debugger to extract keys. **After Path C** (keys on client only): No, admin has no access to client keys. Admin can see ciphertext and metadata (conversation, sender, timestamp) but not plaintext. This is the fundamental difference.

---

## References

1. RFC 9420 — The Messaging Layer Security (MLS) Protocol: https://www.rfc-editor.org/info/rfc9420
2. RFC 9750 — The Messaging Layer Security (MLS) Architecture: https://www.rfc-editor.org/info/rfc9750
3. OpenMLS Book — Performance: https://book.openmls.tech/performance.html
4. ADR 010 — MLS-First Direction (Famichat): `docs/decisions/010-mls-first-for-neighborhood-scale.md`
5. Signal's E2EE & Multi-Device Design: https://signal.org/docs/
6. WASM + Rust + Crypto: https://github.com/rustwasm/wasm-bindgen (Rust WASM guide)

---

## Document Maintenance

- **Last updated**: 2026-03-01
- **Author**: Architecture Analysis (Famichat Team)
- **Status**: Ready for stakeholder review and decision
- **Next review**: After Phase 1 spike (openmls-wasm viability confirmed)

---

## Navigation

- **Quick decision**: Start with `E2EE_DECISION_MATRIX.md`
- **For executives**: Read `E2EE_ARCHITECTURE_SUMMARY.md`
- **For detailed analysis**: Read `E2EE_ARCHITECTURE_OPTIONS.md`
- **For implementation**: Read `NIF_SALVAGE_PLAN.md`
- **For this overview**: You're reading it now

---

**Ready to ship real E2EE by end of March 2026.** 🚀
