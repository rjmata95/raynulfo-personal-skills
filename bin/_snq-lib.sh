#!/usr/bin/env bash
# Shared library for the snq family (snq, snq-doctor, snq-auth).
# Sourced, never executed directly.

# ---------------------------------------------------------------------------
# Config locations
#
# The session file holds a LIVE production ServiceNow session. It lives in
# ~/.config/snq/ (chmod 600), never in the git repo. The repo carries only
# instance.conf — a hostname, no secrets.
# ---------------------------------------------------------------------------

SNQ_CFG_DIR="${SNQ_CONFIG_DIR:-$HOME/.config/snq}"
SNQ_SESSION_FILE="$SNQ_CFG_DIR/session"
SNQ_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNQ_INSTANCE_CONF="$SNQ_REPO_ROOT/config/instance.conf"

# Default instance; overridable via instance.conf or SNQ_INSTANCE.
SNQ_DEFAULT_INSTANCE="https://chenmed.service-now.com"

snq_die() { printf '%s\n' "snq: $*" >&2; exit 1; }
snq_warn() { printf '%s\n' "snq: $*" >&2; }

# --- instance resolution ---------------------------------------------------

snq_load_instance() {
  if [[ -n "${SNQ_INSTANCE:-}" ]]; then
    SNQ_URL="${SNQ_INSTANCE%/}"
    return 0
  fi
  if [[ -f "$SNQ_INSTANCE_CONF" ]]; then
    local line
    line="$(grep -E '^[[:space:]]*instance[[:space:]]*=' "$SNQ_INSTANCE_CONF" 2>/dev/null | head -1)"
    if [[ -n "$line" ]]; then
      SNQ_URL="${line#*=}"
      SNQ_URL="$(printf '%s' "$SNQ_URL" | tr -d '[:space:]')"
      SNQ_URL="${SNQ_URL%/}"
      [[ -n "$SNQ_URL" ]] && return 0
    fi
  fi
  SNQ_URL="$SNQ_DEFAULT_INSTANCE"
}

# --- session file ----------------------------------------------------------
#
# Format (shell-sourceable, chmod 600):
#   SNQ_COOKIE='JSESSIONID=...; glide_user_route=...; BIGipServerpool_chenmed=...'
#   SNQ_USER_TOKEN='<window.g_ck value>'
#   SNQ_CAPTURED_AT='2026-08-07T19:04:00Z'
#   SNQ_CAPTURED_USER='rmata'
#
# SNQ_USER_TOKEN is ServiceNow's CSRF token (g_ck). Reads work without it;
# every write (POST/PUT/PATCH/DELETE) is rejected without it.

snq_session_exists() { [[ -f "$SNQ_SESSION_FILE" ]]; }

snq_load_session() {
  snq_session_exists || return 1
  # shellcheck disable=SC1090
  source "$SNQ_SESSION_FILE"
  [[ -n "${SNQ_COOKIE:-}" ]] || return 1
  return 0
}

# Age of the session file in seconds; prints nothing if absent.
snq_session_age() {
  snq_session_exists || return 1
  local mtime now
  mtime="$(stat -f %m "$SNQ_SESSION_FILE" 2>/dev/null)" || return 1
  now="$(date +%s)"
  printf '%s' "$(( now - mtime ))"
}

snq_session_age_human() {
  local secs; secs="$(snq_session_age)" || { printf 'absent'; return; }
  if (( secs < 60 )); then printf '%ds' "$secs"
  elif (( secs < 3600 )); then printf '%dm' "$(( secs / 60 ))"
  else printf '%dh%dm' "$(( secs / 3600 ))" "$(( (secs % 3600) / 60 ))"
  fi
}

snq_ensure_cfg_dir() {
  if [[ ! -d "$SNQ_CFG_DIR" ]]; then
    mkdir -p "$SNQ_CFG_DIR" || snq_die "cannot create $SNQ_CFG_DIR"
    chmod 700 "$SNQ_CFG_DIR"
  fi
}

# --- HTTP ------------------------------------------------------------------
#
# Every call goes through here so auth handling and the 401 message live in
# exactly one place.
#
# snq_api <METHOD> <PATH_WITH_QUERY> [JSON_BODY]

snq_api() {
  local method="$1" path="$2" body="${3:-}"
  local url="$SNQ_URL$path"
  local -a args=(
    -sS --max-time "${SNQ_TIMEOUT:-45}"
    -X "$method"
    -H "Accept: application/json"
    -H "Cookie: $SNQ_COOKIE"
    -w $'\n__SNQ_HTTP__%{http_code}'
  )

  # ServiceNow rejects session-authenticated writes without the g_ck CSRF token.
  case "$method" in
    POST|PUT|PATCH|DELETE)
      if [[ -z "${SNQ_USER_TOKEN:-}" ]]; then
        snq_die "this session has no CSRF token (g_ck), so writes are impossible.
       Re-run: snq auth   (the capture step must read window.g_ck)"
      fi
      ;;
  esac

  # Send X-UserToken on EVERY method, reads included. A session cookie alone is
  # not enough for /api/now/: the instance answers 401 with
  #   {"error":{"message":"User is not authenticated",
  #             "detail":"Required to provide Auth information"}}
  # even on a cookie captured seconds earlier. The g_ck token is what makes a
  # browser-derived session acceptable to the REST layer, so it is not a
  # write-only concern — it is the auth signal.
  if [[ -n "${SNQ_USER_TOKEN:-}" ]]; then
    args+=(-H "X-UserToken: $SNQ_USER_TOKEN")
  fi

  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" --data-binary "$body")
  fi

  local raw code payload
  raw="$(curl "${args[@]}" "$url" 2>&1)" || snq_die "curl failed: $raw"
  code="${raw##*__SNQ_HTTP__}"
  payload="${raw%$'\n'__SNQ_HTTP__*}"

  case "$code" in
    2*) printf '%s' "$payload" ;;
    401|302)
      snq_die "session expired or not authenticated (HTTP $code).
       Session age: $(snq_session_age_human). ServiceNow drops idle sessions after ~30 min.
       Re-authenticate: snq auth
       ServiceNow said: $(printf '%s' "$payload" | head -c 400)"
      ;;
    403)
      snq_die "HTTP 403 — authenticated, but your ServiceNow roles don't permit this.
       Writing to the incident table needs the 'itil' role. Reads may still work."
      ;;
    *)
      snq_die "HTTP $code from $method $path
$(printf '%s' "$payload" | head -c 800)"
      ;;
  esac
}

# Load instance + session, or exit with a directed message.
snq_require_session() {
  snq_load_instance
  if ! snq_load_session; then
    snq_die "no ServiceNow session found at $SNQ_SESSION_FILE
       Run: snq auth      (opens a browser for Okta SSO, then captures the session)"
  fi
}

# --- JSON helpers ----------------------------------------------------------
# python3 is a hard dependency; it ships with macOS and beats hand-rolled sed.

snq_have_python() { command -v python3 >/dev/null 2>&1; }

snq_json_field() {
  # snq_json_field <json> <dotted.path>
  snq_have_python || snq_die "python3 not found; required for JSON handling"
  printf '%s' "$1" | python3 -c '
import json,sys
path=sys.argv[1].split(".")
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
for p in path:
    if isinstance(d,list):
        try: d=d[int(p)]
        except Exception: sys.exit(1)
    elif isinstance(d,dict): d=d.get(p)
    else: sys.exit(1)
    if d is None: sys.exit(1)
print(d if not isinstance(d,(dict,list)) else json.dumps(d))
' "$2" 2>/dev/null
}
