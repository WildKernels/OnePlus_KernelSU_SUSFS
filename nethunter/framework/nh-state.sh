#!/bin/bash
# NetHunter takeover state machine
# Usage: source nh-state.sh

NH_STATE_DIR="${NH_STATE_DIR:-/data/adb/nethunter}"
NH_LOCK_DIR="${NH_LOCK_DIR:-/data/adb/nethunter}"

nh_valid_radio() {
  case "$1" in
    wifi|bt|nfc|usb|gnss) return 0 ;;
    *) return 1 ;;
  esac
}

nh_get_state() {
  local radio="$1"
  nh_valid_radio "$radio" || { echo "IDLE"; return 0; }
  local state_file="$NH_STATE_DIR/${radio}.state"
  if [ -f "$state_file" ]; then
    cat "$state_file"
  else
    echo "IDLE"
  fi
}

nh_set_state() {
  local radio="$1"
  local state="$2"
  nh_valid_radio "$radio" || return 1
  mkdir -p "$NH_STATE_DIR"
  echo "$state" > "$NH_STATE_DIR/${radio}.state"
}

nh_acquire_lock() {
  local radio="$1"
  nh_valid_radio "$radio" || return 1
  local lockdir="$NH_LOCK_DIR/${radio}.lock"
  mkdir -p "$NH_LOCK_DIR"
  if ! mkdir "$lockdir" 2>/dev/null; then
    echo "ERROR: ${radio} already locked" >&2
    return 1
  fi
  nh_set_state "$radio" "QUIESCE"
  return 0
}

nh_release_lock() {
  local radio="$1"
  nh_valid_radio "$radio" || return 1
  local lockdir="$NH_LOCK_DIR/${radio}.lock"
  nh_set_state "$radio" "IDLE"
  rmdir "$lockdir" 2>/dev/null || true
}

nh_journal_dir() {
  nh_valid_radio "$1" || return 1
  printf '%s/%s.journal\n' "$NH_STATE_DIR" "$1"
}

# v1 radios are exclusive: Wi-Fi and Bluetooth cannot be taken over at the
# same time (and NFC/USB/GNSS inherit the same rule until proven otherwise).
nh_other_session_active() {
  local radio="$1" other
  for other in wifi bt nfc usb gnss; do
    [ "$other" = "$radio" ] && continue
    [ -e "$NH_LOCK_DIR/$other.lock" ] && return 0
  done
  return 1
}

nh_begin_session() {
  local radio="$1"
  nh_valid_radio "$radio" || return 1
  local journal
  journal=$(nh_journal_dir "$radio")

  [ ! -e "$journal" ] || {
    echo "ERROR: ${radio} recovery journal requires manual recovery" >&2
    return 1
  }
  if nh_other_session_active "$radio"; then
    echo "ERROR: another radio is in an active session; release it first" >&2
    return 1
  fi
  nh_acquire_lock "$radio" || return 1
  if ! mkdir "$journal" 2>/dev/null; then
    nh_release_lock "$radio"
    echo "ERROR: ${radio} journal already exists" >&2
    return 1
  fi
  nh_set_state "$radio" "PREPARE"
}

nh_snapshot_put() {
  local radio="$1"
  local key="$2"
  local value="$3"
  local journal
  journal=$(nh_journal_dir "$radio")

  [ -d "$journal" ] || {
    echo "ERROR: ${radio} session is not active" >&2
    return 1
  }
  case "$key" in
    *[!A-Za-z0-9_.-]*|'')
      echo "ERROR: invalid snapshot key: $key" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$value" > "$journal/$key"
}

nh_snapshot_get() {
  local radio="$1"
  local key="$2"
  local journal
  journal=$(nh_journal_dir "$radio")
  case "$key" in
    *[!A-Za-z0-9_.-]*|'') return 1 ;;
  esac
  [ -f "$journal/$key" ] || return 1
  cat "$journal/$key"
}

nh_mark_takeover() {
  nh_valid_radio "$1" || return 1
  nh_set_state "$1" "TAKEOVER"
}

nh_mark_recovery_required() {
  local radio="$1"
  local reason="$2"
  nh_valid_radio "$radio" || return 1
  local journal
  journal=$(nh_journal_dir "$radio")
  [ -d "$journal" ] || {
    echo "ERROR: ${radio} session is not active" >&2
    return 1
  }
  printf '%s\n' "$reason" > "$journal/error"
  nh_set_state "$radio" "RECOVERY_REQUIRED"
}

nh_finish_session() {
  local radio="$1"
  nh_valid_radio "$radio" || return 1
  local journal
  journal=$(nh_journal_dir "$radio")
  rm -rf "$journal"
  nh_release_lock "$radio"
}
