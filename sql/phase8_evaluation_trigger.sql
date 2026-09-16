-- Phase 8 — evaluation trigger lookup
-- See ../README.md for the big picture.
--
-- Depends on: sql/phase3_rules_engine.sql (uw_rule_matches, uw_outcome_rank,
-- evaluate_quote_full)
--
-- Purely additive: no new table or column, quote_evaluation is untouched. The one existing
-- function this file changes is evaluate_quote_short_circuit, and only its body - same
-- signature, same input/output contract, re-verified against phase6_tests.sql's existing
-- assertions after this file runs. Its walk moves into uw_short_circuit_stop_rule below so
-- it has exactly one home instead of being copy-pasted into a second function.
--
-- Lets the API answer "which rule decided this outcome, and which answer(s) drove it"
-- without duplicating rule-matching logic at the application layer - see
-- underwritting_api/app/quotes.py's evaluate_quote for how it's used.

SET search_path TO "myins";


-- The walk from evaluate_quote_short_circuit, extracted so it has exactly one home:
-- returns the id of the first stop-rule whose questions are all reachable and all match,
-- walking product_question in sequence order. NULL if nothing stops the walk.
CREATE OR REPLACE FUNCTION uw_short_circuit_stop_rule(p_quote_id INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
	v_product_id INT;
	v_seq        INT;
	v_match      RECORD;
BEGIN
	SELECT product_id INTO v_product_id FROM quote WHERE id = p_quote_id;

	FOR v_seq IN
		SELECT DISTINCT pq.sequence
		FROM product_question pq
		WHERE pq.product_id = v_product_id
		ORDER BY pq.sequence
	LOOP
		FOR v_match IN
			SELECT r.id
			FROM uw_rule r
			WHERE r.product_id = v_product_id
			  AND r.stop_evaluation = TRUE
			  AND EXISTS (SELECT 1 FROM uw_rule_condition rc WHERE rc.rule_id = r.id)
			  -- every question this rule needs must already be reachable at this point
			  AND NOT EXISTS (
					SELECT 1
					FROM uw_rule_condition rc
					JOIN product_question pq2
					   ON pq2.product_id = v_product_id
					  AND pq2.question_id = rc.question_id
					WHERE rc.rule_id = r.id
					  AND pq2.sequence > v_seq
			  )
			  -- and every one of its conditions must actually match
			  AND NOT EXISTS (
					SELECT 1
					FROM uw_rule_condition rc
					JOIN uw_question q ON q.id = rc.question_id
					LEFT JOIN quote_answer qa
						   ON qa.quote_id = p_quote_id
						  AND qa.question_id = rc.question_id
					WHERE rc.rule_id = r.id
					  AND NOT uw_condition_matches(rc.operator, rc.value, qa.answer_text, q.answer_type)
			  )
			ORDER BY r.priority
		LOOP
			RETURN v_match.id;
		END LOOP;
	END LOOP;

	RETURN NULL;
END;
$$;


-- evaluate_quote_short_circuit, rewritten to call the walk above instead of repeating it.
-- Same signature, same behavior (falls back to evaluate_quote_full when nothing stops the
-- walk) - re-verified against phase6_tests.sql's existing assertions.
CREATE OR REPLACE FUNCTION evaluate_quote_short_circuit(p_quote_id INT)
RETURNS uw_outcome
LANGUAGE sql
AS $$
	SELECT COALESCE(
		(SELECT outcome FROM uw_rule WHERE id = uw_short_circuit_stop_rule(p_quote_id)),
		evaluate_quote_full(p_quote_id)
	);
$$;


-- Model A's trigger: the same tie-break evaluate_quote_full uses (worst severity, then
-- lowest priority) via the same uw_rule_matches it already calls - just the rule id
-- instead of its outcome. NULL when nothing matched (the 'accept' default has no rule to
-- point to).
CREATE OR REPLACE FUNCTION uw_evaluation_trigger_full(p_quote_id INT)
RETURNS INT
LANGUAGE sql
AS $$
	SELECT m.rule_id
	FROM uw_rule_matches(p_quote_id) m
	JOIN uw_outcome_rank rnk ON rnk.outcome = m.outcome
	ORDER BY rnk.severity DESC, m.priority ASC
	LIMIT 1;
$$;


-- Which rule decided a quote's outcome under a given strategy. NULL means the 'accept'
-- default with nothing matched.
CREATE OR REPLACE FUNCTION uw_evaluation_trigger(p_quote_id INT, p_strategy TEXT)
RETURNS INT
LANGUAGE sql
AS $$
	SELECT CASE p_strategy
		WHEN 'short_circuit' THEN
			COALESCE(uw_short_circuit_stop_rule(p_quote_id), uw_evaluation_trigger_full(p_quote_id))
		ELSE
			uw_evaluation_trigger_full(p_quote_id)
	END;
$$;
