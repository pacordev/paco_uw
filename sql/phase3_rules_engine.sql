-- Phase 3 — rules engine + evaluation functions
-- See ../uw_plan.md for the full build plan.
--
-- Depends on: sql/phase1_core_schema.sql, sql/phase2_expected_answer.sql

SET search_path TO "myins";


-- possible outcomes for our evaluation model
CREATE TYPE uw_outcome AS ENUM (
	'accept',
	'increase_premium',
	'refer_to_insurer',
	'decline'
	)
;


-- a named underwriting rule for a product. A rule fires only when ALL of its
-- uw_rule_condition rows match (AND semantics) - this is what lets us express
-- compound rules like "decline if smoker AND bmi > 32", not just single-question ones.
CREATE TABLE uw_rule (
	id SERIAL PRIMARY KEY,
	product_id INT NOT NULL REFERENCES insurance_product(id),
	name TEXT NOT NULL,
	priority INT NOT NULL DEFAULT 1, -- tie-breaker when several matched rules share severity
	outcome uw_outcome NOT NULL,
	stop_evaluation BOOLEAN NOT NULL DEFAULT FALSE -- for Model B: may short-circuit once all its questions are known
	)
;


-- one AND-ed condition belonging to a rule. A rule with N rows here requires all N to hold.
CREATE TABLE uw_rule_condition (
	id SERIAL PRIMARY KEY,
	rule_id INT NOT NULL REFERENCES uw_rule(id) ON DELETE CASCADE,
	question_id INT NOT NULL REFERENCES uw_question(id),
	operator TEXT NOT NULL, -- '=', '<>', '>', '>=', '<', '<='
	value TEXT NOT NULL
	)
;


-- severity ranking for Model A: higher = worse
CREATE TABLE uw_outcome_rank (
	outcome uw_outcome PRIMARY KEY,
	severity INT NOT NULL
	)
;


INSERT INTO uw_outcome_rank (outcome, severity) VALUES
	('accept', 1),
	('increase_premium', 2),
	('refer_to_insurer', 3),
	('decline', 4)
;


-- generic single-condition evaluator. Dispatches on the question's answer_type so
-- numeric and text conditions are handled the same way boolean ones always were,
-- instead of numeric_range rules silently never being matched.
CREATE OR REPLACE FUNCTION uw_condition_matches(
	p_operator TEXT,
	p_condition_value TEXT,
	p_answer_text TEXT,
	p_answer_type TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
	IF p_answer_text IS NULL THEN
		RETURN FALSE; -- question not yet answered -> condition can't be satisfied
	END IF;

	IF p_answer_type = 'boolean' THEN
		RETURN CASE p_operator
			WHEN '='  THEN (p_answer_text::boolean) =  (p_condition_value::boolean)
			WHEN '<>' THEN (p_answer_text::boolean) <> (p_condition_value::boolean)
			ELSE NULL
		END;
	ELSIF p_answer_type = 'number' THEN
		RETURN CASE p_operator
			WHEN '='  THEN (p_answer_text::numeric) =  (p_condition_value::numeric)
			WHEN '<>' THEN (p_answer_text::numeric) <> (p_condition_value::numeric)
			WHEN '>'  THEN (p_answer_text::numeric) >  (p_condition_value::numeric)
			WHEN '>=' THEN (p_answer_text::numeric) >= (p_condition_value::numeric)
			WHEN '<'  THEN (p_answer_text::numeric) <  (p_condition_value::numeric)
			WHEN '<=' THEN (p_answer_text::numeric) <= (p_condition_value::numeric)
			ELSE NULL
		END;
	ELSE -- 'text' / 'enum'
		RETURN CASE p_operator
			WHEN '='  THEN lower(p_answer_text) = lower(p_condition_value)
			WHEN '<>' THEN lower(p_answer_text) <> lower(p_condition_value)
			ELSE NULL
		END;
	END IF;
END;
$$;


-- rules for a quote where every one of their conditions matches (AND).
-- a rule with zero conditions never matches (it would otherwise match vacuously).
CREATE OR REPLACE FUNCTION uw_rule_matches(p_quote_id INT)
RETURNS TABLE(rule_id INT, outcome uw_outcome, priority INT, stop_evaluation BOOLEAN)
LANGUAGE sql
AS $$
	SELECT r.id, r.outcome, r.priority, r.stop_evaluation
	FROM uw_rule r
	JOIN quote qt
		ON qt.id = p_quote_id
	   AND qt.product_id = r.product_id
	WHERE EXISTS (SELECT 1 FROM uw_rule_condition rc WHERE rc.rule_id = r.id)
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
$$;


-- Model A: evaluate every rule, return the worst (highest-severity) outcome among matches
CREATE OR REPLACE FUNCTION evaluate_quote_full(p_quote_id INT)
RETURNS uw_outcome
LANGUAGE sql
AS $$
	SELECT COALESCE(
		(SELECT m.outcome
		 FROM uw_rule_matches(p_quote_id) m
		 JOIN uw_outcome_rank rnk ON rnk.outcome = m.outcome
		 ORDER BY rnk.severity DESC, m.priority ASC
		 LIMIT 1),
		'accept'::uw_outcome -- default if no rules matched
	);
$$;


-- Model B: walk questions in sequence; as soon as every question a "stop" rule needs
-- has been reached and that rule fully matches, return its outcome immediately.
-- A compound rule can only stop the walk once ALL of its questions have been reached.
-- If nothing stops the walk, fall back to the Model A aggregate instead of a
-- hardcoded outcome, so increase_premium/refer_to_insurer remain reachable here too.
CREATE OR REPLACE FUNCTION evaluate_quote_short_circuit(p_quote_id INT)
RETURNS uw_outcome
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
			SELECT r.id, r.outcome
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
			RETURN v_match.outcome;
		END LOOP;
	END LOOP;

	RETURN evaluate_quote_full(p_quote_id);
END;
$$;
