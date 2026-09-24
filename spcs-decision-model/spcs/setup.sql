-- =============================================================================
-- SPCS Infrastructure for Decision Engine
-- =============================================================================
-- One service, one generic DECIDE() function.
-- Swap engines by changing DECISION_ENGINE env var and redeploying.
-- =============================================================================

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS DJEV_DEMO;
CREATE SCHEMA IF NOT EXISTS DJEV_DEMO.INFERENCE;
USE SCHEMA DJEV_DEMO.INFERENCE;

CREATE IMAGE REPOSITORY IF NOT EXISTS DJEV_DEMO.INFERENCE.DJEV_REPO;
SHOW IMAGE REPOSITORIES LIKE 'DJEV_REPO' IN SCHEMA DJEV_DEMO.INFERENCE;

CREATE WAREHOUSE IF NOT EXISTS DJEV_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

CREATE COMPUTE POOL IF NOT EXISTS DJEV_GPU_POOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = 'GPU_NV_S'
    AUTO_RESUME = TRUE
    AUTO_SUSPEND_SECS = 600;

-- External Access for HuggingFace downloads
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NETWORK RULE DJEV_DEMO.INFERENCE.DJEV_HF_NETWORK_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('huggingface.co', 'cdn-lfs.huggingface.com',
                  'cdn-lfs-us-1.huggingface.com', 'cdn-lfs-eu-1.huggingface.com',
                  'raw.githubusercontent.com',
                  'cas-server.xethub.hf.co', 'hub.hf.co', '*.hf.co',
                  'us.aws.cdn.hf.co', '*.aws.cdn.hf.co', '*.cdn.hf.co');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION DJEV_HF_ACCESS
    ALLOWED_NETWORK_RULES = (DJEV_DEMO.INFERENCE.DJEV_HF_NETWORK_RULE)
    ENABLED = TRUE;

GRANT USAGE ON INTEGRATION DJEV_HF_ACCESS TO ROLE SYSADMIN;
USE ROLE SYSADMIN;

-- =============================================================================
-- Service (change DECISION_ENGINE + OPENJEV_CHECKPOINT to swap engines)
-- =============================================================================
-- Engine options:
--   DECISION_ENGINE: "laya" | "openjev"
--   OPENJEV_CHECKPOINT: "qwen3.5-0.8b-nli-v5" | "qwen3.5-2b-nli-v5" | "qwen3.5-4b-nli-v5"

CREATE SERVICE DJEV_DEMO.INFERENCE.DECISION_SERVICE
    IN COMPUTE POOL DJEV_GPU_POOL
    FROM SPECIFICATION $$
spec:
  containers:
  - name: decision-engine
    image: /djev_demo/inference/djev_repo/decision-spcs:latest
    env:
      DECISION_ENGINE: "laya"
      OPENJEV_CHECKPOINT: "qwen3.5-4b-nli-v5"
    readinessProbe:
      port: 8080
      path: /ready
    resources:
      requests:
        memory: 8G
        cpu: 4
        nvidia.com/gpu: 1
      limits:
        memory: 20G
        cpu: 6
        nvidia.com/gpu: 1
    volumeMounts:
    - name: model-cache
      mountPath: /cache
  endpoints:
  - name: predict
    port: 8080
    public: false
  volumes:
  - name: model-cache
    source: local
$$
    EXTERNAL_ACCESS_INTEGRATIONS = (DJEV_HF_ACCESS)
    MIN_INSTANCES = 1
    MAX_INSTANCES = 1
    QUERY_WAREHOUSE = DJEV_WH;

-- Monitor
SELECT SYSTEM$GET_SERVICE_STATUS('DJEV_DEMO.INFERENCE.DECISION_SERVICE');
SELECT SYSTEM$GET_SERVICE_LOGS('DJEV_DEMO.INFERENCE.DECISION_SERVICE', 0, 'decision-engine', 50);

-- =============================================================================
-- Generic DECIDE() service function
-- =============================================================================
-- Usage: DECIDE(state_text, questions_variant) -> answers_variant
--
-- The caller defines the question schema as a VARIANT:
--   DECIDE('some text', {'sentiment': {'type': 'choice', ...}})

CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 128
    BATCH_TIMEOUT_SECS = 600
    AS '/predict';
