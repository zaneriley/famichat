# [DEPRECATED] ADR 002: Early Encryption Approach (Historical)

**Date**: 2025-03-10
**Status**: Deprecated and superseded
**Superseded By**: [ADR 010](010-mls-first-for-neighborhood-scale.md)

---

## Purpose of This File

This ADR is preserved only as historical context for the original pre-MLS framing.

It is **not** the active encryption decision and must not be used as implementation guidance.

---

## Historical Summary

ADR 002 captured an early hybrid-security framing:

1. E2EE for message confidentiality.
2. Field-level encryption for sensitive account/auth fields.
3. Encryption at rest for infrastructure defense-in-depth.

That framing predated the MLS-first direction now required by product scope.

---

## Canonical Sources (Use These Instead)

1. [ADR 010: MLS-first E2EE direction](010-mls-first-for-neighborhood-scale.md)
2. [ENCRYPTION.md](../ENCRYPTION.md)
3. [Sprint 9 MLS NIF contract](../sprints/9.0-mls-rust-nif-contract-deep-dive.md)
4. [Sprint 9 MLS TDD plan](../sprints/9.1-mls-contract-tdd-plan.md)

---

## Migration Note

Any references in older documents to Signal/Megolm-specific implementation details are historical and non-authoritative.

