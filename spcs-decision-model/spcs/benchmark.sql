-- =============================================================================
-- Benchmark: Compare Decision Engines vs Snowflake AI Functions
-- =============================================================================
-- Run after the SPCS service is READY.
--
-- Workflow:
--   1. Run section 1 (test data) once
--   2. Run section 2 (SPCS engine) for current engine config
--   3. Run section 3 (Snowflake AI) once (no SPCS needed)
--   4. Run section 4 (batch size comparison) to tune throughput
--   5. Switch engine (drop/recreate service), repeat section 2
--   6. Run section 5 (summary) after collecting all results
-- =============================================================================
USE SCHEMA DJEV_DEMO.INFERENCE;

-- =============================================================================
-- SECTION 1: Test Data with Ground Truth Labels
-- =============================================================================

-- Results table: collects predictions from all engines for comparison
-- All ground_truth and predicted values are stored UPPER-CASE for consistent matching
CREATE OR REPLACE TABLE BENCHMARK_RESULTS (
    run_id VARCHAR DEFAULT UUID_STRING(),
    engine VARCHAR,
    use_case VARCHAR,
    row_id INT,
    text VARCHAR,
    ground_truth VARCHAR,
    predicted VARCHAR,
    confidence FLOAT,
    input_tokens INT,
    output_tokens INT,
    tokens_used INT,
    raw_result VARIANT,
    run_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ---- Sentiment (40 rows) ----
CREATE OR REPLACE TABLE BENCHMARK_SENTIMENT (
    id INT, text VARCHAR, ground_truth VARCHAR
);

INSERT INTO BENCHMARK_SENTIMENT VALUES
    -- Positive (14)
    (1,  'This laptop is absolutely fantastic! The battery life exceeds all expectations.', 'positive'),
    (2,  'Customer support was incredibly helpful and resolved my issue within minutes.', 'positive'),
    (3,  'The pasta was divine and the ambiance was perfect!', 'positive'),
    (4,  'Record-breaking quarterly earnings, surpassing analyst estimates by 20%.', 'positive'),
    (5,  'I am thrilled with the new update. Everything runs so much smoother now.', 'positive'),
    (6,  'Best purchase I have made all year. Highly recommend to everyone.', 'positive'),
    (7,  'The team delivered an outstanding presentation. The client was visibly impressed.', 'positive'),
    (8,  'Our net promoter score jumped 15 points after the redesign launched.', 'positive'),
    (9,  'Love the new feature. It saves me at least an hour every week.', 'positive'),
    (10, 'The concert was electrifying. Every song was better than the last.', 'positive'),
    (11, 'Revenue grew 32% year-over-year, the strongest quarter in company history.', 'positive'),
    (12, 'The hotel staff went above and beyond to make our anniversary special.', 'positive'),
    (13, 'Shipping was lightning fast and the packaging was immaculate.', 'positive'),
    (14, 'This framework makes building APIs a joy. Clean, intuitive, well-documented.', 'positive'),
    -- Negative (14)
    (15, 'Terrible build quality. Screen cracked after just two weeks of normal use.', 'negative'),
    (16, 'Three hours on hold. This is the worst customer service experience I have ever had.', 'negative'),
    (17, 'Rain ruined my commute again. Soaked through before reaching the train.', 'negative'),
    (18, 'Massive layoffs hit the tech sector as recession fears grow and spending plummets.', 'negative'),
    (19, 'The app crashes every time I try to upload a photo. Completely unusable.', 'negative'),
    (20, 'We lost three major clients this quarter due to repeated outages.', 'negative'),
    (21, 'The food was cold, the waiter was rude, and we waited 45 minutes for the check.', 'negative'),
    (22, 'My account was charged twice and nobody will respond to my support tickets.', 'negative'),
    (23, 'The new policy is a disaster. Employee satisfaction has cratered.', 'negative'),
    (24, 'Investors dumped the stock after guidance was cut for the third consecutive quarter.', 'negative'),
    (25, 'The product arrived damaged with no option for return or refund.', 'negative'),
    (26, 'Performance degraded significantly after the last update. Rollback was needed.', 'negative'),
    (27, 'Security breach exposed 2 million customer records. Trust is gone.', 'negative'),
    (28, 'The contractor missed every deadline and went 40% over budget.', 'negative'),
    -- Neutral (12)
    (29, 'The laptop weighs 3.2 pounds and has a 14-inch display with 1920x1080 resolution.', 'neutral'),
    (30, 'Support hours are Monday through Friday, 9am to 5pm Eastern.', 'neutral'),
    (31, 'Weather forecast says 72 degrees and sunny tomorrow.', 'neutral'),
    (32, 'The Federal Reserve held interest rates steady at its latest meeting, as expected.', 'neutral'),
    (33, 'The meeting is scheduled for 2pm in conference room B.', 'neutral'),
    (34, 'Python 3.12 was released in October 2023 with several performance improvements.', 'neutral'),
    (35, 'The company has 12,000 employees across 30 offices worldwide.', 'neutral'),
    (36, 'The API accepts POST requests with a JSON body. Rate limit is 100 requests per minute.', 'neutral'),
    (37, 'The new office is located at 123 Main Street, three blocks from the subway.', 'neutral'),
    (38, 'Q2 results will be announced on August 15 during the earnings call.', 'neutral'),
    (39, 'The database migration is scheduled for this weekend during the maintenance window.', 'neutral'),
    (40, 'The report contains 47 pages covering operations in 12 countries.', 'neutral');

-- ---- Entity Resolution (20 rows) ----
CREATE OR REPLACE TABLE BENCHMARK_ENTITIES (
    id INT, description VARCHAR, candidates VARCHAR, ground_truth VARCHAR
);

INSERT INTO BENCHMARK_ENTITIES VALUES
    (1,  'Tech giant known for iPhone, iPad, and Mac computers. Headquartered in Cupertino, California.',
         '["Apple Inc.", "Apple Records", "Apple Farming Cooperative"]', 'Apple Inc.'),
    (2,  'British record label founded by The Beatles in 1968. Released albums on green apple logo.',
         '["Apple Inc.", "Apple Records", "Apple Farming Cooperative"]', 'Apple Records'),
    (3,  'Global e-commerce and cloud computing company founded by Jeff Bezos. Started as online bookstore.',
         '["Amazon.com Inc.", "Amazon River Tours", "Amazone Motorcycles"]', 'Amazon.com Inc.'),
    (4,  'The largest river by water volume in South America, flowing through Brazil and Peru.',
         '["Amazon.com Inc.", "Amazon River Tours", "Amazone Motorcycles"]', 'Amazon River Tours'),
    (5,  'Investment bank and financial services company on Wall Street. Known for trading and M&A.',
         '["Goldman Sachs Group", "Gold Man Jewelry", "Goldman Family Foundation"]', 'Goldman Sachs Group'),
    (6,  'Japanese automaker producing Corolla, Camry, and Prius. Pioneer of hybrid vehicles.',
         '["Toyota Motor Corporation", "Toyoda Automatic Loom Works", "Toyota City Tourism Bureau"]', 'Toyota Motor Corporation'),
    (7,  'Creator of the Python programming language. Worked at Google, then Microsoft.',
         '["Guido van Rossum", "Python Software Foundation", "Rossum Robotics"]', 'Guido van Rossum'),
    (8,  'Professional networking platform acquired by Microsoft in 2016 for $26.2 billion.',
         '["LinkedIn Corporation", "Link-In Chain Manufacturing", "Linked Data Institute"]', 'LinkedIn Corporation'),
    (9,  'South Korean electronics conglomerate that makes Galaxy smartphones and semiconductor chips.',
         '["Samsung Electronics", "Samsung Life Insurance", "Samsung C&T Corporation"]', 'Samsung Electronics'),
    (10, 'Open-source relational database management system owned by Oracle Corporation.',
         '["MySQL AB", "My Sequel Film Productions", "MySQL Community Edition"]', 'MySQL AB'),
    (11, 'Electric vehicle manufacturer founded by Elon Musk, known for Model S, 3, X, and Y.',
         '["Tesla Inc.", "Tesla Electric Light Company", "Nikola Tesla Museum"]', 'Tesla Inc.'),
    (12, 'Serbian-American inventor who pioneered alternating current electrical systems.',
         '["Tesla Inc.", "Tesla Electric Light Company", "Nikola Tesla Museum"]', 'Nikola Tesla Museum'),
    (13, 'Streaming music service founded in Sweden. Freemium model with ad-supported and premium tiers.',
         '["Spotify Technology", "Spotify Studios", "Swedish Music Export"]', 'Spotify Technology'),
    (14, 'Cloud data platform that enables data warehousing, data lakes, and data sharing.',
         '["Snowflake Inc.", "Snowflake Gelato", "Snowflake Mountain Resort"]', 'Snowflake Inc.'),
    (15, 'Luxury fashion house founded in Florence, Italy. Known for bamboo-handled handbags.',
         '["Gucci (Kering)", "Guccio Gucci Foundation", "Gucci Osteria Restaurant"]', 'Gucci (Kering)'),
    (16, 'Ride-hailing company founded in San Francisco. Competes with Lyft.',
         '["Uber Technologies", "Uber Eats (standalone)", "Uber Freight Logistics"]', 'Uber Technologies'),
    (17, 'Video conferencing platform that surged during COVID-19 pandemic.',
         '["Zoom Video Communications", "Zoom Telephonics", "Zoom Media Group"]', 'Zoom Video Communications'),
    (18, 'Legacy router and network infrastructure company. Dominant in enterprise networking.',
         '["Cisco Systems", "Sysco Corporation", "Francisco Partners"]', 'Cisco Systems'),
    (19, 'German automaker known for the 911 sports car and Cayenne SUV.',
         '["Porsche AG", "Porsche Design", "Ferdinand Porsche Foundation"]', 'Porsche AG'),
    (20, 'Fast food chain known for the Big Mac and golden arches logo.',
         '["McDonald''s Corporation", "MacDonald Dettwiler", "Old MacDonald Farms"]', 'McDonald''s Corporation');

-- ---- Document Filtering (30 rows, ground_truth stored as VARCHAR for clean matching) ----
CREATE OR REPLACE TABLE BENCHMARK_DOCUMENTS (
    id INT, text VARCHAR, criteria VARCHAR, ground_truth VARCHAR
);

INSERT INTO BENCHMARK_DOCUMENTS VALUES
    -- Financial metrics (criteria: "Contains quantitative financial performance metrics")
    (1,  'Q3 Earnings: Revenue increased 18% YoY to $4.2B. Operating margin improved to 23%. Free cash flow was $890M.', 'Contains quantitative financial performance metrics', 'TRUE'),
    (2,  'EBITDA reached $1.3B, up from $980M last year. Gross margin expanded 340 basis points to 67.2%.', 'Contains quantitative financial performance metrics', 'TRUE'),
    (3,  'The company reported a net loss of $42M on revenue of $310M, missing consensus by $0.12 per share.', 'Contains quantitative financial performance metrics', 'TRUE'),
    (4,  'ARR crossed the $500M milestone this quarter, with net revenue retention at 128%.', 'Contains quantitative financial performance metrics', 'TRUE'),
    (5,  'Same-store sales grew 4.7% driven by a 2.1% increase in traffic and 2.6% increase in average ticket.', 'Contains quantitative financial performance metrics', 'TRUE'),
    (6,  'The board of directors declared a quarterly dividend of $0.50 per share payable December 15.', 'Contains quantitative financial performance metrics', 'FALSE'),
    (7,  'We remain committed to long-term shareholder value creation and operational excellence.', 'Contains quantitative financial performance metrics', 'FALSE'),
    (8,  'The company plans to expand into three new markets in the coming fiscal year.', 'Contains quantitative financial performance metrics', 'FALSE'),
    (9,  'Management believes the current macroeconomic environment presents both challenges and opportunities.', 'Contains quantitative financial performance metrics', 'FALSE'),
    (10, 'The annual shareholder meeting will be held on May 15 at corporate headquarters.', 'Contains quantitative financial performance metrics', 'FALSE'),
    -- PII (criteria: "Contains personally identifiable information")
    (11, 'We are pleased to offer you the position of Senior Software Engineer at $185,000 base salary with benefits.', 'Contains personally identifiable information', 'TRUE'),
    (12, 'Patient John Smith, DOB 03/15/1987, presented with acute respiratory symptoms. SpO2 was 94%.', 'Contains personally identifiable information', 'TRUE'),
    (13, 'Please ship the order to Sarah Johnson, 742 Evergreen Terrace, Springfield, IL 62704.', 'Contains personally identifiable information', 'TRUE'),
    (14, 'The applicant, Maria Garcia (SSN ending 4589), passed the background check and drug screening.', 'Contains personally identifiable information', 'TRUE'),
    (15, 'Contact the account holder at david.chen@example.com or (555) 867-5309 for verification.', 'Contains personally identifiable information', 'TRUE'),
    (16, 'Annual performance reviews will be conducted in Q1. All employees must complete self-assessments by Feb 15.', 'Contains personally identifiable information', 'FALSE'),
    (17, 'The API endpoint accepts POST requests with JSON body containing state and questions fields.', 'Contains personally identifiable information', 'FALSE'),
    (18, 'Company policy requires two-factor authentication for all systems with access to production data.', 'Contains personally identifiable information', 'FALSE'),
    (19, 'The infrastructure team will perform scheduled maintenance on Saturday from 2am to 6am EST.', 'Contains personally identifiable information', 'FALSE'),
    (20, 'All new hires must complete security awareness training within their first 30 days.', 'Contains personally identifiable information', 'FALSE'),
    -- Legal content (criteria: "Contains legal terms, obligations, or regulatory language")
    (21, 'WHEREAS the parties agree to the terms and conditions of this software license agreement effective Jan 1, 2025.', 'Contains legal terms, obligations, or regulatory language', 'TRUE'),
    (22, 'The defendant filed a motion to dismiss citing lack of jurisdiction under 28 U.S.C. section 1332.', 'Contains legal terms, obligations, or regulatory language', 'TRUE'),
    (23, 'Indemnification: Vendor shall indemnify and hold harmless the Client from any claims arising from negligence.', 'Contains legal terms, obligations, or regulatory language', 'TRUE'),
    (24, 'Under GDPR Article 17, the data subject has the right to erasure of personal data without undue delay.', 'Contains legal terms, obligations, or regulatory language', 'TRUE'),
    (25, 'Non-compete: Employee agrees not to engage in competing business within 50 miles for 24 months post-termination.', 'Contains legal terms, obligations, or regulatory language', 'TRUE'),
    (26, 'The project kickoff meeting is Thursday at 10am. Please review the attached requirements document.', 'Contains legal terms, obligations, or regulatory language', 'FALSE'),
    (27, 'Disk usage on prod-db-03 has reached 87%. Consider archiving tables older than 90 days.', 'Contains legal terms, obligations, or regulatory language', 'FALSE'),
    (28, 'The marketing team requests a new landing page for the Q4 campaign launching November 1.', 'Contains legal terms, obligations, or regulatory language', 'FALSE'),
    (29, 'Sprint velocity averaged 42 points over the last 4 sprints with a standard deviation of 3.1.', 'Contains legal terms, obligations, or regulatory language', 'FALSE'),
    (30, 'The CI pipeline takes approximately 12 minutes and runs 847 unit tests across 3 services.', 'Contains legal terms, obligations, or regulatory language', 'FALSE');

-- ---- Scale up to 1000 rows for latency testing ----
-- Cycles through the seed rows so every row has a valid ground truth label.
-- Accuracy tests use the original tables; latency tests use these.

CREATE OR REPLACE TABLE DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K AS
SELECT
    ROW_NUMBER() OVER (ORDER BY g.seq, s.id) AS id,
    s.text,
    s.ground_truth
FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT s
CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 25))) g
ORDER BY id
LIMIT 1000;

CREATE OR REPLACE TABLE DJEV_DEMO.INFERENCE.BENCHMARK_ENTITIES_1K AS
SELECT
    ROW_NUMBER() OVER (ORDER BY g.seq, e.id) AS id,
    e.description,
    e.candidates,
    e.ground_truth
FROM DJEV_DEMO.INFERENCE.BENCHMARK_ENTITIES e
CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 50))) g
ORDER BY id
LIMIT 1000;

CREATE OR REPLACE TABLE DJEV_DEMO.INFERENCE.BENCHMARK_DOCUMENTS_1K AS
SELECT
    ROW_NUMBER() OVER (ORDER BY g.seq, d.id) AS id,
    d.text,
    d.criteria,
    d.ground_truth
FROM DJEV_DEMO.INFERENCE.BENCHMARK_DOCUMENTS d
CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 34))) g
ORDER BY id
LIMIT 1000;


-- =============================================================================
-- SECTION 2: SPCS Engine Benchmarks (run per engine config)
-- =============================================================================
-- Before running, note which engine is deployed:
--   SELECT SYSTEM$GET_SERVICE_STATUS('DJEV_DEMO.INFERENCE.DECISION_SERVICE');

-- 2A. Sentiment
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'CURRENT_ENGINE' AS engine,  -- replace with actual engine name before running
    'sentiment' AS use_case,
    s.id,
    s.text,
    LOWER(s.ground_truth),
    LOWER(TRIM(result:sentiment:choice::VARCHAR)) AS predicted,
    result:sentiment:confidence::FLOAT AS confidence,
    NULL AS input_tokens,
    NULL AS output_tokens,
    NULL AS tokens_used,
    result
FROM (
    SELECT s.*, DECIDE(s.text, OBJECT_CONSTRUCT(
        'sentiment', OBJECT_CONSTRUCT(
            'type', 'choice',
            'instructions', 'Classify the sentiment of the text.',
            'criteria', OBJECT_CONSTRUCT(
                'positive', 'The text expresses a positive sentiment, opinion, or emotion.',
                'negative', 'The text expresses a negative sentiment, opinion, or emotion.',
                'neutral', 'The text is neutral, factual, or does not express clear sentiment.'
            )
        )
    )) AS result
    FROM BENCHMARK_SENTIMENT s
) s;

-- 2B. Entity Resolution
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'CURRENT_ENGINE' AS engine,
    'entity_resolution' AS use_case,
    e.id,
    e.description,
    TRIM(e.ground_truth),
    TRIM(result:match:choice::VARCHAR) AS predicted,
    result:match:confidence::FLOAT AS confidence,
    NULL AS input_tokens,
    NULL AS output_tokens,
    NULL AS tokens_used,
    result
FROM (
    SELECT e.*, DECIDE(e.description, OBJECT_CONSTRUCT(
        'match', OBJECT_CONSTRUCT(
            'type', 'choice',
            'instructions', 'Which entity best matches this description?',
            'criteria', PARSE_JSON(e.candidates)
        )
    )) AS result
    FROM BENCHMARK_ENTITIES e
) e;

-- 2C. Document Filtering
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'CURRENT_ENGINE' AS engine,
    'document_filter' AS use_case,
    d.id,
    d.text,
    UPPER(TRIM(d.ground_truth)),
    IFF(result:relevant:noul::FLOAT >= 0.5, 'TRUE', 'FALSE') AS predicted,
    result:relevant:noul::FLOAT AS confidence,
    NULL AS input_tokens,
    NULL AS output_tokens,
    NULL AS tokens_used,
    result
FROM (
    SELECT d.*, DECIDE(d.text, OBJECT_CONSTRUCT(
        'relevant', OBJECT_CONSTRUCT(
            'type', 'noul',
            'instructions', d.criteria
        )
    )) AS result
    FROM BENCHMARK_DOCUMENTS d
) d;


-- =============================================================================
-- SECTION 3: Snowflake AI Function Baselines
-- =============================================================================

-- 3A. AI_CLASSIFY — Sentiment
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'ai_classify' AS engine,
    'sentiment' AS use_case,
    s.id,
    s.text,
    LOWER(s.ground_truth),
    LOWER(TRIM(result:labels[0]::VARCHAR)) AS predicted,
    NULL AS confidence,
    AI_COUNT_TOKENS('ai_classify', s.text, ['positive', 'negative', 'neutral']) AS input_tokens,
    NULL AS output_tokens,
    input_tokens AS tokens_used,
    result
FROM (
    SELECT s.*, AI_CLASSIFY(s.text, ['positive', 'negative', 'neutral']) AS result
    FROM BENCHMARK_SENTIMENT s
) s;

-- 3B. AI_COMPLETE — Sentiment (structured output with token tracking)
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'ai_complete' AS engine,
    'sentiment' AS use_case,
    s.id,
    s.text,
    LOWER(s.ground_truth),
    LOWER(TRIM(result:structured_output[0]:raw_message:label::VARCHAR)) AS predicted,
    result:structured_output[0]:raw_message:confidence::FLOAT AS confidence,
    result:usage:prompt_tokens::INT AS input_tokens,
    result:usage:completion_tokens::INT AS output_tokens,
    result:usage:total_tokens::INT AS tokens_used,
    result
FROM (
    SELECT s.*, AI_COMPLETE(
        model => 'claude-haiku-4-5',
        prompt => 'Classify the sentiment of the following text as exactly one of: positive, negative, neutral. Return the label and a confidence score between 0 and 1.\n\nText: "' || s.text || '"',
        response_format => {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'label': {'type': 'string', 'enum': ['positive', 'negative', 'neutral']},
                    'confidence': {'type': 'number'}
                },
                'required': ['label', 'confidence']
            }
        },
        show_details => TRUE
    ) AS result
    FROM BENCHMARK_SENTIMENT s
) s;

-- 3C. AI_CLASSIFY — Entity Resolution
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'ai_classify' AS engine,
    'entity_resolution' AS use_case,
    e.id,
    e.description,
    TRIM(e.ground_truth),
    TRIM(result:labels[0]::VARCHAR) AS predicted,
    NULL AS confidence,
    AI_COUNT_TOKENS('ai_classify', e.description, PARSE_JSON(e.candidates)) AS input_tokens,
    NULL AS output_tokens,
    input_tokens AS tokens_used,
    result
FROM (
    SELECT e.*, AI_CLASSIFY(e.description, PARSE_JSON(e.candidates)) AS result
    FROM BENCHMARK_ENTITIES e
) e;

-- 3D. AI_COMPLETE — Entity Resolution (structured output with token tracking)
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'ai_complete' AS engine,
    'entity_resolution' AS use_case,
    e.id,
    e.description,
    TRIM(e.ground_truth),
    TRIM(result:structured_output[0]:raw_message:match::VARCHAR) AS predicted,
    result:structured_output[0]:raw_message:confidence::FLOAT AS confidence,
    result:usage:prompt_tokens::INT AS input_tokens,
    result:usage:completion_tokens::INT AS output_tokens,
    result:usage:total_tokens::INT AS tokens_used,
    result
FROM (
    SELECT e.*, AI_COMPLETE(
        model => 'claude-haiku-4-5',
        prompt => 'Given this description: "' || e.description ||
            '"\nWhich of these entities is the best match?\nOptions: ' || e.candidates ||
            '\nReturn the exact entity name and a confidence score between 0 and 1.',
        response_format => {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'match': {'type': 'string'},
                    'confidence': {'type': 'number'}
                },
                'required': ['match', 'confidence']
            }
        },
        show_details => TRUE
    ) AS result
    FROM BENCHMARK_ENTITIES e
) e;

-- 3E. AI_CLASSIFY — Document Filtering (task_description provides per-row criteria)
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'ai_classify' AS engine,
    'document_filter' AS use_case,
    d.id,
    d.text,
    UPPER(TRIM(d.ground_truth)),
    IFF(LOWER(TRIM(result:labels[0]::VARCHAR)) = 'yes', 'TRUE', 'FALSE') AS predicted,
    NULL AS confidence,
    AI_COUNT_TOKENS('ai_classify', d.text, ['yes', 'no'], {'task_description': d.criteria || '? Answer yes or no.'}) AS input_tokens,
    NULL AS output_tokens,
    input_tokens AS tokens_used,
    result
FROM (
    SELECT d.*, AI_CLASSIFY(
        d.text,
        ['yes', 'no'],
        {'task_description': d.criteria || '? Answer yes or no.'}
    ) AS result
    FROM BENCHMARK_DOCUMENTS d
) d;

-- 3F. AI_COMPLETE — Document Filtering (structured output with token tracking)
INSERT INTO BENCHMARK_RESULTS (engine, use_case, row_id, text, ground_truth, predicted, confidence, input_tokens, output_tokens, tokens_used, raw_result)
SELECT
    'ai_complete' AS engine,
    'document_filter' AS use_case,
    d.id,
    d.text,
    UPPER(TRIM(d.ground_truth)),
    IFF(result:structured_output[0]:raw_message:meets_criteria::BOOLEAN, 'TRUE', 'FALSE') AS predicted,
    result:structured_output[0]:raw_message:confidence::FLOAT AS confidence,
    result:usage:prompt_tokens::INT AS input_tokens,
    result:usage:completion_tokens::INT AS output_tokens,
    result:usage:total_tokens::INT AS tokens_used,
    result
FROM (
    SELECT d.*, AI_COMPLETE(
        model => 'claude-haiku-4-5',
        prompt => 'Does the following text meet this criteria: "' || d.criteria ||
            '"?\nReturn whether the criteria is met and a confidence score between 0 and 1.\n\nText: "' || d.text || '"',
        response_format => {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'meets_criteria': {'type': 'boolean'},
                    'confidence': {'type': 'number'}
                },
                'required': ['meets_criteria', 'confidence']
            }
        },
        show_details => TRUE
    ) AS result
    FROM BENCHMARK_DOCUMENTS d
) d;


-- =============================================================================
-- SECTION 4: Batch Size Comparison (SPCS engine throughput tuning)
-- =============================================================================

-- Batch size 1 (no batching)
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE_BATCH_1(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 1
    AS '/predict';

-- Batch size 4
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE_BATCH_4(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 4
    AS '/predict';

-- Batch size 8 (default)
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE_BATCH_8(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 8
    AS '/predict';

-- Batch size 16
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE_BATCH_16(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 16
    AS '/predict';

-- Batch size 32
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE_BATCH_32(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 32
    AS '/predict';

-- Batch size 64
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE_BATCH_64(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 64
    AS '/predict';

-- Run batch size comparison via stored procedure (CTAS forces full materialization)
CREATE OR REPLACE TABLE DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY (
    batch_size INT,
    row_count INT,
    total_ms INT,
    ms_per_row FLOAT
);

CREATE OR REPLACE PROCEDURE DJEV_DEMO.INFERENCE.RUN_BATCH_BENCHMARKS()
RETURNS VARCHAR
LANGUAGE SQL
AS
DECLARE
    t_start TIMESTAMP_NTZ;
    t_end TIMESTAMP_NTZ;
    elapsed INT;
    cnt INT;
    per_row FLOAT;
BEGIN
    DELETE FROM DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY;

    -- Batch 1
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._BATCH_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE_BATCH_1(text, OBJECT_CONSTRUCT('sentiment', OBJECT_CONSTRUCT('type', 'choice', 'instructions', 'Classify the sentiment of the text.', 'criteria', OBJECT_CONSTRUCT('positive', 'positive sentiment', 'negative', 'negative sentiment', 'neutral', 'neutral or factual')))) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._BATCH_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY VALUES (1, :cnt, :elapsed, :per_row);

    -- Batch 4
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._BATCH_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE_BATCH_4(text, OBJECT_CONSTRUCT('sentiment', OBJECT_CONSTRUCT('type', 'choice', 'instructions', 'Classify the sentiment of the text.', 'criteria', OBJECT_CONSTRUCT('positive', 'positive sentiment', 'negative', 'negative sentiment', 'neutral', 'neutral or factual')))) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._BATCH_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY VALUES (4, :cnt, :elapsed, :per_row);

    -- Batch 8
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._BATCH_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE_BATCH_8(text, OBJECT_CONSTRUCT('sentiment', OBJECT_CONSTRUCT('type', 'choice', 'instructions', 'Classify the sentiment of the text.', 'criteria', OBJECT_CONSTRUCT('positive', 'positive sentiment', 'negative', 'negative sentiment', 'neutral', 'neutral or factual')))) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._BATCH_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY VALUES (8, :cnt, :elapsed, :per_row);

    -- Batch 16
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._BATCH_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE_BATCH_16(text, OBJECT_CONSTRUCT('sentiment', OBJECT_CONSTRUCT('type', 'choice', 'instructions', 'Classify the sentiment of the text.', 'criteria', OBJECT_CONSTRUCT('positive', 'positive sentiment', 'negative', 'negative sentiment', 'neutral', 'neutral or factual')))) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._BATCH_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY VALUES (16, :cnt, :elapsed, :per_row);

    -- Batch 32
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._BATCH_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE_BATCH_32(text, OBJECT_CONSTRUCT('sentiment', OBJECT_CONSTRUCT('type', 'choice', 'instructions', 'Classify the sentiment of the text.', 'criteria', OBJECT_CONSTRUCT('positive', 'positive sentiment', 'negative', 'negative sentiment', 'neutral', 'neutral or factual')))) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._BATCH_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY VALUES (32, :cnt, :elapsed, :per_row);

    -- Batch 64
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._BATCH_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE_BATCH_64(text, OBJECT_CONSTRUCT('sentiment', OBJECT_CONSTRUCT('type', 'choice', 'instructions', 'Classify the sentiment of the text.', 'criteria', OBJECT_CONSTRUCT('positive', 'positive sentiment', 'negative', 'negative sentiment', 'neutral', 'neutral or factual')))) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._BATCH_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY VALUES (64, :cnt, :elapsed, :per_row);

    DROP TABLE IF EXISTS DJEV_DEMO.INFERENCE._BATCH_TMP;
    RETURN 'Done: 6 batch size benchmarks recorded';
END;

-- Run it:
CALL DJEV_DEMO.INFERENCE.RUN_BATCH_BENCHMARKS();

-- View results:
SELECT
    batch_size,
    row_count,
    total_ms,
    ROUND(ms_per_row, 1) AS ms_per_row
FROM DJEV_DEMO.INFERENCE.BENCHMARK_BATCH_LATENCY
ORDER BY batch_size;


-- =============================================================================
-- SECTION 5: Latency — All Engines x All Use Cases
-- =============================================================================
-- A stored procedure runs each query and records wall-clock time.

CREATE OR REPLACE TABLE DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY (
    engine VARCHAR,
    use_case VARCHAR,
    row_count INT,
    total_ms INT,
    ms_per_row FLOAT
);

CREATE OR REPLACE PROCEDURE DJEV_DEMO.INFERENCE.RUN_LATENCY_BENCHMARKS()
RETURNS VARCHAR
LANGUAGE SQL
AS
DECLARE
    t_start TIMESTAMP_NTZ;
    t_end TIMESTAMP_NTZ;
    elapsed INT;
    cnt INT;
    per_row FLOAT;
BEGIN
    DELETE FROM DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY;

    -- SPCS: Sentiment
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE(text, OBJECT_CONSTRUCT(
            'sentiment', OBJECT_CONSTRUCT(
                'type', 'choice',
                'instructions', 'Classify the sentiment of the text.',
                'criteria', OBJECT_CONSTRUCT(
                    'positive', 'positive sentiment',
                    'negative', 'negative sentiment',
                    'neutral', 'neutral or factual'
                )
            )
        )) AS result FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('CURRENT_ENGINE', 'sentiment', :cnt, :elapsed, :per_row);

    -- SPCS: Entity Resolution
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE(description, OBJECT_CONSTRUCT(
            'match', OBJECT_CONSTRUCT(
                'type', 'choice',
                'instructions', 'Which entity best matches this description?',
                'criteria', PARSE_JSON(candidates)
            )
        )) AS result FROM DJEV_DEMO.INFERENCE.BENCHMARK_ENTITIES_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('CURRENT_ENGINE', 'entity_resolution', :cnt, :elapsed, :per_row);

    -- SPCS: Document Filtering
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT DJEV_DEMO.INFERENCE.DECIDE(text, OBJECT_CONSTRUCT(
            'relevant', OBJECT_CONSTRUCT(
                'type', 'noul',
                'instructions', criteria
            )
        )) AS result FROM DJEV_DEMO.INFERENCE.BENCHMARK_DOCUMENTS_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('CURRENT_ENGINE', 'document_filter', :cnt, :elapsed, :per_row);

    -- AI_CLASSIFY: Sentiment
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT AI_CLASSIFY(text, ['positive', 'negative', 'neutral']) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('ai_classify', 'sentiment', :cnt, :elapsed, :per_row);

    -- AI_CLASSIFY: Entity Resolution
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT AI_CLASSIFY(description, PARSE_JSON(candidates)) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_ENTITIES_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('ai_classify', 'entity_resolution', :cnt, :elapsed, :per_row);

    -- AI_CLASSIFY: Document Filtering
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT AI_CLASSIFY(text, ['yes', 'no'], {'task_description': criteria || '? Answer yes or no.'}) AS result
        FROM DJEV_DEMO.INFERENCE.BENCHMARK_DOCUMENTS_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('ai_classify', 'document_filter', :cnt, :elapsed, :per_row);

    -- AI_COMPLETE: Sentiment
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT AI_COMPLETE(
            model => 'claude-haiku-4-5',
            prompt => 'Classify the sentiment as positive, negative, or neutral. Return label and confidence.\n\nText: "' || text || '"',
            response_format => {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'label': {'type': 'string', 'enum': ['positive', 'negative', 'neutral']},
                        'confidence': {'type': 'number'}
                    },
                    'required': ['label', 'confidence']
                }
            }
        ) AS result FROM DJEV_DEMO.INFERENCE.BENCHMARK_SENTIMENT_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('ai_complete', 'sentiment', :cnt, :elapsed, :per_row);

    -- AI_COMPLETE: Entity Resolution
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT AI_COMPLETE(
            model => 'claude-haiku-4-5',
            prompt => 'Which entity best matches: "' || description || '"?\nOptions: ' || candidates || '\nReturn exact name and confidence.',
            response_format => {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'match': {'type': 'string'},
                        'confidence': {'type': 'number'}
                    },
                    'required': ['match', 'confidence']
                }
            }
        ) AS result FROM DJEV_DEMO.INFERENCE.BENCHMARK_ENTITIES_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('ai_complete', 'entity_resolution', :cnt, :elapsed, :per_row);

    -- AI_COMPLETE: Document Filtering
    t_start := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    CREATE OR REPLACE TEMPORARY TABLE DJEV_DEMO.INFERENCE._LATENCY_TMP AS
        SELECT AI_COMPLETE(
            model => 'claude-haiku-4-5',
            prompt => 'Does this text meet criteria "' || criteria || '"? Return boolean and confidence.\n\nText: "' || text || '"',
            response_format => {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'meets_criteria': {'type': 'boolean'},
                        'confidence': {'type': 'number'}
                    },
                    'required': ['meets_criteria', 'confidence']
                }
            }
        ) AS result FROM DJEV_DEMO.INFERENCE.BENCHMARK_DOCUMENTS_1K;
    t_end := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    SELECT COUNT(*) INTO :cnt FROM DJEV_DEMO.INFERENCE._LATENCY_TMP;
    elapsed := TIMESTAMPDIFF('millisecond', :t_start, :t_end);
    per_row := :elapsed / :cnt;
    INSERT INTO DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY VALUES ('ai_complete', 'document_filter', :cnt, :elapsed, :per_row);

    DROP TABLE IF EXISTS DJEV_DEMO.INFERENCE._LATENCY_TMP;
    RETURN 'Done: 9 latency benchmarks recorded';
END;

-- Run it:
CALL DJEV_DEMO.INFERENCE.RUN_LATENCY_BENCHMARKS();

-- View results:
SELECT
    engine,
    use_case,
    row_count,
    total_ms,
    ROUND(ms_per_row, 1) AS ms_per_row
FROM DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY
ORDER BY use_case, total_ms;


-- =============================================================================
-- SECTION 6: Summary — Accuracy & Comparison
-- =============================================================================

-- Overall accuracy by engine and use case
SELECT
    engine,
    use_case,
    COUNT(*) AS total,
    SUM(IFF(predicted = ground_truth, 1, 0)) AS correct,
    ROUND(correct / total, 4) AS accuracy,
    ROUND(AVG(confidence), 4) AS avg_confidence
FROM BENCHMARK_RESULTS
GROUP BY engine, use_case
ORDER BY use_case, accuracy DESC;

-- Overall accuracy by engine (across all use cases)
SELECT
    engine,
    COUNT(*) AS total,
    SUM(IFF(predicted = ground_truth, 1, 0)) AS correct,
    ROUND(correct / total, 4) AS accuracy
FROM BENCHMARK_RESULTS
GROUP BY engine
ORDER BY accuracy DESC;

-- Head-to-head: where do engines disagree?
-- Uses normalized comparison to handle any residual case/whitespace differences
SELECT
    a.use_case,
    a.row_id,
    LEFT(a.text, 80) AS text_preview,
    a.ground_truth,
    a.engine AS engine_a,
    a.predicted AS predicted_a,
    (LOWER(TRIM(a.predicted)) = LOWER(TRIM(a.ground_truth))) AS a_correct,
    b.engine AS engine_b,
    b.predicted AS predicted_b,
    (LOWER(TRIM(b.predicted)) = LOWER(TRIM(b.ground_truth))) AS b_correct
FROM BENCHMARK_RESULTS a
JOIN BENCHMARK_RESULTS b
    ON a.use_case = b.use_case AND a.row_id = b.row_id AND a.engine < b.engine
WHERE LOWER(TRIM(a.predicted)) != LOWER(TRIM(b.predicted))
ORDER BY a.use_case, a.row_id, a.engine;

-- Confidence calibration: are high-confidence predictions more accurate?
SELECT
    engine,
    CASE
        WHEN confidence >= 0.9 THEN '0.9-1.0'
        WHEN confidence >= 0.7 THEN '0.7-0.9'
        WHEN confidence >= 0.5 THEN '0.5-0.7'
        ELSE '<0.5'
    END AS confidence_bucket,
    COUNT(*) AS n,
    SUM(IFF(LOWER(TRIM(predicted)) = LOWER(TRIM(ground_truth)), 1, 0)) AS correct,
    ROUND(correct / n, 4) AS accuracy
FROM BENCHMARK_RESULTS
WHERE confidence IS NOT NULL
GROUP BY engine, confidence_bucket
ORDER BY engine, confidence_bucket DESC;


-- =============================================================================
-- SECTION 7: Cost Analysis
-- =============================================================================

-- Token usage by engine and use case (AI_COMPLETE only — SPCS and AI_CLASSIFY don't report tokens inline)
SELECT
    engine,
    use_case,
    COUNT(*) AS total_rows,
    SUM(input_tokens) AS total_input_tokens,
    SUM(output_tokens) AS total_output_tokens,
    SUM(tokens_used) AS total_tokens,
    ROUND(AVG(input_tokens), 0) AS avg_input_per_row,
    ROUND(AVG(output_tokens), 0) AS avg_output_per_row,
    ROUND(AVG(tokens_used), 0) AS avg_total_per_row
FROM DJEV_DEMO.INFERENCE.BENCHMARK_RESULTS
WHERE tokens_used IS NOT NULL
GROUP BY engine, use_case
ORDER BY engine, use_case;

-- =============================================================================
-- Consolidated: Use Case x Engine — Accuracy, Latency, Tokens, Credits
-- =============================================================================
-- Single query, no temp tables, no ACCOUNT_USAGE dependency.
-- Credit rates (from Snowflake Service Consumption Table):
--   AI_CLASSIFY: 1.62 credits per million tokens
--   AI_COMPLETE (claude-haiku-4-5): 0.60 credits/M input tokens, 3.00 credits/M output tokens
--   SPCS GPU_NV_S: replace 0.57 with your actual credits/hour

SELECT
    r.engine,
    r.use_case,
    r.total_rows,
    r.correct,
    r.accuracy,
    r.total_input_tokens,
    r.total_output_tokens,
    r.total_tokens,
    l.total_ms AS latency_total_ms,
    ROUND(l.ms_per_row, 1) AS latency_ms_per_row,
    CASE
        -- AI_CLASSIFY: 1.62 credits/M tokens (actual token counts from AI_COUNT_TOKENS)
        WHEN r.engine = 'ai_classify' THEN ROUND(r.total_tokens * 1.62 / 1000000, 6)
        -- AI_COMPLETE: 0.60 credits/M input + 3.00 credits/M output
        WHEN r.engine = 'ai_complete' THEN ROUND(
            r.total_input_tokens * 0.60 / 1000000 + r.total_output_tokens * 3.00 / 1000000, 6)
        -- SPCS: GPU wall-clock time
        WHEN r.engine = 'CURRENT_ENGINE' THEN ROUND(l.total_ms / 1000.0 / 3600.0 * 0.57, 6)
        ELSE NULL
    END AS estimated_credits
FROM (
    SELECT
        engine,
        use_case,
        COUNT(*) AS total_rows,
        SUM(IFF(LOWER(TRIM(predicted)) = LOWER(TRIM(ground_truth)), 1, 0)) AS correct,
        ROUND(SUM(IFF(LOWER(TRIM(predicted)) = LOWER(TRIM(ground_truth)), 1, 0)) / COUNT(*), 4) AS accuracy,
        SUM(input_tokens) AS total_input_tokens,
        SUM(output_tokens) AS total_output_tokens,
        SUM(tokens_used) AS total_tokens
    FROM DJEV_DEMO.INFERENCE.BENCHMARK_RESULTS
    GROUP BY engine, use_case
) r
LEFT JOIN DJEV_DEMO.INFERENCE.BENCHMARK_LATENCY l
    ON r.engine = l.engine AND r.use_case = l.use_case
ORDER BY r.use_case, r.engine;
