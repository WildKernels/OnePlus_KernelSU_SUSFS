#!/system/bin/sh
# Bounded background log capture for device-hang diagnosis.
#
# Writes the kernel ring buffer (dmesg) and Android logcat to a persistent
# path so the last lines before a kernel hang survive and can be read after
# a forced reboot. Usage:
#   nh-logcapture.sh start
#   nh-logcapture.sh mark <label...>
#   nh-logcapture.sh status
#   nh-logcapture.sh stop
#
# Each capturer records its own PID (via `sh -c 'echo $$; exec ...'`) then
# setsid detaches it, so the stored PID is the real process and stop can kill
# it precisely.
#
# On this device `logcat -b kernel` is empty, so kernel messages must come
# from dmesg; logcat only carries the userspace HAL.

set -u

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
LOG_DIR="${NH_LOG_DIR:-$NH_STATE_DIR/logs}"
KMSG_LOG="$LOG_DIR/kernel.log"
LOGCAT_LOG="$LOG_DIR/logcat.log"
KMSG_PID="$LOG_DIR/.kmsg.pid"
LOGCAT_PID="$LOG_DIR/.logcat.pid"
LOGCAT_ROTATE_KB="${NH_LOGCAT_ROTATE_KB:-2048}"
LOGCAT_ROTATE_COUNT="${NH_LOGCAT_ROTATE_COUNT:-4}"

usage() {
  echo "Usage: nh-logcapture.sh <start|stop|status|mark> [label...]" >&2
  exit 2
}

pid_alive() {
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null
}

is_running() {
  local pid
  [ -f "$KMSG_PID" ] && { pid=$(cat "$KMSG_PID" 2>/dev/null); pid_alive "$pid" && return 0; }
  [ -f "$LOGCAT_PID" ] && { pid=$(cat "$LOGCAT_PID" 2>/dev/null); pid_alive "$pid" && return 0; }
  return 1
}

mark() {
  local msg="NH-LOG-MARK $*"
  mkdir -p "$LOG_DIR"
  # dmesg stream picks this up; logcat picks up the userspace side.
  printf '%s\n' "$msg" > /dev/kmsg 2>/dev/null || true
  log -t nethunter "$msg" 2>/dev/null || true
}

start() {
  mkdir -p "$LOG_DIR"
  if is_running; then
    echo "log capture already running"
    return 0
  fi
  # Fresh capture per run so the file tail maps to this test.
  : > "$KMSG_LOG"
  : > "$LOGCAT_LOG"
  mark "capture start pid=$$"

  # Each capturer records its own PID (the session leader) then setsid
  # detaches it, so stop can kill the whole process group precisely.
  setsid sh -c "echo \$\$ > '$KMSG_PID'; dmesg -w | grep --line-buffered -e . >> '$KMSG_LOG'" \
    </dev/null >/dev/null 2>&1 &

  setsid sh -c "echo \$\$ > '$LOGCAT_PID'; exec logcat -b all -v threadtime -f '$LOGCAT_LOG' -r $LOGCAT_ROTATE_KB -n $LOGCAT_ROTATE_COUNT" \
    </dev/null >/dev/null 2>&1 &

  sleep 1
  if ! is_running; then
    echo "ERROR: log capture failed to start" >&2
    return 1
  fi
  echo "log capture started; logs in $LOG_DIR"
}

stop() {
  local pid
  for f in "$KMSG_PID" "$LOGCAT_PID"; do
    [ -f "$f" ] || continue
    pid=$(cat "$f" 2>/dev/null)
    if pid_alive "$pid"; then
      kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$f"
  done
  mark "capture stop"
  sync
  echo "log capture stopped"
}

status() {
  if is_running; then
    echo "running"
  else
    echo "stopped"
  fi
  [ -f "$KMSG_LOG" ] && echo "kernel.log: $(wc -l < "$KMSG_LOG" 2>/dev/null) lines"
  [ -f "$LOGCAT_LOG" ] && echo "logcat.log: $(wc -l < "$LOGCAT_LOG" 2>/dev/null) lines"
}

[ "$#" -ge 1 ] || usage
case "$1" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  mark) shift; mark "$@" ;;
  *) usage ;;
esac
