-- ============================================================
-- COCO DATA ENGINEERING LAB — SETUP SCRIPT
-- Purpose: Create messy vendor data for CoCo data engineering demo
-- Duration: ~30 seconds to run
-- ============================================================

CREATE DATABASE IF NOT EXISTS COCO_DE_LAB;
CREATE SCHEMA IF NOT EXISTS COCO_DE_LAB.RAW;
CREATE SCHEMA IF NOT EXISTS COCO_DE_LAB.STAGING;
CREATE SCHEMA IF NOT EXISTS COCO_DE_LAB.MART;
USE SCHEMA COCO_DE_LAB.RAW;

-- ============================================================
-- VENDOR A: PayRight — MM/DD/YYYY dates, $amounts, ALL CAPS merchants
-- ============================================================
CREATE OR REPLACE TABLE VENDOR_A_TRANSACTIONS (
    TRANSACTION_ID VARCHAR,
    TRANSACTION_DATE VARCHAR,
    MERCHANT_NAME VARCHAR,
    AMOUNT VARCHAR,
    CATEGORY VARCHAR,
    CARD_LAST_FOUR VARCHAR,
    STATUS VARCHAR
);

INSERT INTO VENDOR_A_TRANSACTIONS
WITH merchants AS (
    SELECT column1 AS merchant_name, column2 AS category, column3 AS amt_low, column4 AS amt_high
    FROM VALUES
        ('WALMART SUPERCENTER #4521', 'GROCERY', 35, 200),
        ('TARGET #1892', 'RETAIL', 20, 150),
        ('COSTCO WHOLESALE #312', 'GROCERY', 80, 350),
        ('SHELL OIL 57422', 'GAS', 25, 85),
        ('CHEVRON #09841', 'GAS', 30, 80),
        ('BP #7234', 'GAS', 28, 75),
        ('CHIPOTLE MEXICAN GRILL #2847', 'DINING', 10, 45),
        ('OLIVE GARDEN #4412', 'DINING', 25, 75),
        ('STARBUCKS #18294', 'DINING', 4, 12),
        ('MCDONALDS F#14982', 'DINING', 5, 25),
        ('AMAZON.COM*M24KT9VZ3', 'RETAIL', 10, 200),
        ('HOME DEPOT #4078', 'RETAIL', 15, 400),
        ('BEST BUY #938', 'RETAIL', 25, 500),
        ('MARRIOTT HOTEL CHI', 'TRAVEL', 120, 450),
        ('UNITED AIRLINES', 'TRAVEL', 150, 500),
        ('DELTA AIR LINES', 'TRAVEL', 175, 500),
        ('NETFLIX.COM', 'ENTERTAINMENT', 15, 23),
        ('AMC THEATRES #2841', 'ENTERTAINMENT', 12, 50),
        ('KROGER #4521', 'GROCERY', 30, 180),
        ('WALGREENS #12847', 'RETAIL', 5, 60)
),
seq AS (
    SELECT SEQ4() AS rn, UNIFORM(1, 20, RANDOM()) AS merch_idx,
           UNIFORM(1, 181, RANDOM()) AS day_offset,
           UNIFORM(1, 9999, RANDOM()) AS card,
           UNIFORM(1, 100, RANDOM()) AS status_roll,
           UNIFORM(1, 100, RANDOM()) AS null_roll,
           UNIFORM(1, 50000, RANDOM()) AS rand_amt
    FROM TABLE(GENERATOR(ROWCOUNT => 500))
)
SELECT
    'PRA-' || LPAD(seq.rn::VARCHAR, 6, '0') AS transaction_id,
    LPAD(MONTH(DATEADD(day, seq.day_offset, '2024-01-01'::DATE))::VARCHAR, 2, '0') || '/' ||
        LPAD(DAY(DATEADD(day, seq.day_offset, '2024-01-01'::DATE))::VARCHAR, 2, '0') || '/' ||
        YEAR(DATEADD(day, seq.day_offset, '2024-01-01'::DATE))::VARCHAR AS transaction_date,
    CASE WHEN seq.null_roll <= 3 THEN NULL ELSE m.merchant_name END AS merchant_name,
    CASE WHEN seq.null_roll BETWEEN 4 AND 5 THEN ''
         ELSE '$' || TO_CHAR((m.amt_low * 100 + MOD(seq.rand_amt, (m.amt_high - m.amt_low) * 100)) / 100.0, '9,999.99')
    END AS amount,
    m.category,
    LPAD(seq.card::VARCHAR, 4, '0') AS card_last_four,
    CASE WHEN seq.status_roll <= 85 THEN 'APPROVED'
         WHEN seq.status_roll <= 95 THEN 'DECLINED'
         ELSE 'PENDING' END AS status
FROM seq
JOIN (SELECT ROW_NUMBER() OVER (ORDER BY merchant_name) AS idx, * FROM merchants) m
    ON seq.merch_idx = m.idx;

-- ============================================================
-- VENDOR B: SwiftPay — YYYY-MM-DD dates, clean decimals, Title Case, lowercase status
-- ============================================================
CREATE OR REPLACE TABLE VENDOR_B_TRANSACTIONS (
    TXN_ID VARCHAR,
    TXN_DATE VARCHAR,
    MERCHANT VARCHAR,
    TXN_AMOUNT NUMBER(10,2),
    MERCHANT_CATEGORY VARCHAR,
    CARD_NUMBER_LAST4 VARCHAR,
    TXN_STATUS VARCHAR
);

INSERT INTO VENDOR_B_TRANSACTIONS
WITH merchants AS (
    SELECT column1 AS merchant_name, column2 AS category, column3 AS amt_low, column4 AS amt_high
    FROM VALUES
        ('Walmart Supercenter #4521', 'Grocery Stores', 35, 200),
        ('Target #1892', 'Retail Stores', 20, 150),
        ('Costco Wholesale #312', 'Grocery Stores', 80, 350),
        ('Shell Oil 57422', 'Gas Stations', 25, 85),
        ('Chevron #09841', 'Gas Stations', 30, 80),
        ('Bp #7234', 'Gas Stations', 28, 75),
        ('Chipotle Mexican Grill #2847', 'Restaurants', 10, 45),
        ('Olive Garden #4412', 'Restaurants', 25, 75),
        ('Starbucks #18294', 'Restaurants', 4, 12),
        ('McDonalds F#14982', 'Restaurants', 5, 25),
        ('Amazon.com*M24KT9VZ3', 'Retail Stores', 10, 200),
        ('Home Depot #4078', 'Retail Stores', 15, 400),
        ('Best Buy #938', 'Retail Stores', 25, 500),
        ('Marriott Hotel Chi', 'Travel & Lodging', 120, 450),
        ('United Airlines', 'Travel & Lodging', 150, 500),
        ('Delta Air Lines', 'Travel & Lodging', 175, 500),
        ('Netflix.com', 'Entertainment', 15, 23),
        ('Amc Theatres #2841', 'Entertainment', 12, 50),
        ('Kroger #4521', 'Grocery Stores', 30, 180),
        ('Walgreens #12847', 'Retail Stores', 5, 60)
),
seq AS (
    SELECT SEQ4() AS rn, UNIFORM(1, 20, RANDOM()) AS merch_idx,
           UNIFORM(1, 181, RANDOM()) AS day_offset,
           UNIFORM(1, 9999, RANDOM()) AS card,
           UNIFORM(1, 100, RANDOM()) AS status_roll,
           UNIFORM(1, 50000, RANDOM()) AS rand_amt
    FROM TABLE(GENERATOR(ROWCOUNT => 500))
)
SELECT
    'SP-' || LPAD(seq.rn::VARCHAR, 8, '0') AS txn_id,
    TO_CHAR(DATEADD(day, seq.day_offset, '2024-01-01'::DATE), 'YYYY-MM-DD') AS txn_date,
    m.merchant_name AS merchant,
    ROUND((m.amt_low * 100 + MOD(seq.rand_amt, (m.amt_high - m.amt_low) * 100)) / 100.0, 2) AS txn_amount,
    m.category AS merchant_category,
    LPAD(seq.card::VARCHAR, 4, '0') AS card_number_last4,
    CASE WHEN seq.status_roll <= 85 THEN 'approved'
         WHEN seq.status_roll <= 95 THEN 'declined'
         ELSE 'pending' END AS txn_status
FROM seq
JOIN (SELECT ROW_NUMBER() OVER (ORDER BY merchant_name) AS idx, * FROM merchants) m
    ON seq.merch_idx = m.idx;

-- ============================================================
-- VENDOR C: QuickSettle — DD-Mon-YY dates, cents, lowercase w/ spaces, abbreviations
-- ============================================================
CREATE OR REPLACE TABLE VENDOR_C_TRANSACTIONS (
    ID NUMBER,
    DT VARCHAR,
    MERCH_NM VARCHAR,
    AMT NUMBER(38,0),
    CAT VARCHAR,
    CARD VARCHAR,
    STAT VARCHAR
);

INSERT INTO VENDOR_C_TRANSACTIONS
WITH merchants AS (
    SELECT column1 AS merchant_name, column2 AS category, column3 AS amt_low, column4 AS amt_high
    FROM VALUES
        ('  walmart supercenter #4521  ', 'GR', 35, 200),
        ('target #1892', 'RT', 20, 150),
        ('  costco wholesale #312', 'GR', 80, 350),
        ('shell oil 57422  ', 'GS', 25, 85),
        (' chevron #09841', 'GS', 30, 80),
        ('bp #7234  ', 'GS', 28, 75),
        ('  chipotle mexican grill #2847', 'DN', 10, 45),
        ('olive garden #4412  ', 'DN', 25, 75),
        (' starbucks #18294 ', 'DN', 4, 12),
        ('mcdonalds f#14982', 'DN', 5, 25),
        ('  amazon.com*m24kt9vz3  ', 'RT', 10, 200),
        ('home depot #4078', 'RT', 15, 400),
        (' best buy #938  ', 'RT', 25, 500),
        ('marriott hotel chi', 'TR', 120, 450),
        ('  united airlines', 'TR', 150, 500),
        ('delta air lines  ', 'TR', 175, 500),
        ('netflix.com', 'EN', 15, 23),
        (' amc theatres #2841', 'EN', 12, 50),
        ('kroger #4521  ', 'GR', 30, 180),
        ('  walgreens #12847', 'RT', 5, 60)
),
seq AS (
    SELECT SEQ4() AS rn, UNIFORM(1, 20, RANDOM()) AS merch_idx,
           UNIFORM(1, 181, RANDOM()) AS day_offset,
           UNIFORM(1, 9999, RANDOM()) AS card,
           UNIFORM(1, 100, RANDOM()) AS status_roll,
           UNIFORM(1, 50000, RANDOM()) AS rand_amt
    FROM TABLE(GENERATOR(ROWCOUNT => 500))
)
SELECT
    seq.rn AS id,
    TO_CHAR(DATEADD(day, seq.day_offset, '2024-01-01'::DATE), 'DD-Mon-YY') AS dt,
    m.merchant_name AS merch_nm,
    m.amt_low * 100 + MOD(seq.rand_amt, (m.amt_high - m.amt_low) * 100) AS amt,
    m.category AS cat,
    LPAD(seq.card::VARCHAR, 4, '0') AS card,
    CASE WHEN seq.status_roll <= 85 THEN 'A'
         WHEN seq.status_roll <= 95 THEN 'D'
         ELSE 'P' END AS stat
FROM seq
JOIN (SELECT ROW_NUMBER() OVER (ORDER BY merchant_name) AS idx, * FROM merchants) m
    ON seq.merch_idx = m.idx;

-- ============================================================
-- VENDOR D: ClearCharge — Pipe-delimited style, mixed nulls, epoch timestamps
-- Used in Tier 3 (Advanced) to demo the dbt-ingest-pipeline skill
-- ============================================================
CREATE OR REPLACE TABLE VENDOR_D_TRANSACTIONS (
    RECORD_NUM NUMBER,
    EPOCH_TS NUMBER,
    VENDOR_DESC VARCHAR,
    CHARGE_AMT VARCHAR,
    TYPE_CD VARCHAR,
    PAN_SUFFIX VARCHAR,
    RESULT_CD NUMBER
);

INSERT INTO COCO_DE_LAB.RAW.VENDOR_D_TRANSACTIONS
WITH merchants AS (
    SELECT column1 AS merchant_name, column2 AS type_cd, column3 AS amt_low, column4 AS amt_high
    FROM VALUES
        ('WAL-MART #4521 BENTONVILLE AR', 'GRC', 35, 200),
        ('TARGET T-1892', 'RTL', 20, 150),
        ('COSTCO WHSE #312', 'GRC', 80, 350),
        ('SHELL SERVICE STATION', 'FUL', 25, 85),
        ('CHEVRON 09841', 'FUL', 30, 80),
        ('BP AMOCO 7234', 'FUL', 28, 75),
        ('CHIPOTLE 2847', 'RST', 10, 45),
        ('DARDEN REST OG 4412', 'RST', 25, 75),
        ('STARBUCKS STORE 18294', 'RST', 4, 12),
        ('MCD 14982', 'RST', 5, 25),
        ('AMZN Mktp US*M24K', 'RTL', 10, 200),
        ('THE HOME DEPOT #4078', 'RTL', 15, 400),
        ('BEST BUY      00938', 'RTL', 25, 500),
        ('MARRIOTT CHI DT', 'TRV', 120, 450),
        ('UNITED 016 2458372691', 'TRV', 150, 500),
        ('DELTA AIR 006 2891045', 'TRV', 175, 500),
        ('NETFLIX.COM', 'ENT', 15, 23),
        ('AMC ONLINE 2841', 'ENT', 12, 50),
        ('KROGER #4521 FUEL', 'FUL', 25, 70),
        ('WALGREENS #12847', 'RTL', 5, 60)
),
seq AS (
    SELECT SEQ4() AS rn, UNIFORM(1, 20, RANDOM()) AS merch_idx,
           UNIFORM(1, 181, RANDOM()) AS day_offset,
           UNIFORM(1, 9999, RANDOM()) AS card,
           UNIFORM(1, 100, RANDOM()) AS status_roll,
           UNIFORM(1, 50000, RANDOM()) AS rand_amt,
           UNIFORM(1, 100, RANDOM()) AS null_roll
    FROM TABLE(GENERATOR(ROWCOUNT => 500))
)
SELECT
    seq.rn AS record_num,
    DATEDIFF(second, '1970-01-01'::TIMESTAMP, DATEADD(day, seq.day_offset, '2024-01-01'::DATE)::TIMESTAMP)
        + UNIFORM(0, 86399, RANDOM()) AS epoch_ts,
    CASE WHEN seq.null_roll <= 2 THEN NULL ELSE m.merchant_name END AS vendor_desc,
    CASE
        WHEN seq.null_roll = 3 THEN NULL
        WHEN MOD(seq.rn, 25) = 0 THEN '-' || CAST((m.amt_low * 100 + MOD(seq.rand_amt, (m.amt_high - m.amt_low) * 100)) / 100.0 AS VARCHAR) || '  '
        ELSE '  ' || CAST((m.amt_low * 100 + MOD(seq.rand_amt, (m.amt_high - m.amt_low) * 100)) / 100.0 AS VARCHAR)
    END AS charge_amt,
    m.type_cd,
    CASE WHEN seq.null_roll = 4 THEN NULL ELSE LPAD(seq.card::VARCHAR, 4, '0') END AS pan_suffix,
    CASE WHEN seq.status_roll <= 82 THEN 0
         WHEN seq.status_roll <= 92 THEN 1
         WHEN seq.status_roll <= 97 THEN 2
         ELSE 9 END AS result_cd
FROM seq
JOIN (SELECT ROW_NUMBER() OVER (ORDER BY merchant_name) AS idx, * FROM merchants) m
    ON seq.merch_idx = m.idx;

-- ============================================================
-- VERIFY
-- ============================================================
SELECT 'VENDOR_A_TRANSACTIONS' AS tbl, COUNT(*) AS cnt FROM COCO_DE_LAB.RAW.VENDOR_A_TRANSACTIONS
UNION ALL SELECT 'VENDOR_B_TRANSACTIONS', COUNT(*) FROM COCO_DE_LAB.RAW.VENDOR_B_TRANSACTIONS
UNION ALL SELECT 'VENDOR_C_TRANSACTIONS', COUNT(*) FROM COCO_DE_LAB.RAW.VENDOR_C_TRANSACTIONS
UNION ALL SELECT 'VENDOR_D_TRANSACTIONS', COUNT(*) FROM COCO_DE_LAB.RAW.VENDOR_D_TRANSACTIONS;
