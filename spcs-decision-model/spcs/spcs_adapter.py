"""Generic SPCS service-function adapter.

Single endpoint: /predict
Receives: {"data": [[row_idx, state_text, questions_json], ...]}
Returns:  {"data": [[row_idx, answers_variant], ...]}

Sends the entire batch to the backend in a single HTTP call via /v1/systemone/batch.
Falls back to per-row /v1/systemone if batch endpoint is unavailable.
"""
from __future__ import annotations

import asyncio
import json
import os

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

UPSTREAM = os.environ.get("DECISION_UPSTREAM", "http://127.0.0.1:8001")
MAX_CONCURRENT = int(os.environ.get("ADAPTER_MAX_CONCURRENT", "4"))

app = FastAPI(title="SPCS Decision Adapter")
client = httpx.AsyncClient(base_url=UPSTREAM, timeout=600)

_batch_supported = None


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/ready")
async def ready():
    try:
        resp = await client.get("/health")
        if resp.status_code == 200:
            return JSONResponse({"ready": True}, status_code=200)
    except Exception:
        pass
    return JSONResponse({"ready": False}, status_code=503)


async def _predict_batch(rows_parsed: list[tuple[int, str, dict]]) -> list:
    """Send all rows in one HTTP call to /v1/systemone/batch."""
    batch_payload = [
        {"state": state if isinstance(state, str) else json.dumps(state),
         "questions": questions}
        for _, state, questions in rows_parsed
    ]
    resp = await client.post("/v1/systemone/batch", json={"requests": batch_payload})
    resp.raise_for_status()
    data = resp.json()
    responses = data["responses"]
    return [[row_idx, r.get("answers", {})] for (row_idx, _, _), r in zip(rows_parsed, responses)]


async def _predict_concurrent(rows_parsed: list[tuple[int, str, dict]]) -> list:
    """Fallback: send rows concurrently via individual /v1/systemone calls."""
    sem = asyncio.Semaphore(MAX_CONCURRENT)

    async def one(row_idx, state, questions):
        async with sem:
            try:
                resp = await client.post("/v1/systemone", json={
                    "state": state if isinstance(state, str) else json.dumps(state),
                    "questions": questions,
                })
                resp.raise_for_status()
                return [row_idx, resp.json().get("answers", {})]
            except Exception as e:
                return [row_idx, {"error": str(e)}]

    tasks = [one(idx, state, qs) for idx, state, qs in rows_parsed]
    return list(await asyncio.gather(*tasks))


@app.post("/predict")
async def predict(request: Request):
    global _batch_supported
    payload = await request.json()
    rows = payload["data"]

    rows_parsed = []
    for row in rows:
        row_idx = row[0]
        state = row[1]
        questions = row[2]
        if isinstance(questions, str):
            questions = json.loads(questions)
        rows_parsed.append((row_idx, state, questions))

    # Try batch endpoint first, fall back to concurrent per-row
    if _batch_supported is not False:
        try:
            results = await _predict_batch(rows_parsed)
            _batch_supported = True
            return JSONResponse({"data": results})
        except (httpx.HTTPStatusError, httpx.ConnectError) as e:
            if _batch_supported is None:
                _batch_supported = False  # endpoint doesn't exist, stop trying
            else:
                raise

    results = await _predict_concurrent(rows_parsed)
    return JSONResponse({"data": results})


if __name__ == "__main__":
    import uvicorn
    workers = int(os.environ.get("ADAPTER_WORKERS", "4"))
    uvicorn.run("spcs_adapter:app", host="0.0.0.0", port=8080, workers=workers)
