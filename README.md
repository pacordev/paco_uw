# Underwriting Rules Engine

A data-driven insurance underwriting engine, built entirely in PostgreSQL. Products,
questions, and rules all live in tables — adding a new product or tweaking a rule is just a
data change, not a code change. If you want the full requirements, check `goal.txt`; for the
full build history and the API plan we haven't started yet, see `uw_plan.md`.

## How it works

An applicant works through a **quote**: we show them a product's questions in order, they
answer, and then we run those answers against the product's rules to get a decision —
`accept`, `increase_premium`, `refer_to_insurer`, or `decline`.

We support two evaluation strategies side by side:

- **Model A — full evaluation** (`evaluate_quote_full`): looks at every answer, checks every
  rule, and gives back the single worst outcome out of everything that matched.
- **Model B — short-circuit evaluation** (`evaluate_quote_short_circuit`): walks the questions
  in order and bails out as soon as a rule flagged `stop_evaluation` fully matches, without
  bothering to look at later answers. If nothing stops the walk, it just falls back to
  whatever Model A would've said.

These two can legitimately disagree with each other — Model B might return something milder
than Model A if a worse rule only becomes decidable further down the question list. We
seeded a demo quote for every product that shows this divergence on purpose, so it's easy to
see (check `sql/phase6_tests.sql`).

## Running it

```bash
docker compose up -d          # first run builds schema + seed data; after that it just reuses it
scripts/run_tests.sh          # runs the 80-test suite on demand, not part of container init - safe to run repeatedly, cleans up after itself
scripts/reset_db.sh           # nukes the volume and rebuilds from scratch, e.g. after editing a sql/ file
```

You need a `.env` file — see `docker-compose.yml` for what it expects, it won't start without
one. Data sticks around in the `uw_pgdata` Docker volume across restarts, so nothing gets
wiped unless you ask for it.

## Tables

### Products & questions — the interview definition

**`insurance_product`** — one row per product (`LIFE_SIMPLE`, `AUTO_BASIC`, etc.). Adding a
new product is just inserting a row here, plus its questions and rules below.

**`uw_question`** — the shared pool of underwriting questions, reusable across products.
Each one has an `answer_type` (`boolean`, `number`, `text`, or `enum`); `enum_options` holds
the allowed values when it's an enum.

**`product_question`** — links a question to a product, with where it sits in the interview
(`sequence`) and whether it's required (`is_mandatory`). It also carries `expected_answer` —
just an informational field for what a "clean" answer looks like, doesn't drive evaluation at
all, and should never be exposed to an applicant-facing client (that'd basically hand them the
answer key). `UNIQUE(product_id, question_id)` and `UNIQUE(product_id, sequence)` keep the
order unambiguous, which Model B relies on.

### Quotes & answers — one applicant's run through a product

**`quote`** — one applicant's attempt at a product. This is the anchor for everything else —
answers and evaluation results are always tied to a `quote_id`, never to an "application."

**`quote_answer`** — the actual answers, stored as text and cast to the right type when we
evaluate. `UNIQUE(quote_id, question_id)` means one answer per question per quote. A trigger
(`quote_answer_validate`) rejects anything that doesn't fit the question's
`answer_type`/`enum_options` before it even gets written, so garbage data never makes it to
the evaluation functions.

### Rules — where the actual decisions come from

**`uw_outcome`** (a type, not a table) — the four possible decisions: `accept`,
`increase_premium`, `refer_to_insurer`, `decline`.

**`uw_rule`** — a named rule for a product (like "Smoker with high BMI"). It only fires when
*all* of its conditions match — that's what lets us do compound rules. `priority` is just a
tie-breaker for when a couple of matched rules land on the same severity. `stop_evaluation`
says whether Model B is allowed to stop the walk on this one.

**`uw_rule_condition`** — one AND-ed condition on a rule (`question_id`, `operator`, `value`).
A rule with N of these needs all N to hold; a rule with zero conditions never matches (didn't
want rules matching vacuously by accident).

**`uw_outcome_rank`** — severity ranking (`accept`=1 ... `decline`=4) that Model A uses to
pick the single worst outcome out of everything that matched.

### Evaluation history — so we can audit what happened

**`quote_evaluation`** — one row per evaluation run. We never overwrite these, so both
strategies' results stick around even when they disagree, and every past decision stays
auditable. The only thing that writes here is `evaluate_and_record_quote` — the evaluation
functions themselves don't touch the database, they just compute.

**`quote_latest_evaluation`** (view) — the latest row per `(quote_id, strategy)`, for when you
just want "what's the current status" without caring about the history table's rules.

## Core functions

| Function | What it does |
|---|---|
| `uw_condition_matches(operator, condition_value, answer_text, answer_type)` | The generic single-condition check, dispatched by answer type. An unanswered question never matches. |
| `uw_rule_matches(quote_id)` | Which rules fully match a quote's answers. |
| `evaluate_quote_full(quote_id)` | Model A — worst outcome across everything that matched. |
| `evaluate_quote_short_circuit(quote_id)` | Model B — stops early on a matching stop-rule, falls back to Model A otherwise. |
| `evaluate_and_record_quote(quote_id, strategy)` | Runs a strategy and saves the outcome to `quote_evaluation`. Only function that actually writes an outcome. |

## Where things stand

**The database (done):** we built this in 6 phases, each one a separate file in `sql/`, and
all 80 tests are green against Postgres 16.

1. Core schema — products, questions, quote, quote_answer
2. `expected_answer` added to `product_question`
3. Rules engine — `uw_rule`, conditions, Model A / Model B
4. Evaluation history — `quote_evaluation`, `evaluate_and_record_quote`
5. Production hardening — uniqueness constraints, indexes, the answer-validation trigger
6. Seed data (8 products) + the full test suite

We deliberately left a couple of things out of v1: rule versioning (editing a rule changes
how *past* quotes would re-evaluate — no snapshotting), and multi-quote-per-application
modeling.

**The API layer (planned, not started):** we're building this in Python + FastAPI, as a thin
layer that just calls into the SQL above — no business logic duplicated in app code. Draft
contract:

- `GET /products`
- `GET /products/{code}/questions` (never returns `expected_answer` — that'd leak the answer key)
- `POST /quotes` → `{quote_id}`
- `POST /quotes/{quote_id}/answers`
- `POST /quotes/{quote_id}/evaluate` → `{outcome}`
- `GET /quotes/{quote_id}` (status/history)

`uw_plan.md` is the living version of this — phase-by-phase, checked off as we go — so check
there for anything more current than what's written here.

## Project structure

```
sql/
  phase1_core_schema.sql        products, questions, quote, quote_answer
  phase2_expected_answer.sql    adds product_question.expected_answer
  phase3_rules_engine.sql       uw_rule, conditions, Model A / Model B functions
  phase4_evaluation_history.sql quote_evaluation, evaluate_and_record_quote, latest view
  phase5_hardening.sql          uniqueness constraints, indexes, answer-validation trigger
  phase6_seed_data.sql          8 demo products with questions, rules, and demo quotes
  phase6_tests.sql              80-assertion test suite (unit-level + per-product demo checks)
docker-compose.yml               Postgres 16, applies phase1-6_seed_data on first run
scripts/run_tests.sh             runs phase6_tests.sql against the running container
scripts/reset_db.sh              wipes the volume and rebuilds from scratch
uw_plan.md                       full build history + the API layer plan we haven't started
```
