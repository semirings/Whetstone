import json
import socket
import threading

import pytest
from fastapi.testclient import TestClient

from whetstone_be.app import create_app
from whetstone_be.blender import BlenderClient, BlenderError, OpError, ops_to_code


class FakeBlender:
    """Speaks the MCP add-on's protocol: one JSON request ended by NUL, one reply likewise."""

    def __init__(self, reply):
        self.reply, self.requests = reply, []
        self.srv = socket.socket()
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen(4)
        self.port = self.srv.getsockname()[1]
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self):
        while True:
            try:
                c, _ = self.srv.accept()
            except OSError:
                return
            buf = b""
            while b"\0" not in buf:
                d = c.recv(4096)
                if not d:
                    break
                buf += d
            self.requests.append(json.loads(buf.split(b"\0")[0]))
            c.sendall(json.dumps(self.reply).encode() + b"\0")
            c.close()

    def close(self):
        self.srv.close()


@pytest.fixture()
def fake():
    f = FakeBlender({"status": "ok", "result": {"created": ["Eye"]}, "stdout": ""})
    yield f
    f.close()


@pytest.fixture()
def client(tmp_path, fake):
    return TestClient(create_app(tmp_path, BlenderClient(port=fake.port, timeout=3)))


def test_ops_to_code_compiles_and_quotes():
    code = ops_to_code([
        {"op": "create", "shape": "sphere", "name": "it's \"x\"", "at": [1, 2, 3]},
        {"op": "move", "object": "a", "mode": "by", "point": [1, 0, 0]},
        {"op": "rotate", "object": "a", "point": [0, 0, 90]},
        {"op": "scale", "object": "a", "factor": 2},
        {"op": "delete", "object": "a"},
        {"op": "render", "to": "f.png"},
    ])
    compile(code, "<ops>", "exec")
    assert "primitive_uv_sphere_add" in code


@pytest.mark.parametrize("ops", [
    [], "x", [1], [{"op": "nope"}], [{"op": "create", "shape": "teapot"}],
    [{"op": "create", "shape": "cube", "at": [1, 2]}],
    [{"op": "move", "object": "a", "point": [1, 2, "3"]}],
    [{"op": "move", "object": "a", "mode": "sideways", "point": [0, 0, 0]}],
    [{"op": "delete"}],
    [{"op": "scale", "object": "a", "factor": True}],
])
def test_bad_ops_rejected(ops):
    with pytest.raises(OpError):
        ops_to_code(ops)


def test_ops_endpoint_sends_code(client, fake):
    r = client.post("/blender/ops", json={"ops": [{"op": "create", "shape": "sphere", "name": "Eye"}]})
    assert r.status_code == 200
    assert r.json()["result"] == {"created": ["Eye"]}
    req = fake.requests[0]
    assert req["type"] == "execute" and req["strict_json"] is True
    assert "primitive_uv_sphere_add" in req["code"] and "'Eye'" in req["code"]


def test_dry_run_sends_nothing(client, fake):
    r = client.post("/blender/ops", json={"ops": [{"op": "delete", "object": "a"}], "dryRun": True})
    assert r.json()["sent"] is False and "bpy.data.objects" in r.json()["code"]
    assert fake.requests == []


def test_malformed_ops_is_422(client, fake):
    assert client.post("/blender/ops", json={"ops": [{"op": "zap"}]}).status_code == 422
    assert fake.requests == []


def test_blender_error_reply_is_502(tmp_path):
    f = FakeBlender({"status": "error", "message": "Traceback (most recent call last):\n  File x\nKeyError: no object named 'a'\n"})
    c = TestClient(create_app(tmp_path, BlenderClient(port=f.port, timeout=3)))
    r = c.post("/blender/ops", json={"ops": [{"op": "delete", "object": "a"}]})
    f.close()
    assert r.status_code == 502 and r.json()["detail"] == "Blender: KeyError: no object named 'a'"


def test_unreachable_is_502_and_status_false(tmp_path):
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    c = TestClient(create_app(tmp_path, BlenderClient(port=port, timeout=1)))
    assert c.get("/blender/status").json()["available"] is False
    r = c.post("/blender/execute", json={"code": "result = {}"})
    assert r.status_code == 502 and "cannot reach Blender" in r.json()["detail"]


def test_status_true_and_execute(client, fake):
    assert client.get("/blender/status").json()["available"] is True
    r = client.post("/blender/execute", json={"code": "result = {'a': 1}"})
    assert r.status_code == 200 and fake.requests[-1]["code"] == "result = {'a': 1}"


def test_client_rejects_non_json():
    class Garbage(FakeBlender):
        def _serve(self):
            c, _ = self.srv.accept()
            c.recv(4096)
            c.sendall(b"not json\0")
            c.close()

    f = Garbage(None)
    try:
        with pytest.raises(BlenderError, match="not JSON"):
            BlenderClient(port=f.port, timeout=2).execute("1")
    finally:
        f.close()


def test_create_with_name_refuses_a_clash_and_render_path_is_absolute():
    code = ops_to_code([{"op": "create", "shape": "sphere", "name": "Eye"}, {"op": "render", "to": "f.png"}])
    first = code.index("already exists")
    assert first < code.index("primitive_uv_sphere_add")
    assert "bpy.app.tempdir" in code and "import os" in code
    compile(code, "<ops>", "exec")
