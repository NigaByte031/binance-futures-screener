#!/usr/bin/env python3
"""Data layer for the Binance Futures Screener API.

Standard library only. Fetches exchangeInfo, ticker/24hr and 15m klines from
Binance USDT-M futures, then computes the 2h / 6h / 12h / 24h changes exactly
the same way as the browser app in index.html.

The upstream is cached in layers so that many HTTP clients share one scan:

    exchangeInfo   10 minutes   (symbol list rarely changes)
    ticker/24hr    15 seconds   (prices move constantly)
    klines/15m      3 minutes   (a 15m candle anchor only moves on rollover)
    assembled rows  5 seconds   (cheap, but avoids repeated sorting work)

A full scan of ~520 symbols can take 1-2 minutes on a slow link, so the kline
TTL is deliberately longer than a worst-case scan; otherwise the oldest
entries would already be stale by the time the scan finishes and every
request would start another scan.

Set BFS_BINANCE_BASE to override the upstream (useful on restricted networks
and for tests). BFS_API_CONCURRENCY controls the kline worker count.
"""

import hashlib
import json
import math
import os
import queue
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

VERSION = "2.4.1"

BASES = [
    "https://www.binance.com/fapi/v1",
    "https://fapi.binance.com/fapi/v1",
    "https://fapi1.binance.com/fapi/v1",
    "https://fapi2.binance.com/fapi/v1",
    "https://fapi3.binance.com/fapi/v1",
]

TF = ("h2", "h6", "h12", "h24")
TF_HOURS = {"h2": 2, "h6": 6, "h12": 12, "h24": 24}
STEP_H = 0.25
KL_INTERVAL = "15m"
KL_LIMIT = 97


class ApiError(Exception):
    """An error safe to return to an API client."""

    def __init__(self, code, message, status=400):
        Exception.__init__(self, message)
        self.code = code
        self.message = message
        self.status = status


class UpstreamError(ApiError):
    def __init__(self, message):
        ApiError.__init__(self, "UPSTREAM_ERROR", message, 502)


def _fetch_json(url, timeout):
    req = urllib.request.Request(url, headers={
        "User-Agent": "BFScreener/" + VERSION,
        "Accept": "application/json",
    })
    try:
        res = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as exc:
        if exc.code in (418, 429):
            raise UpstreamError("Binance rate limit reached (HTTP %s)" % exc.code)
        if exc.code == 451:
            raise UpstreamError("Binance blocked this region (HTTP 451)")
        raise UpstreamError("Binance returned HTTP %s" % exc.code)
    except Exception as exc:
        raise UpstreamError("Cannot reach Binance: %s" % exc)

    try:
        raw = res.read()
        data = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise UpstreamError("Invalid response from Binance: %s" % exc)
    finally:
        try:
            res.close()
        except Exception:
            pass

    if isinstance(data, dict) and data.get("code") and data.get("msg"):
        raise UpstreamError(str(data["msg"]))
    return data


def _number(value, default=None):
    try:
        out = float(value)
        if not math.isfinite(out):
            return default
        return out
    except (TypeError, ValueError):
        return default


def _round_half_up(value):
    """JS Math.round semantics (Python's round() is banker's rounding)."""
    return int(math.floor(value + 0.5))


class ScreenerData(object):
    """Thread-safe, cached view of the Binance futures screener dataset."""

    TTL_SYMBOLS = 600
    TTL_TICKERS = 15
    TTL_KLINES = 180
    TTL_ROWS = 5

    def __init__(self):
        override = os.environ.get("BFS_BINANCE_BASE", "").strip()
        self.bases = ([override] if override else []) + BASES
        self.active_base = self.bases[0]
        self.timeout = float(os.environ.get("BFS_API_TIMEOUT", "15"))
        try:
            self.concurrency = max(1, min(40, int(os.environ.get("BFS_API_CONCURRENCY", "20"))))
        except ValueError:
            self.concurrency = 20

        self._cache = {}
        self._locks = {}
        self._cache_lock = threading.Lock()
        self._fetched = {}

        # One shared snapshot for every consumer (UI, SSE clients, REST API).
        self._generation = 0
        self._last_update = 0.0
        self._fingerprint = None
        self._subscribers = []
        self._sub_lock = threading.Lock()
        self._bg_started = False

    # ------------------------------------------------------- shared snapshot -
    def generation_info(self):
        return self._generation, self._last_update

    def subscribe(self):
        """Return a queue that receives the generation number on each change."""
        q = queue.Queue(maxsize=2)
        with self._sub_lock:
            self._subscribers.append(q)
        return q

    def unsubscribe(self, q):
        with self._sub_lock:
            if q in self._subscribers:
                self._subscribers.remove(q)

    def _publish(self, rows):
        """Bump the generation only when the snapshot really changed."""
        h = hashlib.sha1()
        for r in rows:
            h.update(r["symbol"].encode("utf-8"))
            h.update(repr((r["price"], r["vol"], r["pct"])).encode("utf-8"))
        digest = h.hexdigest()
        if digest == self._fingerprint:
            return
        self._fingerprint = digest
        self._generation += 1
        self._last_update = time.time()
        with self._sub_lock:
            subs = list(self._subscribers)
        for q in subs:
            try:
                q.put_nowait(self._generation)
            except queue.Full:
                pass

    def start_background(self, interval=5):
        """Keep the shared snapshot fresh without waiting for a visitor."""
        if self._bg_started:
            return
        self._bg_started = True

        def loop():
            while True:
                try:
                    self.rows()
                except Exception as exc:
                    sys.stderr.write("background refresh: %s\n" % exc)
                    sys.stderr.flush()
                time.sleep(interval)

        threading.Thread(target=loop, daemon=True).start()

    def force_refresh(self):
        """Drop price/row caches so the next read really hits Binance."""
        with self._cache_lock:
            self._cache.pop("tickers", None)
            self._cache.pop("rows", None)
        return self.rows()

    # ------------------------------------------------------------- caching --
    def _cached(self, key, ttl, producer):
        now = time.time()
        with self._cache_lock:
            entry = self._cache.get(key)
            if entry and now - entry[0] < ttl:
                return entry[1]
            lock = self._locks.setdefault(key, threading.Lock())

        with lock:
            with self._cache_lock:
                entry = self._cache.get(key)
                if entry and time.time() - entry[0] < ttl:
                    return entry[1]
            value = producer()
            with self._cache_lock:
                self._cache[key] = (time.time(), value)
                self._fetched[key] = time.time()
            return value

    # ------------------------------------------------------------- upstream -
    def _order(self):
        return [self.active_base] + [b for b in self.bases if b != self.active_base]

    def upstream(self, path, params=None):
        last = None
        for base in self._order():
            url = base.rstrip("/") + path
            if params:
                url += "?" + urllib.parse.urlencode(params)
            try:
                data = _fetch_json(url, self.timeout)
                self.active_base = base
                return data
            except UpstreamError as exc:
                last = exc
        raise last or UpstreamError("No Binance endpoint responded")

    # ---------------------------------------------------------------- pieces -
    def symbols(self):
        def load():
            data = self.upstream("/exchangeInfo", None)
            out = []
            for item in data.get("symbols", []):
                if (item.get("contractType") == "PERPETUAL"
                        and item.get("status") == "TRADING"
                        and item.get("quoteAsset") == "USDT"):
                    out.append({"symbol": item["symbol"], "base": item.get("baseAsset", "")})
            return out

        return self._cached("symbols", self.TTL_SYMBOLS, load)

    def tickers(self):
        def load():
            data = self.upstream("/ticker/24hr", None)
            out = {}
            for item in data if isinstance(data, list) else []:
                price = _number(item.get("lastPrice"))
                if price is None or price <= 0:
                    continue
                out[item.get("symbol")] = {
                    "price": price,
                    "vol": _number(item.get("quoteVolume"), 0.0),
                    "pct24": _number(item.get("priceChangePercent")),
                }
            return out

        return self._cached("tickers", self.TTL_TICKERS, load)

    def klines(self, symbol):
        key = "k:" + symbol

        def load():
            data = self.upstream("/klines", {
                "symbol": symbol,
                "interval": KL_INTERVAL,
                "limit": KL_LIMIT,
            })
            closes = []
            for candle in data if isinstance(data, list) else []:
                value = _number(candle[4]) if len(candle) > 4 else None
                if value is not None:
                    closes.append(value)
            if not closes:
                raise UpstreamError("No candles for " + symbol)
            return closes

        return self._cached(key, self.TTL_KLINES, load)

    # ------------------------------------------------------------------ rows -
    @staticmethod
    def anchors_from(closes):
        length = len(closes)

        def at(hours):
            idx = length - 1 - _round_half_up(hours / STEP_H)
            if idx >= 0 and math.isfinite(closes[idx]):
                return closes[idx]
            return None

        return {
            "h2": at(2),
            "h6": at(6),
            "h12": at(12),
            "h24": at(24),
        }

    @staticmethod
    def sparkline(closes):
        step = max(1, int(math.floor(len(closes) / 32)))
        spark = [closes[i] for i in range(0, len(closes), step)]
        if closes and spark[-1] != closes[-1]:
            spark.append(closes[-1])
        return spark

    @staticmethod
    def pct(price, anchor):
        if price and anchor:
            return (price / anchor - 1.0) * 100.0
        return None

    def rows(self):
        def build():
            syms = self.symbols()
            tick = self.tickers()
            usable = [s for s in syms if s["symbol"] in tick]
            anchors = {}
            sparks = {}

            def work(sym):
                symbol = sym["symbol"]
                try:
                    closes = self.klines(symbol)
                    anchors[symbol] = self.anchors_from(closes)
                    sparks[symbol] = self.sparkline(closes)
                except Exception:
                    anchors[symbol] = None
                    sparks[symbol] = None

            with ThreadPoolExecutor(max_workers=self.concurrency) as pool:
                list(pool.map(work, usable))

            rows = []
            for sym in usable:
                symbol = sym["symbol"]
                t = tick[symbol]
                price = t["price"]
                a = anchors.get(symbol)
                pct = {}
                for tf in ("h2", "h6", "h12"):
                    pct[tf] = self.pct(price, a[tf]) if a else None
                pct["h24"] = t["pct24"]
                if pct["h24"] is None:
                    pct["h24"] = self.pct(price, a["h24"]) if a else None
                rows.append({
                    "symbol": symbol,
                    "base": sym["base"],
                    "price": price,
                    "pct": pct,
                    "vol": t["vol"],
                    "spark": sparks.get(symbol),
                })
            self._fetched["rows"] = time.time()
            self._publish(rows)
            return rows

        return self._cached("rows", self.TTL_ROWS, build)

    # ------------------------------------------------------------- insights -
    def overview(self, tf="h2"):
        rows = self.rows()
        values = []
        up = down = flat = 0
        total_vol = 0.0
        for row in rows:
            total_vol += row["vol"] or 0.0
            value = row["pct"].get(tf)
            if value is None:
                continue
            values.append(value)
            if value > 0:
                up += 1
            elif value < 0:
                down += 1
            else:
                flat += 1

        best = None
        worst = None
        for row in rows:
            value = row["pct"].get(tf)
            if value is None:
                continue
            if best is None or value > best["pct"][tf]:
                best = row
            if worst is None or value < worst["pct"][tf]:
                worst = row

        considered = up + down
        return {
            "timeframe": tf,
            "total": len(rows),
            "with_change": len(values),
            "up": up,
            "down": down,
            "flat": flat,
            "unchanged": flat,
            "breadth": round(up * 100.0 / considered, 2) if considered else None,
            "average_change": round(sum(values) / len(values), 4) if values else None,
            "total_quote_volume": round(total_vol, 2),
            "top_gainer": self._brief(best, tf),
            "top_loser": self._brief(worst, tf),
        }

    @staticmethod
    def _brief(row, tf):
        if not row:
            return None
        return {
            "symbol": row["symbol"],
            "base": row["base"],
            "price": row["price"],
            "change": round(row["pct"][tf], 4) if row["pct"].get(tf) is not None else None,
        }

    def cache_info(self):
        now = time.time()
        out = {}
        for key in ("symbols", "tickers", "k:*", "rows"):
            if key == "k:*":
                count = sum(1 for k in self._fetched if k.startswith("k:"))
                newest = max([self._fetched[k] for k in self._fetched if k.startswith("k:")] or [0])
                out["klines"] = {
                    "symbols_cached": count,
                    "age_seconds": round(now - newest, 1) if newest else None,
                    "ttl_seconds": self.TTL_KLINES,
                }
                continue
            if key in self._fetched:
                out[key if key != "tickers" else "tickers"] = {
                    "age_seconds": round(now - self._fetched[key], 1),
                    "ttl_seconds": {
                        "symbols": self.TTL_SYMBOLS,
                        "tickers": self.TTL_TICKERS,
                        "rows": self.TTL_ROWS,
                    }[key],
                }
            else:
                out[key] = {"age_seconds": None, "ttl_seconds": {
                    "symbols": self.TTL_SYMBOLS,
                    "tickers": self.TTL_TICKERS,
                    "rows": self.TTL_ROWS,
                }[key]}
        return out
