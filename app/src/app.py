"""Small HTTP service used to exercise the platform.

It exposes Prometheus metrics (request count, latency histogram, build info)
so the dashboards and alerts have real signals to work with.
"""

import os
import random
import time

from flask import Flask, Response, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

APP_VERSION = os.getenv("APP_VERSION", "dev")
# Lets you inject failures to test alerting and rollbacks (0.0 - 1.0).
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))

REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests handled",
    ["method", "path", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5),
)
BUILD_INFO = Gauge("app_build_info", "Build metadata", ["version"])
BUILD_INFO.labels(version=APP_VERSION).set(1)

UNTRACKED_PATHS = {"/metrics", "/healthz", "/readyz"}


def create_app() -> Flask:
    app = Flask(__name__)

    @app.before_request
    def _start_timer():
        request.environ["_start"] = time.perf_counter()

    @app.after_request
    def _record(response):
        if request.path not in UNTRACKED_PATHS:
            elapsed = time.perf_counter() - request.environ.get("_start", time.perf_counter())
            path = request.url_rule.rule if request.url_rule else "unmatched"
            LATENCY.labels(request.method, path).observe(elapsed)
            REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        return response

    @app.get("/")
    def index():
        if ERROR_RATE and random.random() < ERROR_RATE:
            return jsonify(error="injected failure"), 500
        return jsonify(service="demo-app", version=APP_VERSION, status="ok")

    @app.get("/api/items")
    def items():
        if ERROR_RATE and random.random() < ERROR_RATE:
            return jsonify(error="injected failure"), 500
        return jsonify(items=[{"id": i, "name": f"item-{i}"} for i in range(1, 6)])

    @app.get("/healthz")
    def healthz():
        return jsonify(status="alive")

    @app.get("/readyz")
    def readyz():
        return jsonify(status="ready")

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
