"""Wire models. JSON keys are camelCase (all single words today); the keys
inside `fields` are the card's own field names (e.g. `applies_from`)."""
from __future__ import annotations

from pydantic import BaseModel, Field


class Button(BaseModel):
    name: str
    script: str = ""


class Card(BaseModel):
    id: str = Field(min_length=1)
    name: str = ""
    kind: str = "card"
    stack: str = "Recipes"
    script: str = ""
    fields: dict[str, str] = Field(default_factory=dict)
    buttons: list[Button] = Field(default_factory=list)
    required: list[str] = Field(default_factory=list)  # names of required fields
