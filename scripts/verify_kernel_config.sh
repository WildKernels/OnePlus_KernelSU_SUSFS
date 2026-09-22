#!/usr/bin/env bash
set -euo pipefail

config="${1:?usage: verify_kernel_config.sh path/to/.config}"
source_tree="${2:?usage: verify_kernel_config.sh path/to/.config kernel/source}"

required=(
  CONFIG_KSU=y
  CONFIG_KSU_SUSFS=y
  CONFIG_KSU_SUSFS_SUS_PATH=y
  CONFIG_KSU_SUSFS_SUS_MOUNT=y
  CONFIG_KSU_SUSFS_SUS_KSTAT=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
  CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
  CONFIG_KSU_SUSFS_SUS_MAP=y
  CONFIG_NOMOUNT=y
  CONFIG_VPNHIDE=y
  CONFIG_VPNHIDE_FS_HIDING=y
  CONFIG_BBG=y
  CONFIG_LTO_CLANG=y
  CONFIG_LTO_CLANG_THIN=y
  CONFIG_TCP_CONG_BBR=y
  CONFIG_TCP_CONG_BBR3=y
  CONFIG_NET_SCH_CAKE=y
  CONFIG_NET_SCH_PIE=y
  CONFIG_NET_SCH_FQ_PIE=y
  CONFIG_WIREGUARD=y
  CONFIG_IP_SET=y
  CONFIG_IP6_NF_NAT=y
  CONFIG_IP_NF_TARGET_TTL=y
  CONFIG_IP6_NF_TARGET_HL=y
  CONFIG_TMPFS_XATTR=y
  CONFIG_TMPFS_POSIX_ACL=y
  CONFIG_UNICODE=y
  CONFIG_SYSVIPC=y
  CONFIG_POSIX_MQUEUE=y
  CONFIG_DEVTMPFS=y
  CONFIG_PID_NS=y
  CONFIG_UTS_NS=y
  CONFIG_IPC_NS=y
  CONFIG_NET_NS=y
  CONFIG_USER_NS=y
  CONFIG_NTSYNC=y
)

for expected in "${required[@]}"; do
  actual=$(grep -E "^${expected%%=*}(=| is not set)" "$config" || true)
  [[ "$actual" == "$expected" ]] || { echo "Missing config: $expected" >&2; exit 1; }
done

[[ -f "$source_tree/fs/nomount/Kconfig" ]] || { echo 'NoMount Kconfig missing' >&2; exit 1; }
[[ -f "$source_tree/fs/nomount/Makefile" ]] || { echo 'NoMount Makefile missing' >&2; exit 1; }
[[ -f "$source_tree/security/vpnhide/Kconfig" ]] || { echo 'VPNHide Kconfig missing' >&2; exit 1; }
[[ -f "$source_tree/security/vpnhide/Makefile" ]] || { echo 'VPNHide Makefile missing' >&2; exit 1; }
[[ -f "$source_tree/include/linux/vpnhide.h" ]] || { echo 'VPNHide public header missing' >&2; exit 1; }
grep -q 'source "fs/nomount/Kconfig"' "$source_tree/fs/Kconfig" || { echo 'NoMount Kconfig not wired' >&2; exit 1; }
grep -q 'obj-$(CONFIG_NOMOUNT) += nomount/' "$source_tree/fs/Makefile" || { echo 'NoMount Makefile not wired' >&2; exit 1; }
grep -q 'source "security/vpnhide/Kconfig"' "$source_tree/security/Kconfig" || { echo 'VPNHide Kconfig not wired' >&2; exit 1; }
grep -q 'obj-$(CONFIG_VPNHIDE) += vpnhide/' "$source_tree/security/Makefile" || { echo 'VPNHide Makefile not wired' >&2; exit 1; }
grep -q 'susfs_is_avc_log_spoofing_enabled' "$source_tree/security/selinux/avc.c" || { echo 'SUSFS AVC integration missing' >&2; exit 1; }
grep -q 'Check if the decomposition result is empty' "$source_tree/fs/unicode/utf8-norm.c" || { echo 'Unicode bypass patch missing' >&2; exit 1; }

echo "Kernel feature contract passed: $config"
