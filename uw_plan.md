# Underwriting Rules Engine — Build Plan

Source of truth for requirements: `goal.txt`.

Two decisions locked in before starting:
- `quote` replaces `application` 1:1 (rename, not a new entity).
- `expected_answer` is an informational column on `product_question` only — it does not drive outcomes. `uw_rule` / `uw_rule_condition` remain the single source of truth for evaluation logic.

## Phases

- [x] **Phase 1 — Core entity schema (quote-based naming)**
  `insurance_product`, `uw_question`, `product_question`, `quote`, `quote_answer`.
  File: `sql/phase1_core_schema.sql`

- [x] **Phase 2 — Expected answer**
  Add `product_question.expected_answer TEXT` (nullable, informational only).
  File: `sql/phase2_expected_answer.sql`

- [x] **Phase 3 — Rules engine + evaluation functions**
  `uw_rule`, `uw_rule_condition`, `uw_outcome` enum, `uw_outcome_rank`,
  `uw_condition_matches`, `uw_rule_matches`,
  `evaluate_quote_full` (Model A), `evaluate_quote_short_circuit` (Model B).
  File: `sql/phase3_rules_engine.sql`

- [x] **Phase 4 — Evaluation persistence & audit trail**
  `quote_evaluation` (one row per evaluation run — history, not overwrite),
  `evaluate_and_record_quote` (runs a strategy and persists the outcome),
  `quote_latest_evaluation` (view: most recent outcome per quote/strategy).
  File: `sql/phase4_evaluation_history.sql`

- [x] **Phase 5 — Production hardening**
  - `UNIQUE(product_id, question_id)` and `UNIQUE(product_id, sequence)` on `product_question`.
  - `UNIQUE(quote_id, question_id)` on `quote_answer`.
  - Validation trigger on `quote_answer.answer_text` against `answer_type`/`enum_options`.
  - Confirm indexes on FK columns used in joins (`uw_rule_condition.rule_id`/`question_id`, etc.).
  File: `sql/phase5_hardening.sql`

- [x] **Phase 6 — Seed data & tests**
  8 demo products (LIFE_SIMPLE, AUTO_BASIC, HOME_BASIC, HEALTH_BASIC, TRAVEL_BASIC,
  PET_BASIC, RENTERS_BASIC, UMBRELLA_BASIC), each with questions (+ `expected_answer`),
  rules, and 2-3 demo quotes. Full test suite: unit-level building blocks plus a formal
  assertion block per product, including a deliberate Model A/B divergence case per new product.
  80/80 tests passing against Postgres 16.
  Files: `sql/phase6_seed_data.sql`, `sql/phase6_tests.sql`

## Explicitly out of scope for v1
- Rule versioning/history (a rule edit affects future evals of past quotes — no snapshot-at-eval-time).
- Multi-quote-per-application modeling.

## Running it — Docker

`docker-compose.yml` runs Postgres 16 with a named volume (`uw_pgdata`) for persistence.
Phases 1-6 seed data (not the test suite) are bind-mounted into
`/docker-entrypoint-initdb.d/`, which Postgres only runs once, on a genuinely empty data
directory — so `docker compose up -d` builds the schema + seed data on first run, and every
run after that just reuses the volume, preserving any changes/additions made since.

- `docker compose up -d` — start (builds on first run, reuses data after)
- `scripts/run_tests.sh` — run the Phase 6 test suite on demand (not part of init — it
  inserts throwaway `T_*` test rows that shouldn't live in real seed data). Self-cleaning:
  it deletes its own leftover `T_*` rows at the start, so it's safe to run repeatedly
  against a live database without a reset in between.
- `scripts/reset_db.sh` — wipe the volume and rebuild from scratch (prompts for confirmation)

Verified: fresh init loads exactly 8 products / 21 quotes with zero test pollution; a
manually inserted row survived a full `docker compose down` + `up` (container recreated,
volume untouched).

---

# Part 2 — API Layer (planned, not started)

Goal: a thin REST API so a frontend can (1) pick a product, (2) fetch its questions to render
dynamically, (3) submit answers, (4) evaluate, (5) show the result. The API must stay a thin
orchestration layer over the existing SQL — no business rules re-implemented in application
code, so "new product/rule = data change" stays true at this layer too.

Backend stack: **Python + FastAPI**.

## Endpoints (draft contract)
- `GET /products` — list `{code, name, description}`
- `GET /products/{code}/questions` — ordered `{question_code, text, answer_type, enum_options, sequence, is_mandatory}`.
  **Must exclude `expected_answer`** — leaking it to a public/applicant-facing client tells them the "correct" answer.
- `POST /quotes` `{product_code}` → `{quote_id}`
- `POST /quotes/{quote_id}/answers` `{answers: [{question_code, answer_text}, ...]}` (batch submit)
- `POST /quotes/{quote_id}/evaluate` `{strategy: "full" | "short_circuit"}` → `{outcome, evaluated_at}`
- `GET /quotes/{quote_id}` — status + latest evaluation(s) (convenience, for a confirmation screen)

## Phases

- [ ] **Phase A — Stack & scaffold**
  Python + FastAPI. DB connection pooling TBD (e.g. asyncpg/psycopg). No new migrations
  tool — schema changes continue as new numbered files in `sql/`, applied in order (same
  as Phases 1-6).

- [ ] **Phase B — Read endpoints**
  `GET /products`, `GET /products/{code}/questions`. Read-only, no risk of corrupting state.

- [ ] **Phase C — Quote creation & answer submission**
  `POST /quotes`, `POST /quotes/{quote_id}/answers`. Must translate DB errors (unknown
  product_code → 404; the Phase 5 validation trigger rejecting a bad answer_text → 422 with a
  clear message) instead of leaking raw SQL errors to the client.

- [ ] **Phase D — Evaluation endpoint**
  `POST /quotes/{quote_id}/evaluate`, thin wrapper over `evaluate_and_record_quote`. Caller
  picks the strategy explicitly (both Model A and Model B stay reachable) — no auto-evaluate
  on last answer, keeps the contract simple and frontend-controlled.

- [ ] **Phase E — Cross-cutting concerns**
  Consistent error/response shape, CORS (if frontend is a different origin), and a decision on
  auth (public applicant-facing vs. internal-only tool) — deferred until this phase since it
  changes significantly depending on the answer.

- [ ] **Phase F — API-level tests**
  Contract tests hitting real endpoints against a test DB (reusing `sql/phase6_seed_data.sql`),
  mirroring the coverage the SQL test suite already has at the DB layer.
