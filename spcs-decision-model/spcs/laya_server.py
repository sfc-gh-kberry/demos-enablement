"""Custom Laya HTTP server with batch endpoint for SPCS throughput.

Replaces laya-serve with a server that exposes both /v1/systemone (single)
and /v1/systemone/batch (bulk) using Laya's predict_batch() for shared
forward passes across multiple requests.
"""
from __future__ import annotations

import json
import os
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, HTTPException, Request

app = FastAPI(title="laya-serve-batch")

_router = None
_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="laya-infer")


def _get_router():
    global _router
    if _router is None:
        from laya import Router
        device = os.environ.get("LAYA_DEVICE") or None
        _router = Router(device=device)
        if os.environ.get("LAYA_PRELOAD", "1") in ("1", "true", "True"):
            _router.preload()
        print("Laya router loaded")
    return _router


@app.get("/health")
def health():
    return {"status": "ok", "engine": "laya", "loaded": _router is not None}


@app.post("/v1/systemone")
async def systemone(request: Request):
    import asyncio
    body = await request.json()
    if not isinstance(body, dict) or "questions" not in body:
        raise HTTPException(status_code=400, detail="request must have 'questions' field")

    state = body.get("state")
    questions = body["questions"]
    model = body.get("model")

    router = _get_router()
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        _pool, lambda: router.predict(state, questions, model=model))
    return result


@app.post("/v1/systemone/batch")
async def systemone_batch(request: Request):
    """Process multiple requests in shared forward passes via predict_batch()."""
    import asyncio
    body = await request.json()
    requests_list = body.get("requests", [])

    if not requests_list:
        return {"responses": []}

    router = _get_router()

    # Build batch input for predict_batch
    batch_requests = []
    for req in requests_list:
        batch_requests.append({
            "state": req.get("state", ""),
            "questions": req.get("questions", {}),
        })

    loop = asyncio.get_running_loop()
    results = await loop.run_in_executor(
        _pool, lambda: router.predict_batch(batch_requests))

    return {"responses": results}


if __name__ == "__main__":
    import uvicorn
    _get_router()
    uvicorn.run(app,
                host=os.environ.get("LAYA_HOST", "0.0.0.0"),
                port=int(os.environ.get("LAYA_PORT", "8001")))
