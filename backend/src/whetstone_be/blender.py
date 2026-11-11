"""Talk to Blender, and turn Speakeasy's Blender operations into Python for it.

Blender side: the `mcp` extension runs a small TCP server inside Blender
(127.0.0.1:9876). A request is one JSON object ended by a NUL byte,

    {"type": "execute", "code": "<python>", "strict_json": true}\\0

and the reply is one JSON object ended by a NUL byte,

    {"status": "ok", "result": {...}, "stdout": "..."}\\0
    {"status": "error", "message": "<traceback>"}\\0

The code runs in Blender with `bpy`; whatever it assigns to the dict `result`
comes back. One request per connection.

An *operation tree* is a list of plain dicts, the form Speakeasy's Blender
extension produces:

    {"op": "create", "shape": "sphere", "name": "Eye", "at": [0, 0, 0]}
    {"op": "move",   "object": "Eye", "mode": "to" | "by", "point": [x, y, z]}
    {"op": "rotate", "object": "Eye", "mode": "to" | "by", "point": [x, y, z]}  # degrees
    {"op": "scale",  "object": "Eye", "mode": "to" | "by", "point": [x, y, z]}  # or "factor": n
    {"op": "delete", "object": "Eye"}
    {"op": "render", "to": "frame.png"}                                          # "to" optional

`ops_to_code` turns it into a Python script. The same script is what a recipe
card keeps as its `calls`, so a card can be replayed without Whetstone.
"""
from __future__ import annotations

import json
import os
import socket
from typing import Any

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9876
_MAX_REPLY = 64 * 1024 * 1024


class BlenderError(Exception):
    """Blender could not be reached, or it reported an error."""


class BlenderClient:
    def __init__(self, host: str | None = None, port: int | None = None, timeout: float = 30.0):
        self.host = host or os.environ.get("WHETSTONE_BLENDER_HOST", DEFAULT_HOST)
        self.port = port or int(os.environ.get("WHETSTONE_BLENDER_PORT", DEFAULT_PORT))
        self.timeout = timeout

    def execute(self, code: str, strict_json: bool = True) -> dict[str, Any]:
        """Run [code] in Blender; return the reply dict (status, result, stdout...)."""
        request = json.dumps({"type": "execute", "code": code, "strict_json": strict_json})
        try:
            with socket.create_connection((self.host, self.port), timeout=self.timeout) as s:
                s.sendall(request.encode("utf-8") + b"\0")
                buf = bytearray()
                while b"\0" not in buf:
                    chunk = s.recv(65536)
                    if not chunk:
                        break
                    buf += chunk
                    if len(buf) > _MAX_REPLY:
                        raise BlenderError("Blender's reply is too large")
        except (OSError, socket.timeout) as e:
            raise BlenderError(
                f"cannot reach Blender at {self.host}:{self.port} ({e}). "
                "Is Blender open with the MCP extension running?"
            ) from e
        raw = bytes(buf).split(b"\0", 1)[0]
        if not raw:
            raise BlenderError("Blender closed the connection without replying")
        try:
            return json.loads(raw)
        except ValueError as e:
            raise BlenderError(f"Blender sent something that is not JSON: {raw[:200]!r}") from e

    def available(self) -> bool:
        try:
            return self.execute("import bpy\nresult = {'v': bpy.app.version_string}").get("status") == "ok"
        except BlenderError:
            return False


# ── operation tree → Python ──────────────────────────────────────────────────

_SHAPES = {
    "cube": "bpy.ops.mesh.primitive_cube_add(location={at})",
    "sphere": "bpy.ops.mesh.primitive_uv_sphere_add(location={at})",
    "plane": "bpy.ops.mesh.primitive_plane_add(location={at})",
    "cylinder": "bpy.ops.mesh.primitive_cylinder_add(location={at})",
    "cone": "bpy.ops.mesh.primitive_cone_add(location={at})",
    "camera": "bpy.ops.object.camera_add(location={at})",
    "light": "bpy.ops.object.light_add(type='POINT', location={at})",
}


class OpError(ValueError):
    """An operation is malformed."""


def _num(v: Any, what: str) -> float:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise OpError(f"{what} must be a number, got {v!r}")
    f = float(v)
    if f != f or f in (float("inf"), float("-inf")):
        raise OpError(f"{what} must be a finite number")
    return f


def _point(v: Any, what: str) -> tuple[float, float, float]:
    if not isinstance(v, (list, tuple)) or len(v) != 3:
        raise OpError(f"{what} must be three numbers, got {v!r}")
    return (_num(v[0], what), _num(v[1], what), _num(v[2], what))


def _str(v: Any, what: str) -> str:
    if not isinstance(v, str) or not v:
        raise OpError(f"{what} must be a non-empty string, got {v!r}")
    return v


def _mode(op: dict) -> str:
    m = op.get("mode", "to")
    if m not in ("to", "by"):
        raise OpError(f"mode must be 'to' or 'by', got {m!r}")
    return m


def op_to_lines(op: dict, index: int) -> list[str]:
    """Python lines for one operation. Strings go in via repr(), so no quoting trouble."""
    if not isinstance(op, dict):
        raise OpError(f"operation {index} is not an object")
    kind = op.get("op")
    if kind == "create":
        shape = op.get("shape")
        if shape not in _SHAPES:
            raise OpError(f"unknown shape {shape!r}; expected one of {', '.join(_SHAPES)}")
        at = _point(op.get("at", [0, 0, 0]), "at")
        lines = [_SHAPES[shape].format(at=repr(at)), "_o = bpy.context.active_object"]
        if op.get("name") is not None:
            n = _str(op["name"], "name")
            # Refuse before creating anything: a clash would make Blender name the
            # new object "Eye.001" and later commands would hit the old "Eye".
            lines.insert(0, f"if {n!r} in bpy.data.objects: raise KeyError('an object named ' + {n!r} + ' already exists')")
            lines.append(f"_o.name = {n!r}")
        lines.append("_created.append(_o.name)")
        return lines

    if kind in ("move", "rotate", "scale", "delete"):
        name = _str(op.get("object"), "object")
        get = [
            f"_o = bpy.data.objects.get({name!r})",
            f"if _o is None: raise KeyError('no object named ' + {name!r})",
        ]
        if kind == "delete":
            return get + [
                "_d = _o.data",
                "bpy.data.objects.remove(_o, do_unlink=True)",
                "if _d is not None and _d.users == 0: bpy.data.batch_remove([_d])",
                f"_deleted.append({name!r})",
            ]
        mode = _mode(op)
        if kind == "move":
            p = _point(op.get("point"), "point")
            body = (
                [f"_o.location = {p!r}"]
                if mode == "to"
                else [f"_o.location = tuple(a + b for a, b in zip(_o.location, {p!r}))"]
            )
        elif kind == "rotate":
            p = _point(op.get("point"), "point")  # degrees
            body = (
                [f"_o.rotation_euler = tuple(math.radians(d) for d in {p!r})"]
                if mode == "to"
                else [
                    "_o.rotation_euler = tuple(a + math.radians(d) "
                    f"for a, d in zip(_o.rotation_euler, {p!r}))"
                ]
            )
        else:  # scale
            if op.get("factor") is not None:
                f = _num(op["factor"], "factor")
                p = (f, f, f)
            else:
                p = _point(op.get("point"), "point")
            body = (
                [f"_o.scale = {p!r}"]
                if mode == "to"
                else [f"_o.scale = tuple(a * b for a, b in zip(_o.scale, {p!r}))"]
            )
        return get + body + [f"_touched.append({name!r})"]

    if kind == "render":
        # A relative path would be resolved against Blender's working folder
        # (often "/"), so put it beside the .blend file, or in Blender's temp dir.
        src = repr(_str(op["to"], "to")) if op.get("to") is not None else "bpy.context.scene.render.filepath"
        return [
            f"_p = {src}",
            "if not os.path.isabs(_p): _p = os.path.join(os.path.dirname(bpy.data.filepath) or bpy.app.tempdir, _p)",
            "bpy.context.scene.render.filepath = _p",
            "bpy.ops.render.render(write_still=True)",
            "_rendered.append(_p)",
        ]

    raise OpError(f"operation {index}: unknown op {kind!r}")


def ops_to_code(ops: list[dict]) -> str:
    """A complete Python script for [ops]. Raises OpError on a malformed tree."""
    if not isinstance(ops, list) or not ops:
        raise OpError("ops must be a non-empty list")
    out = [
        "import math",
        "import os",
        "import bpy",
        "_created, _touched, _deleted, _rendered = [], [], [], []",
    ]
    for i, op in enumerate(ops):
        out.append(f"# {i + 1}: {op.get('op') if isinstance(op, dict) else '?'}")
        out += op_to_lines(op, i)
    out.append(
        "result = {'created': _created, 'touched': _touched, "
        "'deleted': _deleted, 'rendered': _rendered}"
    )
    return "\n".join(out) + "\n"
