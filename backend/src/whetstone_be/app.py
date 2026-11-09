"""Whetstone backend: FastAPI on port 8402 (DoubleNaught 8400, SegForge 8401)."""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Response

from .models import Card
from .store import ParquetCardStore


def default_storage_dir() -> Path:
    env = os.environ.get("WHETSTONE_STORAGE")
    if env:
        return Path(env)
    # backend/src/whetstone_be/app.py -> the Whetstone project root
    return Path(__file__).resolve().parents[3] / "storage"


def create_app(storage_dir: str | Path | None = None) -> FastAPI:
    app = FastAPI(title="Whetstone backend")
    app.state.store = ParquetCardStore(storage_dir or default_storage_dir())

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

    return app
