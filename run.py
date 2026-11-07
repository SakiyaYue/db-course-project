"""开发入口：python run.py"""

from __future__ import annotations

import os

from app import create_app

app = create_app()

if __name__ == "__main__":
    host = os.environ.get("TEABAR_HOST", "127.0.0.1")
    port = int(os.environ.get("TEABAR_PORT", "5000"))
    debug = os.environ.get("TEABAR_DEBUG", "1") in {"1", "yes", "true"}
    app.run(host=host, port=port, debug=debug)
