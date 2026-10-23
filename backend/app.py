"""
Flask application factory.

Serves the built React frontend from ``frontend/dist`` and the API from
``/api``. One process, one Core, one PLC connection.

NOTE ON debug/reloader: the app is started from run.py with the reloader OFF.
The legacy ``Final/app.py`` ran ``app.run(debug=True)``, which forks a second
Werkzeug process -- and since that module connected to the PLC at import time,
it produced two competing Snap7 clients from a single command. Never re-enable
the reloader while a PLC connection is owned at module scope.
"""

from __future__ import annotations

import logging
import os

from flask import Flask, jsonify, send_from_directory

from backend.api.extended import extended
from backend.api.rest import api
from backend.api.stream import stream
from backend.core import Core

log = logging.getLogger("app")

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
_DIST = os.path.join(_ROOT, "frontend", "dist")


def create_app(core: Core) -> Flask:
    app = Flask(__name__, static_folder=None)
    app.config["CORE"] = core
    app.config["JSON_SORT_KEYS"] = False

    app.register_blueprint(api)
    app.register_blueprint(extended)
    app.register_blueprint(stream)

    # ---- frontend ----------------------------------------------------
    @app.get("/")
    def index():
        if not os.path.exists(os.path.join(_DIST, "index.html")):
            return _build_hint(), 503
        return send_from_directory(_DIST, "index.html")

    @app.get("/<path:path>")
    def assets(path: str):
        candidate = os.path.join(_DIST, path)
        if os.path.isfile(candidate):
            return send_from_directory(_DIST, path)
        # SPA fallback: any unknown non-API path renders the app shell so
        # deep links like /diagnostics survive a refresh.
        if not os.path.exists(os.path.join(_DIST, "index.html")):
            return _build_hint(), 503
        return send_from_directory(_DIST, "index.html")

    # ---- errors ------------------------------------------------------
    @app.errorhandler(404)
    def not_found(_):
        return jsonify({"ok": False, "error": {
            "code": "not_found", "message": "No such endpoint."}}), 404

    @app.errorhandler(500)
    def server_error(exc):
        log.exception("unhandled error")
        return jsonify({"ok": False, "error": {
            "code": "internal", "message": str(exc)}}), 500

    return app


def _build_hint() -> str:
    return (
        "<!doctype html><meta charset='utf-8'>"
        "<title>Frontend not built</title>"
        "<body style='font:15px/1.6 system-ui;background:#0b0f14;color:#e6edf3;"
        "padding:48px;max-width:760px;margin:auto'>"
        "<h1 style='color:#facc15'>Frontend build not found</h1>"
        "<p>The API is running, but <code>frontend/dist</code> does not exist yet.</p>"
        "<pre style='background:#111827;padding:16px;border-radius:8px'>"
        "cd frontend\nnpm install\nnpm run build</pre>"
        "<p>Or run the Vite dev server on port 5173 during development:</p>"
        "<pre style='background:#111827;padding:16px;border-radius:8px'>"
        "cd frontend\nnpm run dev</pre>"
        "<p>The API itself is live at "
        "<a style='color:#38bdf8' href='/api/health'>/api/health</a>.</p>"
        "</body>"
    )
