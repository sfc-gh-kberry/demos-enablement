-- =============================================================================
-- Switch Engine Configuration
-- =============================================================================
-- Uncomment ONE block below, then run the whole script.
-- The service will restart with the new engine. Wait for READY before running
-- benchmarks. Model weights are cached on the local volume, so subsequent
-- switches to a previously-loaded engine start in seconds.
-- =============================================================================
USE SCHEMA DJEV_DEMO.INFERENCE;

DROP SERVICE IF EXISTS DJEV_DEMO.INFERENCE.DECISION_SERVICE;

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- OPTION 1: Laya (ModernBERT 421M — fastest, English-optimized)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/*
CREATE SERVICE DJEV_DEMO.INFERENCE.DECISION_SERVICE
    IN COMPUTE POOL DJEV_GPU_POOL
    FROM SPECIFICATION $$
spec:
  containers:
  - name: decision-engine
    image: /djev_demo/inference/djev_repo/decision-spcs:latest
    env:
      DECISION_ENGINE: "laya"
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
*/
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- OPTION 2: openjev 0.8B (Qwen3.5 — smallest, fastest openjev)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/*
CREATE SERVICE DJEV_DEMO.INFERENCE.DECISION_SERVICE
    IN COMPUTE POOL DJEV_GPU_POOL
    FROM SPECIFICATION $$
spec:
  containers:
  - name: decision-engine
    image: /djev_demo/inference/djev_repo/decision-spcs:latest
    env:
      DECISION_ENGINE: "openjev"
      OPENJEV_CHECKPOINT: "qwen3.5-0.8b-nli-v5"
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
*/

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- OPTION 3: openjev 2B (Qwen3.5 — balanced)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

CREATE SERVICE DJEV_DEMO.INFERENCE.DECISION_SERVICE
    IN COMPUTE POOL DJEV_GPU_POOL
    FROM SPECIFICATION $$
spec:
  containers:
  - name: decision-engine
    image: /djev_demo/inference/djev_repo/decision-spcs:latest
    env:
      DECISION_ENGINE: "openjev"
      OPENJEV_CHECKPOINT: "qwen3.5-2b-nli-v5"
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


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- OPTION 4: openjev 4B (Qwen3.5 — highest accuracy)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/*
CREATE SERVICE DJEV_DEMO.INFERENCE.DECISION_SERVICE
    IN COMPUTE POOL DJEV_GPU_POOL
    FROM SPECIFICATION $$
spec:
  containers:
  - name: decision-engine
    image: /djev_demo/inference/djev_repo/decision-spcs:latest
    env:
      DECISION_ENGINE: "openjev"
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
*/

-- =============================================================================
-- Recreate DECIDE() function (needed after service drop/create)
-- =============================================================================
CREATE OR REPLACE FUNCTION DJEV_DEMO.INFERENCE.DECIDE(state VARCHAR, questions VARIANT)
    RETURNS VARIANT
    SERVICE = DJEV_DEMO.INFERENCE.DECISION_SERVICE
    ENDPOINT = predict
    MAX_BATCH_ROWS = 128
    BATCH_TIMEOUT_SECS = 600
    AS '/predict';

-- =============================================================================
-- Wait for service to be ready
-- =============================================================================
SELECT SYSTEM$GET_SERVICE_STATUS('DJEV_DEMO.INFERENCE.DECISION_SERVICE');
SELECT SYSTEM$GET_SERVICE_LOGS('DJEV_DEMO.INFERENCE.DECISION_SERVICE', 0, 'decision-engine', 50);

-- Quick smoke test
SELECT DECIDE('I love this product!', OBJECT_CONSTRUCT(
    'sentiment', OBJECT_CONSTRUCT(
        'type', 'choice',
        'instructions', 'Classify the sentiment.',
        'criteria', OBJECT_CONSTRUCT(
            'positive', 'positive sentiment',
            'negative', 'negative sentiment',
            'neutral', 'neutral or factual'
        )
    )
)) AS result;
