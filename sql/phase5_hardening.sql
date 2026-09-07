-- Phase 5 — production hardening
-- See ../uw_plan.md for the full build plan.
--
-- Depends on: sql/phase1_core_schema.sql .. sql/phase4_evaluation_history.sql

SET search_path TO "myins";


-- product_question: prevent a question being linked twice to the same
-- product, and prevent two questions sharing the same interview position
-- for a product — Model B's short-circuit walk depends on `sequence` being
-- an unambiguous total order per product.
ALTER TABLE product_question
	ADD CONSTRAINT uq_product_question_product_question UNIQUE (product_id, question_id);

ALTER TABLE product_question
	ADD CONSTRAINT uq_product_question_product_sequence UNIQUE (product_id, sequence);


-- quote_answer: one answer per question per quote. Without this, a
-- duplicate/conflicting answer row could sit alongside the real one.
ALTER TABLE quote_answer
	ADD CONSTRAINT uq_quote_answer_quote_question UNIQUE (quote_id, question_id);


-- FK-column indexes for the joins evaluate_quote_full / evaluate_quote_short_circuit
-- run on every evaluation. Postgres does not auto-index the referencing side
-- of a foreign key.
CREATE INDEX idx_uw_rule_product_id ON uw_rule (product_id);
CREATE INDEX idx_uw_rule_condition_rule_id ON uw_rule_condition (rule_id);
CREATE INDEX idx_uw_rule_condition_question_id ON uw_rule_condition (question_id);


-- Validate answer_text against the question's answer_type/enum_options at
-- write time, so bad data fails fast at INSERT/UPDATE instead of raising
-- deep inside an evaluation function — or worse, silently mis-evaluating if
-- a bad value happens to satisfy a cast some other operator relies on.
CREATE OR REPLACE FUNCTION quote_answer_validate() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
	v_answer_type  TEXT;
	v_enum_options TEXT[];
BEGIN
	SELECT answer_type, enum_options INTO v_answer_type, v_enum_options
	FROM uw_question
	WHERE id = NEW.question_id;

	IF v_answer_type = 'boolean' THEN
		BEGIN
			PERFORM NEW.answer_text::boolean;
		EXCEPTION WHEN invalid_text_representation THEN
			RAISE EXCEPTION 'answer_text % is not a valid boolean for question_id %', NEW.answer_text, NEW.question_id;
		END;

	ELSIF v_answer_type = 'number' THEN
		BEGIN
			PERFORM NEW.answer_text::numeric;
		EXCEPTION WHEN invalid_text_representation THEN
			RAISE EXCEPTION 'answer_text % is not a valid number for question_id %', NEW.answer_text, NEW.question_id;
		END;

	ELSIF v_answer_type = 'enum' THEN
		IF NOT EXISTS (
			SELECT 1 FROM unnest(v_enum_options) opt WHERE lower(opt) = lower(NEW.answer_text)
		) THEN
			RAISE EXCEPTION 'answer_text % is not one of the allowed enum_options % for question_id %',
				NEW.answer_text, v_enum_options, NEW.question_id;
		END IF;
	END IF;
	-- 'text' accepts any value

	RETURN NEW;
END;
$$;

CREATE TRIGGER trg_quote_answer_validate
	BEFORE INSERT OR UPDATE ON quote_answer
	FOR EACH ROW
	EXECUTE FUNCTION quote_answer_validate();
