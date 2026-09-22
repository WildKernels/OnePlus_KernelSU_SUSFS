#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

resolver=scripts/resolve_sources.sh
action=.github/actions/build-kernel/action.yml
workflow=.github/workflows/build-ace5-a16.yml
config=scripts/verify_kernel_config.sh

grep -q 'vpnhide_repo' "$resolver"
grep -q 'vpnhide_builtin_sha256' "$resolver"
grep -q 'vpnhide_commit' "$action"
grep -q 'builtin/scripts/integrate.py' "$action"
grep -q 'CONFIG_VPNHIDE=y' "$config"
grep -q 'CONFIG_VPNHIDE_FS_HIDING=y' "$config"
grep -q 'vpnhide-builtin.zip' "$workflow"
grep -q 'vpnhide.apk' "$workflow"
grep -q 'releases/latest' "$resolver"
grep -q 'nomount_tag' "$resolver"
grep -q 'nomount_asset_url' "$resolver"
if grep -q 'actions/runs?branch=${nomount_branch}' "$resolver"; then
  echo 'NoMount resolver still tracks branch CI runs' >&2
  exit 1
fi
if grep -q 'ziglang.org/download' "$workflow"; then
  echo 'NoMount workflow still rebuilds a dev module' >&2
  exit 1
fi
grep -q 'NoMount release' "$workflow"
grep -q 'nomount_tag' "$workflow"

echo 'VPNHide integration contract passed'
