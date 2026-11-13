#!/usr/bin/env bash
#
# Binance Futures Screener — installer
#
#   curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash
#
# With a terminal attached it asks one thing: the domain (blank = plain IP
# access). Everything else is automatic — free port, service, firewall, and
# nginx + Let's Encrypt when a domain is given.
#
#   ... | bash -s -- --unattended                                      # no questions at all
#   ... | bash -s -- --domain app.example.com --email me@example.com   # + nginx + HTTPS
#   ... | bash -s -- --interactive                                     # guided setup
#   ... | bash -s -- --check                                           # environment report
#   ... | bash -s -- --uninstall                                       # remove everything
#
# After installing, `binance-screener` (or `bfs`) opens the settings menu.
#
# Supports: Ubuntu / Debian / CentOS / Rocky / Alma / Fedora / Arch / Alpine / openSUSE
#
set -Eeuo pipefail

INSTALLER_VERSION="2.3.1"
APP_NAME="Binance Futures Screener"
SERVICE_NAME="binance-screener"
REPO="NigaByte031/binance-futures-screener"
BRANCH="main"
SELF_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/install.sh"
SERVICE_USER="bfscreener"
DEFAULT_DIR="/opt/binance-futures-screener"
DEFAULT_PORT="8080"
STATE_FILE="/etc/${SERVICE_NAME}.install"
LOG="/var/log/${SERVICE_NAME}-install.log"
LIB_DIR="/usr/local/lib/${SERVICE_NAME}"
CLI_BIN="/usr/local/bin/binance-screener"
CLI_ALIAS="/usr/local/bin/bfs"

# ---------------------------------------------------------------- options ----
OPT_PORT=""
OPT_DOMAIN=""
OPT_DIR=""
OPT_BIND=""
OPT_EMAIL=""
USE_NGINX=""        # "" = decide automatically
USE_SSL=""          # "" = decide automatically
SSL_SET=0
USE_FW=""           # "" = decide automatically
INTERACTIVE=0
UNATTENDED=0
CLEAR_DOMAIN=0
DRY=0
DO_UNINSTALL=0
DO_CHECK=0
DO_MENU=0

ORIG_ARGS=("$@")

# ----------------------------------------------------------------- colors ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_C=$'\033[36m'
else
  C_RESET=""; C_B=""; C_DIM=""; C_G=""; C_Y=""; C_R=""; C_C=""
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '     %s✔%s %s\n' "$C_G" "$C_RESET" "$*"; }
info() { printf '     %s•%s %s\n' "$C_C" "$C_RESET" "$*"; }
warn() { printf '     %s!%s %s\n' "$C_Y" "$C_RESET" "$*"; }
die()  { printf '\n%s✘ %s%s\n' "$C_R" "$*" "$C_RESET" >&2; exit 1; }
rule() { printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"; }
step() { printf '\n%s[%s/%s]%s %s%s%s\n' "$C_DIM" "$1" "$2" "$C_RESET" "$C_B" "$3" "$C_RESET"; }

note() {
  # timestamped, colour-free log line — used for post-mortem support
  [ -n "${LOG:-}" ] || return 0
  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; } 2>/dev/null >>"$LOG" || true
}

on_error() {
  local code=$?
  trap - ERR
  printf '\n%s✘ نصب متوقف شد (خط %s، کد %s)%s\n' "$C_R" "$1" "$code" "$C_RESET" >&2
  if [ -f "$LOG" ]; then
    printf '%s\n' "${C_DIM}── آخرین خطوط لاگ ──${C_RESET}" >&2
    tail -n 12 "$LOG" >&2 || true
  fi
  printf '%s\n' "${C_DIM}گزارش کامل: ${LOG}${C_RESET}" >&2
  exit "$code"
}

trap 'on_error $LINENO' ERR

usage() {
  cat <<EOF
${C_B}${APP_NAME} — نصب‌کننده v${INSTALLER_VERSION}${C_RESET}

${C_B}نصب${C_RESET}
  curl -fsSL ${SELF_URL} | bash

  دامنه را می‌پرسد (خالی بگذارید تا با IP کار کند). بقیه‌اش خودکار است:
  انتخاب پورت آزاد، سرویس، فایروال، و اگر دامنه بدهید nginx + HTTPS.

${C_B}بعد از نصب${C_RESET}
  ${C_C}binance-screener${C_RESET}    باز کردن منوی تنظیمات   (یا ${C_C}bfs${C_RESET})

${C_B}گزینه‌ها${C_RESET}
  --port <n>         پورت سرویس (پیش‌فرض: اولین پورت آزاد از ${DEFAULT_PORT})
  --domain <d>       دامنه؛ nginx و SSL را هم خودکار راه می‌اندازد
  --email <mail>     ایمیل برای Let's Encrypt (بدون آن هم تلاش می‌شود)
  --dir <path>       مسیر نصب (پیش‌فرض: ${DEFAULT_DIR})
  --bind <addr>      آدرس bind (پیش‌فرض: 0.0.0.0 یا 127.0.0.1 پشت nginx)
  --unattended       هیچ سؤالی نپرسد (برای اسکریپت و نصب خودکار)
  --interactive, -i  حالت پرسش‌وپاسخ کامل (پورت، دامنه، nginx، SSL، فایروال)
  --no-domain        دامنه را حذف کن و به دسترسی با IP برگرد
  --menu             منوی تنظیمات را باز کن (همان دستور binance-screener)
  --no-nginx         حتی با داشتن دامنه، nginx نصب نشود
  --no-ssl           بدون گواهی Let's Encrypt
  --no-firewall      پورت‌ها در فایروال باز نشوند
  --dry-run          فقط نشان بده چه کاری انجام می‌شود (هیچ تغییری اعمال نمی‌شود)
  --check            گزارش وضعیت سیستم و نصب فعلی، بدون تغییر
  --uninstall        حذف کامل سرویس، فایل‌ها و کانفیگ nginx
  --version          نسخه نصب‌کننده
  -h, --help         همین راهنما

${C_B}مثال‌ها${C_RESET}
  # نصب با پرسیدن دامنه، روی اولین پورت آزاد
  curl -fsSL ${SELF_URL} | bash

  # با دامنه + HTTPS، بدون هیچ پرسشی
  curl -fsSL ${SELF_URL} | bash -s -- --domain app.example.com --email me@example.com

  # نصب کاملاً خودکار (مثلاً در اسکریپت یا cloud-init)
  curl -fsSL ${SELF_URL} | bash -s -- --unattended

  # پورت مشخص و نصب تعاملی
  curl -fsSL ${SELF_URL} | bash -s -- --port 9000 --interactive

${C_DIM}اجرای دوباره‌ی همین دستور، برنامه را به‌روزرسانی می‌کند و تنظیمات فعلی را نگه می‌دارد.${C_RESET}
EOF
}

# -------------------------------------------------------------- utilities ---
have() { command -v "$1" >/dev/null 2>&1; }

group_exists() {
  if have getent; then getent group "$1" >/dev/null 2>&1
  else grep -q "^$1:" /etc/group 2>/dev/null
  fi
}

# run <cmd...> — the only place system changes happen, so --dry-run can cover
# the whole flow instead of guessing.
run() {
  if [ "$DRY" = "1" ]; then
    printf '     %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  note "exec: $*"
  "$@"
}

# write_file <path> [mode]  (content on stdin)
write_file() {
  local path="$1" mode="${2:-644}" tmp
  if [ "$DRY" = "1" ]; then
    printf '     %s$ write %s (mode %s)%s\n' "$C_DIM" "$path" "$mode" "$C_RESET"
    cat >/dev/null
    return 0
  fi
  tmp="$(mktemp "${path}.XXXXXX")"
  cat >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
  note "wrote $path"
}

download() { # download <url> <dest>
  if have curl; then
    curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
  elif have wget; then
    wget -q -O "$2" "$1"
  else
    return 1
  fi
}

http_ok() { # http_ok <url> -> 0 when the body looks like our health payload
  if have curl; then
    curl -fsS -m 4 "$1" 2>/dev/null | grep -q '"status"'
  elif have wget; then
    wget -q -O - -T 4 "$1" 2>/dev/null | grep -q '"status"'
  else
    return 1
  fi
}

detect_pm() {
  local pm
  for pm in apt-get dnf yum apk pacman zypper; do
    if have "$pm"; then
      case "$pm" in apt-get) echo apt ;; *) echo "$pm" ;; esac
      return 0
    fi
  done
  return 1
}

PM=""
install_pkgs() {
  [ "$#" -gt 0 ] || return 0
  if [ "$DRY" = "1" ]; then
    info "نصب بسته‌ها: $*"
    printf '     %s$ %s install %s%s\n' "$C_DIM" "${PM:-<package-manager>}" "$*" "$C_RESET"
    return 0
  fi
  [ -n "$PM" ] || PM="$(detect_pm)" || die "مدیر بسته‌ای پیدا نشد؛ نصب بسته‌های لازم ممکن نیست."
  info "نصب بسته‌ها: $*"
  note "install packages: $*"
  case "$PM" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
    dnf)    dnf install -y -q "$@" ;;
    yum)    yum install -y -q "$@" ;;
    apk)    apk add --no-cache "$@" ;;
    pacman) pacman -Sy --noconfirm --needed "$@" ;;
    zypper) zypper -q install -y "$@" ;;
  esac
}

port_busy() {
  local p="$1"
  if have ss; then
    ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -Eq "[:.]${p}$"
  elif have netstat; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$"
  elif have lsof; then
    lsof -nP -iTCP:"${p}" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1   # cannot tell; let the service fail loudly if it is taken
  fi
}

pick_port() {
  local p
  for p in "$DEFAULT_PORT" 8081 8082 8083 8084 8090 8091 9000 9090; do
    if ! port_busy "$p"; then echo "$p"; return 0; fi
  done
  for p in $(seq 20000 20050); do
    if ! port_busy "$p"; then echo "$p"; return 0; fi
  done
  return 1
}

public_ip() {
  local ip=""
  if have curl; then
    for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
      ip="$(curl -fsS -m 5 "$u" 2>/dev/null | tr -d '[:space:]')" || true
      case "$ip" in *[!0-9a-fA-F:.]*|"") ip="" ;; esac
      [ -n "$ip" ] && { echo "$ip"; return 0; }
    done
  fi
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
  [ -n "$ip" ] && { echo "$ip"; return 0; }
  echo "<server-ip>"
}

# ------------------------------------------------------------ tty + prompts -
TTY_READY=0
# stdin is the script itself under `curl | bash`, so a terminal on stdout/stderr
# is what actually tells us prompts can work.
if [ -r /dev/tty ] && { [ -t 1 ] || [ -t 2 ]; }; then TTY_READY=1; fi

ask() { # ask <varname> <question> [default]
  local __var="$1" __q="$2" __def="${3:-}" __ans=""
  if [ "$TTY_READY" = "0" ]; then printf -v "$__var" '%s' "$__def"; return 0; fi
  { printf '%s' "$__q"; [ -n "$__def" ] && printf ' %s[%s]%s' "$C_DIM" "$__def" "$C_RESET"; printf ': '; } > /dev/tty 2>/dev/null || true
  IFS= read -r __ans < /dev/tty || __ans=""
  [ -z "$__ans" ] && __ans="$__def"
  printf -v "$__var" '%s' "$__ans"
}

ask_yn() { # ask_yn <question> <y|n> ; 0 = yes
  local __q="$1" __def="${2:-n}" __ans="" __hint
  if [ "$TTY_READY" = "0" ]; then [ "$__def" = "y" ]; return; fi
  __hint="[y/N]"; [ "$__def" = "y" ] && __hint="[Y/n]"
  printf '%s %s%s%s ' "$__q" "$C_DIM" "$__hint" "$C_RESET" > /dev/tty 2>/dev/null || true
  IFS= read -r __ans < /dev/tty || __ans=""
  [ -z "$__ans" ] && __ans="$__def"
  case "$__ans" in y|Y|yes|YES|بله|ب|آره|اره) return 0 ;; *) return 1 ;; esac
}

# ------------------------------------------------------------------ args ----
while [ $# -gt 0 ]; do
  case "$1" in
    --port)        OPT_PORT="${2:-}"; shift 2 ;;
    --domain)      OPT_DOMAIN="${2:-}"; shift 2 ;;
    --email)       OPT_EMAIL="${2:-}"; shift 2 ;;
    --dir)         OPT_DIR="${2:-}"; shift 2 ;;
    --bind)        OPT_BIND="${2:-}"; shift 2 ;;
    --interactive|-i) INTERACTIVE=1; shift ;;
    --unattended|--auto) UNATTENDED=1; shift ;;
    --no-domain)   CLEAR_DOMAIN=1; shift ;;
    --menu)        DO_MENU=1; shift ;;
    --nginx)       USE_NGINX=1; shift ;;
    --no-nginx)    USE_NGINX=0; shift ;;
    --ssl)         USE_SSL=1; SSL_SET=1; shift ;;
    --no-ssl)      USE_SSL=0; SSL_SET=1; shift ;;
    --no-firewall) USE_FW=0; shift ;;
    --firewall)    USE_FW=1; shift ;;
    --dry-run)     DRY=1; shift ;;
    --check)       DO_CHECK=1; shift ;;
    --uninstall)   DO_UNINSTALL=1; shift ;;
    --yes|-y)      UNATTENDED=1; shift ;;         # old spelling of --unattended
    --version)     echo "$INSTALLER_VERSION"; exit 0 ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "گزینه ناشناخته: $1  (راهنما: --help)" ;;
  esac
done

# --------------------------------------------------------- early validation -
# Fail on bad input before touching sudo or the system.
if [ -n "$OPT_PORT" ]; then
  case "$OPT_PORT" in ''|*[!0-9]*) die "پورت باید عدد باشد: ${OPT_PORT}" ;; esac
  { [ "$OPT_PORT" -ge 1 ] && [ "$OPT_PORT" -le 65535 ]; } || die "پورت باید بین ۱ تا ۶۵۵۳۵ باشد: ${OPT_PORT}"
fi
if [ -n "$OPT_DIR" ]; then
  case "$OPT_DIR" in /*) ;; *) die "--dir باید مسیر مطلق باشد (مثل /opt/app): ${OPT_DIR}" ;; esac
fi
if [ -n "$OPT_DOMAIN" ]; then
  _d="${OPT_DOMAIN#http://}"; _d="${_d#https://}"; _d="${_d%%/*}"
  printf '%s' "$_d" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' || die "دامنه نامعتبر است: ${OPT_DOMAIN}"
fi
if [ -n "$OPT_EMAIL" ] && ! printf '%s' "$OPT_EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$'; then
  die "ایمیل نامعتبر است: ${OPT_EMAIL}"
fi

# --------------------------------------------------------------- elevation --
elevate() {
  [ "$(id -u)" -eq 0 ] && return 0
  [ "$DRY" = "1" ] && return 0
  have sudo || die "برای نصب به دسترسی root نیاز است و sudo هم پیدا نشد."

  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    info "دسترسی root لازم است؛ با sudo ادامه می‌دهیم…"
    exec sudo -E bash "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}"
  fi

  # arrived through a pipe (curl | bash): re-fetch so sudo gets a real file
  local tmp
  tmp="$(mktemp)"
  info "دسترسی root لازم است؛ اسکریپت با sudo دوباره اجرا می‌شود…"
  download "$SELF_URL" "$tmp" || die "دریافت مجدد اسکریپت برای اجرای sudo ناموفق بود."
  exec sudo -E bash "$tmp" "${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}"
}

# ------------------------------------------------------------ state helpers --
# always succeeds: an absent key must not trip `set -e` at the call site
state_get() {
  if [ -f "$STATE_FILE" ]; then
    sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | head -1
  fi
  return 0
}

# ============================================================== doctor ======
doctor() {
  local py init
  say ""
  say "${C_B}  ${APP_NAME}${C_RESET} ${C_DIM}// گزارش وضعیت${C_RESET}"
  rule
  say "  ${C_DIM}سیستم${C_RESET}        $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-?}" || uname -s)  $(uname -m)"
  say "  ${C_DIM}کرنل${C_RESET}          $(uname -r)"
  if have systemctl; then init="systemd ($(systemctl --version 2>/dev/null | head -1 | awk '{print $2}'))"
  elif have rc-service; then init="openrc"
  else init="بدون init (اجرای دستی)"; fi
  say "  ${C_DIM}init${C_RESET}           ${init}"
  if have python3; then
    py="$(python3 --version 2>&1)"
    say "  ${C_DIM}python${C_RESET}         ${py}"
  else
    say "  ${C_DIM}python${C_RESET}         ${C_Y}نصب نیست${C_RESET}"
  fi
  say "  ${C_DIM}curl/wget${C_RESET}      $(have curl && echo -n "curl " ; have wget && echo -n "wget"; true)"
  say "  ${C_DIM}مدیر بسته${C_RESET}      $(detect_pm 2>/dev/null || echo '—')"
  say "  ${C_DIM}فایروال${C_RESET}       $(if have ufw && ufw status 2>/dev/null | grep -qi 'Status: active'; then echo 'ufw فعال'; elif have firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then echo 'firewalld فعال'; else echo 'غیرفعال/نامشخص'; fi)"
  say "  ${C_DIM}IP عمومی${C_RESET}      $(public_ip)"
  say "  ${C_DIM}فضای دیسک${C_RESET}     $(df -h / 2>/dev/null | awk 'NR==2{print $4" آزاد از "$2}')"
  rule
  if [ -f "$STATE_FILE" ]; then
    say "  ${C_B}نصب موجود${C_RESET}"
    say "    پورت       $(state_get PORT)"
    say "    bind       $(state_get BIND)"
    say "    مسیر       $(state_get DIR)"
    say "    دامنه      $(state_get DOMAIN || echo '—')"
    say "    SSL        $(state_get SSL)"
    if have systemctl; then
      say "    سرویس      $(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo unknown) / $(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo unknown)"
    fi
    if [ -x "$CLI_BIN" ]; then say "    منو        binance-screener"; fi
  else
    say "  ${C_DIM}نصب فعالی پیدا نشد.${C_RESET}"
  fi
  rule
  say ""
  exit 0
}

# ============================================================ uninstall =====
uninstall() {
  say ""
  say "${C_B}  حذف ${APP_NAME}${C_RESET}"
  rule
  local dir port
  dir="$(state_get DIR)"; dir="${dir:-${OPT_DIR:-$DEFAULT_DIR}}"
  port="$(state_get PORT)"; port="${port:-$DEFAULT_PORT}"

  if have systemctl; then
    run systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    run systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  elif have rc-service; then
    run rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    run rc-update del "$SERVICE_NAME" default 2>/dev/null || true
  fi
  run rm -f "/etc/systemd/system/${SERVICE_NAME}.service" "/etc/init.d/${SERVICE_NAME}"
  have systemctl && { run systemctl daemon-reload || true; }
  run rm -f "/etc/nginx/conf.d/${SERVICE_NAME}.conf" "/etc/nginx/http.d/${SERVICE_NAME}.conf"
  if have nginx && nginx -t >/dev/null 2>&1; then
    run systemctl reload nginx 2>/dev/null || run nginx -s reload 2>/dev/null || true
  fi
  run rm -rf "$dir"
  run rm -rf "$LIB_DIR"
  run rm -f "$CLI_BIN" "$CLI_ALIAS"
  run rm -f "$STATE_FILE"
  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    run userdel "$SERVICE_USER" 2>/dev/null || true
  fi
  ok "سرویس، فایل‌ها و کانفیگ nginx حذف شدند."
  info "گواهی SSL (اگر گرفته شده) در certbot باقی می‌ماند: certbot delete --cert-name <domain>"
  info "پورت ${port} آزاد شد."
  say ""
  exit 0
}

# ================================================================= menu =====
# Interactive settings menu, installed as `binance-screener` (alias `bfs`).
MENU_IN=""; MENU_OUT=""; MENU_EOF=0; MENU_SELF=""; MENU_IP=""

if [ -r /dev/tty ] && { [ -t 1 ] || [ -t 2 ]; }; then MENU_IN=/dev/tty; MENU_OUT=/dev/tty; fi

mout()    { if [ -n "$MENU_OUT" ]; then printf '%s\n' "$*" >"$MENU_OUT"; else printf '%s\n' "$*"; fi; }
mprintf() { if [ -n "$MENU_OUT" ]; then printf '%s' "$*" >"$MENU_OUT"; else printf '%s' "$*"; fi; }

mread() { # mread <var> [prompt] [default]
  local __v="$1" __p="${2:-}" __d="${3:-}" __a=""
  [ -n "$__p" ] && mprintf "$__p"
  if [ -n "$MENU_IN" ]; then
    IFS= read -r __a <"$MENU_IN" || { MENU_EOF=1; __a=""; }
  else
    IFS= read -r __a || { MENU_EOF=1; __a=""; }
  fi
  [ -z "$__a" ] && __a="$__d"
  printf -v "$__v" '%s' "$__a"
}

mpause() {
  local _x=""
  mprintf "  ${C_DIM}Enter برای بازگشت به منو…${C_RESET}"
  if [ -n "$MENU_IN" ]; then IFS= read -r _x <"$MENU_IN" || true; else IFS= read -r _x || true; fi
}

menu_service_state() {
  if have systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then echo "فعال"
  elif have rc-service && rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then echo "فعال"
  elif [ -f "$STATE_FILE" ]; then echo "متوقف"
  else echo "نصب نشده"; fi
}

menu_draw() {
  local port domain ssl url state
  # repaint the screen on a real terminal so the menu stays clean
  [ -n "$MENU_OUT" ] && printf '\033[H\033[2J' >"$MENU_OUT"
  port="$(state_get PORT)"; port="${port:-—}"
  domain="$(state_get DOMAIN)"
  ssl="$(state_get SSL)"
  state="$(menu_service_state)"
  if [ -n "$domain" ]; then
    if [ "$ssl" = "1" ]; then url="https://${domain}"; else url="http://${domain}"; fi
  else
    url="http://${MENU_IP:-$(public_ip)}:${port}"
  fi
  mout ""
  mout "  ${C_B}${APP_NAME}${C_RESET} ${C_DIM}// منوی مدیریت${C_RESET}"
  mout "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"
  mout "  ${C_DIM}وضعیت${C_RESET}   ${state}"
  mout "  ${C_DIM}آدرس${C_RESET}    ${C_B}${url}${C_RESET}"
  mout "  ${C_DIM}پورت${C_RESET}    ${port}    ${C_DIM}دامنه${C_RESET}  $([ -n "$domain" ] && echo "$domain" || echo '—')    ${C_DIM}SSL${C_RESET}  $([ "$ssl" = "1" ] && echo 'فعال' || echo 'غیرفعال')"
  mout "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"
  mout "   ${C_B}1${C_RESET}   نمایش وضعیت و سلامت سرویس"
  mout "   ${C_B}2${C_RESET}   تغییر پورت"
  mout "   ${C_B}3${C_RESET}   تنظیم یا تغییر دامنه   ${C_DIM}(HTTPS خودکار)${C_RESET}"
  mout "   ${C_B}4${C_RESET}   حذف دامنه و برگشت به دسترسی با IP"
  mout "   ${C_B}5${C_RESET}   ری‌استارت سرویس"
  mout "   ${C_B}6${C_RESET}   دیدن لاگ سرویس"
  mout "   ${C_B}7${C_RESET}   به‌روزرسانی به آخرین نسخه"
  mout "   ${C_B}8${C_RESET}   حذف کامل نصب"
  mout "   ${C_B}0${C_RESET}   بستن منو"
  mout "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"
}

menu_apply() {
  local rc=0
  mout ""
  bash "$MENU_SELF" "$@" || rc=$?
  mout ""
  [ "$rc" -ne 0 ] && mout "  ${C_Y}عملیات با خطا تمام شد (کد ${rc}).${C_RESET}"
  mpause
}

menu_change_port() {
  local cur new
  cur="$(state_get PORT)"; cur="${cur:-$DEFAULT_PORT}"
  mout ""
  mout "  ${C_DIM}پورت فعلی: ${cur}${C_RESET}"
  mread new "  پورت جدید (خالی = انصراف): " ""
  [ -z "$new" ] && { mout "  ${C_DIM}تغییری اعمال نشد.${C_RESET}"; return 0; }
  case "$new" in *[!0-9]*) mout "  ${C_Y}پورت باید عدد باشد.${C_RESET}"; mpause; return 0 ;; esac
  if [ "$new" -lt 1 ] || [ "$new" -gt 65535 ]; then
    mout "  ${C_Y}پورت باید بین ۱ تا ۶۵۵۳۵ باشد.${C_RESET}"; mpause; return 0
  fi
  if [ "$new" = "$cur" ]; then mout "  ${C_DIM}همان پورت فعلی است.${C_RESET}"; return 0; fi
  menu_apply --port "$new"
}

menu_change_domain() {
  local cur d e
  cur="$(state_get DOMAIN)"
  mout ""
  mout "  ${C_DIM}دامنه فعلی: $([ -n "$cur" ] && echo "$cur" || echo '— (دسترسی با IP)')${C_RESET}"
  mread d "  دامنه جدید (خالی = انصراف): " ""
  [ -z "$d" ] && { mout "  ${C_DIM}تغییری اعمال نشد.${C_RESET}"; return 0; }
  d="${d#http://}"; d="${d#https://}"; d="${d%%/*}"
  if ! printf '%s' "$d" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'; then
    mout "  ${C_Y}دامنه نامعتبر است: ${d}${C_RESET}"; mpause; return 0
  fi
  e="$(state_get EMAIL)"
  mread e "  ایمیل برای گواهی SSL (اختیاری): " "$e"
  if [ -n "$e" ]; then menu_apply --domain "$d" --email "$e"; else menu_apply --domain "$d"; fi
}

menu_remove_domain() {
  local a
  mout ""
  if [ -z "$(state_get DOMAIN)" ]; then
    mout "  ${C_DIM}الان دامنه‌ای تنظیم نشده است.${C_RESET}"; return 0
  fi
  mout "  ${C_DIM}سایت به دسترسی مستقیم با IP برمی‌گردد و کانفیگ nginx حذف می‌شود.${C_RESET}"
  mread a "  مطمئنید؟ (y/N): " "n"
  case "$a" in y|Y|yes|YES|بله|ب) menu_apply --no-domain ;; *) mout "  ${C_DIM}لغو شد.${C_RESET}" ;; esac
}

menu_restart() {
  mout ""
  if have systemctl; then
    if systemctl restart "$SERVICE_NAME" 2>/dev/null; then ok "سرویس ری‌استارت شد"; else warn "ری‌استارت ناموفق بود"; fi
  elif have rc-service; then
    if rc-service "$SERVICE_NAME" restart >/dev/null 2>&1; then ok "سرویس ری‌استارت شد"; else warn "ری‌استارت ناموفق بود"; fi
  else
    warn "init سیستم شناسایی نشد"
  fi
  mpause
}

menu_logs() {
  mout ""
  if have journalctl; then
    journalctl -u "$SERVICE_NAME" -n 25 --no-pager 2>/dev/null || true
  elif [ -f "/var/log/${SERVICE_NAME}.log" ]; then
    tail -n 25 "/var/log/${SERVICE_NAME}.log" 2>/dev/null || true
  else
    warn "لاگی پیدا نشد"
  fi
  mpause
}

menu_uninstall() {
  local a
  mout ""
  mout "  ${C_Y}این کار سرویس، فایل‌ها و کانفیگ nginx را پاک می‌کند.${C_RESET}"
  mread a "  مطمئنید؟ (y/N): " "n"
  case "$a" in y|Y|yes|YES|بله|ب) menu_apply --uninstall ;; *) mout "  ${C_DIM}لغو شد.${C_RESET}" ;; esac
}

menu() {
  MENU_SELF="${BASH_SOURCE[0]:-$0}"
  MENU_IP="$(public_ip 2>/dev/null || echo '<server-ip>')"
  local choice=""
  while :; do
    menu_draw
    mprintf "  ${C_DIM}شماره گزینه${C_RESET} (0 = بستن منو): "
    mread choice
    if [ "$MENU_EOF" = "1" ] && [ -z "$choice" ]; then mout ""; return 0; fi
    case "$choice" in
      0|q|Q|exit|خروج) mout ""; mout "  ${C_DIM}منو بسته شد.${C_RESET}"; mout ""; return 0 ;;
      1) mout ""; bash "$MENU_SELF" --check || true; mpause ;;
      2) menu_change_port ;;
      3) menu_change_domain ;;
      4) menu_remove_domain ;;
      5) menu_restart ;;
      6) menu_logs ;;
      7) menu_apply ;;
      8) menu_uninstall ;;
      "") : ;;
      *) mout "  ${C_Y}گزینه نامعتبر: ${choice}${C_RESET}" ;;
    esac
  done
}

# ================================================================ main ======
# the menu itself needs no privileges; each action re-runs the installer, which
# elevates on its own (so a normal user can still read status and logs)
[ "$DO_MENU" = "1" ] && { menu; exit 0; }
[ "$DO_CHECK" = "1" ] && doctor
[ "$DO_UNINSTALL" = "1" ] && { elevate; uninstall; }

elevate

if [ "$DRY" != "1" ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  : >>"$LOG" 2>/dev/null || LOG=""
fi
note "=== install start (installer $INSTALLER_VERSION, args: ${ORIG_ARGS[*]:-none}) ==="

say ""
say "${C_B}  ${APP_NAME}${C_RESET} ${C_DIM}// نصب‌کننده v${INSTALLER_VERSION}${C_RESET}"
say "${C_DIM}  لیست کوین‌های فیوچرز بایننس بر اساس ریزش/رشد ۲، ۶، ۱۲ و ۲۴ ساعته${C_RESET}"
rule
[ "$DRY" = "1" ] && { say "  ${C_Y}حالت آزمایشی: هیچ تغییری روی سیستم اعمال نمی‌شود.${C_RESET}"; }

# ---------------------------------------------------------- 1) preflight ----
step 1 7 "بررسی پیش‌نیازها"

INIT=""
if have systemctl && [ -d /run/systemd/system ]; then INIT="systemd"
elif have rc-service; then INIT="openrc"
else INIT="none"; fi

case "$INIT" in
  systemd) ok "systemd" ;;
  openrc)  ok "openrc" ;;
  *)       warn "init سیستم‌عامل شناسایی نشد؛ فایل‌ها نصب می‌شوند ولی سرویس خودکار ساخته نمی‌شود." ;;
esac

if have python3; then
  if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,5) else 1)' 2>/dev/null; then
    ok "python3 $(python3 -c 'import platform;print(platform.python_version())' 2>/dev/null)"
  else
    warn "python3 قدیمی است؛ تلاش برای نصب نسخه جدیدتر…"
    install_pkgs python3
  fi
else
  info "python3 پیدا نشد، در حال نصب…"
  install_pkgs python3
  have python3 || die "نصب python3 ناموفق بود."
fi
PY="$(command -v python3)"
[ "$DRY" = "1" ] && PY="python3"

if ! have curl && ! have wget; then
  install_pkgs curl
  have curl || die "نه curl داریم نه wget؛ دانلود سورس ممکن نیست."
fi
ok "ابزار دانلود: $(have curl && echo curl || echo wget)"

# ------------------------------------------------------------- 2) config ---
step 2 7 "تنظیمات"

PREV_PORT="$(state_get PORT || true)"
PREV_BIND="$(state_get BIND || true)"
PREV_DOMAIN="$(state_get DOMAIN || true)"
PREV_NGINX="$(state_get NGINX || true)"
PREV_SSL="$(state_get SSL || true)"
PREV_DIR="$(state_get DIR || true)"
PREV_EMAIL="$(state_get EMAIL || true)"
UPGRADE=0
[ -f "$STATE_FILE" ] && UPGRADE=1
for unit in "/etc/systemd/system/${SERVICE_NAME}.service" "/etc/init.d/${SERVICE_NAME}"; do
  [ -f "$unit" ] && UPGRADE=1
done

# migrating from an install without a state file: recover the port it was using
if [ "$UPGRADE" = "1" ] && [ -z "$PREV_PORT" ]; then
  for unit in "/etc/systemd/system/${SERVICE_NAME}.service" "/etc/init.d/${SERVICE_NAME}"; do
    [ -f "$unit" ] && PREV_PORT="$(sed -n 's/.*--port \([0-9][0-9]*\).*/\1/p' "$unit" 2>/dev/null | head -1)"
    [ -n "$PREV_PORT" ] && break
  done
fi

INSTALL_DIR="${OPT_DIR:-${PREV_DIR:-$DEFAULT_DIR}}"

# --- port
if [ -n "$OPT_PORT" ]; then
  PORT="$OPT_PORT"
  if port_busy "$PORT" && [ "$UPGRADE" = "0" ]; then
    die "پورت ${PORT} اشغال است. پورت دیگری بدهید یا --port را حذف کنید تا خودکار انتخاب شود."
  fi
elif [ "$UPGRADE" = "1" ] && [ -n "$PREV_PORT" ]; then
  PORT="$PREV_PORT"
else
  PORT="$(pick_port)" || die "پورت آزادی پیدا نشد؛ با --port یکی مشخص کنید."
fi

# --- domain
DOMAIN="${OPT_DOMAIN:-${PREV_DOMAIN:-}}"
[ "$CLEAR_DOMAIN" = "1" ] && DOMAIN=""
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
EMAIL="${OPT_EMAIL:-${PREV_EMAIL:-}}"

# fresh install with a terminal: ask for the domain (the only question we ask)
if [ "$UPGRADE" = "0" ] && [ -z "$OPT_DOMAIN" ] && [ "$CLEAR_DOMAIN" = "0" ] \
   && [ "$UNATTENDED" = "0" ] && [ "$INTERACTIVE" = "0" ] && [ "$TTY_READY" = "1" ]; then
  say ""
  say "  ${C_DIM}دامنه${C_RESET}  اگر دامنه ندارید خالی بگذارید تا سایت با IP و پورت ${PORT} کار کند."
  say "  ${C_DIM}با دامنه، nginx و گواهی رایگان HTTPS هم خودکار راه می‌افتند.${C_RESET}"
  ask DOMAIN "  دامنه" ""
  DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
  if [ -n "$DOMAIN" ]; then
    ask EMAIL "  ایمیل برای گواهی SSL (اختیاری)" "$EMAIL"
    [ -z "$EMAIL" ] && info "بدون ایمیل هم گواهی گرفته می‌شود؛ فقط اطلاع‌رسانی تمدید نمی‌آید."
  fi
  say ""
fi

if [ -n "$DOMAIN" ] && ! printf '%s' "$DOMAIN" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'; then
  die "دامنه نامعتبر است: ${DOMAIN}"
fi
if [ -n "$EMAIL" ] && ! printf '%s' "$EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$'; then
  die "ایمیل نامعتبر است: ${EMAIL}"
fi

# --- interactive overrides
if [ "$INTERACTIVE" = "1" ]; then
  if [ "$TTY_READY" = "1" ]; then
    say ""
    say "  ${C_DIM}حالت تعاملی — خالی گذاشتن هر مورد یعنی مقدار پیش‌فرض.${C_RESET}"
    ask PORT "  پورت سرویس" "$PORT"
    case "$PORT" in ''|*[!0-9]*) die "پورت باید عدد باشد." ;; esac
    ask DOMAIN "  دامنه (خالی = دسترسی با IP)" "$DOMAIN"
    DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
    if [ -n "$DOMAIN" ]; then
      ask_yn "  nginx و ریورس‌پروکسی روی دامنه نصب شود؟" y && USE_NGINX=1 || USE_NGINX=0
      if [ "$USE_NGINX" = "1" ]; then
        ask_yn "  گواهی SSL رایگان (Let's Encrypt) گرفته شود؟" y && USE_SSL=1 || USE_SSL=0
        if [ "$USE_SSL" = "1" ] && [ -z "$OPT_EMAIL" ]; then
          ask OPT_EMAIL "  ایمیل برای Let's Encrypt (اختیاری)" ""
        fi
      fi
    fi
    ask_yn "  پورت(های) لازم در فایروال باز شوند؟" y && USE_FW=1 || USE_FW=0
    say ""
  else
    warn "--interactive داده شد ولی ترمینال تعاملی نیست؛ با مقادیر خودکار ادامه می‌دهیم."
  fi
fi

# --- nginx / ssl defaults
if [ -z "$USE_NGINX" ]; then
  if [ -n "$DOMAIN" ]; then USE_NGINX=1; else USE_NGINX=0; fi
fi
[ -z "$DOMAIN" ] && USE_NGINX=0

if [ -z "$USE_SSL" ]; then
  if [ "$USE_NGINX" = "1" ] && [ -n "$DOMAIN" ]; then USE_SSL=1; else USE_SSL=0; fi
fi
# an unchanged re-run keeps the SSL choice made the first time
if [ "$SSL_SET" = "0" ] && [ "$UPGRADE" = "1" ] && [ -n "$PREV_SSL" ] && [ "$DOMAIN" = "$PREV_DOMAIN" ]; then
  USE_SSL="$PREV_SSL"
fi
[ "$USE_NGINX" = "0" ] && USE_SSL=0

if [ -z "$OPT_BIND" ]; then
  if [ "$USE_NGINX" = "1" ]; then BIND="127.0.0.1"; else BIND="0.0.0.0"; fi
else
  BIND="$OPT_BIND"
fi

ok "پورت ${C_B}${PORT}${C_RESET}$([ "$UPGRADE" = "1" ] && echo " (از نصب قبلی)" || true)"
if [ "$USE_NGINX" = "1" ]; then ok "دامنه ${C_B}${DOMAIN}${C_RESET} — nginx + $([ "$USE_SSL" = "1" ] && echo 'HTTPS' || echo 'HTTP')"; else ok "دسترسی مستقیم با IP روی پورت ${PORT}"; fi
ok "مسیر ${INSTALL_DIR}$([ "$UPGRADE" = "1" ] && echo "  (به‌روزرسانی نصب موجود)" || true)"

# ------------------------------------------------------------ 3) source ----
step 3 7 "دریافت فایل‌های برنامه"

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf -- "$TMP_DIR" 2>/dev/null || true; }
trap 'cleanup' EXIT

SRC_DIR=""
SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
fi
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/index.html" ] && [ -f "$SELF_DIR/server.py" ]; then
  SRC_DIR="$SELF_DIR"
  ok "استفاده از فایل‌های کنار اسکریپت"
else
  TARBALL="$TMP_DIR/src.tar.gz"
  download "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}" "$TARBALL" \
    || download "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" "$TARBALL" \
    || die "دانلود سورس از GitHub ناموفق بود. اتصال شبکه/پراکسی را بررسی کنید."
  mkdir -p "$TMP_DIR/src"
  # extract with a relative path: GNU tar treats "host:path" as a remote archive,
  # which breaks when TMPDIR contains a colon
  ( cd "$TMP_DIR" && tar -xzf "src.tar.gz" -C "src" --strip-components=1 ) \
    || die "استخراج آرشیو ناموفق بود."
  SRC_DIR="$TMP_DIR/src"
  [ -f "$SRC_DIR/index.html" ] || die "سورس دانلود شد ولی index.html داخلش نبود."
  ok "سورس از GitHub دریافت شد"
fi

# ------------------------------------------------------------- 4) files ----
step 4 7 "نصب فایل‌ها"

run mkdir -p "$INSTALL_DIR"

# keep the previous build so a failed upgrade can be rolled back
if [ "$UPGRADE" = "1" ] && [ -f "$INSTALL_DIR/index.html" ] && [ "$DRY" != "1" ]; then
  mkdir -p "$INSTALL_DIR/.previous"
  cp -f "$INSTALL_DIR/index.html" "$INSTALL_DIR/.previous/index.html" 2>/dev/null || true
  cp -f "$INSTALL_DIR/server.py"  "$INSTALL_DIR/.previous/server.py"  2>/dev/null || true
  ok "نسخه قبلی برای بازگشت پشتیبان‌گیری شد"
fi

run cp -f "$SRC_DIR/index.html" "$INSTALL_DIR/index.html"
run cp -f "$SRC_DIR/server.py"  "$INSTALL_DIR/server.py"
[ -f "$SRC_DIR/README.md" ] && run cp -f "$SRC_DIR/README.md" "$INSTALL_DIR/README.md" || true
[ -f "$SRC_DIR/INSTALL.md" ] && run cp -f "$SRC_DIR/INSTALL.md" "$INSTALL_DIR/INSTALL.md" || true
[ -f "$SRC_DIR/LICENSE" ]   && run cp -f "$SRC_DIR/LICENSE"   "$INSTALL_DIR/LICENSE"   || true
run chmod 755 "$INSTALL_DIR"
run chmod 644 "$INSTALL_DIR/index.html"
run chmod 755 "$INSTALL_DIR/server.py"
ok "فایل‌ها در ${INSTALL_DIR}"

# --------------------------------------------------------------- CLI menu ---
# a copy of this script plus a `binance-screener` command that opens the menu
run mkdir -p "$LIB_DIR"
if [ -f "$SRC_DIR/install.sh" ]; then
  # the freshly fetched tarball carries the newest installer — prefer it
  run cp -f "$SRC_DIR/install.sh" "$LIB_DIR/install.sh"
elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  run cp -f "${BASH_SOURCE[0]}" "$LIB_DIR/install.sh"
elif [ "$DRY" = "1" ]; then
  info "در حالت آزمایشی اسکریپت مدیریت ذخیره نمی‌شود"
else
  download "$SELF_URL" "$LIB_DIR/install.sh" 2>/dev/null \
    || warn "ذخیره‌ی اسکریپت مدیریت ناموفق بود؛ منو بعداً در دسترس نیست."
fi
[ -f "$LIB_DIR/install.sh" ] && run chmod 755 "$LIB_DIR/install.sh" || true

write_file "$CLI_BIN" 755 <<CLI_EOF
#!/bin/sh
# ${APP_NAME} — settings menu
exec bash "${LIB_DIR}/install.sh" --menu "\$@"
CLI_EOF
run ln -sf "$CLI_BIN" "$CLI_ALIAS" 2>/dev/null || true
ok "دستور مدیریت: ${C_B}binance-screener${C_RESET} ${C_DIM}(یا bfs)${C_RESET}"

# service user (unprivileged)
if ! group_exists "$SERVICE_USER"; then
  if have groupadd; then
    run groupadd --system "$SERVICE_USER" 2>/dev/null || run groupadd -r "$SERVICE_USER" 2>/dev/null || true
  elif have addgroup; then
    run addgroup -S "$SERVICE_USER" 2>/dev/null || true
  fi
fi
SERVICE_GROUP=""
group_exists "$SERVICE_USER" && SERVICE_GROUP="$SERVICE_USER"

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  if have useradd; then
    if [ -n "$SERVICE_GROUP" ]; then
      run useradd --system --no-create-home --gid "$SERVICE_GROUP" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
        || run useradd -r -M -g "$SERVICE_GROUP" -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || true
    else
      run useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
        || run useradd -r -M -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || true
    fi
  elif have adduser; then
    run adduser -S -H -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || true
  fi
fi
if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  run chown -R "root:${SERVICE_GROUP:-root}" "$INSTALL_DIR" 2>/dev/null || true
  run chmod -R g+rX,o-rwx "$INSTALL_DIR" 2>/dev/null || true
  RUN_USER="$SERVICE_USER"
  ok "اجرا با کاربر بدون دسترسی: ${SERVICE_USER}"
else
  RUN_USER="root"
  warn "کاربر سرویس ساخته نشد؛ برنامه با root اجرا می‌شود."
fi

# persist the resolved settings so the next run is an in-place upgrade
write_file "$STATE_FILE" 600 <<STATE_EOF
PORT=${PORT}
BIND=${BIND}
DIR=${INSTALL_DIR}
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
NGINX=${USE_NGINX}
SSL=${USE_SSL}
VERSION=${INSTALLER_VERSION}
STATE_EOF

# ----------------------------------------------------------- 5) service ----
step 5 7 "راه‌اندازی سرویس"

if [ "$INIT" = "systemd" ]; then
  GROUP_LINE=""
  [ -n "$SERVICE_GROUP" ] && GROUP_LINE="Group=${SERVICE_GROUP}"
  CAP_LINES=""
  if [ "$PORT" -lt 1024 ] && [ "$RUN_USER" != "root" ]; then
    CAP_LINES="AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
  fi
  write_file "/etc/systemd/system/${SERVICE_NAME}.service" 644 <<UNIT_EOF
[Unit]
Description=${APP_NAME} (web UI)
Documentation=https://github.com/${REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
${GROUP_LINE}
WorkingDirectory=${INSTALL_DIR}
Environment=PYTHONUNBUFFERED=1
ExecStart=${PY} ${INSTALL_DIR}/server.py --port ${PORT} --bind ${BIND}
Restart=always
RestartSec=3
TimeoutStopSec=10
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=full
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
${CAP_LINES}
LimitNOFILE=4096
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
UNIT_EOF

  run systemctl daemon-reload
  run systemctl enable "$SERVICE_NAME"
  run systemctl restart "$SERVICE_NAME"
  ok "سرویس systemd ثبت و اجرا شد"

elif [ "$INIT" = "openrc" ]; then
  OC_USER="$RUN_USER"
  if [ "$PORT" -lt 1024 ]; then OC_USER="root"; warn "پورت زیر ۱۰۲۴ است؛ سرویس OpenRC با root اجرا می‌شود."; fi
  write_file "/etc/init.d/${SERVICE_NAME}" 755 <<OPENRC_EOF
#!/sbin/openrc-run
name="${SERVICE_NAME}"
description="${APP_NAME}"
command="${PY}"
command_args="${INSTALL_DIR}/server.py --port ${PORT} --bind ${BIND}"
command_user="${OC_USER}"
directory="${INSTALL_DIR}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.log"

depend() {
    need net
    after firewall
}
OPENRC_EOF

  run rc-update add "$SERVICE_NAME" default
  run rc-service "$SERVICE_NAME" restart
  ok "سرویس OpenRC ثبت و اجرا شد"

else
  warn "بدون init: اجرای دستی لازم است."
  info "  ${PY} ${INSTALL_DIR}/server.py --port ${PORT} --bind ${BIND}"
fi

# ------------------------------------------------------- 6) health check ----
step 6 7 "بررسی سلامت"

if [ "$DRY" = "1" ]; then
  info "در حالت آزمایشی بررسی سلامت انجام نمی‌شود"
else
  HEALTHY=0
  for _ in $(seq 1 20); do
    if http_ok "http://127.0.0.1:${PORT}/healthz"; then HEALTHY=1; break; fi
    sleep 0.7
  done

  if [ "$HEALTHY" = "1" ]; then
    ok "پاسخ /healthz سالم است (پورت ${PORT})"
  else
    warn "سرویس پاسخ نداد؛ لاگ سرویس:"
    if [ "$INIT" = "systemd" ] && have journalctl; then journalctl -u "$SERVICE_NAME" -n 15 --no-pager || true; fi
    note "health check failed"
    if [ -f "$INSTALL_DIR/.previous/index.html" ]; then
      warn "بازگشت به نسخه قبلی…"
      cp -f "$INSTALL_DIR/.previous/index.html" "$INSTALL_DIR/index.html" 2>/dev/null || true
      cp -f "$INSTALL_DIR/.previous/server.py"  "$INSTALL_DIR/server.py"  2>/dev/null || true
      if [ "$INIT" = "systemd" ]; then systemctl restart "$SERVICE_NAME" 2>/dev/null || true; fi
      if [ "$INIT" = "openrc" ]; then rc-service "$SERVICE_NAME" restart 2>/dev/null || true; fi
      die "به‌روزرسانی ناموفق بود و نسخه قبلی بازگردانده شد."
    fi
    die "راه‌اندازی ناموفق بود."
  fi
fi

# ------------------------------------------------------------ 7) nginx ------
step 7 7 "وب‌سرور و فایروال"

SSL_RESULT="غیرفعال"

if [ "$USE_NGINX" = "1" ]; then
  if ! have nginx; then
    install_pkgs nginx
  fi
  if [ "$DRY" = "1" ] || have nginx; then
    if [ -d /etc/nginx/http.d ]; then
      NGINX_CONF="/etc/nginx/http.d/${SERVICE_NAME}.conf"     # Alpine
    else
      run mkdir -p /etc/nginx/conf.d
      NGINX_CONF="/etc/nginx/conf.d/${SERVICE_NAME}.conf"      # Debian / RHEL
    fi
    write_file "$NGINX_CONF" 644 <<NGINX_EOF
# ${APP_NAME} — generated by install.sh
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

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
        proxy_connect_timeout 10s;
    }
}
NGINX_EOF

    if [ "$DRY" = "1" ] || nginx -t >/dev/null 2>&1; then
      run systemctl enable nginx 2>/dev/null || true
      run systemctl reload nginx 2>/dev/null || run systemctl restart nginx 2>/dev/null || true
      ok "nginx روی ${DOMAIN} پیکربندی شد"
    else
      warn "پیکربندی nginx خطا دارد:"
      nginx -t || true
    fi

    if [ "$USE_SSL" = "1" ]; then
      if ! have certbot; then
        case "$PM" in
          apk) install_pkgs certbot certbot-nginx ;;
          pacman) install_pkgs certbot certbot-nginx ;;
          *) install_pkgs certbot python3-certbot-nginx ;;
        esac
      fi
      if [ "$DRY" = "1" ] || have certbot; then
        CERT_ARGS=(--nginx -d "$DOMAIN" --agree-tos --no-eff-email --redirect -n)
        if [ -n "$EMAIL" ]; then
          CERT_ARGS+=(-m "$EMAIL")
        else
          CERT_ARGS+=(--register-unsafely-without-email)
          warn "ایمیلی داده نشد؛ گواهی بدون ایمیل ثبت می‌شود (اطلاع‌رسانی تمدید نخواهید داشت)."
        fi
        info "درخواست گواهی SSL برای ${DOMAIN}…"
        if [ "$DRY" = "1" ]; then
          printf '     %s$ certbot %s%s\n' "$C_DIM" "${CERT_ARGS[*]}" "$C_RESET"
          SSL_RESULT="فعال"
        elif certbot "${CERT_ARGS[@]}" >/dev/null 2>&1; then
          SSL_RESULT="فعال"
          ok "SSL فعال شد: https://${DOMAIN}"
        else
          SSL_RESULT="ناموفق — فعلاً HTTP"
          warn "گرفتن گواهی ناموفق بود (معمولاً DNS هنوز به این سرور وصل نیست)."
          info "بعد از اصلاح DNS:  certbot --nginx -d ${DOMAIN}"
        fi
      fi
    fi
  fi
else
  info "بدون nginx — دسترسی مستقیم روی پورت ${PORT}"
  STALE_CONF=0
  for conf in "/etc/nginx/conf.d/${SERVICE_NAME}.conf" "/etc/nginx/http.d/${SERVICE_NAME}.conf"; do
    if [ -f "$conf" ]; then run rm -f "$conf"; STALE_CONF=1; fi
  done
  if [ "$STALE_CONF" = "1" ]; then
    if [ "$DRY" = "1" ] || { have nginx && nginx -t >/dev/null 2>&1; }; then
      run systemctl reload nginx 2>/dev/null || run nginx -s reload 2>/dev/null || true
      ok "کانفیگ قبلی nginx حذف شد"
    else
      warn "کانفیگ nginx حذف شد ولی reload نشد؛ دستی: nginx -t && systemctl reload nginx"
    fi
  fi
fi

# firewall (automatic, reported in the summary)
FW_NOTE="دست‌نخورده"
if [ "$USE_FW" != "0" ]; then
  if [ "$USE_NGINX" = "1" ]; then FW_PORTS="80 443"; else FW_PORTS="$PORT"; fi
  if have ufw && ufw status 2>/dev/null | grep -qi "Status: active"; then
    for p in $FW_PORTS; do run ufw allow "$p/tcp" >/dev/null 2>&1 || true; done
    FW_NOTE="پورت ${FW_PORTS} در ufw باز شد"
    ok "$FW_NOTE"
  elif have firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
    for p in $FW_PORTS; do run firewall-cmd --permanent --add-port="$p/tcp" >/dev/null 2>&1 || true; done
    run firewall-cmd --reload >/dev/null 2>&1 || true
    FW_NOTE="پورت ${FW_PORTS} در firewalld باز شد"
    ok "$FW_NOTE"
  else
    info "فایروال فعالی پیدا نشد؛ پورتی باز نشد"
  fi
fi

# ------------------------------------------------------------ summary ------
PUBLIC_IP="$(public_ip)"
if [ "$USE_NGINX" = "1" ]; then
  if [ "$SSL_RESULT" = "فعال" ]; then URL="https://${DOMAIN}"; else URL="http://${DOMAIN}"; fi
else
  URL="http://${PUBLIC_IP}:${PORT}"
fi

note "=== install done: $URL (port $PORT, nginx=$USE_NGINX ssl=$USE_SSL) ==="

say ""
rule
if [ "$UPGRADE" = "1" ]; then
  printf '%s  ✔ تنظیمات اعمال شد%s  %s—  %s%s\n' "$C_G$C_B" "$C_RESET" "$C_DIM" "$APP_NAME" "$C_RESET"
else
  printf '%s  ✔ نصب کامل شد%s  %s—  %s%s\n' "$C_G$C_B" "$C_RESET" "$C_DIM" "$APP_NAME" "$C_RESET"
fi
rule
say "  ${C_DIM}آدرس${C_RESET}          ${C_B}${C_C}${URL}${C_RESET}"
[ "$USE_NGINX" = "1" ] && say "  ${C_DIM}پورت داخلی${C_RESET}    ${PORT}  (فقط 127.0.0.1)"
[ "$USE_NGINX" = "0" ] && say "  ${C_DIM}پورت${C_RESET}          ${PORT}  (${BIND})"
say "  ${C_DIM}مسیر نصب${C_RESET}      ${INSTALL_DIR}"
say "  ${C_DIM}سرویس${C_RESET}         ${SERVICE_NAME}  (${INIT})"
say "  ${C_DIM}فایروال${C_RESET}       ${FW_NOTE}"
say "  ${C_DIM}SSL${C_RESET}           ${SSL_RESULT}"
say "  ${C_DIM}لاگ نصب${C_RESET}       ${LOG:-—}"
if [ "$USE_NGINX" = "0" ]; then
  say ""
  say "  ${C_Y}اگر سایت از بیرون باز نشد:${C_RESET} پورت ${C_B}${PORT}${C_RESET} را در فایروال ابری سرور"
  say "  ${C_DIM}(Security Group در AWS / Firewall در Hetzner و …) هم باز کنید.${C_RESET}"
fi
rule
say "  ${C_DIM}مدیریت${C_RESET}"
say "    ${C_B}binance-screener${C_RESET}   ${C_DIM}منوی تنظیمات (یا bfs)${C_RESET}"
if [ "$INIT" = "systemd" ]; then
  say "    systemctl status ${SERVICE_NAME}"
  say "    systemctl restart ${SERVICE_NAME}"
  say "    journalctl -u ${SERVICE_NAME} -f"
elif [ "$INIT" = "openrc" ]; then
  say "    rc-service ${SERVICE_NAME} restart"
  say "    tail -f /var/log/${SERVICE_NAME}.log"
fi
say "    curl -s ${URL%/}/healthz"
rule
say "  ${C_DIM}به‌روزرسانی${C_RESET}   همان دستور نصب را دوباره اجرا کنید (تنظیمات فعلی حفظ می‌شود)"
say "  ${C_DIM}حذف${C_RESET}           curl -fsSL ${SELF_URL} | bash -s -- --uninstall"
rule
if [ "$USE_SSL" = "1" ] && [ "$USE_NGINX" = "1" ]; then
  say "  ${C_DIM}اگر HTTPS بالا نیامد، رکورد A دامنه را به این سرور وصل کنید و دوباره اجرا کنید.${C_RESET}"
fi
say ""
