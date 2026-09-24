"""openjev HTTP server with request batching for high-throughput SPCS serving.

Incoming requests are queued and flushed together through the model's predict()
method in one batched forward pass. This amortizes GPU overhead across many
concurrent requests instead of running one forward pass per option per request.

Configuration via env vars:
    OPENJEV_CHECKPOINT      subfolder (default: qwen3.5-4b-nli-v5)
    OPENJEV_DEVICE          torch device (default: cuda)
    OPENJEV_HOST            bind address (default: 0.0.0.0)
    OPENJEV_PORT            bind port (default: 8001)
    OPENJEV_BATCH_DEADLINE  max ms to wait for more requests before flushing (default: 50)
    OPENJEV_MAX_BATCH       max pairs to accumulate before flushing (default: 256)
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import time
from dataclasses import dataclass, field

import numpy as np

OPENJEV_CODE_DIR = os.environ.get("OPENJEV_CODE_DIR", "/opt/app/openjev_code")
if OPENJEV_CODE_DIR not in sys.path:
    sys.path.insert(0, OPENJEV_CODE_DIR)

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

BATCH_DEADLINE_MS = int(os.environ.get("OPENJEV_BATCH_DEADLINE", "50"))
MAX_BATCH_PAIRS = int(os.environ.get("OPENJEV_MAX_BATCH", "256"))

app = FastAPI(title="openjev-serve")

_jev = None
_ce = None
_batch_queue: asyncio.Queue | None = None
_batch_task: asyncio.Task | None = None

RUBRIC_MARK = "\nAllowed answers and rubric: "
TEMPLATE = 'The answer to "{instr}" is {label}: {crit}'
WINDOW_CHARS = 24_000


def _get_model():
    global _jev, _ce
    if _ce is None:
        from openjev_decide import OpenJev
        checkpoint = os.environ.get("OPENJEV_CHECKPOINT", "qwen3.5-4b-nli-v5")
        device = os.environ.get("OPENJEV_DEVICE", "cuda")
        print(f"Loading openjev checkpoint: AlexWortega/openjev/{checkpoint} on {device}")
        _jev = OpenJev.from_pretrained("AlexWortega/openjev", subfolder=checkpoint, device=device)
        _ce = _jev.ce
        print("openjev loaded")
    return _jev, _ce


def _rubric(instructions: str, options: list) -> tuple:
    instr, crits = instructions, {}
    if RUBRIC_MARK in instructions:
        instr, _, tail = instructions.partition(RUBRIC_MARK)
        try:
            crits = json.loads(tail)
        except json.JSONDecodeError:
            crits = {}
    return instr.strip(), {o: str(crits.get(o, o)) for o in options}


@dataclass
class PendingRequest:
    """One incoming /v1/systemone request waiting for batched inference."""
    state_str: str
    questions: dict
    oj_questions: list
    names: list
    pair_ranges: list  # [(start_idx, end_idx, n_windows, n_options), ...] per question
    future: asyncio.Future = field(default_factory=lambda: asyncio.get_event_loop().create_future())


def _laya_to_openjev_questions(questions: dict):
    names = []
    oj_questions = []
    for name, q in questions.items():
        names.append(name)
        qtype = q["type"]
        instructions = q.get("instructions", "")
        if qtype == "choice":
            criteria = q.get("criteria", {})
            if isinstance(criteria, list):
                options = [str(c) for c in criteria]
                rubric_str = json.dumps({o: o for o in options})
            else:
                options = list(criteria.keys())
                rubric_str = json.dumps({k: str(v) for k, v in criteria.items()})
        elif qtype == "score":
            criteria = q.get("criteria", [])
            options = [str(i) for i in range(len(criteria))]
            rubric_str = json.dumps({str(i): str(c) for i, c in enumerate(criteria)})
        elif qtype == "noul":
            criteria = q.get("criteria", {})
            false_desc = criteria.get("false", "no") if isinstance(criteria, dict) else "no"
            true_desc = criteria.get("true", "yes") if isinstance(criteria, dict) else "yes"
            options = ["no", "yes"]
            rubric_str = json.dumps({"no": str(false_desc), "yes": str(true_desc)})
        else:
            raise ValueError(f"Unknown question type: {qtype}")
        oj_questions.append({
            "type": qtype,
            "instructions": instructions + RUBRIC_MARK + rubric_str,
            "options": options,
        })
        names.append(name)
    # deduplicate - we appended name twice
    names = names[::2]
    return names, oj_questions


def _build_pairs(state_str: str, oj_questions: list) -> tuple[list, list]:
    """Build all (premise, hypothesis) pairs for one request. Returns (pairs, metadata)."""
    windows = [state_str] if len(state_str) <= WINDOW_CHARS else [
        state_str[s:s + WINDOW_CHARS]
        for s in range(0, max(len(state_str) - 2000, 1), WINDOW_CHARS - 2000)
    ]
    pairs = []
    meta = []  # (n_windows, n_options, qtype, options) per question
    for q in oj_questions:
        options = q["options"]
        instr, crits = _rubric(q["instructions"], options)
        q_pairs = [(w, TEMPLATE.format(instr=instr, label=o, crit=crits[o]))
                    for w in windows for o in options]
        pairs.extend(q_pairs)
        meta.append((len(windows), len(options), q["type"], options))
    return pairs, meta


def _decode_answers(probs_flat: np.ndarray, meta: list, questions: dict, names: list) -> dict:
    """Convert flat entailment probabilities back into typed answers."""
    from modeling_openjev import ENT
    answers = {}
    offset = 0
    for i, (n_win, n_opt, qtype, options) in enumerate(meta):
        chunk = probs_flat[offset:offset + n_win * n_opt, ENT].reshape(n_win, n_opt)
        p = chunk.max(0)
        p = p / max(float(p.sum()), 1e-9)
        name = names[i]
        if qtype == "noul":
            yes_idx = options.index("yes") if "yes" in options else len(options) - 1
            answers[name] = {"type": "noul", "noul": float(p[yes_idx])}
        elif qtype == "choice":
            winner = options[int(p.argmax())]
            total = float(p.sum())
            conf = float(p.max()) / total if total > 0 else 0
            answers[name] = {
                "type": "choice",
                "choice": winner,
                "probabilities": {o: float(x) for o, x in zip(options, p)},
                "confidence": conf,
            }
        elif qtype == "score":
            probs_dict = {o: float(x) for o, x in zip(options, p)}
            score = sum(float(k) * v for k, v in probs_dict.items())
            answers[name] = {"type": "score", "score": score, "probabilities": probs_dict}
        offset += n_win * n_opt
    return answers


async def _batch_worker():
    """Background task: collects pending requests, batches their pairs, runs one predict()."""
    _, ce = _get_model()

    while True:
        # Wait for at least one request
        pending: list[tuple[PendingRequest, list, list]] = []
        total_pairs = 0

        req = await _batch_queue.get()
        pairs, meta = _build_pairs(req.state_str, req.oj_questions)
        pending.append((req, pairs, meta))
        total_pairs += len(pairs)

        # Drain more requests within the deadline or until batch is full
        deadline = asyncio.get_event_loop().time() + BATCH_DEADLINE_MS / 1000.0
        while total_pairs < MAX_BATCH_PAIRS:
            remaining = deadline - asyncio.get_event_loop().time()
            if remaining <= 0:
                break
            try:
                req = await asyncio.wait_for(_batch_queue.get(), timeout=remaining)
                pairs, meta = _build_pairs(req.state_str, req.oj_questions)
                pending.append((req, pairs, meta))
                total_pairs += len(pairs)
            except asyncio.TimeoutError:
                break

        # Combine all pairs into one mega-batch and run predict()
        all_pairs = []
        for _, pairs, _ in pending:
            all_pairs.extend(pairs)

        try:
            all_probs = ce.predict(all_pairs)  # one batched GPU call

            # Slice results back to each request
            offset = 0
            for req, pairs, meta in pending:
                n = len(pairs)
                req_probs = all_probs[offset:offset + n]
                answers = _decode_answers(req_probs, meta, req.questions, req.names)
                req.future.set_result(answers)
                offset += n
        except Exception as e:
            for req, _, _ in pending:
                if not req.future.done():
                    req.future.set_exception(e)


@app.on_event("startup")
async def startup():
    global _batch_queue, _batch_task
    _batch_queue = asyncio.Queue()
    _get_model()  # preload
    _batch_task = asyncio.create_task(_batch_worker())


@app.get("/health")
def health():
    return {"status": "ok", "engine": "openjev",
            "checkpoint": os.environ.get("OPENJEV_CHECKPOINT", "qwen3.5-4b-nli-v5")}


@app.post("/v1/systemone")
async def systemone(request: Request):
    body = await request.json()
    if not isinstance(body, dict) or "questions" not in body:
        raise HTTPException(status_code=400, detail="request must have 'questions' field")

    state = body.get("state", "")
    questions = body["questions"]

    if not isinstance(questions, dict) or len(questions) == 0:
        return {"model": "openjev", "answers": {}, "usage": {"input_tokens": 0, "output_tokens": 0}}

    names, oj_questions = _laya_to_openjev_questions(questions)
    state_str = state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)

    pending = PendingRequest(
        state_str=state_str,
        questions=questions,
        oj_questions=oj_questions,
        names=names,
    )
    await _batch_queue.put(pending)
    answers = await pending.future

    return {
        "model": "openjev",
        "answers": answers,
        "usage": {"input_tokens": 0, "output_tokens": 0},
    }


@app.post("/v1/systemone/batch")
async def systemone_batch(request: Request):
    """Process multiple requests in one call. All pairs across all requests are
    batched into shared forward passes, eliminating per-row HTTP overhead."""
    body = await request.json()
    requests_list = body.get("requests", [])

    if not requests_list:
        return {"responses": []}

    # Build all pairs across all requests
    _, ce = _get_model()
    from modeling_openjev import ENT

    all_pairs = []
    request_meta = []  # (start_idx, meta_list, names, questions) per request

    for req in requests_list:
        state = req.get("state", "")
        questions = req.get("questions", {})
        if not isinstance(questions, dict) or len(questions) == 0:
            request_meta.append((len(all_pairs), [], [], questions))
            continue
        names, oj_questions = _laya_to_openjev_questions(questions)
        state_str = state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)
        pairs, meta = _build_pairs(state_str, oj_questions)
        request_meta.append((len(all_pairs), meta, names, questions))
        all_pairs.extend(pairs)

    # One batched predict() call for ALL pairs across ALL requests
    if all_pairs:
        all_probs = ce.predict(all_pairs)
    else:
        all_probs = np.empty((0, 3))

    # Slice results back to each request
    responses = []
    for i, (start_idx, meta, names, questions) in enumerate(request_meta):
        if not meta:
            responses.append({"model": "openjev", "answers": {}, "usage": {"input_tokens": 0, "output_tokens": 0}})
            continue
        n_pairs = sum(nw * no for nw, no, _, _ in meta)
        req_probs = all_probs[start_idx:start_idx + n_pairs]
        answers = _decode_answers(req_probs, meta, questions, names)
        responses.append({"model": "openjev", "answers": answers, "usage": {"input_tokens": 0, "output_tokens": 0}})

    return {"responses": responses}


if __name__ == "__main__":
    import uvicorn
    _get_model()
    uvicorn.run(app,
                host=os.environ.get("OPENJEV_HOST", "0.0.0.0"),
                port=int(os.environ.get("OPENJEV_PORT", "8001")))
