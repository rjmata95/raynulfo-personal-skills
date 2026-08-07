#!/usr/bin/env bash
# _dbq-lib.sh — shared registry, paths, and credential lookup for dbq.
#
# PORTABILITY: this file must run on bash 3.2, which is what macOS ships as
# /bin/bash (version 3.2.57, 2007). That rules out:
#   * associative arrays (declare -A)     -> use parallel indexed arrays
#   * mapfile / readarray                 -> use while-read loops
#   * [[ -v arr[key] ]]                   -> use reg_index()
#   * ${arr[@]} on an empty array under `set -u`  -> guard with count checks
# Do not "modernise" this file without also shipping a bash 4 dependency.
#
# Sourced by: dbq, dbq-doctor, dbq-init. Single source of truth so the runner
# and the diagnostics can never disagree about what an alias means.

# ------------------------------------------------------------------ resolution

# Follow symlinks to find the real repo root, however deep we are linked.
_dbq_resolve_root() {
  local self="$1" link
  while [ -L "$self" ]; do
    link=$(readlink "$self")
    case "$link" in
      /*) self="$link" ;;
      *)  self="$(cd -P "$(dirname "$self")" && pwd)/$link" ;;
    esac
  done
  (cd -P "$(dirname "$self")/.." && pwd)
}

# ----------------------------------------------------------------------- paths

dbq_init_paths() {
  REPO_ROOT="${REPO_ROOT:?REPO_ROOT must be set before dbq_init_paths}"
  SHARED_CONF="$REPO_ROOT/config/connections.conf"
  KNOWLEDGE_DIR="$REPO_ROOT/knowledge"

  CFG_DIR="${DBQ_CONFIG_DIR:-$HOME/.config/dbq}"
  ENV_FILE="$CFG_DIR/env"
  MYCNF="$CFG_DIR/my.cnf"
  LOCAL_CONF="$CFG_DIR/connections.local.conf"
  SKIP_FILE="$CFG_DIR/skipped"
  ROLLBACK="$CFG_DIR/mcp-rollback.json"
  CLAUDE_JSON="${DBQ_CLAUDE_JSON:-$HOME/.claude.json}"

  SCRATCH_ROOT="${DBQ_SCRATCH_ROOT:-$HOME/.dbq/scratch}"
  RETENTION_DAYS="${DBQ_RETENTION_DAYS:-7}"
}

# ------------------------------------------------------------------- colouring

dbq_init_colors() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m';  C_BOLD=$'\033[1m'
    C_RED=$'\033[31m';  C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYN=$'\033[36m'
  else
    C_RESET=""; C_DIM=""; C_BOLD=""; C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""
  fi
}

dbq_die()  { printf '%s%s: %s%s\n' "${C_RED:-}" "${DBQ_PROG:-dbq}" "$*" "${C_RESET:-}" >&2; exit 1; }
dbq_warn() { printf '%s%s: %s%s\n' "${C_YEL:-}" "${DBQ_PROG:-dbq}" "$*" "${C_RESET:-}" >&2; }
dbq_dim()  { printf '%s%s%s\n' "${C_DIM:-}" "$*" "${C_RESET:-}"; }

# ------------------------------------------------------- registry (bash 3.2 ok)

# Parallel indexed arrays. Index i describes one alias across all six.
REG_ALIAS=(); REG_KIND=(); REG_ENV=(); REG_MODE=(); REG_DDB=(); REG_DESC=()

reg_count() { printf '%s' "${#REG_ALIAS[@]}"; }

# Echo the index of an alias, or return 1.
reg_index() {
  local want="$1" i n="${#REG_ALIAS[@]}"
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${REG_ALIAS[$i]}" = "$want" ]; then printf '%s' "$i"; return 0; fi
    i=$((i+1))
  done
  return 1
}

reg_has() { reg_index "$1" >/dev/null 2>&1; }

# reg_get <field> <alias>   field: kind|env|mode|ddb|desc
reg_get() {
  local field="$1" alias="$2" i
  i=$(reg_index "$alias") || return 1
  case "$field" in
    kind) printf '%s' "${REG_KIND[$i]}" ;;
    env)  printf '%s' "${REG_ENV[$i]}" ;;
    mode) printf '%s' "${REG_MODE[$i]}" ;;
    ddb)  printf '%s' "${REG_DDB[$i]}" ;;
    desc) printf '%s' "${REG_DESC[$i]}" ;;
    *) return 1 ;;
  esac
}

# reg_put <alias> <kind> <env> <mode> <ddb> <desc>  — upsert by alias.
reg_put() {
  local alias="$1" kind="$2" env="$3" mode="$4" ddb="$5" desc="$6" i
  if i=$(reg_index "$alias"); then
    REG_KIND[$i]="$kind"; REG_ENV[$i]="$env"; REG_MODE[$i]="$mode"
    REG_DDB[$i]="$ddb";   REG_DESC[$i]="$desc"
  else
    REG_ALIAS[${#REG_ALIAS[@]}]="$alias"
    REG_KIND[${#REG_KIND[@]}]="$kind"
    REG_ENV[${#REG_ENV[@]}]="$env"
    REG_MODE[${#REG_MODE[@]}]="$mode"
    REG_DDB[${#REG_DDB[@]}]="$ddb"
    REG_DESC[${#REG_DESC[@]}]="$desc"
  fi
}

_reg_load_file() {
  local file="$1" line alias kind env mode ddb desc
  [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%$'\r'}"
    case "$line" in ''|\#*|'	'*) ;; esac
    case "$line" in ''|\#*) continue ;; esac
    IFS='|' read -r alias kind env mode ddb desc <<EOF
$line
EOF
    [ -n "${alias:-}" ] && [ -n "${kind:-}" ] || continue
    case "$kind" in
      mongo|mysql) ;;
      *) dbq_warn "$(basename "$file"): alias '$alias' has unknown kind '$kind' — skipped"; continue ;;
    esac
    reg_put "$alias" "$kind" "${env:-unknown}" "${mode:-ro}" "${ddb:--}" "${desc:-}"
  done <"$file"
}

# Shared registry first, then the personal overlay, which overrides by alias.
# That is what lets a user repoint or add connections without touching git.
reg_load() {
  [ -r "$SHARED_CONF" ] || dbq_die "missing shared registry: $SHARED_CONF"
  _reg_load_file "$SHARED_CONF"
  _reg_load_file "$LOCAL_CONF"
  [ "$(reg_count)" -gt 0 ] || dbq_die "registry is empty"
}

# ------------------------------------------------------------------ credentials

# medication -> DBQ_MEDICATION_URI ; mysql-prod -> DBQ_MYSQL_PROD_URI
dbq_env_key() {
  printf 'DBQ_%s_URI' "$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
}

dbq_source_env() {
  [ -r "$ENV_FILE" ] || return 1
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE" 2>/dev/null
  set +a
}

# Echo the mongo URI for an alias. Never logged, never placed in argv.
dbq_mongo_uri() {
  local key val
  key=$(dbq_env_key "$1")
  dbq_source_env || return 1
  eval "val=\${$key:-}"
  [ -n "$val" ] || return 1
  printf '%s' "$val"
}

dbq_mysql_group_exists() {
  [ -r "$MYCNF" ] && grep -q "^\[client-$1\]" "$MYCNF" 2>/dev/null
}

dbq_has_credential() {
  case "$2" in
    mongo) dbq_mongo_uri "$1" >/dev/null 2>&1 ;;
    mysql) dbq_mysql_group_exists "$1" ;;
    *) return 1 ;;
  esac
}

dbq_is_skipped() {
  [ -r "$SKIP_FILE" ] && grep -qxF "$1" "$SKIP_FILE" 2>/dev/null
}

# --------------------------------------------------------------------- masking

# Redact credentials before any display. Applied to every printed URI and to
# error text, which frequently echoes the connection string back.
dbq_mask_uri() {
  printf '%s' "$1" | sed -E \
    -e 's#(://[^:/@]+):[^@]*@#\1:****@#g' \
    -e 's#(password[[:space:]]*=[[:space:]]*)[^[:space:]]*#\1****#Ig'
}

dbq_perms_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

# --------------------------------------------------------------------- scratch

# macOS has no /etc/periodic/daily/110.clean-tmps and no periodic-daily launchd
# job, so /tmp does not self-clean. Retention is enforced here, on every run.
dbq_prune_scratch() {
  [ -d "$SCRATCH_ROOT" ] || return 0
  find "$SCRATCH_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -mtime "+$RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
}

dbq_scratch_today() {
  local d="$SCRATCH_ROOT/$(date +%F)"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s' "$d"
}

# ------------------------------------------------------------- live ping tests
#
# macOS ships no `timeout`/`gtimeout` (they are GNU coreutils), so we must not
# depend on them. Strategy, in order of preference:
#   1. native driver timeouts   — mysql --connect-timeout, mongo
#                                 serverSelectionTimeoutMS/connectTimeoutMS
#   2. `timeout` if it happens to exist (Linux, or brew coreutils)
#   3. a portable background watchdog that kills the child
# Belt and braces: a hung DNS lookup can outlast a driver-level timeout.

# Echo a timeout prefix if a suitable binary exists; otherwise echo nothing.
_dbq_timeout_prefix() {
  local secs="${DBQ_PING_TIMEOUT:-20}"
  if command -v timeout >/dev/null 2>&1; then printf 'timeout %s' "$secs"; return 0; fi
  if command -v gtimeout >/dev/null 2>&1; then printf 'gtimeout %s' "$secs"; return 0; fi
  printf ''
}

# Run "$@" under a watchdog, capturing combined output into DBQ_RUN_OUT.
# Returns the child's exit status, or 124 if the watchdog fired.
_dbq_run_guarded() {
  local secs="${DBQ_PING_TIMEOUT:-20}" tmp rc child watchdog
  tmp=$(mktemp "${TMPDIR:-/tmp}/dbq-ping.XXXXXX") || { DBQ_RUN_OUT="cannot create temp file"; return 1; }

  "$@" >"$tmp" 2>&1 &
  child=$!

  # Watchdog: sleep, then kill the child if it is still running.
  ( sleep "$secs"; kill -0 "$child" 2>/dev/null && kill -TERM "$child" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog=$!

  wait "$child" 2>/dev/null; rc=$?

  # Tear the watchdog down so it cannot outlive the check.
  kill -TERM "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null

  DBQ_RUN_OUT=$(cat "$tmp" 2>/dev/null)
  rm -f "$tmp"

  # 143 = SIGTERM: the watchdog fired.
  [ "$rc" -eq 143 ] && rc=124
  return "$rc"
}

# Add server-selection timeouts to a mongo URI so the driver itself gives up.
_dbq_mongo_uri_with_timeout() {
  local uri="$1" secs_ms
  secs_ms=$(( ${DBQ_PING_TIMEOUT:-20} * 1000 ))
  case "$uri" in
    *serverSelectionTimeoutMS=*) printf '%s' "$uri" ;;
    *\?*) printf '%s&serverSelectionTimeoutMS=%s&connectTimeoutMS=%s' "$uri" "$secs_ms" "$secs_ms" ;;
    *)    printf '%s?serverSelectionTimeoutMS=%s&connectTimeoutMS=%s' "$uri" "$secs_ms" "$secs_ms" ;;
  esac
}

# Returns 0 on a successful round-trip. Prints nothing; the caller reports.
# Sets DBQ_PING_OUT to masked diagnostic text on failure.
dbq_ping_mongo() {
  local uri="$1" rc turi
  command -v mongosh >/dev/null 2>&1 || { DBQ_PING_OUT="mongosh not installed"; return 1; }
  turi=$(_dbq_mongo_uri_with_timeout "$uri")

  __DBQ_URI="$turi" _dbq_run_guarded mongosh --nodb --quiet \
    --eval 'db = connect(process.env.__DBQ_URI); print(db.runCommand({ping:1}).ok)'
  rc=$?

  if [ "$rc" -eq 0 ] && printf '%s' "$DBQ_RUN_OUT" | grep -q '1'; then DBQ_PING_OUT=""; return 0; fi
  if [ "$rc" -eq 124 ]; then DBQ_PING_OUT="timed out after ${DBQ_PING_TIMEOUT:-20}s — VPN or firewall?"; return 1; fi
  DBQ_PING_OUT=$(dbq_ping_hint "$DBQ_RUN_OUT")
  return 1
}

# dbq_ping_mysql_direct <host> <port> <user> <pass>
# Password goes through MYSQL_PWD, never argv.
dbq_ping_mysql_direct() {
  local h="$1" p="${2:-3306}" u="$3" pw="$4" rc ct
  command -v mysql >/dev/null 2>&1 || { DBQ_PING_OUT="mysql not installed"; return 1; }
  ct="${DBQ_PING_TIMEOUT:-20}"

  MYSQL_PWD="$pw" _dbq_run_guarded mysql -h "$h" -P "$p" -u "$u" \
    --batch --skip-column-names --connect-timeout="$ct" -e 'SELECT 1'
  rc=$?

  if [ "$rc" -eq 0 ] && printf '%s' "$DBQ_RUN_OUT" | grep -q '1'; then DBQ_PING_OUT=""; return 0; fi
  if [ "$rc" -eq 124 ]; then DBQ_PING_OUT="timed out after ${ct}s — VPN or firewall?"; return 1; fi
  DBQ_PING_OUT=$(dbq_ping_hint "$DBQ_RUN_OUT")
  return 1
}

# dbq_ping_mysql_group <alias> — uses the option file, so no password in argv.
dbq_ping_mysql_group() {
  local a="$1" rc ct
  command -v mysql >/dev/null 2>&1 || { DBQ_PING_OUT="mysql not installed"; return 1; }
  ct="${DBQ_PING_TIMEOUT:-20}"

  _dbq_run_guarded mysql --defaults-file="$MYCNF" --defaults-group-suffix="-$a" \
    --batch --skip-column-names --connect-timeout="$ct" -e 'SELECT 1'
  rc=$?

  if [ "$rc" -eq 0 ] && printf '%s' "$DBQ_RUN_OUT" | grep -q '1'; then DBQ_PING_OUT=""; return 0; fi
  if [ "$rc" -eq 124 ]; then DBQ_PING_OUT="timed out after ${ct}s — VPN or firewall?"; return 1; fi
  DBQ_PING_OUT=$(dbq_ping_hint "$DBQ_RUN_OUT")
  return 1
}

# Turn raw driver noise into one actionable line.
dbq_ping_hint() {
  local out="$1"
  case "$out" in
    *"Authentication failed"*|*"Access denied"*|*"bad auth"*)
      printf 'authentication failed — wrong user or password' ;;
    *ENOTFOUND*|*"Unknown MySQL server"*|*"Name or service not known"*|*"getaddrinfo"*)
      printf 'host not found — VPN connected?' ;;
    *ETIMEDOUT*|*"timed out"*|*"Can'\''t connect"*|*"connection timed out"*)
      printf 'timed out — VPN or firewall?' ;;
    *"not authorized"*)
      printf 'connected, but user lacks permission' ;;
    *"self signed"*|*"certificate"*)
      printf 'TLS/certificate problem' ;;
    *)
      dbq_mask_uri "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-90)" ;;
  esac
}
