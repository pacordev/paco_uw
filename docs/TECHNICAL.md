# Technical Reference

This is the detailed engineering reference for the Insurance Underwriting Rules Engine — the
data model, the two evaluation strategies, and the full table/function reference. See the
[README](../README.md) for the high-level overview; this document goes deep on the parts a
contributor needs to actually work with the schema.

## Contents

1. [Diagrams](#diagrams)
2. [How it works](#how-it-works)
3. [Running it](#running-it)
4. [Tables](#tables)
5. [Core functions](#core-functions)
6. [Project structure](#project-structure)

## Diagrams

Three interactive views of the system — pan, zoom, search, and trace relationships live in
the browser:

- [**Architecture**](https://pacordev.github.io/paco_uw/diagrams/underwriting-architecture.html) — runtime components, request path, rate limiting, and the admin key
- [**Data flow**](https://pacordev.github.io/paco_uw/diagrams/underwriting-dataflow.html) — how seed data, quote answers, and evaluation results move through the tables
- [**Sequence**](https://pacordev.github.io/paco_uw/diagrams/underwriting-sequence.html) — the full quote lifecycle call by call, including the wrong-token error path

Source specs are in `diagrams/*.json`; the `.html` files are generated from them and
published via GitHub Pages.

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
`access_token` (a random `UUID`, unique) exists because `quote_id` alone is a guessable
sequential integer — the API requires this token on every request scoped to a `quote_id`, so
one applicant can't read or overwrite another's answers just by incrementing the id.

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
| `uw_short_circuit_stop_rule(quote_id)` | The stop-rule (if any) that would end Model B's walk early — `evaluate_quote_short_circuit` calls this instead of repeating its own walk. |
| `uw_evaluation_trigger(quote_id, strategy)` | Which rule *decided* a strategy's outcome — `NULL` when nothing matched. Not stored anywhere; the API computes it fresh alongside every evaluation. |

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
  phase7_quote_access_token.sql adds quote.access_token, so a bare quote_id can't be guessed
  phase8_evaluation_trigger.sql adds "which rule decided this outcome" lookup functions
docker-compose.yml               Postgres 16, applies phase1-8 (not phase6_tests) on first run
scripts/run_tests.sh             runs phase6_tests.sql against the running container
scripts/reset_db.sh              wipes the volume and rebuilds from scratch
docs/goal.txt                    initial simple requirements I created, as a target MVP (local only)
docs/uw_plan.md                  detailed planning notes (local only)
```
