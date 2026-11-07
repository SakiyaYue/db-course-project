"""Flask 应用工厂。"""

from __future__ import annotations

import json
import logging
import os
import secrets
import time
import traceback
from pathlib import Path

from flask import g, Flask, jsonify, render_template, request, session

from .dao.common import health
from .config import Config
from .db import Database
from .errors import AppError, translate_db_error
from .security import CSRF_KEY, csrf_token, current_auth, get_database, validate_csrf

BASE_DIR = Path(__file__).resolve().parent.parent


def create_app(config: Config | None = None) -> Flask:
    app = Flask(__name__, static_folder="static", template_folder="templates")
    cfg = config or Config.from_env(BASE_DIR / ".env")
    app.config.update(
        SECRET_KEY=cfg.secret_key,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=cfg.session_cookie_secure,
        JSON_AS_ASCII=False,
        MAX_CONTENT_LENGTH=256 * 1024,
    )
    app.extensions["teabar_config"] = cfg
    app.extensions["teabar_db"] = Database(cfg)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

    from .routes import admin_routes, api_routes, auth_routes, menu_routes, order_routes, work_routes

    app.register_blueprint(auth_routes.bp)
    app.register_blueprint(menu_routes.bp)
    app.register_blueprint(order_routes.bp)
    app.register_blueprint(work_routes.bp)
    app.register_blueprint(admin_routes.bp)
    app.register_blueprint(api_routes.bp)

    @app.before_request
    def _csrf_protect():
        g.request_id = secrets.token_hex(12)
        g.started_at = time.monotonic()
        g.audit_actor = dict(current_auth() or {})
        validate_csrf()

    @app.after_request
    def _attach_csrf(response):
        auth = current_auth() or getattr(g, "audit_actor", {})
        response.headers["X-Request-ID"] = getattr(g, "request_id", "unknown")
        app.logger.info("request %s", json.dumps({
            "request_id": getattr(g, "request_id", None),
            "operation": request.endpoint or "unmatched", "method": request.method,
            "account_id": auth.get("account_id"), "role": auth.get("app_role"),
            "error_code": getattr(g, "error_code", None),
            "sql_number": getattr(g, "sql_number", None), "sql_state": getattr(g, "sql_state", None),
            "status": response.status_code, "result": "ok" if response.status_code < 400 else "failed",
            "elapsed_ms": round((time.monotonic()-getattr(g, "started_at", time.monotonic()))*1000, 2),
        }, ensure_ascii=False))
        token = session.get(CSRF_KEY)
        if token:
            response.headers["X-CSRF-Token"] = token
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "same-origin"
        return response

    @app.context_processor
    def _inject_globals():
        return {"csrf_token": csrf_token, "auth": current_auth()}

    @app.errorhandler(AppError)
    def _handle_app_error(exc: AppError):
        if request.path.startswith("/api/") or request.is_json:
            return jsonify({"error": {"code": exc.code, "message": exc.message}}), exc.status
        return render_template("error.html", code=exc.code, message=exc.message, status=exc.status), exc.status

    @app.errorhandler(Exception)
    def _handle_unexpected(exc: Exception):
        if isinstance(exc, AppError):
            return _handle_app_error(exc)
        from werkzeug.exceptions import HTTPException
        if isinstance(exc, HTTPException):
            error = AppError("http_error", "请求地址或请求内容不正确。", exc.code or 500)
        else:
            error = translate_db_error(exc)
        # File/line/function identify code location without exposing exception parameter values.
        app.logger.error("failure request_id=%s type=%s frames=%s",
                         getattr(g, "request_id", None), type(exc).__name__,
                         [(Path(f.filename).name, f.lineno, f.name) for f in traceback.extract_tb(exc.__traceback__)])
        if request.path.startswith("/api/") or request.is_json:
            return jsonify({"error": {"code": error.code, "message": error.message}}), error.status
        return render_template("error.html", code=error.code, message=error.message, status=error.status), error.status

    @app.get("/healthz")
    def healthz():
        db = get_database()
        try:
            with db.connection("teabar-health") as conn:
                health(conn)
            return jsonify({"status": "ok"})
        except AppError as exc:
            return jsonify({"status": "error", "message": exc.message}), 503

    return app
