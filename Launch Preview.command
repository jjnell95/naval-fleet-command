#!/bin/zsh
# Serve the bundled browser build locally. Close this window to stop the preview.
cd -- "$(dirname -- "$0")" || exit 1
exec python3 - <<'PY'
import errno
import functools
import os
import http.server
import pathlib
import sys
import threading
import webbrowser
import urllib.request

docs = pathlib.Path.cwd() / "docs"
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(docs))
# A stable origin is essential: browser mission storage is keyed by host AND port.
try:
    preview = http.server.ThreadingHTTPServer(("127.0.0.1", 8879), handler)
except OSError as error:
    address = "http://127.0.0.1:8879/"
    if error.errno == errno.EADDRINUSE:
        try:
            with urllib.request.urlopen(address, timeout=2) as response:
                page = response.read(32768)
            if b"Naval Fleet Command" in page and b"play/" in page:
                print(f"The Naval Fleet Command preview is already running.\n{address}")
                if os.environ.get("NFC_PREVIEW_NO_BROWSER") != "1":
                    webbrowser.open(address)
                sys.exit(0)
        except (OSError, ValueError):
            pass
    print(f"Cannot start the preview: {error}")
    print("An earlier preview may already be running at http://127.0.0.1:8879/")
    print("Use that window, or close it and launch again. The fixed port preserves saved missions.")
    sys.exit(1)
with preview as server:
    address = f"http://127.0.0.1:{server.server_port}/"
    print(f"Naval Fleet Command\n{address}\nClose this window to stop.", flush=True)
    if os.environ.get("NFC_PREVIEW_NO_BROWSER") != "1":
        threading.Timer(0.5, lambda: webbrowser.open(address)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
PY
