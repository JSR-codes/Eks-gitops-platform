import pytest

from src.app import create_app


@pytest.fixture()
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


def test_index_returns_version(client):
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["service"] == "demo-app"
    assert "version" in body


def test_items(client):
    resp = client.get("/api/items")
    assert resp.status_code == 200
    assert len(resp.get_json()["items"]) == 5


@pytest.mark.parametrize("path", ["/healthz", "/readyz"])
def test_probes(client, path):
    assert client.get(path).status_code == 200


def test_metrics_exposed(client):
    client.get("/")
    resp = client.get("/metrics")
    assert resp.status_code == 200
    text = resp.get_data(as_text=True)
    assert "http_requests_total" in text
    assert "http_request_duration_seconds_bucket" in text
    assert "app_build_info" in text


def test_probe_paths_not_counted(client):
    client.get("/healthz")
    text = client.get("/metrics").get_data(as_text=True)
    assert 'path="/healthz"' not in text
