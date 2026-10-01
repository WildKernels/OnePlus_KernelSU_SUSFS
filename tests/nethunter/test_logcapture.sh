#!/usr/bin/env bash
set -euo pipefail

# Runs nh-logcapture.sh against mocked device commands. Verifies that start
# records live PIDs, status reports running, stop kills both capturers and
# clears the PID files, and that a stale PID file does not read as running.

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/nethunter/framework/nh-logcapture.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0
pass() { pass=$((pass + 1)); echo "  PASS: $1"; }
fail() { fail=$((fail + 1)); echo "  FAIL: $1"; }

mockbin="$tmpdir/bin"
logdir="$tmpdir/logs"
mkdir -p "$mockbin" "$logdir"

# dmesg/logcat mock: write the pid we were given, then sleep like a follower.
cat > "$mockbin/dmesg" <<'EOF'
#!/usr/bin/env bash
echo "dmesg $*" >> "$CALLS"
# mimic `dmesg -w | grep`: emit one line and keep running
printf '[0.0] mock kernel line\n'
while :; do sleep 1; done
EOF
cat > "$mockbin/logcat" <<'EOF'
#!/usr/bin/env bash
echo "logcat $*" >> "$CALLS"
printf 'mock logcat line\n'
while :; do sleep 1; done
EOF
cat > "$mockbin/kill" <<'EOF'
#!/usr/bin/env bash
echo "kill $*" >> "$CALLS"
exec /bin/kill "$@"
EOF
chmod +x "$mockbin/dmesg" "$mockbin/logcat" "$mockbin/kill"

run() {
  env PATH="$mockbin:$PATH" CALLS="$tmpdir/calls.log" \
      NH_STATE_DIR="$tmpdir/state" NH_LOG_DIR="$logdir" \
      bash "$script" "$@"
}

: > "$tmpdir/calls.log"

if run start > "$tmpdir/start.out" 2>&1; then
  pass "start succeeds"
else
  fail "start failed: $(cat "$tmpdir/start.out")"
fi

kpid=$(cat "$logdir/.kmsg.pid" 2>/dev/null || true)
lpid=$(cat "$logdir/.logcat.pid" 2>/dev/null || true)
if [[ -n "$kpid" ]] && kill -0 "$kpid" 2>/dev/null; then
  pass "kernel capturer PID recorded and alive"
else
  fail "kernel capturer PID missing/dead: '$kpid'"
fi
if [[ -n "$lpid" ]] && kill -0 "$lpid" 2>/dev/null; then
  pass "logcat capturer PID recorded and alive"
else
  fail "logcat capturer PID missing/dead: '$lpid'"
fi

status=$(run status)
grep -q '^running' <<< "$status" && pass "status reports running" || fail "status: $status"

if run stop > "$tmpdir/stop.out" 2>&1; then
  pass "stop succeeds"
else
  fail "stop failed: $(cat "$tmpdir/stop.out")"
fi
sleep 1
if kill -0 "$kpid" 2>/dev/null; then
  fail "kernel capturer still alive after stop"
else
  pass "kernel capturer killed on stop"
fi
if kill -0 "$lpid" 2>/dev/null; then
  fail "logcat capturer still alive after stop"
else
  pass "logcat capturer killed on stop"
fi
[[ ! -e "$logdir/.kmsg.pid" && ! -e "$logdir/.logcat.pid" ]] \
  && pass "PID files cleared on stop" || fail "PID files left after stop"

status=$(run status)
grep -q '^stopped' <<< "$status" && pass "status reports stopped" || fail "status after stop: $status"

# Stale PID file must not read as running.
echo "999999" > "$logdir/.kmsg.pid"
status=$(run status)
grep -q '^stopped' <<< "$status" && pass "stale PID reads as stopped" || fail "stale PID read running: $status"
rm -f "$logdir/.kmsg.pid"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "LOG CAPTURE TESTS PASSED"
