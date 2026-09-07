-- Phase 6 — seed data: 8 demo products
-- See ../uw_plan.md for the full build plan.
--
-- Depends on: sql/phase1_core_schema.sql .. sql/phase5_hardening.sql
--
-- Each product below gets a "clean pass" quote (accept under both models) and,
-- for the four new products, a deliberate Model A / Model B divergence quote:
-- a mild stop-rule fires early (Model B returns it immediately) while a
-- worse compound rule only becomes decidable later (Model A still finds it
-- because it looks at every answer). This is the same pattern HEALTH_BASIC's
-- quote 8 demonstrates below.

SET search_path TO "myins";


----------------------------------------------------------------------------------
-- Product: Simple Life Insurance – Product Code: LIFE_SIMPLE
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('LIFE_SIMPLE', 'Simple Life Insurance', 'Basic life insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_SMOKER', 'Are you a smoker?', 'boolean', NULL),
	('Q_CANCER', 'Any history of cancer?', 'boolean', NULL),
	('Q_BMI', 'What is your BMI?', 'number', NULL),
	('Q_HOSP', 'Hospitalized in last 12 months?', 'boolean', NULL),
	('Q_SPORTS', 'Do you engage in high risk sports?', 'boolean', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_SMOKER', 1, 'false'),
		('Q_CANCER', 2, 'false'),
		('Q_BMI', 3, '22'),
		('Q_HOSP', 4, 'false'),
		('Q_SPORTS', 5, 'false')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'LIFE_SIMPLE'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('Smoker',                 1, 'increase_premium', FALSE),
		('Cancer history',         1, 'decline',           TRUE),
		('BMI too low',            1, 'refer_to_insurer',  FALSE),
		('BMI too high',           2, 'refer_to_insurer',  FALSE),
		('Recent hospitalization', 1, 'refer_to_insurer',  TRUE),
		('High risk sports',       1, 'increase_premium',  FALSE),
		('Smoker with high BMI',   1, 'decline',           FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'LIFE_SIMPLE'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'LIFE_SIMPLE'
JOIN (
	VALUES
		('Smoker',                 'Q_SMOKER', '=', 'true'),
		('Cancer history',         'Q_CANCER', '=', 'true'),
		('BMI too low',            'Q_BMI',    '<', '18'),
		('BMI too high',           'Q_BMI',    '>', '32'),
		('Recent hospitalization', 'Q_HOSP',   '=', 'true'),
		('High risk sports',       'Q_SPORTS', '=', 'true'),
		('Smoker with high BMI',   'Q_SMOKER', '=', 'true'),
		('Smoker with high BMI',   'Q_BMI',    '>', '32')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 1: smoker=false, bmi=34, sports=true -> expect refer_to_insurer (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'LIFE_SIMPLE';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'LIFE_SIMPLE')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_SMOKER', 'false'),
		('Q_CANCER', 'false'),
		('Q_BMI', '34'),
		('Q_HOSP', 'false'),
		('Q_SPORTS', 'true')
) AS a(code, ans) ON a.code = q.code
;

-- quote 2: smoker=true + high BMI -> expect decline (compound AND rule, both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'LIFE_SIMPLE';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'LIFE_SIMPLE')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_SMOKER', 'true'),
		('Q_CANCER', 'false'),
		('Q_BMI', '34'),
		('Q_HOSP', 'false'),
		('Q_SPORTS', 'false')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Auto Insurance – Product Code: AUTO_BASIC
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('AUTO_BASIC', 'Basic Auto Insurance', 'Basic auto insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_AUTO_DUI', 'Any DUI/DWI convictions?', 'boolean', NULL),
	('Q_AUTO_ACCIDENTS', 'Any accidents in the last 5 years?', 'boolean', NULL),
	('Q_AUTO_AGE', 'Driver age?', 'number', NULL),
	('Q_AUTO_VIOLATIONS', 'Any moving violations in the last 3 years?', 'boolean', NULL),
	('Q_AUTO_MILEAGE', 'Annual mileage?', 'number', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_AUTO_DUI', 1, 'false'),
		('Q_AUTO_ACCIDENTS', 2, 'false'),
		('Q_AUTO_AGE', 3, '35'),
		('Q_AUTO_VIOLATIONS', 4, 'false'),
		('Q_AUTO_MILEAGE', 5, '12000')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'AUTO_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('DUI conviction',      1, 'decline',          TRUE),
		('Accident history',    1, 'refer_to_insurer',  TRUE),
		('Young driver',        1, 'increase_premium',  FALSE),
		('High annual mileage', 1, 'increase_premium',  FALSE),
		('Moving violations',   1, 'increase_premium',  FALSE),
		('Young driver with violations', 1, 'decline', FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'AUTO_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'AUTO_BASIC'
JOIN (
	VALUES
		('DUI conviction',               'Q_AUTO_DUI',        '=', 'true'),
		('Accident history',             'Q_AUTO_ACCIDENTS',  '=', 'true'),
		('Young driver',                 'Q_AUTO_AGE',        '<', '21'),
		('High annual mileage',          'Q_AUTO_MILEAGE',    '>', '20000'),
		('Moving violations',            'Q_AUTO_VIOLATIONS', '=', 'true'),
		('Young driver with violations', 'Q_AUTO_AGE',        '<', '21'),
		('Young driver with violations', 'Q_AUTO_VIOLATIONS', '=', 'true')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 3: no DUI/accidents, but a young driver with violations -> compound decline (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'AUTO_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'AUTO_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_AUTO_DUI', 'false'),
		('Q_AUTO_ACCIDENTS', 'false'),
		('Q_AUTO_AGE', '19'),
		('Q_AUTO_VIOLATIONS', 'true'),
		('Q_AUTO_MILEAGE', '15000')
) AS a(code, ans) ON a.code = q.code
;

-- quote 4: an accident on record -> stop rule fires immediately in Model B, refer_to_insurer (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'AUTO_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'AUTO_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_AUTO_DUI', 'false'),
		('Q_AUTO_ACCIDENTS', 'true'),
		('Q_AUTO_AGE', '35'),
		('Q_AUTO_VIOLATIONS', 'false'),
		('Q_AUTO_MILEAGE', '12000')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Home Insurance – Product Code: HOME_BASIC
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('HOME_BASIC', 'Basic Home Insurance', 'Basic home insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_HOME_OCCUPIED', 'Is the property occupied full-time?', 'boolean', NULL),
	('Q_HOME_HYDRANT_DIST', 'Distance to nearest fire hydrant (km)?', 'number', NULL),
	('Q_HOME_CLAIMS', 'Any prior claims in the last 5 years?', 'boolean', NULL),
	('Q_HOME_ROOF_AGE', 'Roof age (years)?', 'number', NULL),
	('Q_HOME_ELECTRICAL_AGE', 'Electrical system age (years)?', 'number', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_HOME_OCCUPIED', 1, 'true'),
		('Q_HOME_HYDRANT_DIST', 2, '0.5'),
		('Q_HOME_CLAIMS', 3, 'false'),
		('Q_HOME_ROOF_AGE', 4, '10'),
		('Q_HOME_ELECTRICAL_AGE', 5, '10')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'HOME_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('Not occupied full-time',   1, 'decline',          TRUE),
		('Far from fire hydrant',    1, 'refer_to_insurer',  TRUE),
		('Old roof',                 1, 'refer_to_insurer',  FALSE),
		('Old electrical system',    1, 'refer_to_insurer',  FALSE),
		('Prior claims',             1, 'increase_premium',  FALSE),
		('Prior claims with old roof', 1, 'decline', FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'HOME_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'HOME_BASIC'
JOIN (
	VALUES
		('Not occupied full-time',     'Q_HOME_OCCUPIED',       '=', 'false'),
		('Far from fire hydrant',      'Q_HOME_HYDRANT_DIST',   '>', '1'),
		('Old roof',                   'Q_HOME_ROOF_AGE',       '>', '20'),
		('Old electrical system',      'Q_HOME_ELECTRICAL_AGE', '>', '30'),
		('Prior claims',               'Q_HOME_CLAIMS',         '=', 'true'),
		('Prior claims with old roof', 'Q_HOME_CLAIMS',         '=', 'true'),
		('Prior claims with old roof', 'Q_HOME_ROOF_AGE',       '>', '20')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 5: occupied, close to a hydrant, but prior claims + an old roof -> compound decline (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'HOME_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'HOME_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_HOME_OCCUPIED', 'true'),
		('Q_HOME_HYDRANT_DIST', '0.5'),
		('Q_HOME_CLAIMS', 'true'),
		('Q_HOME_ROOF_AGE', '25'),
		('Q_HOME_ELECTRICAL_AGE', '10')
) AS a(code, ans) ON a.code = q.code
;

-- quote 6: not occupied full-time -> stop rule fires immediately in Model B, decline (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'HOME_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'HOME_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_HOME_OCCUPIED', 'false'),
		('Q_HOME_HYDRANT_DIST', '0.2'),
		('Q_HOME_CLAIMS', 'false'),
		('Q_HOME_ROOF_AGE', '5'),
		('Q_HOME_ELECTRICAL_AGE', '5')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Health Insurance – Product Code: HEALTH_BASIC
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('HEALTH_BASIC', 'Basic Health Insurance', 'Basic health insurance product with 7 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_HEALTH_PREEXISTING', 'Any pre-existing conditions?', 'boolean', NULL),
	('Q_HEALTH_AGE', 'Applicant age?', 'number', NULL),
	('Q_HEALTH_SMOKER', 'Do you smoke?', 'boolean', NULL),
	('Q_HEALTH_BMI', 'What is your BMI?', 'number', NULL),
	('Q_HEALTH_RISK_CATEGORY', 'Occupation risk category?', 'enum', ARRAY['low', 'medium', 'high']),
	('Q_HEALTH_HOSPITALIZATIONS', 'Hospitalizations in the last 2 years?', 'number', NULL),
	('Q_HEALTH_FAMILY_HISTORY', 'Family history of chronic illness?', 'boolean', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_HEALTH_PREEXISTING', 1, 'false'),
		('Q_HEALTH_AGE', 2, '35'),
		('Q_HEALTH_SMOKER', 3, 'false'),
		('Q_HEALTH_BMI', 4, '22'),
		('Q_HEALTH_RISK_CATEGORY', 5, 'low'),
		('Q_HEALTH_HOSPITALIZATIONS', 6, '0'),
		('Q_HEALTH_FAMILY_HISTORY', 7, 'false')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'HEALTH_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('Pre-existing condition',    1, 'increase_premium', FALSE),
		('Smoker',                    1, 'increase_premium', FALSE),
		('High-risk occupation',      1, 'refer_to_insurer',  TRUE),
		('BMI too low',               1, 'refer_to_insurer',  FALSE),
		('BMI too high',              2, 'refer_to_insurer',  FALSE),
		('Frequent hospitalizations', 1, 'refer_to_insurer',  FALSE),
		('Older smoker with pre-existing condition', 1, 'decline',          FALSE),
		('Family history with high BMI',             1, 'refer_to_insurer', FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'HEALTH_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'HEALTH_BASIC'
JOIN (
	VALUES
		('Pre-existing condition',                   'Q_HEALTH_PREEXISTING',      '=',  'true'),
		('Smoker',                                   'Q_HEALTH_SMOKER',           '=',  'true'),
		('High-risk occupation',                     'Q_HEALTH_RISK_CATEGORY',    '=',  'high'),
		('BMI too low',                              'Q_HEALTH_BMI',              '<',  '18'),
		('BMI too high',                              'Q_HEALTH_BMI',              '>',  '35'),
		('Frequent hospitalizations',                'Q_HEALTH_HOSPITALIZATIONS', '>=', '2'),
		('Older smoker with pre-existing condition', 'Q_HEALTH_AGE',              '>',  '55'),
		('Older smoker with pre-existing condition', 'Q_HEALTH_SMOKER',           '=',  'true'),
		('Older smoker with pre-existing condition', 'Q_HEALTH_PREEXISTING',      '=',  'true'),
		('Family history with high BMI',             'Q_HEALTH_FAMILY_HISTORY',   '=',  'true'),
		('Family history with high BMI',             'Q_HEALTH_BMI',              '>',  '35')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 7: everything bad at once, no stop rule fires -> decline (both models agree)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'HEALTH_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'HEALTH_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_HEALTH_PREEXISTING', 'true'),
		('Q_HEALTH_AGE', '60'),
		('Q_HEALTH_SMOKER', 'true'),
		('Q_HEALTH_BMI', '38'),
		('Q_HEALTH_RISK_CATEGORY', 'medium'),
		('Q_HEALTH_HOSPITALIZATIONS', '3'),
		('Q_HEALTH_FAMILY_HISTORY', 'true')
) AS a(code, ans) ON a.code = q.code
;

-- quote 8: 3-way compound decline is already satisfied by question 3 (age/smoker/preexisting),
-- but that rule isn't flagged stop_evaluation, so Model B keeps walking and instead stops on
-- the milder "high-risk occupation" rule at question 5 -> full=decline, short_circuit=refer_to_insurer
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'HEALTH_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'HEALTH_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_HEALTH_PREEXISTING', 'true'),
		('Q_HEALTH_AGE', '60'),
		('Q_HEALTH_SMOKER', 'true'),
		('Q_HEALTH_BMI', '20'),
		('Q_HEALTH_RISK_CATEGORY', 'high'),
		('Q_HEALTH_HOSPITALIZATIONS', '0'),
		('Q_HEALTH_FAMILY_HISTORY', 'false')
) AS a(code, ans) ON a.code = q.code
;

-- quote 9: clean pass, nothing matches -> accept (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'HEALTH_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'HEALTH_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_HEALTH_PREEXISTING', 'false'),
		('Q_HEALTH_AGE', '30'),
		('Q_HEALTH_SMOKER', 'false'),
		('Q_HEALTH_BMI', '22'),
		('Q_HEALTH_RISK_CATEGORY', 'low'),
		('Q_HEALTH_HOSPITALIZATIONS', '0'),
		('Q_HEALTH_FAMILY_HISTORY', 'false')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Travel Insurance – Product Code: TRAVEL_BASIC
-- 5 underwriting questions:
--  1) Destination risk category? (enum: low / medium / high)
--  2) Trip length (days)?
--  3) Any pre-existing medical condition?
--  4) Traveler age?
--  5) Participating in adventure sports?
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('TRAVEL_BASIC', 'Basic Travel Insurance', 'Basic travel insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_TRAVEL_DEST_RISK', 'Destination risk category?', 'enum', ARRAY['low', 'medium', 'high']),
	('Q_TRAVEL_TRIP_LENGTH', 'Trip length (days)?', 'number', NULL),
	('Q_TRAVEL_PREEXISTING', 'Any pre-existing medical condition?', 'boolean', NULL),
	('Q_TRAVEL_AGE', 'Traveler age?', 'number', NULL),
	('Q_TRAVEL_ADVENTURE', 'Participating in adventure sports?', 'boolean', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_TRAVEL_DEST_RISK', 1, 'low'),
		('Q_TRAVEL_TRIP_LENGTH', 2, '7'),
		('Q_TRAVEL_PREEXISTING', 3, 'false'),
		('Q_TRAVEL_AGE', 4, '35'),
		('Q_TRAVEL_ADVENTURE', 5, 'false')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'TRAVEL_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('High risk destination',                  1, 'refer_to_insurer',  TRUE),
		('Pre-existing condition',                  1, 'increase_premium', FALSE),
		('Long trip',                               1, 'increase_premium', FALSE),
		('Elderly traveler',                        1, 'refer_to_insurer', FALSE),
		('Adventure sports',                        1, 'increase_premium', FALSE),
		-- compound: an elderly traveler with a pre-existing condition is worse than either alone,
		-- and is only decidable once question 4 (age) is reached -- after the destination-risk
		-- stop rule would already have fired for a high-risk destination.
		('Elderly with pre-existing condition',     1, 'decline',          FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'TRAVEL_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'TRAVEL_BASIC'
JOIN (
	VALUES
		('High risk destination',              'Q_TRAVEL_DEST_RISK',   '=', 'high'),
		('Pre-existing condition',              'Q_TRAVEL_PREEXISTING', '=', 'true'),
		('Long trip',                           'Q_TRAVEL_TRIP_LENGTH', '>', '30'),
		('Elderly traveler',                    'Q_TRAVEL_AGE',         '>', '70'),
		('Adventure sports',                    'Q_TRAVEL_ADVENTURE',   '=', 'true'),
		('Elderly with pre-existing condition', 'Q_TRAVEL_AGE',         '>', '70'),
		('Elderly with pre-existing condition', 'Q_TRAVEL_PREEXISTING', '=', 'true')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 10: clean pass -> accept (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'TRAVEL_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'TRAVEL_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_TRAVEL_DEST_RISK', 'low'),
		('Q_TRAVEL_TRIP_LENGTH', '10'),
		('Q_TRAVEL_PREEXISTING', 'false'),
		('Q_TRAVEL_AGE', '40'),
		('Q_TRAVEL_ADVENTURE', 'false')
) AS a(code, ans) ON a.code = q.code
;

-- quote 11: divergence. High-risk destination (question 1) stops Model B immediately with
-- refer_to_insurer; Model A also sees the elderly+pre-existing compound at questions 3/4 and
-- returns the worse decline -> full=decline, short_circuit=refer_to_insurer
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'TRAVEL_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'TRAVEL_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_TRAVEL_DEST_RISK', 'high'),
		('Q_TRAVEL_TRIP_LENGTH', '10'),
		('Q_TRAVEL_PREEXISTING', 'true'),
		('Q_TRAVEL_AGE', '80'),
		('Q_TRAVEL_ADVENTURE', 'false')
) AS a(code, ans) ON a.code = q.code
;

-- quote 12: adventure sports only, no stop rule fires anywhere along the walk ->
-- Model B falls through to the Model A aggregate -> both = increase_premium
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'TRAVEL_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'TRAVEL_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_TRAVEL_DEST_RISK', 'low'),
		('Q_TRAVEL_TRIP_LENGTH', '5'),
		('Q_TRAVEL_PREEXISTING', 'false'),
		('Q_TRAVEL_AGE', '30'),
		('Q_TRAVEL_ADVENTURE', 'true')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Pet Insurance – Product Code: PET_BASIC
-- 5 underwriting questions:
--  1) Pet species? (enum: dog / cat / other)
--  2) Pet age (years)?
--  3) Any pre-existing conditions?
--  4) Breed risk category? (enum: low / medium / high)
--  5) Vet visits in last year?
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('PET_BASIC', 'Basic Pet Insurance', 'Basic pet insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_PET_SPECIES', 'Pet species?', 'enum', ARRAY['dog', 'cat', 'other']),
	('Q_PET_AGE', 'Pet age (years)?', 'number', NULL),
	('Q_PET_PREEXISTING', 'Any pre-existing conditions?', 'boolean', NULL),
	('Q_PET_BREED_RISK', 'Breed risk category?', 'enum', ARRAY['low', 'medium', 'high']),
	('Q_PET_VET_VISITS', 'Vet visits in last year?', 'number', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_PET_SPECIES', 1, 'dog'),
		('Q_PET_AGE', 2, '3'),
		('Q_PET_PREEXISTING', 3, 'false'),
		('Q_PET_BREED_RISK', 4, 'low'),
		('Q_PET_VET_VISITS', 5, '1')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'PET_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('Pre-existing condition',   1, 'refer_to_insurer',  TRUE),
		('Senior pet',               1, 'increase_premium',  FALSE),
		('High-risk breed',          1, 'increase_premium',  FALSE),
		('Frequent vet visits',      1, 'refer_to_insurer',  FALSE),
		-- compound: a senior pet of a high-risk breed is worse than either alone, and is only
		-- decidable once question 4 (breed risk) is reached -- after the pre-existing-condition
		-- stop rule at question 3 would already have fired.
		('Senior high-risk breed',   1, 'decline',           FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'PET_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'PET_BASIC'
JOIN (
	VALUES
		('Pre-existing condition', 'Q_PET_PREEXISTING', '=',  'true'),
		('Senior pet',             'Q_PET_AGE',          '>',  '10'),
		('High-risk breed',        'Q_PET_BREED_RISK',   '=',  'high'),
		('Frequent vet visits',    'Q_PET_VET_VISITS',   '>=', '4'),
		('Senior high-risk breed', 'Q_PET_AGE',          '>',  '10'),
		('Senior high-risk breed', 'Q_PET_BREED_RISK',   '=',  'high')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 13: clean pass -> accept (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'PET_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'PET_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_PET_SPECIES', 'dog'),
		('Q_PET_AGE', '2'),
		('Q_PET_PREEXISTING', 'false'),
		('Q_PET_BREED_RISK', 'low'),
		('Q_PET_VET_VISITS', '1')
) AS a(code, ans) ON a.code = q.code
;

-- quote 14: divergence. Pre-existing condition (question 3) stops Model B immediately with
-- refer_to_insurer; Model A also sees the senior+high-risk-breed compound at questions 2/4
-- and returns the worse decline -> full=decline, short_circuit=refer_to_insurer
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'PET_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'PET_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_PET_SPECIES', 'cat'),
		('Q_PET_AGE', '12'),
		('Q_PET_PREEXISTING', 'true'),
		('Q_PET_BREED_RISK', 'high'),
		('Q_PET_VET_VISITS', '1')
) AS a(code, ans) ON a.code = q.code
;

-- quote 15: frequent vet visits only, no stop rule fires -> both = refer_to_insurer
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'PET_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'PET_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_PET_SPECIES', 'dog'),
		('Q_PET_AGE', '3'),
		('Q_PET_PREEXISTING', 'false'),
		('Q_PET_BREED_RISK', 'low'),
		('Q_PET_VET_VISITS', '5')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Renters Insurance – Product Code: RENTERS_BASIC
-- 5 underwriting questions:
--  1) Building type? (enum: house / apartment / condo)
--  2) Security system installed?
--  3) Prior claims in last 3 years?
--  4) Total insured item value ($)?
--  5) Do you have roommates?
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('RENTERS_BASIC', 'Basic Renters Insurance', 'Basic renters insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_RENT_BUILDING_TYPE', 'Building type?', 'enum', ARRAY['house', 'apartment', 'condo']),
	('Q_RENT_SECURITY_SYSTEM', 'Security system installed?', 'boolean', NULL),
	('Q_RENT_PRIOR_CLAIMS', 'Prior claims in last 3 years?', 'number', NULL),
	('Q_RENT_ITEM_VALUE', 'Total insured item value ($)?', 'number', NULL),
	('Q_RENT_ROOMMATE', 'Do you have roommates?', 'boolean', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_RENT_BUILDING_TYPE', 1, 'apartment'),
		('Q_RENT_SECURITY_SYSTEM', 2, 'true'),
		('Q_RENT_PRIOR_CLAIMS', 3, '0'),
		('Q_RENT_ITEM_VALUE', 4, '10000'),
		('Q_RENT_ROOMMATE', 5, 'false')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'RENTERS_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('Uninsurable building type', 1, 'refer_to_insurer',  TRUE),
		('No security system',        1, 'increase_premium',  FALSE),
		('Prior claims',              1, 'refer_to_insurer',  FALSE),
		('High item value',           2, 'refer_to_insurer',  FALSE),
		('Roommates present',         1, 'increase_premium',  FALSE),
		-- compound: prior claims combined with a high insured value is worse than either alone,
		-- and is only decidable once question 4 (item value) is reached -- after the building-type
		-- stop rule at question 1 would already have fired.
		('Prior claims with high value', 1, 'decline', FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'RENTERS_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'RENTERS_BASIC'
JOIN (
	VALUES
		('Uninsurable building type',    'Q_RENT_BUILDING_TYPE',   '=', 'house'),
		('No security system',           'Q_RENT_SECURITY_SYSTEM', '=', 'false'),
		('Prior claims',                 'Q_RENT_PRIOR_CLAIMS',    '>', '1'),
		('High item value',              'Q_RENT_ITEM_VALUE',      '>', '50000'),
		('Roommates present',            'Q_RENT_ROOMMATE',        '=', 'true'),
		('Prior claims with high value', 'Q_RENT_PRIOR_CLAIMS',    '>', '1'),
		('Prior claims with high value', 'Q_RENT_ITEM_VALUE',      '>', '50000')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 16: clean pass -> accept (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'RENTERS_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'RENTERS_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_RENT_BUILDING_TYPE', 'apartment'),
		('Q_RENT_SECURITY_SYSTEM', 'true'),
		('Q_RENT_PRIOR_CLAIMS', '0'),
		('Q_RENT_ITEM_VALUE', '10000'),
		('Q_RENT_ROOMMATE', 'false')
) AS a(code, ans) ON a.code = q.code
;

-- quote 17: divergence. Uninsurable building type (question 1) stops Model B immediately with
-- refer_to_insurer; Model A also sees the prior-claims+high-value compound at questions 3/4
-- and returns the worse decline -> full=decline, short_circuit=refer_to_insurer
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'RENTERS_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'RENTERS_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_RENT_BUILDING_TYPE', 'house'),
		('Q_RENT_SECURITY_SYSTEM', 'true'),
		('Q_RENT_PRIOR_CLAIMS', '3'),
		('Q_RENT_ITEM_VALUE', '70000'),
		('Q_RENT_ROOMMATE', 'false')
) AS a(code, ans) ON a.code = q.code
;

-- quote 18: roommates only, no stop rule fires -> both = increase_premium
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'RENTERS_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'RENTERS_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_RENT_BUILDING_TYPE', 'apartment'),
		('Q_RENT_SECURITY_SYSTEM', 'true'),
		('Q_RENT_PRIOR_CLAIMS', '0'),
		('Q_RENT_ITEM_VALUE', '10000'),
		('Q_RENT_ROOMMATE', 'true')
) AS a(code, ans) ON a.code = q.code
;


----------------------------------------------------------------------------------
-- Product: Basic Umbrella Insurance – Product Code: UMBRELLA_BASIC
-- 5 underwriting questions:
--  1) Underlying liability limits meet minimum?
--  2) Prior lawsuits in last 5 years?
--  3) Net worth ($)?
--  4) Own high-risk assets (pool, trampoline, etc.)?
--  5) Requested umbrella coverage amount ($)?
----------------------------------------------------------------------------------

INSERT INTO insurance_product (code, name, description)
VALUES ('UMBRELLA_BASIC', 'Basic Umbrella Insurance', 'Basic umbrella/excess liability insurance product with 5 underwriting questions');

INSERT INTO uw_question (code, text, answer_type, enum_options)
VALUES
	('Q_UMB_UNDERLYING_LIMITS', 'Underlying liability limits meet minimum?', 'boolean', NULL),
	('Q_UMB_PRIOR_LAWSUITS', 'Prior lawsuits in last 5 years?', 'number', NULL),
	('Q_UMB_NET_WORTH', 'Net worth ($)?', 'number', NULL),
	('Q_UMB_HIGH_RISK_ASSETS', 'Own high-risk assets (pool, trampoline, etc.)?', 'boolean', NULL),
	('Q_UMB_COVERAGE_AMOUNT', 'Requested umbrella coverage amount ($)?', 'number', NULL)
;

INSERT INTO product_question (product_id, question_id, sequence, is_mandatory, expected_answer)
SELECT p.id, q.id, o.seq, TRUE, o.expected_answer
FROM insurance_product p
JOIN uw_question q ON TRUE
JOIN (
	VALUES
		('Q_UMB_UNDERLYING_LIMITS', 1, 'true'),
		('Q_UMB_PRIOR_LAWSUITS', 2, '0'),
		('Q_UMB_NET_WORTH', 3, '250000'),
		('Q_UMB_HIGH_RISK_ASSETS', 4, 'false'),
		('Q_UMB_COVERAGE_AMOUNT', 5, '1000000')
) AS o(code, seq, expected_answer) ON o.code = q.code
WHERE p.code = 'UMBRELLA_BASIC'
;

INSERT INTO uw_rule (product_id, name, priority, outcome, stop_evaluation)
SELECT p.id, r.name, r.priority, r.outcome::uw_outcome, r.stop_evaluation
FROM insurance_product p
JOIN (
	VALUES
		('Insufficient underlying limits', 1, 'refer_to_insurer',  TRUE),
		('Prior lawsuits',                 1, 'refer_to_insurer',  FALSE),
		('High requested coverage',        2, 'refer_to_insurer',  FALSE),
		('High-risk assets',               1, 'increase_premium',  FALSE),
		-- compound: prior lawsuits combined with high-risk assets is worse than either alone, and
		-- is only decidable once question 4 (high-risk assets) is reached -- after the
		-- underlying-limits stop rule at question 1 would already have fired.
		('Lawsuits with high-risk assets', 1, 'decline',           FALSE)
) AS r(name, priority, outcome, stop_evaluation) ON TRUE
WHERE p.code = 'UMBRELLA_BASIC'
;

INSERT INTO uw_rule_condition (rule_id, question_id, operator, value)
SELECT ru.id, q.id, c.operator, c.value
FROM uw_rule ru
JOIN insurance_product p ON p.id = ru.product_id AND p.code = 'UMBRELLA_BASIC'
JOIN (
	VALUES
		('Insufficient underlying limits', 'Q_UMB_UNDERLYING_LIMITS', '=', 'false'),
		('Prior lawsuits',                 'Q_UMB_PRIOR_LAWSUITS',    '>', '0'),
		('High requested coverage',        'Q_UMB_COVERAGE_AMOUNT',   '>', '5000000'),
		('High-risk assets',               'Q_UMB_HIGH_RISK_ASSETS',  '=', 'true'),
		('Lawsuits with high-risk assets', 'Q_UMB_PRIOR_LAWSUITS',    '>', '0'),
		('Lawsuits with high-risk assets', 'Q_UMB_HIGH_RISK_ASSETS',  '=', 'true')
) AS c(rule_name, question_code, operator, value)
	ON c.rule_name = ru.name
JOIN uw_question q ON q.code = c.question_code
;

-- quote 19: clean pass -> accept (both models)
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'UMBRELLA_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'UMBRELLA_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_UMB_UNDERLYING_LIMITS', 'true'),
		('Q_UMB_PRIOR_LAWSUITS', '0'),
		('Q_UMB_NET_WORTH', '300000'),
		('Q_UMB_HIGH_RISK_ASSETS', 'false'),
		('Q_UMB_COVERAGE_AMOUNT', '1000000')
) AS a(code, ans) ON a.code = q.code
;

-- quote 20: divergence. Insufficient underlying limits (question 1) stops Model B immediately
-- with refer_to_insurer; Model A also sees the lawsuits+high-risk-assets compound at questions
-- 2/4 and returns the worse decline -> full=decline, short_circuit=refer_to_insurer
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'UMBRELLA_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'UMBRELLA_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_UMB_UNDERLYING_LIMITS', 'false'),
		('Q_UMB_PRIOR_LAWSUITS', '2'),
		('Q_UMB_NET_WORTH', '300000'),
		('Q_UMB_HIGH_RISK_ASSETS', 'true'),
		('Q_UMB_COVERAGE_AMOUNT', '1000000')
) AS a(code, ans) ON a.code = q.code
;

-- quote 21: high-risk assets only, no stop rule fires -> both = increase_premium
INSERT INTO quote (product_id) SELECT id FROM insurance_product WHERE code = 'UMBRELLA_BASIC';
INSERT INTO quote_answer (quote_id, question_id, answer_text)
SELECT (SELECT max(id) FROM quote WHERE product_id = (SELECT id FROM insurance_product WHERE code = 'UMBRELLA_BASIC')),
       q.id, a.ans
FROM uw_question q
JOIN (
	VALUES
		('Q_UMB_UNDERLYING_LIMITS', 'true'),
		('Q_UMB_PRIOR_LAWSUITS', '0'),
		('Q_UMB_NET_WORTH', '300000'),
		('Q_UMB_HIGH_RISK_ASSETS', 'true'),
		('Q_UMB_COVERAGE_AMOUNT', '1000000')
) AS a(code, ans) ON a.code = q.code
;
