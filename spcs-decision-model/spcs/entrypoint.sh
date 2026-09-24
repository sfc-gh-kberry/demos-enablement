#!/bin/bash
set -e

ENGINE="${DECISION_ENGINE:-laya}"
echo "Starting decision engine: $ENGINE"

case "$ENGINE" in
    laya)
        echo "Launching laya_server (with batch support) on :8001"
        python3 /opt/app/laya_server.py &
        BACKEND_PID=$!
        ;;
    openjev)
        echo "Launching openjev_server on :8001 (checkpoint: ${OPENJEV_CHECKPOINT:-qwen3.5-4b-nli-v5})"
        python3 /opt/app/openjev_server.py &
        BACKEND_PID=$!
        ;;
    *)
        echo "Unknown DECISION_ENGINE: $ENGINE (must be 'laya' or 'openjev')"
        exit 1
        ;;
esac

echo "Waiting for backend on port 8001..."
until curl -sf http://127.0.0.1:8001/health > /dev/null 2>&1; do
    if ! kill -0 $BACKEND_PID 2>/dev/null; then
        echo "Backend process died"
        exit 1
    fi
    sleep 2
done
echo "Backend is ready"

# SPCS adapter on 0.0.0.0:8080
python3 /opt/app/spcs_adapter.py &
ADAPTER_PID=$!

echo "All processes started: backend=$BACKEND_PID adapter=$ADAPTER_PID"

wait -n $BACKEND_PID $ADAPTER_PID
EXIT_CODE=$?

kill $BACKEND_PID $ADAPTER_PID 2>/dev/null || true
exit $EXIT_CODE
