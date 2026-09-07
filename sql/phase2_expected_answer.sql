-- Phase 2 — expected answer
-- See ../uw_plan.md for the full build plan.
--
-- Informational only: documents what a "clean" answer looks like for a
-- question on a given product, e.g. for UI hints or QA review. It does not
-- drive evaluation outcomes — uw_rule / uw_rule_condition (Phase 3) remain
-- the single source of truth for that.

SET search_path TO "myins";

ALTER TABLE product_question
	ADD COLUMN expected_answer TEXT;
