#!/bin/zsh
# Serve the bundled browser build locally. Close this window to stop the preview.
cd -- "$(dirname -- "$0")" || exit 1
exec python3 - <<'PY'
import functools
import http.server
import pathlib
import threading
import webbrowser

docs = pathlib.Path.cwd() / "docs"
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(docs))
with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
    address = f"http://127.0.0.1:{server.server_port}/"
    print(f"Naval Fleet Command / Cold War 1990\n{address}\nClose this window to stop.", flush=True)
    threading.Timer(0.5, lambda: webbrowser.open(address)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
PY
