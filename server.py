#!/usr/bin/env python3
"""
Binance Futures Screener - tiny dependency-free static server.

Serves index.html (and any other static asset next to it) over HTTP.
Designed to run behind systemd or nginx, but works standalone too.

Usage:
    python3 server.py --port 8080 --bind 0.0.0.0
    PORT=8080 python3 server.py

Endpoints:
    /        -> index.html
    /healthz -> {"status":"ok"}
"""

import argparse
import os
import sys
from http.server import SimpleHTTPRequestHandler
from urllib.parse import urlparse

try:
    from http.server import ThreadingHTTPServer
except ImportError:  # Python < 3.7 (e.g. CentOS 7)
    import socketserver
    from http.server import HTTPServer

    class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
        daemon_threads = True

VERSION = "2.2.0"
DEFAULT_PORT = 8080


class Handler(SimpleHTTPRequestHandler):
    server_version = "BFScreener/" + VERSION
    protocol_version = "HTTP/1.1"

    def end_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Referrer-Policy", "no-referrer")
        if self.path.split("?")[0].endswith((".html", "/")):
            self.send_header("Cache-Control", "no-cache, must-revalidate")
        else:
            self.send_header("Cache-Control", "public, max-age=3600")
        super().end_headers()

    def do_GET(self):
        if urlparse(self.path).path.rstrip("/") == "/healthz":
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        # journald picks this up when running under systemd
        sys.stdout.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


def main():
    here = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(description="Binance Futures Screener static server")
    parser.add_argument("--port", type=int,
                        default=int(os.environ.get("PORT", DEFAULT_PORT)),
                        help="TCP port to listen on (default: %(default)s)")
    parser.add_argument("--bind", default=os.environ.get("BIND", "0.0.0.0"),
                        help="address to bind (default: %(default)s)")
    parser.add_argument("--dir", default=here,
                        help="directory to serve (default: script directory)")
    args = parser.parse_args()

    if not os.path.isfile(os.path.join(args.dir, "index.html")):
        sys.exit("error: index.html not found in %s" % args.dir)

    handler = lambda *a, **kw: Handler(*a, directory=args.dir, **kw)  # noqa: E731

    try:
        httpd = ThreadingHTTPServer((args.bind, args.port), handler)
    except OSError as exc:
        sys.exit("error: cannot bind %s:%s -> %s" % (args.bind, args.port, exc))

    httpd.daemon_threads = True
    print("Binance Futures Screener %s serving %s on http://%s:%s"
          % (VERSION, args.dir, args.bind, args.port), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
