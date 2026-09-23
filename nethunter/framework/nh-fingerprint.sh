#!/system/bin/sh
# Fail-closed device and artifact checks. The kernel module loader is the
# runtime authority for KMI and symbol CRC compatibility.

nh_prop_get() {
  local key="$1" file="$2"
  [ -f "$file" ] || return 1
  grep -m1 "^${key}=" "$file" 2>/dev/null | cut -d= -f2-
}

nh_check_fingerprint() {
  local prop_file="$1" radio="$2" component_path="$3"
  local expected_model expected_device expected_fingerprint expected_release expected_sha
  local actual_model actual_device actual_fingerprint actual_release actual_sha

  [ -f "$prop_file" ] || { echo "INVALID_METADATA_FILE"; return 1; }
  [ -f "$component_path" ] || { echo "MISSING_COMPONENT"; return 1; }

  expected_model=$(nh_prop_get model "$prop_file" || true)
  expected_device=$(nh_prop_get device "$prop_file" || true)
  expected_fingerprint=$(nh_prop_get build_fingerprint "$prop_file" || true)
  expected_release=$(nh_prop_get kernel_release "$prop_file" || true)
  expected_sha=$(nh_prop_get "sha256_${radio}" "$prop_file" || true)

  [ -n "$expected_model" ] || { echo "MISSING_METADATA_MODEL"; return 1; }
  [ -n "$expected_device" ] || { echo "MISSING_METADATA_DEVICE"; return 1; }
  [ -n "$expected_fingerprint" ] || { echo "MISSING_METADATA_BUILD_FINGERPRINT"; return 1; }
  [ -n "$expected_release" ] || { echo "MISSING_METADATA_KERNEL_RELEASE"; return 1; }
  [ -n "$expected_sha" ] || { echo "MISSING_METADATA_SHA256"; return 1; }

  actual_model=$(nh_get_target_model)
  actual_device=$(nh_get_target_device)
  actual_fingerprint=$(nh_get_build_fingerprint)
  actual_release=$(nh_get_running_kernel_release)
  actual_sha=$(sha256sum "$component_path" 2>/dev/null | cut -d' ' -f1) || {
    echo "MISMATCH_SHA256"
    return 1
  }

  [ "$actual_model" = "$expected_model" ] || { echo "MISMATCH_MODEL"; return 1; }
  [ "$actual_device" = "$expected_device" ] || { echo "MISMATCH_DEVICE"; return 1; }
  [ "$actual_fingerprint" = "$expected_fingerprint" ] || { echo "MISMATCH_BUILD_FINGERPRINT"; return 1; }
  [ "$actual_release" = "$expected_release" ] || { echo "MISMATCH_KERNEL_RELEASE"; return 1; }
  [ "$actual_sha" = "$expected_sha" ] || { echo "MISMATCH_SHA256"; return 1; }

  echo "OK"
}

nh_get_target_model() { getprop ro.product.model 2>/dev/null || echo UNKNOWN; }
nh_get_target_device() { getprop ro.product.device 2>/dev/null || echo UNKNOWN; }
nh_get_build_fingerprint() { getprop ro.build.fingerprint 2>/dev/null || echo UNKNOWN; }
nh_get_running_kernel_release() { uname -r 2>/dev/null || echo UNKNOWN; }
