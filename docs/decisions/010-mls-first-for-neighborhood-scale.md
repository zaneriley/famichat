# ADR 010: MLS-First E2EE Direction for Family and Neighborhood Scale

**Date**: 2026-02-25  
**Status**: Accepted  
**Supersedes**: ADR 006 (Signal Protocol for End-to-End Encryption)

---

## Context

Famichat previously selected a Signal-first server-side path (ADR 006), optimized for small family groups.
Product direction now explicitly includes inter-family and neighborhood-scale communication.
That shifts the optimization target from only "2-6 participants per household" to a broader range with potentially higher group churn and larger groups.

At the same time, MLS standardization and ecosystem adoption have progressed since ADR 006:

1. MLS protocol is standardized as RFC 9420 (Proposed Standard, July 2023).
2. MLS architecture guidance is published as RFC 9750 (Informational, April 2025), including application-layer security trade-offs.
3. GSMA RCS E2EE specifications now define MLS-based interoperable E2EE procedures (v1.0 published March 13, 2025; v2.0 published July 24, 2025).
4. OpenMLS is active and production-oriented, but has had recent security advisories requiring prompt upgrade discipline.

---

## Decision

Adopt an **MLS-first** direction for E2EE, using **OpenMLS** as the primary implementation path.

This means:

1. MLS is now the default protocol direction for encrypted conversation design.
2. Signal-specific planning in earlier docs is retained only as historical context, not as the active roadmap.
3. We prioritize product compatibility with inter-family and neighborhood-scale group messaging requirements.
4. We treat crypto dependency hygiene as a first-class operational requirement (rapid patch posture).

---

## Why This Decision

### 1) Better alignment with expected product trajectory

Neighborhood and inter-family messaging pushes us toward group-oriented protocol behavior and long-term interoperability expectations.
MLS is designed for asynchronous secure group messaging from small to very large groups (RFC 9420).

### 2) Standards and ecosystem momentum

MLS is no longer "future only"; it is concretely used in industry specifications (GSMA RCS E2EE).
Choosing MLS now reduces strategic churn if product scope grows beyond single-family boundaries.

### 3) Performance model is acceptable with guardrails

OpenMLS benchmarking guidance indicates:

1. Application message send/receive can be mostly independent of group size in common cases.
2. Group operations (update/add/remove) are sensitive to tree state and churn profile.
3. Sparse trees and high fluctuation groups can materially increase operation cost.

The implication is not "MLS is always fast"; it is "MLS can meet product goals with explicit operational constraints and observability."

### 4) Honest risk profile

Recent OpenMLS advisories (2025-09 and 2026-02) show real maintenance risk.
This is manageable if we explicitly commit to dependency update SLAs and secure defaults.

---

## Performance Implications

MLS-first changes how we must reason about latency and throughput:

1. Per-message encryption/decryption costs are only one part of the budget.
2. Membership churn and commit/update cadence become top performance drivers.
3. Tree health matters; sparse-tree behavior can degrade update/remove performance.
4. Post-quantum ciphersuites can significantly increase message and state sizes, affecting bandwidth and storage.

Operationally, we must monitor:

1. `send_application_message` p50/p95/p99
2. `process_application_message` p50/p95/p99
3. `commit/update/add/remove` p50/p95/p99
4. serialized group-state size and ratchet-tree growth
5. epoch advancement lag / drift across devices

---

## Consequences

### Positive

1. Better strategic alignment with neighborhood-scale messaging.
2. Reduced risk of protocol migration churn if group scope expands.
3. Closer alignment with evolving standards ecosystem.

### Negative / Costs

1. Higher implementation and state-management complexity than the prior small-group Signal framing.
2. Stronger operational burden around dependency patching and crypto lifecycle maintenance.
3. Performance tuning must account for churn behavior, not just steady-state messaging.

---

## Guardrails

1. Keep wire format private-only unless explicitly needed.
2. Avoid enabling standalone proposals unless required by product behavior.
3. Pin OpenMLS versions and patch quickly on advisory publication.
4. Instrument and alert on commit latency and epoch drift before broad dogfooding.
5. Keep group-size and churn expectations explicit in product and infrastructure docs.

---

## Follow-up Actions

1. Update ENCRYPTION, ARCHITECTURE, ROADMAP, STATUS, and NOW docs to reflect MLS-first as authoritative direction.
2. Mark ADR 006 as superseded by this decision.
3. Rewrite Sprint 9 scope around MLS/OpenMLS key package, group state, commit lifecycle, and telemetry.
4. Ensure observability plan includes MLS-specific performance and safety metrics.

---

## References

1. RFC 9420 - The Messaging Layer Security (MLS) Protocol (July 2023)  
   https://www.rfc-editor.org/info/rfc9420
2. RFC 9750 - The Messaging Layer Security (MLS) Architecture (April 2025)  
   https://www.rfc-editor.org/info/rfc9750
3. GSMA RCS E2EE Specification v1.0 (March 13, 2025)  
   https://www.gsma.com/solutions-and-impact/technologies/networks/gsma_resources/rich-communication-suite-end-to-end-encryption-specification-version-1-0/
4. GSMA RCS E2EE Specification v2.0 (July 24, 2025)  
   https://www.gsma.com/solutions-and-impact/technologies/networks/gsma_resources/rcs-end-to-end-encryption-specification-version-2-0/
5. OpenMLS Book - Performance  
   https://book.openmls.tech/performance.html
6. OpenMLS Benchmark Notes (May 18, 2021)  
   https://blog.openmls.tech/posts/2021-05-18-openmls-first-benchmarks/
7. OpenMLS PQ Note (April 11, 2024)  
   https://blog.openmls.tech/posts/2024-04-11-pq-openmls/
8. OpenMLS advisory GHSA-qr9h-x63w-vqfm (published 2025-09-26)  
   https://osv.dev/vulnerability/GHSA-qr9h-x63w-vqfm
9. OpenMLS advisory GHSA-8x3w-qj7j-gqhf (published 2026-02-04)  
   https://osv.dev/vulnerability/GHSA-8x3w-qj7j-gqhf
