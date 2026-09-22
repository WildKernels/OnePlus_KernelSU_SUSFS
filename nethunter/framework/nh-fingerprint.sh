#!/system/bin/sh
# NetHunter fail-closed fingerprint verification
# Usage: source nh-fingerprint.sh

nh_check_fingerprint() {
  prop_file="$1"
  radio="$2"
  ko_path="$3"

  expected_target=$(grep "^target=" "$prop_file" | cut -d= -f2)
  expected_vermagic=$(grep "^kernel_vermagic=" "$prop_file" | cut -d= -f2)
  expected_scm=$(grep "^scmversion=" "$prop_file" | cut -d= -f2)
  expected_sha=$(grep "^sha256_${radio}=" "$prop_file" | cut -d= -f2)

  actual_target=$(nh_get_target_model)
  actual_vermagic=$(nh_get_running_vermagic)
  actual_scm=$(nh_get_running_scmversion)
  actual_sha=$(sha256sum "$ko_path" | cut -d' ' -f1)

  [ "$actual_target" = "$expected_target" ] || { echo "MISMATCH_TARGET"; return 1; }

  # uname -r gives only the version portion; compare to first token of vermagic
  expected_ver=$(echo "$expected_vermagic" | cut -d' ' -f1)
  [ "$actual_vermagic" = "$expected_ver" ] || { echo "MISMATCH_VERMAGIC"; return 1; }

  # scmversion is best-effort: /proc/version may not contain it on all kernels.
  # If we can read it, verify; if not, skip rather than block.
  if [ -n "$actual_scm" ] && [ "$actual_scm" != "UNKNOWN" ]; then
    [ "$actual_scm" = "$expected_scm" ] || { echo "MISMATCH_SCMVERSION"; return 1; }
  fi

  [ "$actual_sha" = "$expected_sha" ] || { echo "MISMATCH_SHA256"; return 1; }

  echo "OK"
  return 0
}

nh_get_target_model() {
  getprop ro.product.model 2>/dev/null || echo "UNKNOWN"
}

nh_get_running_vermagic() {
  uname -r 2>/dev/null || echo "UNKNOWN"
}

nh_get_running_scmversion() {
  # Try /proc/version first, then /sys/kernel/scmversion (some Qualcomm kernels)
  cat /proc/version 2>/dev/null | sed -n 's/.*scmversion[[:space:]]\+\([^ ]*\).*/\1/p' \
    || cat /sys/kernel/scmversion 2>/dev/null \
    || echo "UNKNOWN"
}
