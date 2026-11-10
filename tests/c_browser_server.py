"""Optional local browser-test server; always points at the isolated test database."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ['TEABAR_DB_NAME'] = 'TeabarDB_Phase2_Test'
from app import create_app

if __name__ == '__main__':
    create_app().run(host='127.0.0.1', port=5051, debug=False, use_reloader=False)
