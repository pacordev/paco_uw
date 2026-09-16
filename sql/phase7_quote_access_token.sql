-- Phase 7 — quote ownership token
-- See ../README.md for the big picture.
--
-- Depends on: sql/phase1_core_schema.sql .. sql/phase6_seed_data.sql

SET search_path TO "myins";

-- quote_id is a bare sequential integer - without this, anyone who can guess/increment it
-- can read or overwrite someone else's quote_answer rows. This is a random per-quote secret
-- handed back once at creation time (POST /quotes); the API checks it on every later request
-- scoped to that quote_id instead of trusting the id alone.
--
-- gen_random_uuid() is built into Postgres core since v13 (no pgcrypto extension needed).
ALTER TABLE quote
	ADD COLUMN access_token UUID NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE quote
	ADD CONSTRAINT uq_quote_access_token UNIQUE (access_token);
