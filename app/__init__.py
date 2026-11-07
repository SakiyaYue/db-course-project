"""Flask 应用工厂。"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

from flask import Flask, jsonify, render_template, request, session

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
        validate_csrf()

    @app.after_request
    def _attach_csrf(response):
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
        error = translate_db_error(exc)
        app.logger.exception("未处理异常: %s", exc)
        if request.path.startswith("/api/") or request.is_json:
            return jsonify({"error": {"code": error.code, "message": error.message}}), error.status
        return render_template("error.html", code=error.code, message=error.message, status=error.status), error.status

    @app.get("/healthz")
    def healthz():
        db = get_database()
        try:
            with db.connection("teabar-health") as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT DB_NAME(), SUSER_SNAME()")
                db_name, login = cursor.fetchone()
                cursor.close()
            return jsonify({"status": "ok", "database": db_name, "login": login})
        except AppError as exc:
            return jsonify({"status": "error", "message": exc.message}), 503

    return app
