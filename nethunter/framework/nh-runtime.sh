#!/system/bin/sh

: "${NH_STATE_DIR:=/data/adb/nethunter}"
: "${NH_LOCK_DIR:=$NH_STATE_DIR}"

nh_package_root() {
  printf '%s\n' "${NH_PACKAGE_ROOT:?NH_PACKAGE_ROOT must be set by the caller}"
}

nh_log() {
  local radio="$1"
  shift
  nh_valid_radio "$radio" || return 1
  mkdir -p "$NH_STATE_DIR"
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$NH_STATE_DIR/$radio.log"
}

nh_require_state() {
  local radio="$1" expected="$2" actual
  actual=$(nh_get_state "$radio")
  [ "$actual" = "$expected" ] || {
    echo "ERROR: $radio state is $actual, expected $expected" >&2
    return 1
  }
}

nh_is_enabled() {
  local radio="$1"
  case "$radio" in
    wifi) dumpsys wifi 2>/dev/null | grep -q 'Wi-Fi is operational' ;;
    bt) dumpsys bluetooth_manager 2>/dev/null | grep -q -e 'state: ON' -e 'Bluetooth is enabled' ;;
    nfc) dumpsys nfc 2>/dev/null | grep -q 'mState=on' ;;
    *) return 1 ;;
  esac
}

nh_bt_rfkill_state() {
  local output
  output=$(rfkill list bluetooth 2>/dev/null || true)
  if printf '%s\n' "$output" | grep -q 'Soft blocked: yes'; then
    printf blocked
  elif printf '%s\n' "$output" | grep -q 'Soft blocked: no'; then
    printf unblocked
  else
    printf unknown
  fi
}

nh_bt_hal_state() {
  local state
  state=$(getprop init.svc.bluetooth 2>/dev/null || true)
  if [ -z "$state" ]; then state=$(getprop init.svc.vendor.bluetooth 2>/dev/null || true); fi
  printf '%s\n' "${state:-unknown}"
}

nh_verify_stock_wifi() {
  local expected_enabled stock_hash actual_hash hal_expected hal_actual stock_ko mode_expected mode_actual
  expected_enabled=$(nh_snapshot_get wifi wifi_enabled) || return 1
  stock_hash=$(nh_snapshot_get wifi stock_module_sha256) || return 1
  hal_expected=$(nh_snapshot_get wifi hal_state) || return 1
  mode_expected=$(nh_snapshot_get wifi con_mode) || return 1
  stock_ko="${NH_VENDOR_KO:-/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko}"
  actual_hash=$(sha256sum "$stock_ko" 2>/dev/null | cut -d' ' -f1) || return 1
  [ "$actual_hash" = "$stock_hash" ] || return 1
  mode_actual=$(cat "${NH_WIFI_CON_MODE_PATH:-/sys/module/qca_cld3_kiwi_v2/parameters/con_mode}" 2>/dev/null) || return 1
  [ "$mode_actual" = "$mode_expected" ] || return 1
  if iw dev mon0 info >/dev/null 2>&1; then return 1; fi
  hal_actual=$(getprop init.svc.vendor.wifi_hal_legacy 2>/dev/null || echo unknown)
  [ "$hal_actual" = "$hal_expected" ] || return 1
  if [ "$expected_enabled" = 1 ]; then
    nh_is_enabled wifi
  else
    ! nh_is_enabled wifi
  fi
}

nh_verify_stock_bt() {
  local expected_enabled hal_expected hal_actual rfkill_expected
  expected_enabled=$(nh_snapshot_get bt bt_enabled) || return 1
  hal_expected=$(nh_snapshot_get bt hal_state) || return 1
  rfkill_expected=$(nh_snapshot_get bt rfkill_state) || return 1
  if grep -q '^hci_vhci ' /proc/modules 2>/dev/null; then return 1; fi
  hal_actual=$(nh_bt_hal_state)
  [ "$hal_actual" = "$hal_expected" ] || return 1
  [ "$(nh_bt_rfkill_state)" = "$rfkill_expected" ] || return 1
  if [ "$expected_enabled" = 1 ]; then
    nh_is_enabled bt
  else
    ! nh_is_enabled bt
  fi
}

nh_verify_stock_nfc() {
  local expected_enabled hal_expected hal_actual
  expected_enabled=$(nh_snapshot_get nfc nfc_enabled) || return 1
  hal_expected=$(nh_snapshot_get nfc hal_state) || return 1
  if [ -f "$NH_STATE_DIR/nci_raw_tool.pid" ] && kill -0 "$(cat "$NH_STATE_DIR/nci_raw_tool.pid")" 2>/dev/null; then
    return 1
  fi
  hal_actual=$(getprop init.svc.vendor.nfc_hal_service 2>/dev/null || echo unknown)
  [ "$hal_actual" = "$hal_expected" ] || return 1
  if [ "$expected_enabled" = 1 ]; then
    nh_is_enabled nfc
  else
    ! nh_is_enabled nfc
  fi
}

nh_verify_stock_usb() {
  return 1
}

nh_recover_status() {
  nh_valid_radio "$1" || return 1
  nh_get_state "$1"
}

nh_recover_verify() {
  local radio="$1" verified=1
  nh_valid_radio "$radio" || return 1
  [ -d "$(nh_journal_dir "$radio")" ] || {
    echo "ERROR: $radio recovery journal missing; stock state cannot be verified" >&2
    return 1
  }
  case "$radio" in
    wifi) nh_verify_stock_wifi || verified=0 ;;
    bt) nh_verify_stock_bt || verified=0 ;;
    nfc) nh_verify_stock_nfc || verified=0 ;;
    usb) nh_verify_stock_usb || verified=0 ;;
    *) verified=0 ;;
  esac
  if [ "$verified" != 1 ]; then
    echo "ERROR: $radio stock-state verification failed" >&2
    return 1
  fi
  printf 'OK\n'
}

nh_recover_boot() {
  local radio="$1" journal lockdir state
  nh_valid_radio "$radio" || return 1
  journal=$(nh_journal_dir "$radio")
  lockdir="$NH_LOCK_DIR/$radio.lock"
  state=$(nh_get_state "$radio")
  if [ ! -e "$journal" ] && [ ! -e "$lockdir" ] && [ "$state" = IDLE ]; then
    return 0
  fi
  if [ ! -d "$journal" ]; then
    mkdir -p "$journal"
    printf '%s\n' 'stale state has no trustworthy snapshot' > "$journal/error"
    nh_set_state "$radio" RECOVERY_REQUIRED
    return 1
  fi
  if nh_recover_verify "$radio" >/dev/null 2>&1; then
    nh_set_state "$radio" BOOT_RECOVERED
    rm -rf "$journal"
    rmdir "$lockdir" 2>/dev/null || true
    return 0
  fi
  nh_mark_recovery_required "$radio" 'stock state could not be verified during boot'
  return 1
}

nh_recover_restore() {
  local radio="$1" package_root release_script
  nh_valid_radio "$radio" || return 1
  nh_require_state "$radio" RECOVERY_REQUIRED || return 1
  package_root=$(nh_package_root) || return 1
  release_script="$package_root/$radio/nh-$radio-release.sh"
  [ -x "$release_script" ] || {
    echo "ERROR: recovery release script missing: $release_script" >&2
    return 1
  }
  NH_RECOVERY_MODE=1 NH_PACKAGE_ROOT="$package_root" \
    NH_STATE_DIR="$NH_STATE_DIR" NH_LOCK_DIR="$NH_LOCK_DIR" \
    NH_VENDOR_KO="${NH_VENDOR_KO:-}" "$release_script" || return 1
  [ "$(nh_get_state "$radio")" = IDLE ] && [ ! -e "$(nh_journal_dir "$radio")" ] || {
    echo "ERROR: $radio release returned without clearing verified recovery state" >&2
    return 1
  }
}
