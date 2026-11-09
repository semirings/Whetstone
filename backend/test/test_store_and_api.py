import pyarrow.parquet as pq
import pytest
from fastapi.testclient import TestClient

from whetstone_be.app import create_app
from whetstone_be.models import Button, Card
from whetstone_be.store import ParquetCardStore, StoreError


def card(i="c1", **kw):
    return Card(id=i, **kw)


@pytest.fixture()
def client(tmp_path):
    return TestClient(create_app(tmp_path))


def body(i="c1", **kw):
    return card(i, **kw).model_dump()


def test_health_empty(client):
    assert client.get("/health").json() == {"status": "ok", "cards": 0}


def test_put_get_round_trip_is_exact(client):
    c = body(
        "c1",
        name="Camera points nowhere",
        script="on mouseUp\n  beep\nend mouseUp\n",
        fields={"symptom": "line one\nline two\ttab", "expected": "", "calls": "0.0\tbpy.ops.x()"},
        buttons=[{"name": "Replay", "script": "on mouseUp\nend mouseUp"}, {"name": "Empty", "script": ""}],
    )
    assert client.put("/cards/c1", json=c).status_code == 200
    assert client.get("/cards/c1").json() == c


def test_unicode_and_backslashes(client):
    c = body("c1", name="café \\ naïve", fields={"symptom": "日本語 \\n not a newline"})
    client.put("/cards/c1", json=c)
    assert client.get("/cards/c1").json() == c


def test_list_keeps_order_and_replace_keeps_position(client):
    for i in ("a", "b", "c"):
        client.put(f"/cards/{i}", json=body(i, name=i))
    client.put("/cards/b", json=body("b", name="B2"))
    names = [c["name"] for c in client.get("/cards").json()["cards"]]
    assert names == ["a", "B2", "c"]


def test_delete_and_404(client):
    client.put("/cards/a", json=body("a"))
    assert client.delete("/cards/a").status_code == 204
    assert client.delete("/cards/a").status_code == 404
    assert client.get("/cards/a").status_code == 404


def test_id_must_match_url(client):
    assert client.put("/cards/x", json=body("y")).status_code == 400


def test_empty_id_rejected(client):
    assert client.put("/cards/x", json={"id": ""}).status_code == 422


def test_persists_across_restarts_in_order(tmp_path):
    c1 = TestClient(create_app(tmp_path))
    c1.put("/cards/a", json=body("a", name="A", fields={"symptom": "s"}))
    c1.put("/cards/b", json=body("b", name="B"))
    c2 = TestClient(create_app(tmp_path))
    cards = c2.get("/cards").json()["cards"]
    assert [c["id"] for c in cards] == ["a", "b"]
    assert cards[0]["fields"] == {"symptom": "s"}


def test_file_is_a_row_col_val_array(tmp_path):
    s = ParquetCardStore(tmp_path)
    s.put(Card(id="c1", name="N", fields={"symptom": "x"}, buttons=[Button(name="B", script="s")]))
    t = pq.read_table(tmp_path / "cards.parquet")
    assert t.column_names == ["row", "col", "val"]
    assert str(t.schema.field("val").type) == "string"
    triples = set(zip(*(t.column(n).to_pylist() for n in ("row", "col", "val"))))
    assert ("c1", "field|symptom", "x") in triples
    assert ("c1", "button|B", "s") in triples
    assert ("c1", "name", "N") in triples
    assert ("c1", "kind", "card") in triples


def test_tsv_mirror_is_escaped_and_one_line_per_triple(tmp_path):
    s = ParquetCardStore(tmp_path)
    s.put(Card(id="c1", fields={"symptom": "a\nb\tc"}))
    lines = (tmp_path / "cards.tsv").read_text(encoding="utf-8").splitlines()
    assert lines[0] == "row\tcol\tval"
    assert "c1\tfield|symptom\ta\\nb\\tc" in lines
    assert all(line.count("\t") == 2 for line in lines)


def test_no_temp_files_left(tmp_path):
    s = ParquetCardStore(tmp_path)
    s.put(Card(id="c1"))
    assert sorted(p.name for p in tmp_path.iterdir()) == ["cards.parquet", "cards.tsv"]


def test_corrupt_file_is_refused_and_left_alone(tmp_path):
    (tmp_path / "cards.parquet").write_bytes(b"not parquet")
    with pytest.raises(StoreError):
        ParquetCardStore(tmp_path)
    assert (tmp_path / "cards.parquet").read_bytes() == b"not parquet"


def test_wrong_columns_are_refused(tmp_path):
    import pyarrow as pa

    pq.write_table(pa.table({"a": ["x"]}), tmp_path / "cards.parquet")
    with pytest.raises(StoreError):
        ParquetCardStore(tmp_path)


def test_unknown_columns_are_ignored(tmp_path):
    import pyarrow as pa

    pq.write_table(
        pa.table({"row": ["c1", "c1"], "col": ["name", "futureThing|x"], "val": ["N", "y"]}),
        tmp_path / "cards.parquet",
    )
    s = ParquetCardStore(tmp_path)
    assert s.get("c1").name == "N"


def test_required_fields_round_trip(client):
    card = {"id": "r1", "name": "x", "fields": {"a": "", "b": "1"}, "required": ["b"]}
    assert client.put("/cards/r1", json=card).status_code in (200, 201)
    assert client.get("/cards/r1").json()["required"] == ["b"]
