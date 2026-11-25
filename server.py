#!/usr/bin/env python3
"""Binance Futures Screener - static site + read-only JSON API.

Serves the screener UI as a static site and exposes a small, predictable REST
API under /api/v1. Standard library only, so it runs on any Python 3.6+ box.

Usage:
    python3 server.py --port 8080 --bind 0.0.0.0
    PORT=8080 python3 server.py

Endpoints:
    /                         -> index.html
    /api                      -> API reference page (api.html)
    /healthz                  -> {"status":"ok"}
    /api/v1/health            -> API and upstream status
    /api/v1/meta              -> version, timeframes, limits
    /api/v1/symbols           -> available perpetual USDT symbols
    /api/v1/tickers           -> screener rows, filter/sort/paginate
    /api/v1/ticker/<symbol>   -> one symbol, all timeframes + sparkline
    /api/v1/overview          -> breadth, average, top gainer/loser

All API responses use the same envelope:

    {"ok": true, "data": ..., "meta": {...}}
    {"ok": false, "error": {"code": "...", "message": "..."}}

The API is public and CORS-enabled by design: it exists so other people can
call it from their own apps, scripts and dashboards. It is read-only.
"""

import argparse
import datetime
import json
import os
import queue
import sys
from http.server import SimpleHTTPRequestHandler
from urllib.parse import parse_qs, unquote, urlparse

try:
    from http.server import ThreadingHTTPServer
except ImportError:  # Python < 3.7 (e.g. CentOS 7)
    import socketserver
    from http.server import HTTPServer

    class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
        daemon_threads = True

try:
    import api as api_module
    from api import ApiError, ScreenerData, TF
except ImportError as exc:  # pragma: no cover - only if files are separated
    sys.exit("error: cannot load api.py -> %s" % exc)

VERSION = api_module.VERSION
DEFAULT_PORT = 8080
MAX_LIMIT = 500


def _now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Handler(SimpleHTTPRequestHandler):
    server_version = "BFScreener/" + VERSION
    protocol_version = "HTTP/1.1"
    DATA = None  # shared, injected in main()

    # -------------------------------------------------------------- plumbing -
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Accept")
        self.send_header("Access-Control-Max-Age", "86400")

    def end_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Referrer-Policy", "no-referrer")
        if getattr(self, "_is_api", False):
            self.send_header("Cache-Control", "no-store")
            self._cors()
        elif self.path.split("?")[0].endswith((".html", "/")):
            self.send_header("Cache-Control", "no-cache, must-revalidate")
        else:
            self.send_header("Cache-Control", "public, max-age=3600")
        super().end_headers()

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self._is_api = True
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def ok_json(self, data, meta=None, status=200):
        full = {"ok": True, "data": data}
        full["meta"] = meta if meta is not None else {}
        self.send_json(status, full)

    def error_json(self, code, message, status=400):
        self.send_json(status, {
            "ok": False,
            "error": {"code": code, "message": message},
        })

    def meta_base(self):
        generation, updated = self.DATA.generation_info()
        return {
            "version": VERSION,
            "generated_at": _now(),
            "last_update": updated,
            "generation": generation,
            "source": "binance-usdt-m-futures",
            "upstream": self.DATA.active_base,
            "upstream_health": self.DATA.health_info(),
        }

    # ----------------------------------------------------------- validation -
    def params(self):
        return parse_qs(urlparse(self.path).query, keep_blank_values=True)

    @staticmethod
    def one(params, key, default=None):
        values = params.get(key)
        return values[0] if values else default

    def read_int(self, params, key, default, minimum, maximum):
        raw = self.one(params, key)
        if raw is None or raw == "":
            return default
        try:
            value = int(raw)
        except (TypeError, ValueError):
            raise ApiError("INVALID_PARAM", "%s must be an integer" % key, 400)
        if value < minimum or value > maximum:
            raise ApiError("INVALID_PARAM",
                           "%s must be between %s and %s" % (key, minimum, maximum), 400)
        return value

    def read_float(self, params, key, default, minimum=0.0):
        raw = self.one(params, key)
        if raw is None or raw == "":
            return default
        try:
            value = float(raw)
        except (TypeError, ValueError):
            raise ApiError("INVALID_PARAM", "%s must be a number" % key, 400)
        if value < minimum:
            raise ApiError("INVALID_PARAM", "%s must be >= %s" % (key, minimum), 400)
        return value

    @staticmethod
    def read_tf(params):
        tf = (Handler.one(params, "tf", "h2") or "h2").lower()
        if tf not in TF:
            raise ApiError("INVALID_PARAM",
                           "tf must be one of: %s" % ", ".join(TF), 400)
        return tf

    @staticmethod
    def read_bool(params, key):
        raw = (Handler.one(params, key, "") or "").lower()
        return raw in ("1", "true", "yes", "on")

    # ---------------------------------------------------------------- routes -
    def do_OPTIONS(self):
        self._is_api = True
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path

        if path.rstrip("/") == "/healthz":
            body = b'{"status":"ok"}'
            self._is_api = True
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path.startswith("/api"):
            self.handle_api(path)
            return

        super().do_GET()

    def handle_api(self, path):
        clean = path.rstrip("/")
        try:
            if clean == "/api":
                self.serve_docs()
                return

            if clean == "/api/v1/health":
                self.ok_json({
                    "status": "ok",
                    "version": VERSION,
                    "upstream": self.DATA.active_base,
                    "upstream_health": self.DATA.health_info(),
                    "cache": self.DATA.cache_info(),
                })
                return

            if clean == "/api/v1/meta":
                self.ok_json({
                    "version": VERSION,
                    "timeframes": ["h2", "h6", "h12", "h24"],
                    "default_timeframe": "h2",
                    "sort_fields": ["pct", "symbol", "price", "vol"],
                    "default_sort": "pct",
                    "default_limit": 100,
                    "max_limit": MAX_LIMIT,
                    "candles": {"interval": "15m", "limit": 97},
                    "endpoints": [
                        "/api/v1/health", "/api/v1/meta", "/api/v1/symbols",
                        "/api/v1/tickers", "/api/v1/ticker/{symbol}",
                        "/api/v1/overview", "/api/v1/stream",
                    ],
                }, self.meta_base())
                return

            if clean == "/api/v1/stream":
                self.route_stream()
                return

            if clean == "/api/v1/symbols":
                rows = self.DATA.rows()
                symbols = [{"symbol": r["symbol"], "base": r["base"]} for r in rows]
                symbols.sort(key=lambda x: x["symbol"])
                meta = self.meta_base()
                meta.update({"count": len(symbols)})
                self.ok_json(symbols, meta)
                return

            if clean == "/api/v1/overview":
                tf = self.read_tf(self.params())
                result = self.DATA.overview(tf)
                self.ok_json(result, self.meta_base())
                return

            if clean == "/api/v1/tickers":
                self.route_tickers()
                return

            if clean.startswith("/api/v1/ticker/"):
                symbol = unquote(clean[len("/api/v1/ticker/"):]).upper()
                self.route_one(symbol)
                return

            if clean == "/api/v1/docs":
                self.serve_docs()
                return

            raise ApiError("NOT_FOUND", "Unknown endpoint: %s" % path, 404)

        except ApiError as exc:
            self.error_json(exc.code, exc.message, exc.status)
        except Exception as exc:
            # never leak a traceback to a public API client
            sys.stderr.write("api error: %s\n" % exc)
            sys.stderr.flush()
            self.error_json("INTERNAL_ERROR", "The request could not be completed", 500)

    def serve_docs(self):
        docs = os.path.join(self.directory, "api.html")
        if not os.path.isfile(docs):
            raise ApiError("NOT_FOUND", "API reference page is not installed", 404)
        self._is_api = False
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        with open(docs, "rb") as handle:
            body = handle.read()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ----------------------------------------------------------- live stream -
    def _sse(self, event, payload):
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        self.wfile.write(("event: %s\ndata: %s\n\n" % (event, raw)).encode("utf-8"))
        self.wfile.flush()

    def _snapshot(self):
        rows = self.DATA.rows()
        data = []
        for row in rows:
            data.append({
                "symbol": row["symbol"],
                "base": row["base"],
                "price": row["price"],
                "pct": row["pct"],
                "vol": row["vol"],
                "spark": row["spark"],
            })
        meta = self.meta_base()
        meta["total"] = len(data)
        return {"data": data, "meta": meta}

    def route_stream(self):
        """Server-Sent Events: push the shared snapshot whenever it changes."""
        self._is_api = True
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self._cors()
        self.end_headers()

        q = self.DATA.subscribe()
        last = -1
        try:
            generation, _ = self.DATA.generation_info()
            self._sse("snapshot", self._snapshot())
            last = generation
            while True:
                try:
                    gen = q.get(timeout=15)
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    continue
                if gen != last:
                    last = gen
                    self._sse("update", self._snapshot())
        except (BrokenPipeError, ConnectionResetError, OSError, ValueError):
            pass
        finally:
            self.DATA.unsubscribe(q)

    def route_one(self, symbol):
        if not symbol or not symbol.replace("_", "").isalnum():
            raise ApiError("INVALID_SYMBOL", "Symbol must look like BTCUSDT", 400)

        rows = self.DATA.rows()
        found = None
        for row in rows:
            if row["symbol"] == symbol:
                found = row
                break
        if found is None:
            raise ApiError("SYMBOL_NOT_FOUND", "Unknown or inactive symbol: %s" % symbol, 404)

        item = {
            "symbol": found["symbol"],
            "base": found["base"],
            "quote": "USDT",
            "price": found["price"],
            "pct": found["pct"],
            "vol": found["vol"],
            "spark": found["spark"],
        }
        self.ok_json(item, self.meta_base())

    def route_tickers(self):
        p = self.params()
        tf = self.read_tf(p)
        sort = (self.one(p, "sort", "pct") or "pct").lower()
        if sort not in ("pct", "symbol", "price", "vol", "base"):
            raise ApiError("INVALID_PARAM",
                           "sort must be one of: pct, symbol, price, vol, base", 400)
        direction = (self.one(p, "dir", "desc") or "desc").lower()
        if direction not in ("asc", "desc"):
            raise ApiError("INVALID_PARAM", "dir must be asc or desc", 400)
        limit = self.read_int(p, "limit", 100, 1, MAX_LIMIT)
        offset = self.read_int(p, "offset", 0, 0, 100000)
        min_vol = self.read_float(p, "minVol", 0.0, 0.0)
        query = (self.one(p, "q", "") or "").strip().upper()
        with_spark = self.read_bool(p, "spark")
        if self.read_bool(p, "force"):
            rows = self.DATA.force_refresh()
        else:
            rows = self.DATA.rows()
        if query:
            rows = [r for r in rows
                    if query in r["symbol"].upper() or query in r["base"].upper()]
        if min_vol > 0:
            rows = [r for r in rows if (r["vol"] or 0.0) >= min_vol]

        def key(row):
            if sort == "pct":
                value = row["pct"].get(tf)
                return (value is None, value if value is not None else 0.0)
            if sort == "symbol" or sort == "base":
                return row[sort].upper()
            return row[sort] or 0.0

        rows = sorted(rows, key=key, reverse=(direction == "desc"))
        total = len(rows)
        page = rows[offset:offset + limit]

        data = []
        for row in page:
            item = {
                "symbol": row["symbol"],
                "base": row["base"],
                "price": row["price"],
                "change": round(row["pct"][tf], 4) if row["pct"].get(tf) is not None else None,
                "pct": row["pct"],
                "vol": round(row["vol"], 2),
            }
            if with_spark:
                item["spark"] = row["spark"]
            data.append(item)

        meta = self.meta_base()
        meta.update({
            "timeframe": tf,
            "sort": sort,
            "dir": direction,
            "total": total,
            "returned": len(data),
            "limit": limit,
            "offset": offset,
            "filters": {
                "q": query or None,
                "minVol": min_vol if min_vol > 0 else None,
            },
            "cache": self.DATA.cache_info(),
        })
        self.ok_json(data, meta)

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


def main():
    here = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(description="Binance Futures Screener server + API")
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

    Handler.DATA = ScreenerData()

    # The server keeps one snapshot fresh on its own; visitors and API clients
    # only ever read from it. A client-triggered scan is never required.
    Handler.DATA.start_background()

    handler = lambda *a, **kw: Handler(*a, directory=args.dir, **kw)  # noqa: E731

    try:
        httpd = ThreadingHTTPServer((args.bind, args.port), handler)
    except OSError as exc:
        sys.exit("error: cannot bind %s:%s -> %s" % (args.bind, args.port, exc))

    httpd.daemon_threads = True
    print("Binance Futures Screener %s on http://%s:%s (API: /api/v1)"
          % (VERSION, args.bind, args.port), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
