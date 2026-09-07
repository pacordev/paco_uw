-- Phase 6 — test suite
-- See ../uw_plan.md for the full build plan.
--
-- Unit-level building blocks plus formal demo-data assertions for all 8
-- seeded products, including a deliberate Model A / Model B divergence case
-- for each of the 4 non-original products.
--
-- Run this AFTER phase1..phase6_seed_data.sql in the same database/schema, e.g.:
--   psql -v ON_ERROR_STOP=1 \
--     -f sql/phase1_core_schema.sql -f sql/phase2_expected_answer.sql \
--     -f sql/phase3_rules_engine.sql -f sql/phase4_evaluation_history.sql \
--     -f sql/phase5_hardening.sql -f sql/phase6_seed_data.sql -f sql/phase6_tests.sql
--
-- Most test groups build their own tiny, isolated product/questions/rules so
-- tests can't interfere with each other or with the seed data. The
-- demo-data groups are the exception: they deliberately exercise the seeded
-- products/quotes to confirm the seed data itself evaluates to what its
-- comments claim. The script ends by raising an exception (non-zero exit
-- code) if any assertion failed.
--
-- Self-cleaning: every product/question this suite creates uses a code
-- starting with 'T_' (the seed data never does - its codes are 'LIFE_SIMPLE',
-- 'Q_SMOKER', etc.), so section 0 below wipes anything matching that prefix
-- before the tests run. That makes this file safe to run repeatedly against
-- a live, persistent database - no need for scripts/reset_db.sh in between.

SET search_path TO "myins";


-- ===================================================================
-- 0. cleanup: remove leftover rows from a previous run of this suite.
--    Deletes in FK-safe order; cascades (uw_rule -> uw_rule_condition,
--    quote -> quote_evaluation) handle the rest. No-op on a fresh database.
-- ===================================================================
DELETE FROM quote_answer
WHERE quote_id IN (
	SELECT q.id FROM quote q
	JOIN insurance_product p ON p.id = q.product_id
	WHERE p.code LIKE 'T\_%' ESCAPE '\'
);

DELETE FROM quote
WHERE product_id IN (SELECT id FROM insurance_product WHERE code LIKE 'T\_%' ESCAPE '\');

DELETE FROM product_question
WHERE product_id IN (SELECT id FROM insurance_product WHERE code LIKE 'T\_%' ESCAPE '\');

DELETE FROM uw_rule
WHERE product_id IN (SELECT id FROM insurance_product WHERE code LIKE 'T\_%' ESCAPE '\');

DELETE FROM insurance_product WHERE code LIKE 'T\_%' ESCAPE '\';

DELETE FROM uw_question WHERE code LIKE 'T\_%' ESCAPE '\';


-- ===================================================================
-- test harness
-- ===================================================================
CREATE TABLE IF NOT EXISTS uw_test_results (
	id SERIAL PRIMARY KEY,
	test_name TEXT NOT NULL,
	expected TEXT NOT NULL,
	actual TEXT NOT NULL,
	passed BOOLEAN NOT NULL
);

TRUNCATE uw_test_results;

CREATE OR REPLACE FUNCTION uw_test_assert(p_test_name TEXT, p_expected TEXT, p_actual TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
	INSERT INTO uw_test_results (test_name, expected, actual, passed)
	VALUES (p_test_name, p_expected, p_actual, p_expected IS NOT DISTINCT FROM p_actual);
END;
$$;


-- ===================================================================
-- 1. uw_condition_matches: the generic per-condition evaluator
-- ===================================================================
DO $$
BEGIN
	PERFORM uw_test_assert('uw_condition_matches: boolean operator ''='' - condition value ''true'' vs answer ''true'' should match',
		'true', uw_condition_matches('=', 'true', 'true', 'boolean')::text);
	PERFORM uw_test_assert('uw_condition_matches: boolean operator ''='' - condition value ''true'' vs answer ''false'' should not match',
		'false', uw_condition_matches('=', 'true', 'false', 'boolean')::text);
	PERFORM uw_test_assert('uw_condition_matches: boolean operator ''<>'' - condition value ''true'' vs answer ''false'' should match',
		'true', uw_condition_matches('<>', 'true', 'false', 'boolean')::text);

	PERFORM uw_test_assert('uw_condition_matches: number operator ''>'' - answer 34 vs threshold 32 should match',
		'true', uw_condition_matches('>', '32', '34', 'number')::text);
	PERFORM uw_test_assert('uw_condition_matches: number operator ''>'' - answer 32 vs threshold 32 (equal) should not match (strictly greater)',
		'false', uw_condition_matches('>', '32', '32', 'number')::text);
	PERFORM uw_test_assert('uw_condition_matches: number operator ''>='' - answer 32 vs threshold 32 (equal) should match',
		'true', uw_condition_matches('>=', '32', '32', 'number')::text);
	PERFORM uw_test_assert('uw_condition_matches: number operator ''<'' - answer 15 vs threshold 18 should match',
		'true', uw_condition_matches('<', '18', '15', 'number')::text);
	PERFORM uw_test_assert('uw_condition_matches: number operator ''<='' - answer 18 vs threshold 18 (equal) should match',
		'true', uw_condition_matches('<=', '18', '18', 'number')::text);

	PERFORM uw_test_assert('uw_condition_matches: text operator ''='' - answer ''yes'' vs condition value ''Yes'' should match case-insensitively',
		'true', uw_condition_matches('=', 'Yes', 'yes', 'text')::text);

	PERFORM uw_test_assert('uw_condition_matches: boolean operator ''='' - a NULL answer (question not yet answered) should never match condition value ''true''',
		'false', uw_condition_matches('=', 'true', NULL, 'boolean')::text);
END;
$$;


-- ===================================================================
-- 2. evaluate_quote_full: single boolean condition rule
-- ===================================================================
DO $$
DECLARE
	v_product   INT;
	v_q         INT;
	v_rule      INT;
	v_quote_yes INT;
	v_quote_no  INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_SMOKER', 'Test: single rule') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_SMOKER_Q', 'Smoker?', 'boolean') RETURNING id INTO v_q;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q, 1);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'smoker_rule', 'increase_premium', FALSE) RETURNING id INTO v_rule;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q, '=', 'true');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_yes;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_yes, v_q, 'true');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_no;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_no, v_q, 'false');

	PERFORM uw_test_assert('evaluate_quote_full: question ''Smoker?'' answered ''true'' matches rule ''smoker_rule'' (Q_SMOKER = true) -> increase_premium',
		'increase_premium', evaluate_quote_full(v_quote_yes)::text);
	PERFORM uw_test_assert('evaluate_quote_full: question ''Smoker?'' answered ''false'' does not match ''smoker_rule'' -> defaults to accept',
		'accept', evaluate_quote_full(v_quote_no)::text);
END;
$$;


-- ===================================================================
-- 3. evaluate_quote_full: numeric condition rule
-- ===================================================================
DO $$
DECLARE
	v_product   INT;
	v_q         INT;
	v_rule      INT;
	v_quote_hi  INT;
	v_quote_lo  INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_NUMERIC', 'Test: numeric rule') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_NUMERIC_Q', 'BMI?', 'number') RETURNING id INTO v_q;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q, 1);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'bmi_high', 'refer_to_insurer', FALSE) RETURNING id INTO v_rule;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q, '>', '32');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_hi;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_hi, v_q, '34');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_lo;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_lo, v_q, '20');

	PERFORM uw_test_assert('evaluate_quote_full: question ''BMI?'' answered 34, above rule ''bmi_high'' threshold (>32) -> refer_to_insurer',
		'refer_to_insurer', evaluate_quote_full(v_quote_hi)::text);
	PERFORM uw_test_assert('evaluate_quote_full: question ''BMI?'' answered 20, below rule ''bmi_high'' threshold (>32) -> defaults to accept',
		'accept', evaluate_quote_full(v_quote_lo)::text);
END;
$$;


-- ===================================================================
-- 4. evaluate_quote_full: compound (AND) rule
-- ===================================================================
DO $$
DECLARE
	v_product          INT;
	v_q_smoker         INT;
	v_q_bmi            INT;
	v_rule             INT;
	v_quote_both       INT;
	v_quote_bmi_only   INT;
	v_quote_smoker_only INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_COMPOUND', 'Test: compound rule') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_COMPOUND_SMOKER', 'Smoker?', 'boolean') RETURNING id INTO v_q_smoker;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_COMPOUND_BMI', 'BMI?', 'number') RETURNING id INTO v_q_bmi;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_smoker, 1);
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_bmi, 2);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'smoker_and_high_bmi', 'decline', FALSE) RETURNING id INTO v_rule;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q_smoker, '=', 'true');
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q_bmi, '>', '32');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_both;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_both, v_q_smoker, 'true'), (v_quote_both, v_q_bmi, '34');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_bmi_only;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_bmi_only, v_q_smoker, 'false'), (v_quote_bmi_only, v_q_bmi, '34');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_smoker_only;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_smoker_only, v_q_smoker, 'true'), (v_quote_smoker_only, v_q_bmi, '20');

	PERFORM uw_test_assert('evaluate_quote_full: compound rule ''smoker_and_high_bmi'' fires when ''Smoker?''=true AND ''BMI?''=34 (>32) -> decline',
		'decline', evaluate_quote_full(v_quote_both)::text);
	PERFORM uw_test_assert('evaluate_quote_full: compound rule does not fire when only ''BMI?''=34 matches and ''Smoker?''=false -> accept',
		'accept', evaluate_quote_full(v_quote_bmi_only)::text);
	PERFORM uw_test_assert('evaluate_quote_full: compound rule does not fire when only ''Smoker?''=true matches and ''BMI?''=20 -> accept',
		'accept', evaluate_quote_full(v_quote_smoker_only)::text);
END;
$$;


-- ===================================================================
-- 5. evaluate_quote_full: worst-outcome ranking across several matches
-- ===================================================================
DO $$
DECLARE
	v_product           INT;
	v_q_smoker          INT;
	v_q_cancer          INT;
	v_rule_smoker       INT;
	v_rule_cancer       INT;
	v_quote_both        INT;
	v_quote_smoker_only INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_SEVERITY', 'Test: severity ranking') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_SEVERITY_SMOKER', 'Smoker?', 'boolean') RETURNING id INTO v_q_smoker;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_SEVERITY_CANCER', 'Cancer?', 'boolean') RETURNING id INTO v_q_cancer;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_smoker, 1);
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_cancer, 2);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'smoker', 'increase_premium', FALSE) RETURNING id INTO v_rule_smoker;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule_smoker, v_q_smoker, '=', 'true');

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'cancer', 'decline', FALSE) RETURNING id INTO v_rule_cancer;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule_cancer, v_q_cancer, '=', 'true');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_both;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_both, v_q_smoker, 'true'), (v_quote_both, v_q_cancer, 'true');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_smoker_only;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_smoker_only, v_q_smoker, 'true'), (v_quote_smoker_only, v_q_cancer, 'false');

	PERFORM uw_test_assert('evaluate_quote_full: ''Smoker?''=true (increase_premium, severity 2) and ''Cancer?''=true (decline, severity 4) both match - decline wins as the higher severity',
		'decline', evaluate_quote_full(v_quote_both)::text);
	PERFORM uw_test_assert('evaluate_quote_full: ''Smoker?''=true matches (increase_premium) while ''Cancer?''=false does not match the cancer rule -> increase_premium',
		'increase_premium', evaluate_quote_full(v_quote_smoker_only)::text);
END;
$$;


-- ===================================================================
-- 6. evaluate_quote_full: a rule with zero conditions never matches
-- ===================================================================
DO $$
DECLARE
	v_product INT;
	v_rule    INT;
	v_quote   INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_VACUOUS', 'Test: empty rule') RETURNING id INTO v_product;

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'empty_rule', 'decline', FALSE) RETURNING id INTO v_rule;
	-- deliberately no uw_rule_condition rows for v_rule

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote;

	PERFORM uw_test_assert('evaluate_quote_full: rule ''empty_rule'' has zero uw_rule_condition rows, so it never matches regardless of answers -> accept',
		'accept', evaluate_quote_full(v_quote)::text);
END;
$$;


-- ===================================================================
-- 7. both functions: a product with no rules at all defaults to accept
-- ===================================================================
DO $$
DECLARE
	v_product INT;
	v_q       INT;
	v_quote   INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_NORULES', 'Test: no rules') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_NORULES_Q', 'Anything?', 'boolean') RETURNING id INTO v_q;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q, 1);

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q, 'true');

	PERFORM uw_test_assert('evaluate_quote_full: product ''T_NORULES'' has no uw_rule rows at all, question ''Anything?''=true -> defaults to accept',
		'accept', evaluate_quote_full(v_quote)::text);
	PERFORM uw_test_assert('evaluate_quote_short_circuit: product ''T_NORULES'' has no uw_rule rows at all, question ''Anything?''=true -> defaults to accept',
		'accept', evaluate_quote_short_circuit(v_quote)::text);
END;
$$;


-- ===================================================================
-- 8. evaluate_quote_short_circuit: stops on the first "stop" rule, even
--    when a later (already-answered) question would push the full
--    evaluation to a worse outcome. This is the whole point of Model B.
-- ===================================================================
DO $$
DECLARE
	v_product    INT;
	v_q_cancer   INT;
	v_q_bmi      INT;
	v_rule_stop  INT;
	v_rule_later INT;
	v_quote      INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_STOP_EARLY', 'Test: short-circuit stops early') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_STOP_EARLY_CANCER', 'Cancer?', 'boolean') RETURNING id INTO v_q_cancer;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_STOP_EARLY_BMI', 'BMI?', 'number') RETURNING id INTO v_q_bmi;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_cancer, 1);
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_bmi, 2);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'cancer_stop', 'refer_to_insurer', TRUE) RETURNING id INTO v_rule_stop;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule_stop, v_q_cancer, '=', 'true');

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'bmi_decline', 'decline', FALSE) RETURNING id INTO v_rule_later;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule_later, v_q_bmi, '>', '32');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_cancer, 'true'), (v_quote, v_q_bmi, '40');

	PERFORM uw_test_assert('evaluate_quote_full: ''Cancer?''=true (stop-rule, refer_to_insurer) and ''BMI?''=40 (non-stop rule, decline) both match - decline (worse) wins since full checks every answer',
		'decline', evaluate_quote_full(v_quote)::text);
	PERFORM uw_test_assert('evaluate_quote_short_circuit: ''Cancer?''=true matches stop-rule ''cancer_stop'' at question 1, returns refer_to_insurer immediately without reaching ''BMI?''=40''s decline rule',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote)::text);
END;
$$;


-- ===================================================================
-- 9. evaluate_quote_short_circuit: a compound stop-rule can only fire once
--    ALL of its questions have been reached in sequence, and a partial
--    match falls through to the Model A fallback (accept here).
-- ===================================================================
DO $$
DECLARE
	v_product      INT;
	v_q_smoker     INT;
	v_q_bmi        INT;
	v_rule         INT;
	v_quote_match  INT;
	v_quote_partial INT;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_STOP_COMPOUND', 'Test: compound stop rule') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_STOP_COMPOUND_SMOKER', 'Smoker?', 'boolean') RETURNING id INTO v_q_smoker;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_STOP_COMPOUND_BMI', 'BMI?', 'number') RETURNING id INTO v_q_bmi;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_smoker, 1);
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_bmi, 2);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'smoker_and_high_bmi_stop', 'decline', TRUE) RETURNING id INTO v_rule;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q_smoker, '=', 'true');
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q_bmi, '>', '32');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_match;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_match, v_q_smoker, 'true'), (v_quote_match, v_q_bmi, '34');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote_partial;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote_partial, v_q_smoker, 'true'), (v_quote_partial, v_q_bmi, '20');

	PERFORM uw_test_assert('evaluate_quote_short_circuit: compound stop-rule fires once ''Smoker?''=true AND ''BMI?''=34 (>32) are both reached -> decline',
		'decline', evaluate_quote_short_circuit(v_quote_match)::text);
	PERFORM uw_test_assert('evaluate_quote_short_circuit: compound stop-rule needs ''Smoker?''=true AND ''BMI?''>32, but ''BMI?''=20 fails - falls back to Model A -> accept',
		'accept', evaluate_quote_short_circuit(v_quote_partial)::text);
END;
$$;


-- ===================================================================
-- 10. evaluate_and_record_quote: persists outcomes to quote_evaluation,
--     keeps history across re-evaluation instead of overwriting, and
--     quote_latest_evaluation surfaces the most recent row per
--     (quote, strategy). Also confirms an unknown strategy raises rather
--     than silently doing nothing.
-- ===================================================================
DO $$
DECLARE
	v_product      INT;
	v_q            INT;
	v_rule         INT;
	v_quote        INT;
	v_outcome      uw_outcome;
	v_count        INT;
	v_error_caught BOOLEAN := FALSE;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_RECORD', 'Test: evaluate_and_record_quote') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_RECORD_Q', 'Smoker?', 'boolean') RETURNING id INTO v_q;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q, 1);

	INSERT INTO uw_rule (product_id, name, outcome, stop_evaluation)
	VALUES (v_product, 'smoker_rule', 'increase_premium', TRUE) RETURNING id INTO v_rule;
	INSERT INTO uw_rule_condition (rule_id, question_id, operator, value) VALUES (v_rule, v_q, '=', 'true');

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote;
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q, 'false');

	-- first evaluation: rule doesn't match yet -> accept
	v_outcome := evaluate_and_record_quote(v_quote, 'full');
	PERFORM uw_test_assert('evaluate_and_record_quote: question ''Smoker?''=false (rule not yet matched) returns accept, same as evaluate_quote_full would',
		'accept', v_outcome::text);
	PERFORM uw_test_assert('quote_evaluation: first ''full'' evaluation (Smoker?=false -> accept) is persisted with its strategy and outcome',
		'accept', (SELECT outcome::text FROM quote_evaluation WHERE quote_id = v_quote AND strategy = 'full'));

	-- answer changes, quote is re-evaluated -> increase_premium
	UPDATE quote_answer SET answer_text = 'true' WHERE quote_id = v_quote AND question_id = v_q;
	v_outcome := evaluate_and_record_quote(v_quote, 'full');
	PERFORM uw_test_assert('evaluate_and_record_quote: after ''Smoker?'' answer changes false -> true, re-running ''full'' returns the updated outcome increase_premium',
		'increase_premium', v_outcome::text);

	SELECT count(*) INTO v_count FROM quote_evaluation WHERE quote_id = v_quote AND strategy = 'full';
	PERFORM uw_test_assert('quote_evaluation: two ''full'' evaluations on the same quote (accept, then increase_premium) produce two history rows, not one overwritten row',
		'2', v_count::text);

	PERFORM uw_test_assert('quote_latest_evaluation: surfaces the second, most recent ''full'' outcome (increase_premium), not the first (accept)',
		'increase_premium', (SELECT outcome::text FROM quote_latest_evaluation WHERE quote_id = v_quote AND strategy = 'full'));

	-- a different strategy for the same quote gets its own history line
	v_outcome := evaluate_and_record_quote(v_quote, 'short_circuit');
	PERFORM uw_test_assert('evaluate_and_record_quote: running ''short_circuit'' on the same quote (Smoker?=true) records its own history row independent of the ''full'' strategy''s rows',
		'increase_premium', v_outcome::text);

	SELECT count(*) INTO v_count FROM quote_latest_evaluation WHERE quote_id = v_quote;
	PERFORM uw_test_assert('quote_latest_evaluation: exactly one row per strategy (''full'' and ''short_circuit'') is returned for this quote',
		'2', v_count::text);

	-- unknown strategy must raise, not silently no-op
	BEGIN
		PERFORM evaluate_and_record_quote(v_quote, 'bogus');
	EXCEPTION WHEN OTHERS THEN
		v_error_caught := TRUE;
	END;
	PERFORM uw_test_assert('evaluate_and_record_quote: calling with strategy ''bogus'' raises an exception instead of silently doing nothing',
		'true', v_error_caught::text);
END;
$$;


-- ===================================================================
-- 11. quote_answer_validate trigger: rejects bad data at write time
-- ===================================================================
DO $$
DECLARE
	v_product      INT;
	v_q_bool       INT;
	v_q_num        INT;
	v_q_enum       INT;
	v_quote        INT;
	v_error_caught BOOLEAN;
BEGIN
	INSERT INTO insurance_product (code, name) VALUES ('T_VALIDATE', 'Test: answer validation') RETURNING id INTO v_product;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_VALIDATE_BOOL', 'Bool?', 'boolean') RETURNING id INTO v_q_bool;
	INSERT INTO uw_question (code, text, answer_type) VALUES ('T_VALIDATE_NUM', 'Num?', 'number') RETURNING id INTO v_q_num;
	INSERT INTO uw_question (code, text, answer_type, enum_options)
		VALUES ('T_VALIDATE_ENUM', 'Enum?', 'enum', ARRAY['low', 'high']) RETURNING id INTO v_q_enum;
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_bool, 1);
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_num, 2);
	INSERT INTO product_question (product_id, question_id, sequence) VALUES (v_product, v_q_enum, 3);

	INSERT INTO quote (product_id) VALUES (v_product) RETURNING id INTO v_quote;

	v_error_caught := FALSE;
	BEGIN
		INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_bool, 'maybe');
	EXCEPTION WHEN OTHERS THEN
		v_error_caught := TRUE;
	END;
	PERFORM uw_test_assert('quote_answer_validate trigger: answer_text ''maybe'' for question ''Bool?'' (boolean type) is rejected at insert time', 'true', v_error_caught::text);

	v_error_caught := FALSE;
	BEGIN
		INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_num, 'not-a-number');
	EXCEPTION WHEN OTHERS THEN
		v_error_caught := TRUE;
	END;
	PERFORM uw_test_assert('quote_answer_validate trigger: answer_text ''not-a-number'' for question ''Num?'' (number type) is rejected at insert time', 'true', v_error_caught::text);

	v_error_caught := FALSE;
	BEGIN
		INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_enum, 'extreme');
	EXCEPTION WHEN OTHERS THEN
		v_error_caught := TRUE;
	END;
	PERFORM uw_test_assert('quote_answer_validate trigger: answer_text ''extreme'' for question ''Enum?'' (allowed values: low/high) is rejected at insert time', 'true', v_error_caught::text);

	-- valid values still go through
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_bool, 'true');
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_num, '42');
	INSERT INTO quote_answer (quote_id, question_id, answer_text) VALUES (v_quote, v_q_enum, 'Low');
	PERFORM uw_test_assert('quote_answer_validate trigger: valid boolean (''true''), number (''42''), and enum (''Low'', case-insensitive) answers are all accepted',
		'3', (SELECT count(*)::text FROM quote_answer WHERE quote_id = v_quote));
END;
$$;


-- ===================================================================
-- 12. LIFE_SIMPLE demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id     INT;
	v_quote_refer    INT; -- non-smoker but high BMI + high risk sports -> refer
	v_quote_decline  INT; -- smoker + high BMI -> compound decline
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'LIFE_SIMPLE';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'LIFE_SIMPLE product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_refer   FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_decline FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;

	PERFORM uw_test_assert('LIFE_SIMPLE demo quote 1 (smoker=false, bmi=34, sports=true): evaluate_quote_full -> refer_to_insurer (BMI too high)',
		'refer_to_insurer', evaluate_quote_full(v_quote_refer)::text);
	PERFORM uw_test_assert('LIFE_SIMPLE demo quote 1 (smoker=false, bmi=34, sports=true): evaluate_quote_short_circuit -> refer_to_insurer',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_refer)::text);

	PERFORM uw_test_assert('LIFE_SIMPLE demo quote 2 (smoker=true, bmi=34): evaluate_quote_full -> decline (compound rule ''Smoker with high BMI'')',
		'decline', evaluate_quote_full(v_quote_decline)::text);
	PERFORM uw_test_assert('LIFE_SIMPLE demo quote 2 (smoker=true, bmi=34): evaluate_quote_short_circuit -> decline',
		'decline', evaluate_quote_short_circuit(v_quote_decline)::text);
END;
$$;


-- ===================================================================
-- 13. AUTO_BASIC demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id   INT;
	v_quote_compound INT; -- young driver + moving violations -> compound decline rule
	v_quote_stop     INT; -- accident history -> single stop-rule (refer_to_insurer)
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'AUTO_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'AUTO_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_compound FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_stop     FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;

	PERFORM uw_test_assert('AUTO_BASIC demo quote 3 (age=19, violations=true): evaluate_quote_full -> decline (compound rule ''Young driver with violations'')',
		'decline', evaluate_quote_full(v_quote_compound)::text);
	PERFORM uw_test_assert('AUTO_BASIC demo quote 3 (age=19, violations=true): evaluate_quote_short_circuit -> decline',
		'decline', evaluate_quote_short_circuit(v_quote_compound)::text);

	PERFORM uw_test_assert('AUTO_BASIC demo quote 4 (accidents=true): evaluate_quote_full -> refer_to_insurer (rule ''Accident history'')',
		'refer_to_insurer', evaluate_quote_full(v_quote_stop)::text);
	PERFORM uw_test_assert('AUTO_BASIC demo quote 4 (accidents=true): evaluate_quote_short_circuit -> refer_to_insurer (stops immediately)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_stop)::text);
END;
$$;


-- ===================================================================
-- 14. HOME_BASIC demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id   INT;
	v_quote_compound INT; -- prior claims + old roof -> compound decline rule
	v_quote_stop     INT; -- not occupied full-time -> single stop-rule (decline)
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'HOME_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'HOME_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_compound FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_stop     FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;

	PERFORM uw_test_assert('HOME_BASIC demo quote 5 (claims=true, roof_age=25): evaluate_quote_full -> decline (compound rule ''Prior claims with old roof'')',
		'decline', evaluate_quote_full(v_quote_compound)::text);
	PERFORM uw_test_assert('HOME_BASIC demo quote 5 (claims=true, roof_age=25): evaluate_quote_short_circuit -> decline',
		'decline', evaluate_quote_short_circuit(v_quote_compound)::text);

	PERFORM uw_test_assert('HOME_BASIC demo quote 6 (occupied=false): evaluate_quote_full -> decline (rule ''Not occupied full-time'')',
		'decline', evaluate_quote_full(v_quote_stop)::text);
	PERFORM uw_test_assert('HOME_BASIC demo quote 6 (occupied=false): evaluate_quote_short_circuit -> decline (stops immediately)',
		'decline', evaluate_quote_short_circuit(v_quote_stop)::text);
END;
$$;


-- ===================================================================
-- 15. HEALTH_BASIC demo data (includes the flagship Model A/B divergence)
-- ===================================================================
DO $$
DECLARE
	v_product_id  INT;
	v_quote_all_bad INT; -- everything bad at once, no stop rule fires -> both models agree
	v_quote_diverge INT; -- 3-way compound decline matches early, but isn't a stop rule
	v_quote_clean   INT; -- nothing matches
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'HEALTH_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'HEALTH_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_all_bad FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_diverge FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;
	SELECT id INTO v_quote_clean   FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 2 LIMIT 1;

	PERFORM uw_test_assert('HEALTH_BASIC demo quote 7 (preexisting=true, age=60, smoker=true, bmi=38, risk=medium, hospitalizations=3, family_history=true): evaluate_quote_full -> decline (worst of several matched rules)',
		'decline', evaluate_quote_full(v_quote_all_bad)::text);
	PERFORM uw_test_assert('HEALTH_BASIC demo quote 7 (same answers): evaluate_quote_short_circuit -> decline (no stop-rule fires early, so it agrees with full)',
		'decline', evaluate_quote_short_circuit(v_quote_all_bad)::text);

	PERFORM uw_test_assert('HEALTH_BASIC demo quote 8 (preexisting=true, age=60, smoker=true, risk=high): evaluate_quote_full -> decline (3-way compound rule ''Older smoker with pre-existing condition'' matches at question 3)',
		'decline', evaluate_quote_full(v_quote_diverge)::text);
	PERFORM uw_test_assert('HEALTH_BASIC demo quote 8 (same answers): evaluate_quote_short_circuit -> refer_to_insurer, NOT decline (the 3-way compound rule isn''t flagged stop_evaluation, so it walks on and stops at ''High-risk occupation'' (risk=high) at question 5 instead)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_diverge)::text);

	PERFORM uw_test_assert('HEALTH_BASIC demo quote 9 (all answers clean/negative): evaluate_quote_full -> accept, nothing matches',
		'accept', evaluate_quote_full(v_quote_clean)::text);
	PERFORM uw_test_assert('HEALTH_BASIC demo quote 9 (same answers): evaluate_quote_short_circuit -> accept, nothing matches',
		'accept', evaluate_quote_short_circuit(v_quote_clean)::text);
END;
$$;


-- ===================================================================
-- 16. TRAVEL_BASIC demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id    INT;
	v_quote_clean   INT;
	v_quote_diverge INT;
	v_quote_single  INT;
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'TRAVEL_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'TRAVEL_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_clean   FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_diverge FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;
	SELECT id INTO v_quote_single  FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 2 LIMIT 1;

	PERFORM uw_test_assert('TRAVEL_BASIC demo quote 10 (destination=low, trip_length=10, preexisting=false, age=40, adventure=false): evaluate_quote_full -> accept',
		'accept', evaluate_quote_full(v_quote_clean)::text);
	PERFORM uw_test_assert('TRAVEL_BASIC demo quote 10 (same answers): evaluate_quote_short_circuit -> accept',
		'accept', evaluate_quote_short_circuit(v_quote_clean)::text);

	PERFORM uw_test_assert('TRAVEL_BASIC demo quote 11 (destination=high, preexisting=true, age=80): evaluate_quote_full -> decline (compound rule ''Elderly with pre-existing condition'' at questions 3-4)',
		'decline', evaluate_quote_full(v_quote_diverge)::text);
	PERFORM uw_test_assert('TRAVEL_BASIC demo quote 11 (same answers): evaluate_quote_short_circuit -> refer_to_insurer (stops at question 1 on ''High risk destination'' before reaching the compound rule)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_diverge)::text);

	PERFORM uw_test_assert('TRAVEL_BASIC demo quote 12 (destination=low, adventure=true, all else clean): evaluate_quote_full -> increase_premium (rule ''Adventure sports'')',
		'increase_premium', evaluate_quote_full(v_quote_single)::text);
	PERFORM uw_test_assert('TRAVEL_BASIC demo quote 12 (same answers): evaluate_quote_short_circuit -> increase_premium (no stop-rule fires, falls back to full)',
		'increase_premium', evaluate_quote_short_circuit(v_quote_single)::text);
END;
$$;


-- ===================================================================
-- 17. PET_BASIC demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id    INT;
	v_quote_clean   INT;
	v_quote_diverge INT;
	v_quote_single  INT;
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'PET_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'PET_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_clean   FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_diverge FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;
	SELECT id INTO v_quote_single  FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 2 LIMIT 1;

	PERFORM uw_test_assert('PET_BASIC demo quote 13 (species=dog, age=2, preexisting=false, breed_risk=low, vet_visits=1): evaluate_quote_full -> accept',
		'accept', evaluate_quote_full(v_quote_clean)::text);
	PERFORM uw_test_assert('PET_BASIC demo quote 13 (same answers): evaluate_quote_short_circuit -> accept',
		'accept', evaluate_quote_short_circuit(v_quote_clean)::text);

	PERFORM uw_test_assert('PET_BASIC demo quote 14 (age=12, preexisting=true, breed_risk=high): evaluate_quote_full -> decline (compound rule ''Senior high-risk breed'' at questions 2/4)',
		'decline', evaluate_quote_full(v_quote_diverge)::text);
	PERFORM uw_test_assert('PET_BASIC demo quote 14 (same answers): evaluate_quote_short_circuit -> refer_to_insurer (stops at question 3 on ''Pre-existing condition'' before reaching breed_risk at question 4)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_diverge)::text);

	PERFORM uw_test_assert('PET_BASIC demo quote 15 (vet_visits=5, all else clean): evaluate_quote_full -> refer_to_insurer (rule ''Frequent vet visits'')',
		'refer_to_insurer', evaluate_quote_full(v_quote_single)::text);
	PERFORM uw_test_assert('PET_BASIC demo quote 15 (same answers): evaluate_quote_short_circuit -> refer_to_insurer (no stop-rule fires, falls back to full)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_single)::text);
END;
$$;


-- ===================================================================
-- 18. RENTERS_BASIC demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id    INT;
	v_quote_clean   INT;
	v_quote_diverge INT;
	v_quote_single  INT;
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'RENTERS_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'RENTERS_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_clean   FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_diverge FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;
	SELECT id INTO v_quote_single  FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 2 LIMIT 1;

	PERFORM uw_test_assert('RENTERS_BASIC demo quote 16 (building=apartment, security=true, claims=0, value=10000, roommate=false): evaluate_quote_full -> accept',
		'accept', evaluate_quote_full(v_quote_clean)::text);
	PERFORM uw_test_assert('RENTERS_BASIC demo quote 16 (same answers): evaluate_quote_short_circuit -> accept',
		'accept', evaluate_quote_short_circuit(v_quote_clean)::text);

	PERFORM uw_test_assert('RENTERS_BASIC demo quote 17 (building=house, claims=3, value=70000): evaluate_quote_full -> decline (compound rule ''Prior claims with high value'' at questions 3/4)',
		'decline', evaluate_quote_full(v_quote_diverge)::text);
	PERFORM uw_test_assert('RENTERS_BASIC demo quote 17 (same answers): evaluate_quote_short_circuit -> refer_to_insurer (stops at question 1 on ''Uninsurable building type'' before reaching claims/value)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_diverge)::text);

	PERFORM uw_test_assert('RENTERS_BASIC demo quote 18 (roommate=true, all else clean): evaluate_quote_full -> increase_premium (rule ''Roommates present'')',
		'increase_premium', evaluate_quote_full(v_quote_single)::text);
	PERFORM uw_test_assert('RENTERS_BASIC demo quote 18 (same answers): evaluate_quote_short_circuit -> increase_premium (no stop-rule fires, falls back to full)',
		'increase_premium', evaluate_quote_short_circuit(v_quote_single)::text);
END;
$$;


-- ===================================================================
-- 19. UMBRELLA_BASIC demo data
-- ===================================================================
DO $$
DECLARE
	v_product_id    INT;
	v_quote_clean   INT;
	v_quote_diverge INT;
	v_quote_single  INT;
BEGIN
	SELECT id INTO v_product_id FROM insurance_product WHERE code = 'UMBRELLA_BASIC';
	IF v_product_id IS NULL THEN
		RAISE EXCEPTION 'UMBRELLA_BASIC product not found - run phase6_seed_data.sql before this test file';
	END IF;

	SELECT id INTO v_quote_clean   FROM quote WHERE product_id = v_product_id ORDER BY id ASC LIMIT 1;
	SELECT id INTO v_quote_diverge FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 1 LIMIT 1;
	SELECT id INTO v_quote_single  FROM quote WHERE product_id = v_product_id ORDER BY id ASC OFFSET 2 LIMIT 1;

	PERFORM uw_test_assert('UMBRELLA_BASIC demo quote 19 (limits=true, lawsuits=0, high_risk_assets=false, coverage=1000000): evaluate_quote_full -> accept',
		'accept', evaluate_quote_full(v_quote_clean)::text);
	PERFORM uw_test_assert('UMBRELLA_BASIC demo quote 19 (same answers): evaluate_quote_short_circuit -> accept',
		'accept', evaluate_quote_short_circuit(v_quote_clean)::text);

	PERFORM uw_test_assert('UMBRELLA_BASIC demo quote 20 (limits=false, lawsuits=2, high_risk_assets=true): evaluate_quote_full -> decline (compound rule ''Lawsuits with high-risk assets'' at questions 2/4)',
		'decline', evaluate_quote_full(v_quote_diverge)::text);
	PERFORM uw_test_assert('UMBRELLA_BASIC demo quote 20 (same answers): evaluate_quote_short_circuit -> refer_to_insurer (stops at question 1 on ''Insufficient underlying limits'' before reaching lawsuits/assets)',
		'refer_to_insurer', evaluate_quote_short_circuit(v_quote_diverge)::text);

	PERFORM uw_test_assert('UMBRELLA_BASIC demo quote 21 (high_risk_assets=true, all else clean): evaluate_quote_full -> increase_premium (rule ''High-risk assets'')',
		'increase_premium', evaluate_quote_full(v_quote_single)::text);
	PERFORM uw_test_assert('UMBRELLA_BASIC demo quote 21 (same answers): evaluate_quote_short_circuit -> increase_premium (no stop-rule fires, falls back to full)',
		'increase_premium', evaluate_quote_short_circuit(v_quote_single)::text);
END;
$$;


-- ===================================================================
-- results
-- ===================================================================
SELECT test_name, expected, actual, passed::text AS passed
FROM uw_test_results
ORDER BY id;

DO $$
DECLARE
	v_failed INT;
	v_total  INT;
BEGIN
	SELECT count(*) FILTER (WHERE NOT passed), count(*) INTO v_failed, v_total FROM uw_test_results;
	RAISE NOTICE '% / % tests passed', v_total - v_failed, v_total;
	IF v_failed > 0 THEN
		RAISE EXCEPTION '% test(s) failed - see uw_test_results above', v_failed;
	END IF;
END;
$$;
