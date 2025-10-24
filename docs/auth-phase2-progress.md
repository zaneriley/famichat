# Phase 2 (Token Ledger) – Progress Snapshot

- **2a (Additive)** – ✅ Deployed. Columns `kind`, `audience`, `subject_id` exist with concurrent indexes and are populated on issuance.
- **2b (Enforce)** – ✅ Shipped.
  - Existing rows normalized (no legacy rows in current env).
  - Schema now enforces `NOT NULL` + `CHECK(kind IN …)` and unique `(kind, token_hash)` idx.
  - Issuance telemetry emits `subject_id_present` / `missing_subject_id` for early drift detection.

Phase 2 considered complete; no backfill required for greenfield deployments.
