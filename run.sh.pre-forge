#!/usr/bin/env zsh
# Whetstone task runner — same pattern as DoubleNaught's run.sh.
#
# Foreground (dev, hot reload):
#   ./run.sh FE [flutter run args...]   Flutter macOS app
#   ./run.sh BE [--clear-storage]       FastAPI card backend, auto-reload
#   ./run.sh all [flutter run args...]  BE in background, wait /health, FE foreground
#
# Managed (launchd backend + background app):
#   ./run.sh up [--cold] [--no-fe] [--fg] [--with-dn] [flutter run args...]
#   ./run.sh dn | down                  Stop the app and the backend
#   ./run.sh re [up args...]            dn, then up
#   ./run.sh status                     loaded / pid / port / health
#   ./run.sh logs [be|fe]               tail -F the logs (default: both)
#
# Ports: DoubleNaught 8400, SegForge 8401, Whetstone 8402.
# Override with WHETSTONE_PORT; the app follows it.
# Cards live in storage/cards.parquet (storage/cards.tsv is a readable mirror).

set -e

ROOT="${0:A:h}"
PROG="${0:t}"

PORT="${WHETSTONE_PORT:-8402}"
LOG_DIR="$ROOT/logs"
AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_DOMAIN="gui/$(id -u)"
LABEL="com.populi.whetstone-backend"
PLIST="$AGENT_DIR/$LABEL.plist"
BE_LOG="$LOG_DIR/whetstone-backend.log"
FE_LOG="$LOG_DIR/whetstone-frontend.log"
FE_BUILD="$ROOT/build/macos/Build/Products"
HEALTH_TIMEOUT=60
DN_ROOT="${ROOT:h}/DoubleNaught"
BE_URL="http://127.0.0.1:$PORT"

zmodload zsh/datetime 2>/dev/null || true

usage() {
  print -u2 "Usage: $PROG <command> [args...]"
  print -u2 ""
  print -u2 "  FE [flutter run args...]   Run the Whetstone app (foreground, hot reload)"
  print -u2 "  BE [--clear-storage]       Run the card backend (foreground, reload)"
  print -u2 "  all [flutter run args...]  BE in background, wait for /health, FE foreground"
  print -u2 ""
  print -u2 "  up [--cold] [--no-fe] [--fg] [--with-dn] [flutter run args...]"
  print -u2 "                             Backend as a launchd agent, then the app in the"
  print -u2 "                             BACKGROUND (--no-fe: backend only; --fg: app in"
  print -u2 "                             the foreground; --with-dn: also DoubleNaught's"
  print -u2 "                             and SegForge's backends via DN's run.sh)"
  print -u2 "  dn                         Stop the app and the backend (alias: down)"
  print -u2 "  re [up args...]            Restart: dn, then up"
  print -u2 "  status                     Backend and app report"
  print -u2 "  logs [be|fe]               tail -F the logs"
  exit 1
}

# ── helpers ──────────────────────────────────────────────────────────────────

ensure_venv() {
  if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
    print "Creating $ROOT/.venv"
    python3 -m venv "$ROOT/.venv"
  fi
  if ! "$ROOT/.venv/bin/python" -c 'import whetstone_be' >/dev/null 2>&1; then
    print "Installing backend (pip install -e backend)"
    "$ROOT/.venv/bin/pip" install -q -e "$ROOT/backend" 2>&1 | grep -v "Cache entry" || true
  fi
}

port_pids() { lsof -ti:"$1" 2>/dev/null || true }

# Free a port by asking the OS who holds it (a pidfile lies; the kernel doesn't).
sweep_port() {
  local port="$1" pids pid waited=0
  pids="$(port_pids "$port")"
  [[ -z "$pids" ]] && return 0
  for pid in ${(f)pids}; do
    print -r -- "  freeing port $port — pid $pid: $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-110)"
  done
  print -r -- "$pids" | xargs kill 2>/dev/null || true
  while (( waited < 50 )) && [[ -n "$(port_pids "$port")" ]]; do
    sleep 0.1; (( waited += 1 ))
  done
  pids="$(port_pids "$port")"
  if [[ -n "$pids" ]]; then
    print -r -- "  port $port ignored SIGTERM; sending SIGKILL"
    print -r -- "$pids" | xargs kill -9 2>/dev/null || true
    sleep 0.5
  fi
}

health_body() { curl -fsS -m 3 "$BE_URL/health" 2>/dev/null || true }
healthy()     { [[ -n "$(health_body)" ]] }

now_s() { print -r -- "${EPOCHREALTIME:-$(date +%s)}" }
elapsed_s() { printf '%.1f' "$(( $(now_s) - $1 ))" 2>/dev/null || print -r -- '?' }

wait_healthy() {
  local t0; t0="$(now_s)"
  local n=0 deadline=$(( HEALTH_TIMEOUT * 10 ))
  print -n "  waiting for /health"
  while (( n < deadline )); do
    if healthy; then
      print " ok (${$(elapsed_s "$t0")}s)"
      return 0
    fi
    (( n % 10 == 0 )) && print -n "."
    sleep 0.1; (( n += 1 ))
  done
  print " TIMEOUT after ${$(elapsed_s "$t0")}s"
  return 1
}

log_tail() {
  if [[ -s "$BE_LOG" ]]; then
    print -u2 ""
    print -u2 "── last 30 lines of $BE_LOG ──"
    tail -n 30 "$BE_LOG" >&2 || true
  else
    print -u2 "(no log output at $BE_LOG)"
  fi
}

# ── launchd backend ──────────────────────────────────────────────────────────

svc_loaded() { launchctl print "$LAUNCH_DOMAIN/$LABEL" >/dev/null 2>&1 }
svc_pid() {
  launchctl print "$LAUNCH_DOMAIN/$LABEL" 2>/dev/null \
    | awk '/^[[:space:]]*pid = /{print $3; exit}' || true
}
svc_bootout() { launchctl bootout "$LAUNCH_DOMAIN/$LABEL" >/dev/null 2>&1 || true }

xml_esc() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
  print -r -- "$s"
}

# PATH to bake, minus any */.venv/bin (the shell's active venv is an accident).
baked_path() {
  local -a parts keep; local p
  parts=("${(@s/:/)PATH}")
  for p in $parts; do
    [[ "$p" == */.venv/bin ]] && continue
    keep+=("$p")
  done
  print -r -- "${(j/:/)keep}"
}

# Rewritten on every `up` so it can never describe a path that has moved.
write_plist() {
  mkdir -p "$AGENT_DIR" "$LOG_DIR"
  local -a env_kv
  env_kv=(PATH "$(baked_path)" HOME "$HOME"
          WHETSTONE_PORT "$PORT" WHETSTONE_STORAGE "$ROOT/storage")
  {
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>'
    print -r -- '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    print -r -- '<plist version="1.0">'
    print -r -- '<dict>'
    print -r -- "  <key>Label</key><string>$(xml_esc "$LABEL")</string>"
    print -r -- '  <key>ProgramArguments</key>'
    print -r -- '  <array>'
    print -r -- "    <string>$(xml_esc "$ROOT/.venv/bin/python")</string>"
    print -r -- '    <string>-m</string>'
    print -r -- '    <string>whetstone_be</string>'
    print -r -- '  </array>'
    print -r -- "  <key>WorkingDirectory</key><string>$(xml_esc "$ROOT/backend")</string>"
    print -r -- '  <key>EnvironmentVariables</key>'
    print -r -- '  <dict>'
    local i=1
    while (( i < ${#env_kv[@]} )); do
      print -r -- "    <key>$(xml_esc "${env_kv[$i]}")</key><string>$(xml_esc "${env_kv[$((i+1))]}")</string>"
      (( i += 2 ))
    done
    print -r -- '  </dict>'
    print -r -- '  <key>RunAtLoad</key><true/>'
    # A backend that dies should stay dead and show in `status`.
    print -r -- '  <key>KeepAlive</key><false/>'
    print -r -- "  <key>StandardOutPath</key><string>$(xml_esc "$BE_LOG")</string>"
    print -r -- "  <key>StandardErrorPath</key><string>$(xml_esc "$BE_LOG")</string>"
    print -r -- '  <key>ProcessType</key><string>Interactive</string>'
    print -r -- '</dict>'
    print -r -- '</plist>'
  } > "$PLIST"
}

be_up() {
  local cold="$1"
  print ""
  print -r -- "── Whetstone backend — $LABEL (port $PORT)"
  ensure_venv
  write_plist
  print -r -- "  plist: $PLIST"

  if [[ "$cold" == 1 ]]; then
    print -r -- "  cold: booting out and sweeping the port"
    svc_bootout
    sweep_port "$PORT"
    launchctl bootstrap "$LAUNCH_DOMAIN" "$PLIST" 2>&1 | sed 's/^/  launchctl: /' || true
  elif svc_loaded; then
    if healthy; then
      print -r -- "  already loaded and healthy (pid ${$(svc_pid):-none}) — leaving it"
      return 0
    fi
    print -r -- "  loaded but not healthy — kickstart -k"
    launchctl kickstart -k "$LAUNCH_DOMAIN/$LABEL" 2>&1 | sed 's/^/  launchctl: /' || true
  else
    sweep_port "$PORT"
    launchctl bootstrap "$LAUNCH_DOMAIN" "$PLIST" 2>&1 | sed 's/^/  launchctl: /' || true
  fi

  if ! svc_loaded; then
    print -u2 "  FAILED: $LABEL did not load."
    log_tail
    return 1
  fi
  if ! wait_healthy; then
    print -u2 "  FAILED: backend did not become healthy."
    log_tail
    return 1
  fi
  print -r -- "  pid $(svc_pid) — ready"
}

# ── app (background) ─────────────────────────────────────────────────────────
# `flutter run --no-resident` builds, launches, and exits, leaving only the app.
# The app is found by where it runs from, not by a pid file.

fe_app_pids() { pgrep -f "$FE_BUILD/.*[.]app/Contents/MacOS/" 2>/dev/null || true }
fe_all_pids() { pgrep -f "$FE_BUILD" 2>/dev/null || true }

fe_up() {
  local -a fe_args; fe_args=("$@")
  local pids; pids="$(fe_app_pids)"

  print ""
  print -r -- "── Whetstone app — flutter run --no-resident (background)"
  if [[ -n "$pids" ]]; then
    print -r -- "  already running (pid ${pids//$'\n'/ }) — leaving it"
    return 0
  fi
  if ! command -v flutter >/dev/null 2>&1; then
    print -u2 "  FAILED: flutter not found on PATH."
    print -u2 "  The backend is up and staying up (./run.sh dn stops it)."
    return 1
  fi

  mkdir -p "$LOG_DIR"
  print -r -- "  log: $FE_LOG"
  print -r -- "=== $(date '+%Y-%m-%d %H:%M:%S') up ===" >> "$FE_LOG"
  ( cd "$ROOT" && flutter pub get >> "$FE_LOG" 2>&1 ) || {
    print -u2 "  FAILED: flutter pub get (see $FE_LOG)"; return 1; }

  local tool
  (
    cd "$ROOT" \
      && exec nohup flutter run -d macos --no-resident \
           --dart-define=WHETSTONE_BACKEND_URL="$BE_URL" "${fe_args[@]}" \
           >> "$FE_LOG" 2>&1 < /dev/null
  ) &!
  tool=$!

  local n=0 limit=360
  print -n "  waiting for the app"
  while (( n < limit )); do
    if ! kill -0 "$tool" 2>/dev/null; then
      sleep 3
      if [[ -n "$(fe_app_pids)" ]]; then
        print " up (pid $(fe_app_pids | tr '\n' ' '))"
        # --no-resident cannot bring the app to the front ("Failed to
        # foreground app"), and a macOS menu bar belongs to the front app.
        # `open` on a running app just activates it.
        open -a "$FE_BUILD/Debug/whetstone.app" 2>/dev/null || true
        return 0
      fi
      print " FAILED"
      print -u2 "  flutter exited and no app is running."
      print -u2 ""
      print -u2 "── last 30 lines of $FE_LOG ──"
      tail -n 30 "$FE_LOG" >&2 || true
      return 1
    fi
    (( n % 10 == 0 )) && print -n "."
    sleep 0.5; (( n += 1 ))
  done
  print " still building"
  print -r -- "  not an error: follow it with ./run.sh logs fe"
}

fe_down() {
  local pids pid waited=0
  pids="$(fe_all_pids)"
  [[ -z "$pids" ]] && return 0
  for pid in ${(f)pids}; do
    print -r -- "app: stopping pid $pid: $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-96)"
  done
  print -r -- "$pids" | xargs kill 2>/dev/null || true
  while (( waited < 50 )) && [[ -n "$(fe_all_pids)" ]]; do
    sleep 0.1; (( waited += 1 ))
  done
  pids="$(fe_all_pids)"
  if [[ -n "$pids" ]]; then
    print -r -- "app: ignored SIGTERM; sending SIGKILL to ${pids//$'\n'/ }"
    print -r -- "$pids" | xargs kill -9 2>/dev/null || true
    sleep 0.5
  fi
}

# ── up / dn / re / status / logs ─────────────────────────────────────────────

cmd_up() {
  local cold=0 want_fe=1 fg=0 with_dn=0 a
  local -a fe_args; fe_args=()
  for a in "$@"; do
    case "$a" in
      --cold)    cold=1 ;;
      --no-fe)   want_fe=0 ;;
      --fg)      fg=1 ;;
      --with-dn) with_dn=1 ;;
      *) fe_args+=("$a") ;;
    esac
  done

  if (( with_dn )); then
    if [[ -x "$DN_ROOT/run.sh" ]]; then
      print "── DoubleNaught + SegForge backends (via $DN_ROOT/run.sh up --no-fe)"
      "$DN_ROOT/run.sh" up --no-fe || { print -u2 "up: DN/SF backends failed"; exit 1; }
    else
      print -u2 "up: --with-dn given but $DN_ROOT/run.sh not found"
      exit 1
    fi
  fi

  be_up "$cold" || { print -u2 ""; print -u2 "up: backend is not healthy (see above)."; exit 1; }
  print ""
  print "up: backend healthy."

  (( want_fe )) || return 0

  if (( ! fg )); then
    fe_up "${fe_args[@]}" || exit 1
    print ""
    print "up: Whetstone is running in the background."
    print "up:   ./run.sh dn        stops it (app and backend)"
    print "up:   ./run.sh status    health;  ./run.sh logs fe|be    logs"
    return 0
  fi

  if ! command -v flutter >/dev/null 2>&1; then
    print -u2 "up: flutter not found on PATH — backend stays up (./run.sh dn stops it)."
    exit 1
  fi
  print ""
  print "Starting app in the foreground (backend stays up under launchd; Ctrl-C ends only the app)."
  cd "$ROOT"
  flutter pub get
  local fe_rc=0
  flutter run -d macos --dart-define=WHETSTONE_BACKEND_URL="$BE_URL" "${fe_args[@]}" \
    || fe_rc=$?
  if (( fe_rc != 0 && fe_rc != 130 )); then
    print -u2 "up: app exited non-zero ($fe_rc) — backend stays up."
    exit "$fe_rc"
  fi
  return 0
}

cmd_down() {
  local -a stopped
  local pid pids waited=0 s rc=0

  if svc_loaded; then
    pid="$(svc_pid)"
    svc_bootout
    stopped+=("$LABEL (was pid ${pid:-none})")
  else
    print -r -- "$LABEL: not loaded"
  fi

  # Anything else on the port (an orphan, or a foreground `BE`).
  pids="$(port_pids "$PORT")"
  if [[ -n "$pids" ]]; then
    for pid in ${(f)pids}; do
      print -r -- "port $PORT still held by pid $pid: $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-110)"
      stopped+=("pid $pid on port $PORT")
    done
    print -r -- "$pids" | xargs kill 2>/dev/null || true
    while (( waited < 50 )) && [[ -n "$(port_pids "$PORT")" ]]; do
      sleep 0.1; (( waited += 1 ))
    done
    pids="$(port_pids "$PORT")"
    if [[ -n "$pids" ]]; then
      print -r -- "port $PORT ignored SIGTERM; sending SIGKILL"
      print -r -- "$pids" | xargs kill -9 2>/dev/null || true
      sleep 0.5
    fi
  fi

  if [[ -n "$(fe_all_pids)" ]]; then
    stopped+=("Whetstone app (pids $(fe_all_pids | tr '\n' ' '))")
    fe_down
  fi

  print ""
  if (( ${#stopped[@]} )); then
    print "Stopped:"
    for s in "${stopped[@]}"; do print -r -- "  $s"; done
  else
    print "Nothing was running."
  fi

  if [[ -n "$(port_pids "$PORT")" ]]; then
    print -u2 "port $PORT is STILL held by $(port_pids "$PORT" | tr '\n' ' ')"; rc=1
  else
    print -r -- "port $PORT: free"
  fi
  if [[ -n "$(fe_all_pids)" ]]; then
    print -u2 "Whetstone app is STILL running: $(fe_all_pids | tr '\n' ' ')"; rc=1
  else
    print -r -- "Whetstone app: stopped"
  fi
  (( rc )) && exit 1
  return 0
}

cmd_re() {
  cmd_down
  cmd_up "$@"
}

cmd_status() {
  local pid h tag body holders
  print ""
  print -r -- "── Whetstone backend — $LABEL (port $PORT)"
  if svc_loaded; then
    pid="$(svc_pid)"
    print -r -- "  launchd: loaded, pid ${pid:-none (loaded but not running)}"
  else
    pid=""
    print -r -- "  launchd: not loaded"
  fi
  holders="$(port_pids "$PORT")"
  if [[ -z "$holders" ]]; then
    print -r -- "  port:    free"
  else
    for h in ${(f)holders}; do
      if [[ -n "$pid" && "$h" == "$pid" ]]; then tag="launchd-managed"
      else tag="NOT managed by launchd (foreground BE or orphan)"; fi
      print -r -- "  port:    pid $h [$tag]"
      print -r -- "           $(ps -o command= -p "$h" 2>/dev/null | cut -c1-96)"
    done
  fi
  body="$(health_body)"
  if [[ -z "$body" ]]; then print -r -- "  health:  no answer"
  else print -r -- "  health:  $(print -r -- "$body" | cut -c1-96)"; fi
  print -r -- "  log:     $BE_LOG"
  print ""
  print -r -- "── Whetstone app"
  if [[ -n "$(fe_app_pids)" ]]; then
    print -r -- "  running, pid $(fe_app_pids | tr '\n' ' ')"
  else
    print -r -- "  not running"
  fi
  print -r -- "  log:     $FE_LOG"
  print ""
}

cmd_logs() {
  local -a files
  case "${1:-both}" in
    be) files=("$BE_LOG") ;;
    fe) files=("$FE_LOG") ;;
    both) files=("$BE_LOG" "$FE_LOG") ;;
    *) print -u2 "logs: expected be, fe, or nothing"; exit 1 ;;
  esac
  mkdir -p "$LOG_DIR"
  local f; for f in "${files[@]}"; do [[ -e "$f" ]] || : > "$f"; done
  print -r -- "tail -F ${files[*]}"
  exec tail -F "${files[@]}"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

cmd="$1"
[[ -z "$cmd" ]] && usage
shift

case "$cmd" in
  FE)
    cd "$ROOT"
    flutter pub get
    exec flutter run -d macos --dart-define=WHETSTONE_BACKEND_URL="$BE_URL" "$@"
    ;;
  BE)
    local_args=()
    for a in "$@"; do
      if [[ "$a" == "--clear-storage" ]]; then
        print "Removing $ROOT/storage/cards.parquet and cards.tsv"
        rm -f "$ROOT/storage/cards.parquet" "$ROOT/storage/cards.tsv"
      else
        local_args+=("$a")
      fi
    done
    ensure_venv
    sweep_port "$PORT"
    print "Starting backend on $BE_URL  (docs: $BE_URL/docs)"
    cd "$ROOT/backend"
    export WHETSTONE_PORT="$PORT" WHETSTONE_RELOAD=1
    exec "$ROOT/.venv/bin/python" -m whetstone_be "${local_args[@]}"
    ;;
  all)
    ensure_venv
    sweep_port "$PORT"
    print "Starting backend on $BE_URL"
    (
      cd "$ROOT/backend"
      export WHETSTONE_PORT="$PORT"
      exec "$ROOT/.venv/bin/python" -m whetstone_be
    ) &
    be_pid=$!
    trap 'kill $be_pid 2>/dev/null || true' EXIT INT TERM
    print -n "Waiting for /health"
    ok=0
    for _ in {1..120}; do
      if ! kill -0 $be_pid 2>/dev/null; then
        print ""; print -u2 "Backend exited during startup."; wait $be_pid || true; exit 1
      fi
      if healthy; then ok=1; break; fi
      print -n "."; sleep 0.5
    done
    print ""
    [[ $ok -eq 1 ]] || { print -u2 "Backend did not become healthy within 60s."; exit 1 }
    print "Backend healthy."
    cd "$ROOT"
    flutter pub get
    flutter run -d macos --dart-define=WHETSTONE_BACKEND_URL="$BE_URL" "$@"
    ;;
  up)      cmd_up "$@" ;;
  re)      cmd_re "$@" ;;
  dn|down) cmd_down ;;
  status)  cmd_status ;;
  logs)    cmd_logs "$@" ;;
  STOP)    cmd_down ;;
  *)
    print -u2 "Unknown command: $cmd"
    usage
    ;;
esac
