from pathlib import Path

from app import create_app
from app.config import load_development_server_config
from app.system import consume_server_restart_request

_BASE_DIR = Path(__file__).resolve().parent
_SERVER_CONFIG = load_development_server_config(_BASE_DIR)

if __name__ == "__main__":
    while True:
        app = create_app()
        app.run(
            host=str(_SERVER_CONFIG["host"]),
            port=int(_SERVER_CONFIG["port"]),
            debug=bool(_SERVER_CONFIG["debug"]),
            threaded=bool(_SERVER_CONFIG["threaded"]),
            use_reloader=bool(_SERVER_CONFIG["use_reloader"]),
        )
        if not consume_server_restart_request():
            break
else:
    app = create_app()
