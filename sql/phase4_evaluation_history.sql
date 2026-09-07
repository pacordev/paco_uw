-- Phase 4 — evaluation persistence & audit trail
-- See ../uw_plan.md for the full build plan.
--
-- Depends on: sql/phase1_core_schema.sql, sql/phase3_rules_engine.sql

SET search_path TO "myins";


-- Persisted evaluation history: one row per evaluation run, so outcomes are
-- auditable and both models' results can coexist even when they diverge.
-- evaluate_quote_full/_short_circuit stay pure/side-effect-free; this table
-- + wrapper function are the only place that writes an outcome.
CREATE TABLE quote_evaluation (
	id SERIAL PRIMARY KEY,
	quote_id INT NOT NULL REFERENCES quote(id) ON DELETE CASCADE,
	strategy TEXT NOT NULL CHECK (strategy IN ('full', 'short_circuit')),
	outcome uw_outcome NOT NULL,
	evaluated_at TIMESTAMP NOT NULL DEFAULT clock_timestamp()
	)
;

CREATE INDEX idx_quote_evaluation_quote_id
	ON quote_evaluation (quote_id, strategy, evaluated_at DESC, id DESC);


-- Runs the requested model and records the result, so the API gets
-- persistence for free instead of re-implementing the INSERT itself.
CREATE OR REPLACE FUNCTION evaluate_and_record_quote(
	p_quote_id INT,
	p_strategy TEXT -- 'full' or 'short_circuit'
) RETURNS uw_outcome
LANGUAGE plpgsql
AS $$
DECLARE
	v_outcome uw_outcome;
BEGIN
	IF p_strategy = 'full' THEN
		v_outcome := evaluate_quote_full(p_quote_id);
	ELSIF p_strategy = 'short_circuit' THEN
		v_outcome := evaluate_quote_short_circuit(p_quote_id);
	ELSE
		RAISE EXCEPTION 'Unknown evaluation strategy: % (expected ''full'' or ''short_circuit'')', p_strategy;
	END IF;

	INSERT INTO quote_evaluation (quote_id, strategy, outcome)
	VALUES (p_quote_id, p_strategy, v_outcome);

	RETURN v_outcome;
END;
$$;


-- Most recent outcome per quote/strategy, for quick "what's the status" lookups
-- without needing to know about quote_evaluation's history semantics.
CREATE OR REPLACE VIEW quote_latest_evaluation AS
SELECT DISTINCT ON (quote_id, strategy)
	quote_id, strategy, outcome, evaluated_at
FROM quote_evaluation
ORDER BY quote_id, strategy, evaluated_at DESC, id DESC;
