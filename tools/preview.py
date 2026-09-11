"""Serve the browser build on an available localhost port; no installation required."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import webbrowser

root = Path(__file__).resolve().parents[1] / "docs"
server = ThreadingHTTPServer(("127.0.0.1", 0), partial(SimpleHTTPRequestHandler, directory=str(root)))
url = f"http://127.0.0.1:{server.server_port}/play/"
print(f"Naval Fleet Command: {url}\nPress Ctrl+C to stop the preview.", flush=True)
webbrowser.open(url)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
