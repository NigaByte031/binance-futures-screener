#!/usr/bin/env bash
# Production smoke test for Binance Futures Screener.
# Checks the internal service, HTTP->HTTPS redirect, TLS, REST, live SSE and
# (optionally) that neighbouring services are still listening.
#
# Usage:
#   ./smoke-test.sh whatchlist.cc.cd 18080
#   BFS_SMOKE_EXTRA_PORTS="80 443 8443 6379" ./smoke-test.sh whatchlist.cc.cd

set -u

DOMAIN="${1:-}"
PORT="${2:-${BFS_PORT:-18080}}"
EXTRA_PORTS="${BFS_SMOKE_EXTRA_PORTS:-}"
FAIL=0

pass() { printf '  [OK]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; FAIL=1; }

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 2
fi

if [ -z "$DOMAIN" ]; then
  echo "usage: $0 <domain> [internal-port]" >&2
  exit 2
fi

BASE="https://${DOMAIN}"
echo "Binance Futures Screener — smoke test for ${DOMAIN}"
echo "------------------------------------------------------------"

# 1) Internal service, useful when the script runs on the server itself.
if [ "${BFS_SMOKE_SKIP_LOCAL:-0}" = "1" ]; then
  pass "local port check skipped"
else
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "http://127.0.0.1:${PORT}/healthz" 2>/dev/null || true)"
  if [ "$code" = "200" ]; then
    pass "local service on port ${PORT}"
  else
    fail "local service on port ${PORT} (got ${code:-no answer})"
  fi
fi

# 2) Plain HTTP must redirect to HTTPS.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  "http://${DOMAIN}/" 2>/dev/null || true)"
if [ "$code" = "301" ] || [ "$code" = "302" ]; then
  pass "HTTP redirects to HTTPS (${code})"
else
  fail "HTTP redirect (got ${code:-no answer})"
fi

# 3) Public HTTPS page with certificate verification enabled.
if curl -fsS -o /dev/null --max-time 20 "$BASE/"; then
  pass "HTTPS page and certificate"
else
  fail "HTTPS page or certificate"
fi

# 4) REST metadata.
meta="$(curl -fsS --max-time 20 "$BASE/api/v1/meta" 2>/dev/null || true)"
if printf '%s' "$meta" | grep -q '"ok":true'; then
  pass "GET /api/v1/meta"
else
  fail "GET /api/v1/meta"
fi

if printf '%s' "$meta" | grep -q '"generation"'; then
  pass "shared snapshot metadata present"
else
  fail "shared snapshot metadata missing"
fi

# 5) At least one live row.
rows="$(curl -fsS --max-time 25 "$BASE/api/v1/tickers?limit=1" 2>/dev/null || true)"
count="$(printf '%s' "$rows" | python3 -c \
  'import json,sys
try:
    print(len(json.load(sys.stdin).get("data", [])))
except Exception:
    print(0)' 2>/dev/null || true)"
if [ "${count:-0}" -gt 0 ]; then
  pass "GET /api/v1/tickers returned live rows"
else
  fail "GET /api/v1/tickers returned no rows"
fi

# 6) Live stream must send an immediate snapshot event.
if curl -sS -N --max-time 12 "$BASE/api/v1/stream" 2>/dev/null \
    | grep -q -m1 '^event: snapshot'; then
  pass "SSE snapshot event"
else
  fail "SSE snapshot event"
fi

# 7) Optional: make sure services sharing the server were not disturbed.
if [ -n "$EXTRA_PORTS" ] && command -v ss >/dev/null 2>&1; then
  for p in $EXTRA_PORTS; do
    if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
      pass "neighbour port ${p} still listening"
    else
      fail "neighbour port ${p} is not listening"
    fi
  done
fi

echo "------------------------------------------------------------"
if [ "$FAIL" = "0" ]; then
  echo "RESULT: all checks passed"
else
  echo "RESULT: one or more checks failed"
fi
exit "$FAIL"
