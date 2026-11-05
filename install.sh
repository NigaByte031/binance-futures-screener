#!/usr/bin/env bash
#
# Binance Futures Screener - one-command installer
#
#   curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | sudo bash
#
# The installer asks for the port, the (optional) domain and a few extras,
# then installs the app as a systemd service so it keeps running after reboot.
#
# Works with: Ubuntu / Debian / CentOS / Rocky / Alma / Fedora / Arch / Alpine
#
set -Eeuo pipefail

APP_NAME="binance-futures-screener"
SERVICE_NAME="binance-screener"
REPO="NigaByte031/binance-futures-screener"
BRANCH="main"
SERVICE_USER="bfscreener"
DEFAULT_DIR="/opt/binance-futures-screener"
DEFAULT_PORT="8080"

# ---------- options ----------
OPT_PORT=""
OPT_DOMAIN=""
OPT_DIR=""
ASSUME_YES=0
USE_NGINX=""        # "" = ask, 1 = yes, 0 = no
USE_SSL=""          # "" = ask, 1 = yes, 0 = no
SSL_EMAIL=""
DO_UNINSTALL=0

# ---------- colors ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_C=$'\033[36m'
else
  C_RESET=""; C_B=""; C_DIM=""; C_G=""; C_Y=""; C_R=""; C_C=""
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$C_G" "$C_RESET" "$*"; }
info() { printf '%s•%s %s\n' "$C_C" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_Y" "$C_RESET" "$*"; }
die()  { printf '%s✘ %s%s\n' "$C_R" "$*" "$C_RESET" >&2; exit 1; }
line() { printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"; }

trap 'die "نصب در خط $LINENO با خطا متوقف شد."' ERR

usage() {
  cat <<EOF
${C_B}نصب‌کننده اسکرینر فیوچرز بایننس${C_RESET}

  bash install.sh [گزینه‌ها]

گزینه‌ها:
  --port <n>        پورت سرویس (پیش‌فرض: ${DEFAULT_PORT})
  --domain <d>      دامنه، مثلاً screener.example.com (اختیاری)
  --dir <path>      مسیر نصب (پیش‌فرض: ${DEFAULT_DIR})
  --nginx           نصب و پیکربندی nginx (ریورس‌پروکسی)
  --no-nginx        بدون nginx
  --ssl             گرفتن گواهی Let's Encrypt (نیاز به دامنه)
  --no-ssl          بدون SSL
  --email <mail>    ایمیل برای Let's Encrypt
  --yes, -y         بدون پرسش، با مقادیر پیش‌فرض
  --uninstall       حذف کامل نصب
  -h, --help        همین راهنما

مثال:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | sudo bash
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | sudo bash -s -- --port 9000 --domain app.example.com --yes
EOF
}

# ---------- args ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --port)      OPT_PORT="${2:-}"; shift 2 ;;
    --domain)    OPT_DOMAIN="${2:-}"; shift 2 ;;
    --dir)       OPT_DIR="${2:-}"; shift 2 ;;
    --email)     SSL_EMAIL="${2:-}"; shift 2 ;;
    --nginx)     USE_NGINX=1; shift ;;
    --no-nginx)  USE_NGINX=0; shift ;;
    --ssl)       USE_SSL=1; shift ;;
    --no-ssl)    USE_SSL=0; shift ;;
    --yes|-y)    ASSUME_YES=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "گزینه ناشناخته: $1 (برای راهنما: --help)" ;;
  esac
done

# ---------- helpers ----------
TTY_READY=0
if [ -r /dev/tty ] && [ -w /dev/tty ]; then TTY_READY=1; fi

# ask <varname> <question> [default]
ask() {
  local __var="$1" __q="$2" __def="${3:-}" __ans=""
  if [ "$ASSUME_YES" = "1" ] || [ "$TTY_READY" = "0" ]; then
    printf -v "$__var" '%s' "$__def"; return 0
  fi
  printf '%s' "$__q" > /dev/tty
  [ -n "$__def" ] && printf ' %s[%s]%s' "$C_DIM" "$__def" "$C_RESET" > /dev/tty
  printf ': ' > /dev/tty
  IFS= read -r __ans < /dev/tty || __ans=""
  [ -z "$__ans" ] && __ans="$__def"
  printf -v "$__var" '%s' "$__ans"
}

# ask_yn <question> <y|n>  -> exit status 0 = yes
ask_yn() {
  local __q="$1" __def="${2:-n}" __ans=""
  if [ "$ASSUME_YES" = "1" ] || [ "$TTY_READY" = "0" ]; then
    [ "$__def" = "y" ]; return
  fi
  local __hint="[y/N]"; [ "$__def" = "y" ] && __hint="[Y/n]"
  printf '%s %s%s%s ' "$__q" "$C_DIM" "$__hint" "$C_RESET" > /dev/tty
  IFS= read -r __ans < /dev/tty || __ans=""
  [ -z "$__ans" ] && __ans="$__def"
  case "$__ans" in
    y|Y|yes|YES|بله|ب|آره|اره) return 0 ;;
    *) return 1 ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

download() { # download <url> <dest>
  if have curl; then
    curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
  elif have wget; then
    wget -q -O "$2" "$1"
  else
    die "نه curl پیدا شد نه wget. یکی از آنها را نصب کنید."
  fi
}

install_pkgs() {
  local pm
  pm="$(detect_pm)" || die "مدیر بسته پشتیبانی‌شده‌ای پیدا نشد."
  info "نصب بسته‌ها: $*"
  case "$pm" in
    apt)    $SUDO apt-get update -qq && DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$@" ;;
    dnf)    $SUDO dnf install -y -q "$@" ;;
    yum)    $SUDO yum install -y -q "$@" ;;
    apk)    $SUDO apk add --no-cache "$@" ;;
    pacman) $SUDO pacman -Sy --noconfirm --needed "$@" ;;
    zypper) $SUDO zypper -q install -y "$@" ;;
  esac
}

detect_pm() {
  for pm in apt-get dnf yum apk pacman zypper; do
    if have "$pm"; then case "$pm" in apt-get) echo apt;; *) echo "$pm";; esac; return 0; fi
  done
  return 1
}

# ---------- root ----------
if [ "$(id -u)" -ne 0 ]; then
  if have sudo; then SUDO="sudo"; else die "این اسکریپت نیاز به دسترسی root دارد. با sudo اجرا کنید."; fi
else
  SUDO=""
fi

# ============================================================
# UNINSTALL
# ============================================================
if [ "$DO_UNINSTALL" = "1" ]; then
  say ""
  say "${C_B}حذف ${APP_NAME}${C_RESET}"
  line
  if have systemctl; then
    $SUDO systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    $SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  fi
  $SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  have systemctl && $SUDO systemctl daemon-reload || true
  $SUDO rm -f "/etc/nginx/conf.d/${SERVICE_NAME}.conf" "/etc/nginx/http.d/${SERVICE_NAME}.conf"
  have nginx && $SUDO nginx -t >/dev/null 2>&1 && $SUDO systemctl reload nginx 2>/dev/null || true
  $SUDO rm -rf "${OPT_DIR:-$DEFAULT_DIR}"
  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    $SUDO userdel "$SERVICE_USER" 2>/dev/null || true
  fi
  ok "حذف شد."
  exit 0
fi

# ============================================================
# WELCOME
# ============================================================
say ""
say "${C_B}  Binance Futures Screener${C_RESET} ${C_DIM}//  نصب‌کننده${C_RESET}"
say "${C_DIM}  لیست کوین‌های فیوچرز بایننس بر اساس ریزش/رشد ۲، ۶، ۱۲ و ۲۴ ساعته${C_RESET}"
line
say ""

# ============================================================
# 1) QUESTIONS
# ============================================================
PORT="${OPT_PORT:-}"
if [ -z "$PORT" ]; then
  ask PORT "پورت سرویس" "$DEFAULT_PORT"
fi
case "$PORT" in ''|*[!0-9]*) die "پورت باید عدد باشد." ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "پورت باید بین ۱ تا ۶۵۵۳۵ باشد."

DOMAIN="${OPT_DOMAIN:-}"
if [ -z "$DOMAIN" ] && [ "$ASSUME_YES" != "1" ]; then
  ask DOMAIN "دامنه (خالی بگذارید اگر با IP می‌خواهید)" ""
fi
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
if [ -n "$DOMAIN" ] && ! printf '%s' "$DOMAIN" | grep -Eq '^[A-Za-z0-9.-]+$'; then
  die "دامنه نامعتبر است: $DOMAIN"
fi

if [ -n "$DOMAIN" ]; then
  if [ -z "$USE_NGINX" ]; then
    if ask_yn "nginx نصب و روی دامنه ${C_B}${DOMAIN}${C_RESET} پیکربندی شود؟" y; then USE_NGINX=1; else USE_NGINX=0; fi
  fi
else
  USE_NGINX="${USE_NGINX:-0}"
fi

if [ "$USE_NGINX" = "1" ] && [ -n "$DOMAIN" ] && [ -z "$USE_SSL" ]; then
  if ask_yn "گواهی SSL رایگان (Let's Encrypt) هم گرفته شود؟" y; then USE_SSL=1; else USE_SSL=0; fi
fi
USE_SSL="${USE_SSL:-0}"

if [ "$USE_SSL" = "1" ] && [ -z "$SSL_EMAIL" ]; then
  if [ "$ASSUME_YES" = "1" ] || [ "$TTY_READY" = "0" ]; then
    warn "بدون ایمیل نمی‌توان گواهی Let's Encrypt گرفت؛ SSL رد شد."
    USE_SSL=0
  else
    ask SSL_EMAIL "ایمیل برای Let's Encrypt" ""
    if [ -z "$SSL_EMAIL" ]; then
      warn "ایمیل خالی بود؛ SSL رد شد."
      USE_SSL=0
    fi
  fi
fi

INSTALL_DIR="${OPT_DIR:-$DEFAULT_DIR}"
[ -n "$INSTALL_DIR" ] || INSTALL_DIR="$DEFAULT_DIR"

# soft check: is the port already in use by something else?
if have ss && $SUDO ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${PORT}$"; then
  warn "پورت ${PORT} همین حالا اشغال است (اگر نصب قبلی همین برنامه است، مشکلی نیست)."
  if ! ask_yn "با همین پورت ادامه می‌دهیم؟" y; then die "پورت دیگری انتخاب کنید."; fi
fi

# summary + confirm
say ""
line
say "  ${C_DIM}پورت${C_RESET}          ${C_B}${PORT}${C_RESET}"
say "  ${C_DIM}دامنه${C_RESET}         ${C_B}${DOMAIN:-—  (دسترسی با IP)}${C_RESET}"
say "  ${C_DIM}nginx${C_RESET}         ${C_B}$([ "$USE_NGINX" = 1 ] && echo "بله" || echo "خیر")${C_RESET}"
say "  ${C_DIM}SSL${C_RESET}           ${C_B}$([ "$USE_SSL" = 1 ] && echo "بله" || echo "خیر")${C_RESET}"
say "  ${C_DIM}مسیر نصب${C_RESET}      ${C_B}${INSTALL_DIR}${C_RESET}"
line
if ! ask_yn "ادامه می‌دهیم؟" y; then say "لغو شد."; exit 0; fi
say ""

# ============================================================
# 2) DEPENDENCIES
# ============================================================
if ! have python3; then
  info "python3 پیدا نشد، در حال نصب…"
  install_pkgs python3
fi
PY="$(command -v python3)"
ok "python3: $("$PY" --version 2>&1)"

if [ "$USE_NGINX" = "1" ] && ! have nginx; then
  info "نصب nginx…"
  install_pkgs nginx
fi

# ============================================================
# 3) GET SOURCE
# ============================================================
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap 'cleanup; die "نصب در خط $LINENO با خطا متوقف شد."' ERR

SRC_DIR=""
SELF_DIR=""
# BASH_SOURCE is empty when the script arrives through a pipe (curl | bash)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
fi
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/index.html" ] && [ -f "$SELF_DIR/server.py" ]; then
  SRC_DIR="$SELF_DIR"
  info "استفاده از فایل‌های محلی: $SRC_DIR"
else
  info "دریافت سورس از GitHub…"
  TARBALL="$TMP_DIR/src.tar.gz"
  if ! download "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}" "$TARBALL"; then
    download "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" "$TARBALL"
  fi
  mkdir -p "$TMP_DIR/src"
  tar -xzf "$TARBALL" -C "$TMP_DIR/src" --strip-components=1
  SRC_DIR="$TMP_DIR/src"
  [ -f "$SRC_DIR/index.html" ] || die "سورس دانلود شد ولی index.html داخلش نبود."
fi

# ============================================================
# 4) INSTALL FILES
# ============================================================
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO cp -f "$SRC_DIR/index.html" "$INSTALL_DIR/index.html"
$SUDO cp -f "$SRC_DIR/server.py"  "$INSTALL_DIR/server.py"
[ -f "$SRC_DIR/README.md" ] && $SUDO cp -f "$SRC_DIR/README.md" "$INSTALL_DIR/README.md" || true
[ -f "$SRC_DIR/LICENSE" ]   && $SUDO cp -f "$SRC_DIR/LICENSE"   "$INSTALL_DIR/LICENSE"   || true
$SUDO chmod 755 "$INSTALL_DIR"
$SUDO chmod 644 "$INSTALL_DIR/index.html"
$SUDO chmod 755 "$INSTALL_DIR/server.py"
ok "فایل‌ها در ${INSTALL_DIR} نصب شدند."

# service user
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  if have useradd; then
    $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null || \
    $SUDO useradd -r -M -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || true
  elif have adduser; then
    $SUDO adduser -S -H -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || true
  fi
fi
if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  $SUDO chown -R root:"$SERVICE_USER" "$INSTALL_DIR" 2>/dev/null || true
  RUN_USER="$SERVICE_USER"
else
  RUN_USER="root"
fi

# bind address: behind nginx -> loopback only
if [ "$USE_NGINX" = "1" ]; then BIND_ADDR="127.0.0.1"; else BIND_ADDR="0.0.0.0"; fi

# ============================================================
# 5) SYSTEMD
# ============================================================
if ! have systemctl; then
  warn "systemd پیدا نشد. فایل‌ها نصب شدند ولی سرویس خودکار ساخته نشد."
  say "  اجرای دستی:  $PY ${INSTALL_DIR}/server.py --port ${PORT} --bind ${BIND_ADDR}"
  exit 0
fi

UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
$SUDO tee "$UNIT" >/dev/null <<UNIT_EOF
[Unit]
Description=Binance Futures Screener (web UI)
Documentation=https://github.com/${REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${PY} ${INSTALL_DIR}/server.py --port ${PORT} --bind ${BIND_ADDR}
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
UNIT_EOF

$SUDO systemctl daemon-reload
$SUDO systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
$SUDO systemctl restart "$SERVICE_NAME"
sleep 1.5
if ! $SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
  warn "سرویس بالا نیامد. لاگ:"
  $SUDO journalctl -u "$SERVICE_NAME" -n 20 --no-pager || true
  die "راه‌اندازی ناموفق بود."
fi
ok "سرویس ${SERVICE_NAME} فعال و در حال اجراست."

if have curl; then
  if curl -fsS -m 5 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    ok "پاسخ سرویس روی پورت ${PORT} سالم است."
  else
    warn "سرویس بالا آمد ولی healthz جواب نداد. لاگ: journalctl -u ${SERVICE_NAME} -n 30"
  fi
fi

# ============================================================
# 6) NGINX
# ============================================================
if [ "$USE_NGINX" = "1" ]; then
  if [ -d /etc/nginx/http.d ]; then
    NGINX_CONF="/etc/nginx/http.d/${SERVICE_NAME}.conf"   # Alpine
  else
    $SUDO mkdir -p /etc/nginx/conf.d
    NGINX_CONF="/etc/nginx/conf.d/${SERVICE_NAME}.conf"   # Debian / RHEL
  fi
  SERVER_NAME="${DOMAIN:-_}"
  $SUDO tee "$NGINX_CONF" >/dev/null <<NGINX_EOF
# Binance Futures Screener - managed by install.sh
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAME};

    access_log /var/log/nginx/${SERVICE_NAME}.access.log;
    error_log  /var/log/nginx/${SERVICE_NAME}.error.log;

    location = /healthz {
        proxy_pass http://127.0.0.1:${PORT}/healthz;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }
}
NGINX_EOF

  if $SUDO nginx -t >/dev/null 2>&1; then
    $SUDO systemctl enable nginx >/dev/null 2>&1 || true
    $SUDO systemctl reload nginx 2>/dev/null || $SUDO systemctl restart nginx
    ok "nginx روی دامنه ${SERVER_NAME} پیکربندی شد."
  else
    warn "پیکربندی nginx خطا دارد:"
    $SUDO nginx -t || true
  fi

  # SSL
  if [ "$USE_SSL" = "1" ] && [ -n "$DOMAIN" ]; then
    if ! have certbot; then
      info "نصب certbot…"
      case "$(detect_pm || echo apt)" in
        apt)    install_pkgs certbot python3-certbot-nginx ;;
        dnf|yum) install_pkgs certbot python3-certbot-nginx ;;
        apk)    install_pkgs certbot certbot-nginx ;;
        *)      install_pkgs certbot ;;
      esac
    fi
    info "درخواست گواهی SSL برای ${DOMAIN}…"
    if $SUDO certbot --nginx -d "$DOMAIN" -m "$SSL_EMAIL" --agree-tos --no-eff-email --redirect -n; then
      ok "SSL فعال شد (https://${DOMAIN})."
    else
      warn "گرفتن گواهی ناموفق بود. بعداً دستی: certbot --nginx -d ${DOMAIN}"
    fi
  fi
fi

# ============================================================
# 7) FIREWALL
# ============================================================
FW_OPENED=""
if [ "$USE_NGINX" = "1" ]; then FW_PORTS="80 443"; else FW_PORTS="$PORT"; fi

if have ufw && $SUDO ufw status 2>/dev/null | grep -qi "Status: active"; then
  if ask_yn "پورت(های) ${FW_PORTS} در ufw باز شود؟" y; then
    for p in $FW_PORTS; do $SUDO ufw allow "$p/tcp" >/dev/null 2>&1 || true; done
    FW_OPENED="ufw"
  fi
elif have firewall-cmd && $SUDO systemctl is-active --quiet firewalld 2>/dev/null; then
  if ask_yn "پورت(های) ${FW_PORTS} در firewalld باز شود؟" y; then
    for p in $FW_PORTS; do
      $SUDO firewall-cmd --permanent --add-port="$p/tcp" >/dev/null 2>&1 || true
    done
    $SUDO firewall-cmd --reload >/dev/null 2>&1 || true
    FW_OPENED="firewalld"
  fi
fi

# ============================================================
# 8) SUMMARY
# ============================================================
PUBLIC_IP="$(curl -fsS -m 6 https://api.ipify.org 2>/dev/null || true)"
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[ -n "$PUBLIC_IP" ] || PUBLIC_IP="<server-ip>"

if [ "$USE_SSL" = "1" ] && [ -n "$DOMAIN" ]; then
  URL="https://${DOMAIN}"
elif [ "$USE_NGINX" = "1" ] && [ -n "$DOMAIN" ]; then
  URL="http://${DOMAIN}"
elif [ "$USE_NGINX" = "1" ]; then
  URL="http://${PUBLIC_IP}"
else
  URL="http://${PUBLIC_IP}:${PORT}"
fi

say ""
say "${C_G}${C_B}  نصب کامل شد${C_RESET}"
line
say "  آدرس:            ${C_B}${C_C}${URL}${C_RESET}"
say "  پورت داخلی:      ${PORT}"
say "  مسیر نصب:        ${INSTALL_DIR}"
say "  سرویس:           ${SERVICE_NAME}.service"
[ -n "$FW_OPENED" ] && say "  فایروال:         پورت‌های ${FW_PORTS} باز شد (${FW_OPENED})"
line
say "  ${C_DIM}دستورات مدیریت:${C_RESET}"
say "    systemctl status ${SERVICE_NAME}"
say "    systemctl restart ${SERVICE_NAME}"
say "    journalctl -u ${SERVICE_NAME} -f"
say "    curl -s ${URL%/}/healthz"
line
if [ "$USE_SSL" = "1" ] && [ -n "$DOMAIN" ]; then
  say "  ${C_DIM}نکته: اگر DNS دامنه هنوز به این سرور وصل نشده باشد، SSL ممکن است شکست بخورد.${C_RESET}"
  say "  ${C_DIM}در آن صورت رکورد A دامنه را اصلاح و دوباره اجرا کنید.${C_RESET}"
fi
say ""
