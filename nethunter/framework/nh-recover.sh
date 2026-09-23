#!/system/bin/sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NH_PACKAGE_ROOT="${NH_PACKAGE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$NH_PACKAGE_ROOT/framework/nh-state.sh"
source "$NH_PACKAGE_ROOT/framework/nh-runtime.sh"

usage() {
  echo "Usage: nh-recover.sh <status|verify|restore> <wifi|bt|nfc|usb>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
action="$1"
radio="$2"
nh_valid_radio "$radio" || usage

case "$action" in
  status) nh_recover_status "$radio" ;;
  verify) nh_recover_verify "$radio" ;;
  restore) nh_recover_restore "$radio" ;;
  *) usage ;;
esac
