"""Card store: one Parquet file holding an associative array of triples.

A card is a ROW of the array. Its facts are COLUMNS:

    row = card id
    col = kind | name | stack | script | field|<field name> | button|<button name>
    val = text (a button's val is its script)

The file has three string columns, `row`, `col`, `val`, the same shape
DoubleNaught uses for its ontologies, so D4M can load it as it is.
Every card round-trips exactly, including empty fields (an empty val is stored
as "", not dropped). A `cards.tsv` mirror is written beside it for people
and diffs; it is never read back.

The store keeps all cards in memory and rewrites the file on every change,
through a temporary file and an atomic rename. That is fine for hundreds of
cards. Whetstone's backend is the only writer.
"""
from __future__ import annotations

import os
import threading
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

from .models import Button, Card

FIELD = "field|"
BUTTON = "button|"
REQUIRED = "required|"
_PLAIN = ("kind", "name", "stack", "script")

Triple = tuple[str, str, str]


def card_to_triples(card: Card) -> list[Triple]:
    t: list[Triple] = [
        (card.id, "kind", card.kind),
        (card.id, "name", card.name),
        (card.id, "stack", card.stack),
        (card.id, "script", card.script),
    ]
    t += [(card.id, FIELD + k, v) for k, v in card.fields.items()]
    t += [(card.id, BUTTON + b.name, b.script) for b in card.buttons]
    t += [(card.id, REQUIRED + n, "true") for n in card.required]
    return t


def triples_to_cards(rows: list[Triple]) -> dict[str, Card]:
    """Rebuild cards, keeping the order in which cards first appear."""
    plain: dict[str, dict[str, str]] = {}
    fields: dict[str, dict[str, str]] = {}
    buttons: dict[str, list[Button]] = {}
    required: dict[str, list[str]] = {}
    for row, col, val in rows:
        plain.setdefault(row, {})
        fields.setdefault(row, {})
        buttons.setdefault(row, [])
        required.setdefault(row, [])
        if col in _PLAIN:
            plain[row][col] = val
        elif col.startswith(FIELD):
            fields[row][col[len(FIELD):]] = val
        elif col.startswith(BUTTON):
            buttons[row].append(Button(name=col[len(BUTTON):], script=val))
        elif col.startswith(REQUIRED):
            required[row].append(col[len(REQUIRED):])
        # unknown columns are ignored, so a newer file can be read by an older app
    return {
        row: Card(id=row, fields=fields[row], buttons=buttons[row],
             required=required[row], **plain[row])
        for row in plain
    }


def _tsv_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
    )


class StoreError(Exception):
    """The file on disk could not be read. It is left untouched."""


class ParquetCardStore:
    def __init__(self, directory: str | Path):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / "cards.parquet"
        self.mirror = self.directory / "cards.tsv"
        self._lock = threading.RLock()
        self._cards: dict[str, Card] = {}
        self._load()

    # ---- reading

    def _load(self) -> None:
        if not self.path.exists():
            return
        try:
            table = pq.read_table(self.path)
            if table.column_names != ["row", "col", "val"]:
                raise StoreError(
                    f"{self.path} has columns {table.column_names}, expected row, col, val"
                )
            rows = list(
                zip(
                    table.column("row").to_pylist(),
                    table.column("col").to_pylist(),
                    table.column("val").to_pylist(),
                )
            )
            self._cards = triples_to_cards([(r, c, v if v is not None else "") for r, c, v in rows])
        except StoreError:
            raise
        except Exception as e:  # corrupt or not Parquet: refuse, never overwrite
            raise StoreError(f"cannot read {self.path}: {e}") from e

    def count(self) -> int:
        with self._lock:
            return len(self._cards)

    def list(self) -> list[Card]:
        with self._lock:
            return [c.model_copy(deep=True) for c in self._cards.values()]

    def get(self, card_id: str) -> Card | None:
        with self._lock:
            c = self._cards.get(card_id)
            return c.model_copy(deep=True) if c else None

    # ---- writing

    def put(self, card: Card) -> bool:
        """Create or replace. A replaced card keeps its place in the order.
        Returns True if the card is new."""
        with self._lock:
            is_new = card.id not in self._cards
            self._cards[card.id] = card.model_copy(deep=True)
            self._flush()
            return is_new

    def delete(self, card_id: str) -> bool:
        with self._lock:
            if card_id not in self._cards:
                return False
            del self._cards[card_id]
            self._flush()
            return True

    def _flush(self) -> None:
        triples: list[Triple] = []
        for card in self._cards.values():
            triples += card_to_triples(card)
        table = pa.table(
            {
                "row": pa.array([t[0] for t in triples], pa.string()),
                "col": pa.array([t[1] for t in triples], pa.string()),
                "val": pa.array([t[2] for t in triples], pa.string()),
            }
        )
        self._atomic(self.path, lambda p: pq.write_table(table, p))
        self._atomic(self.mirror, lambda p: self._write_tsv(p, triples))

    @staticmethod
    def _write_tsv(path: Path, triples: list[Triple]) -> None:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("row\tcol\tval\n")
            for r, c, v in triples:
                f.write(f"{_tsv_escape(r)}\t{_tsv_escape(c)}\t{_tsv_escape(v)}\n")

    @staticmethod
    def _atomic(target: Path, write) -> None:
        tmp = target.with_name(target.name + ".tmp")
        try:
            write(tmp)
            os.replace(tmp, target)
        finally:
            if tmp.exists():
                tmp.unlink()
