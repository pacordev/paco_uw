-- Phase 1 — core entity schema (quote-based naming)
-- See ../uw_plan.md for the full build plan.
--
-- Scope: products, the question pool, product-to-question linkage (ordering),
-- and the quote/answer pair everything else hangs off of. No rules or
-- evaluation logic yet (Phase 3) — this is the data these will operate on.

SET CLIENT_ENCODING TO 'UTF8';
CREATE SCHEMA IF NOT EXISTS myins;
SET search_path TO "myins";


-- Insurance products. Adding a new product is a data change: one row here
-- plus its questions/rules, never a code/schema change.
CREATE TABLE insurance_product (
	id          SERIAL PRIMARY KEY,
	code        TEXT UNIQUE NOT NULL,
	name        TEXT NOT NULL,
	description TEXT
);


-- Underwriting questions, shared pool across products.
CREATE TABLE uw_question (
	id           SERIAL PRIMARY KEY,
	code         TEXT UNIQUE NOT NULL,
	text         TEXT NOT NULL,
	answer_type  TEXT NOT NULL,  -- 'boolean', 'number', 'text', 'enum'
	enum_options TEXT[]          -- only used when answer_type = 'enum'
);


-- Links a question to a product with its position in the interview order.
-- Both Model A and Model B depend on `sequence` being a total, stable order
-- per product (Model B walks it; Model A doesn't care about order but the
-- interview UI does).
CREATE TABLE product_question (
	id           SERIAL PRIMARY KEY,
	product_id   INT NOT NULL REFERENCES insurance_product(id),
	question_id  INT NOT NULL REFERENCES uw_question(id),
	sequence     INT NOT NULL,
	is_mandatory BOOLEAN NOT NULL DEFAULT TRUE
);


-- A quote: one applicant's run through a product's questions. Everything
-- underwriting-related (answers, evaluations) hangs off quote_id, never off
-- any upstream "application" concept.
CREATE TABLE quote (
	id         SERIAL PRIMARY KEY,
	product_id INT NOT NULL REFERENCES insurance_product(id),
	created_at TIMESTAMP NOT NULL DEFAULT now()
);


-- Answers given for a quote. Stored as text and cast per answer_type at
-- evaluation time (see Phase 3's uw_condition_matches).
CREATE TABLE quote_answer (
	id          SERIAL PRIMARY KEY,
	quote_id    INT NOT NULL REFERENCES quote(id),
	question_id INT NOT NULL REFERENCES uw_question(id),
	answer_text TEXT NOT NULL
);
