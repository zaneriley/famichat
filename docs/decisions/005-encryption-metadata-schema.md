# [DEPRECATED] ADR 005: Multi-Protocol Encryption Metadata Schema (Historical)

**Date**: 2025-10-05
**Status**: Deprecated exploratory proposal
**Superseded By**:
1. [ADR 010](010-mls-first-for-neighborhood-scale.md)
2. [Sprint 9 MLS contract](../sprints/9.0-mls-rust-nif-contract-deep-dive.md)
3. [Sprint 9 MLS TDD plan](../sprints/9.1-mls-contract-tdd-plan.md)

---

## Purpose of This File

This ADR captured an exploratory metadata-table design while protocol direction was still unsettled.

It included multi-protocol fields (Signal/Megolm/MLS). That is no longer aligned with the current MLS-first plan.

---

## Historical Value Retained

The following idea remains valid and may be reused in MLS-specific designs:

1. Promote query-critical encryption metadata from unstructured JSONB into typed/indexed fields when required by performance and operations.

---

## What Is Not Current

1. Protocol-agnostic field sets intended to support Signal/Megolm in active implementation.
2. Any schema constraints that imply non-MLS protocol paths are first-class runtime options.

---

## Canonical Sources (Use These Instead)

1. [ENCRYPTION.md](../ENCRYPTION.md)
2. [ADR 010](010-mls-first-for-neighborhood-scale.md)
3. [Sprint 9 MLS contract](../sprints/9.0-mls-rust-nif-contract-deep-dive.md)
4. [Sprint 9 MLS TDD plan](../sprints/9.1-mls-contract-tdd-plan.md)

---

## Follow-On Work

If a new encryption metadata table is still needed after MLS integration baselines are measured, create a new MLS-specific ADR with:

1. fields tied to MLS lifecycle/epoch semantics,
2. index plan tied to actual query paths,
3. migration and rollback strategy,
4. test and telemetry acceptance criteria.

