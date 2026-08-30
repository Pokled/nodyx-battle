#!/usr/bin/env python3
"""Serveur statique pour l'export Web Godot (build MONO-THREAD).

Sert widget/nodyx-battle/game/ avec les bons MIME (.wasm, .pck).  PAS de COOP/COEP :
l'export mono-thread n'en a pas besoin, et `require-corp` peut bloquer le chargement.

    python tools/serve_web.py [port]     # defaut 8060
"""
import http.server
import os
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "widget", "nodyx-battle", "game")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    os.chdir(os.path.abspath(ROOT))
    print(f"sert {os.getcwd()}")
    print(f"->  http://localhost:{PORT}/")
    Server(("0.0.0.0", PORT), Handler).serve_forever()
