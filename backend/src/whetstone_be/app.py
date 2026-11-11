"""Whetstone backend: FastAPI on port 8402 (DoubleNaught 8400, SegForge 8401)."""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel

from .blender import BlenderClient, BlenderError, OpError, ops_to_code

from .models import Card
from .store import ParquetCardStore


def default_storage_dir() -> Path:
    env = os.environ.get("WHETSTONE_STORAGE")
    if env:
        return Path(env)
    # backend/src/whetstone_be/app.py -> the Whetstone project root
    return Path(__file__).resolve().parents[3] / "storage"


class OpsRequest(BaseModel):
    ops: list[dict]
    dryRun: bool = False


class ExecuteRequest(BaseModel):
    code: str


def create_app(storage_dir: str | Path | None = None, blender: BlenderClient | None = None) -> FastAPI:
    app = FastAPI(title="Whetstone backend")
    app.state.store = ParquetCardStore(storage_dir or default_storage_dir())
    app.state.blender = blender or BlenderClient()

    def store(request: Request) -> ParquetCardStore:
        return request.app.state.store

    @app.get("/health")
    def health(request: Request) -> dict:
        return {"status": "ok", "cards": store(request).count()}

    @app.get("/cards")
    def list_cards(request: Request) -> dict:
        return {"cards": [c.model_dump() for c in store(request).list()]}

    @app.get("/cards/{card_id}")
    def get_card(card_id: str, request: Request) -> Card:
        card = store(request).get(card_id)
        if card is None:
            raise HTTPException(404, f"no card {card_id}")
        return card

    @app.put("/cards/{card_id}")
    def put_card(card_id: str, card: Card, request: Request) -> Card:
        if card.id != card_id:
            raise HTTPException(400, f"card id {card.id!r} does not match the URL {card_id!r}")
        store(request).put(card)
        return card

    @app.delete("/cards/{card_id}", status_code=204)
    def delete_card(card_id: str, request: Request) -> Response:
        if not store(request).delete(card_id):
            raise HTTPException(404, f"no card {card_id}")
        return Response(status_code=204)

    def run_in_blender(request: Request, code: str) -> dict:
        try:
            reply = request.app.state.blender.execute(code)
        except BlenderError as e:
            raise HTTPException(502, str(e))
        if reply.get("status") != "ok":
            msg = str(reply.get("message", reply)).strip()
            last = msg.splitlines()[-1] if msg else "unknown error"  # a traceback's last line says what went wrong
            raise HTTPException(502, f"Blender: {last}")
        return reply

    @app.get("/blender/status")
    def blender_status(request: Request) -> dict:
        b = request.app.state.blender
        return {"available": b.available(), "host": b.host, "port": b.port}

    @app.post("/blender/ops")
    def blender_ops(req: OpsRequest, request: Request) -> dict:
        try:
            code = ops_to_code(req.ops)
        except OpError as e:
            raise HTTPException(422, str(e))
        if req.dryRun:
            return {"code": code, "sent": False}
        reply = run_in_blender(request, code)
        return {"code": code, "sent": True, "result": reply.get("result"), "stdout": reply.get("stdout", "")}

    @app.post("/blender/execute")
    def blender_execute(req: ExecuteRequest, request: Request) -> dict:
        reply = run_in_blender(request, req.code)
        return {"result": reply.get("result"), "stdout": reply.get("stdout", "")}

    return app
