#!/usr/bin/env bash
set -euo pipefail

repo="${WILD_REPO:-WildKernels/OnePlus_KernelSU_SUSFS}"
resukisu_repo="${RESUKISU_REPO:-ReSukiSU/ReSukiSU}"
nomount_repo="${NOMOUNT_REPO:-maxsteeel/nomount}"
kernel_patches_repo="${KERNEL_PATCHES_REPO:-WildKernels/kernel_patches}"
vpnhide_repo="${VPNHIDE_REPO:-okhsunrog/vpnhide}"
wild_release_json=$(mktemp)
trap 'rm -f "$wild_release_json"' EXIT

api() {
  local headers=(
    -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28'
  )
  if [[ -n "${GH_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
  fi
  curl --fail --silent --show-error --location "${headers[@]}" "$1"
}

resolve_ref() {
  local repository="$1" ref="$2"
  git ls-remote "https://github.com/${repository}.git" "refs/heads/${ref}" "refs/tags/${ref}" "refs/tags/${ref}^{}" |
    awk '{ print $1 }' | tail -n1
}

api "https://api.github.com/repos/${repo}/releases?per_page=100" > "$wild_release_json"
wild_release=$(jq -c '[.[] | select(.draft == false and .prerelease == false)][0] // empty' "$wild_release_json")
wild_tag=$(jq -r '.tag_name // empty' <<< "$wild_release")
[[ -n "$wild_tag" ]] || { echo 'No stable WildKernel release found' >&2; exit 1; }
wild_sha=$(resolve_ref "$repo" "$wild_tag")
[[ "$wild_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Cannot resolve WildKernel tag $wild_tag" >&2; exit 1; }

release_body=$(jq -r '.body // ""' <<< "$wild_release")
wild_published_at=$(jq -r '.published_at // empty' <<< "$wild_release")
[[ -n "$wild_published_at" ]] || { echo "Missing publish time for $wild_tag" >&2; exit 1; }
# SUSFS: Fetch directly from upstream GitLab (simonpunk/susfs4ksu) instead of WildKernels
# Uses gki-android14-6.1 branch HEAD for latest KernelSU compatibility (v2.3.0+)
susfs_sha=$(curl --fail --silent --show-error \
  "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/branches/gki-android14-6.1" | \
  jq -r '.commit.id // empty')
[[ "$susfs_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Cannot resolve SUSFS upstream branch gki-android14-6.1" >&2; exit 1; }
echo "SUSFS upstream: simonpunk/susfs4ksu@gki-android14-6.1 (${susfs_sha:0:8})" >&2

resukisu_sha=$(api "https://api.github.com/repos/${resukisu_repo}/commits/main" | jq -r '.sha // empty')
[[ "$resukisu_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Cannot resolve ReSukiSU main' >&2; exit 1; }

nomount_release=$(api "https://api.github.com/repos/${nomount_repo}/releases/latest")
nomount_tag=$(jq -r '.tag_name // empty' <<< "$nomount_release")
[[ -n "$nomount_tag" ]] || { echo "No latest NoMount release found in $nomount_repo" >&2; exit 1; }
if ! jq -e '.draft == false and .prerelease == false' <<< "$nomount_release" >/dev/null; then
  echo "Latest NoMount release is draft or prerelease: $nomount_tag" >&2
  exit 1
fi
nomount_sha=$(resolve_ref "$nomount_repo" "$nomount_tag")
[[ "$nomount_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Cannot resolve NoMount tag $nomount_tag" >&2; exit 1; }
nomount_asset=$(jq -er --arg name "NoMount-${nomount_tag}-release.zip" '
  [.assets[] | select(.name == $name)] as $matches |
  if ($matches | length) != 1 then error("expected one NoMount asset: " + $name)
  elif (($matches[0].digest // "") | test("^sha256:[0-9a-f]{64}$") | not) then error("NoMount asset lacks SHA-256 digest")
  else {url:$matches[0].browser_download_url,sha256:($matches[0].digest | sub("^sha256:"; ""))}
  end
' <<< "$nomount_release")

kernel_patches_sha=$(api "https://api.github.com/repos/${kernel_patches_repo}/commits?sha=main&until=${wild_published_at}&per_page=1" | jq -r '.[0].sha // empty')
[[ "$kernel_patches_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Cannot resolve kernel_patches main' >&2; exit 1; }

vpnhide_release=$(api "https://api.github.com/repos/${vpnhide_repo}/releases/latest")
vpnhide_tag=$(jq -r '.tag_name // empty' <<< "$vpnhide_release")
[[ -n "$vpnhide_tag" ]] || { echo "No latest VPNHide release found in $vpnhide_repo" >&2; exit 1; }
if ! jq -e '.draft == false and .prerelease == false' <<< "$vpnhide_release" >/dev/null; then
  echo "Latest VPNHide release is draft or prerelease: $vpnhide_tag" >&2
  exit 1
fi
vpnhide_sha=$(resolve_ref "$vpnhide_repo" "$vpnhide_tag")
[[ "$vpnhide_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Cannot resolve VPNHide tag $vpnhide_tag" >&2; exit 1; }
vpnhide_asset() {
  local name="$1"
  jq -er --arg name "$name" '
    [.assets[] | select(.name == $name)] as $matches |
    if ($matches | length) != 1 then error("expected one asset: " + $name)
    elif (($matches[0].digest // "") | test("^sha256:[0-9a-f]{64}$") | not) then error("asset lacks SHA-256 digest: " + $name)
    else {url:$matches[0].browser_download_url,sha256:($matches[0].digest | sub("^sha256:"; ""))}
    end
  ' <<< "$vpnhide_release"
}
vpnhide_builtin=$(vpnhide_asset 'vpnhide-builtin.zip')
vpnhide_apk=$(vpnhide_asset 'vpnhide.apk')

bbg_repo='vc-teahouse/Baseband-guard'
bbg_sha=$(api "https://api.github.com/repos/${bbg_repo}/commits/main" | jq -r '.sha // empty')
[[ "$bbg_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Cannot resolve Baseband Guard main' >&2; exit 1; }

loader_repo='maxsteeel/ko-loader'
loader_sha=$(api "https://api.github.com/repos/${loader_repo}/commits/main" | jq -r '.sha // empty')
[[ "$loader_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Cannot resolve ko-loader main' >&2; exit 1; }

configs=$(api "https://api.github.com/repos/${repo}/git/trees/${wild_sha}?recursive=1" |
  jq -c '[.tree[] | select(.path | test("^configs/a16/OP-ACE-5(-[0-9]+\\.[0-9]+\\.[0-9]+)?\\.json$")) | .path]')
[[ "$configs" != '[]' ]] || { echo "No Ace 5 A16 configs in $wild_tag" >&2; exit 1; }

manifests=$(api "https://api.github.com/repos/${repo}/git/trees/${wild_sha}?recursive=1" |
  jq -c '[.tree[] | select(.path | test("^manifests/a16/oneplus_ace5(_[0-9]+\\.[0-9]+\\.[0-9]+)?_w\\.xml$")) | .path]')
[[ "$manifests" != '[]' ]] || { echo "No Ace 5 A16 manifests in $wild_tag" >&2; exit 1; }

  jq -n \
  --arg wild_repo "$repo" \
  --arg wild_tag "$wild_tag" \
  --arg wild_sha "$wild_sha" \
  --arg wild_published_at "$wild_published_at" \
  --arg susfs_sha "$susfs_sha" \
  --arg resukisu_repo "$resukisu_repo" \
  --arg resukisu_sha "$resukisu_sha" \
  --arg nomount_repo "$nomount_repo" \
   --arg nomount_tag "$nomount_tag" \
   --arg nomount_sha "$nomount_sha" \
   --arg nomount_asset_url "$(jq -r '.url' <<< "$nomount_asset")" \
   --arg nomount_asset_sha256 "$(jq -r '.sha256' <<< "$nomount_asset")" \
  --arg kernel_patches_repo "$kernel_patches_repo" \
  --arg kernel_patches_sha "$kernel_patches_sha" \
  --arg vpnhide_repo "$vpnhide_repo" \
  --arg vpnhide_tag "$vpnhide_tag" \
  --arg vpnhide_sha "$vpnhide_sha" \
  --arg vpnhide_builtin_url "$(jq -r '.url' <<< "$vpnhide_builtin")" \
  --arg vpnhide_builtin_sha256 "$(jq -r '.sha256' <<< "$vpnhide_builtin")" \
  --arg vpnhide_apk_url "$(jq -r '.url' <<< "$vpnhide_apk")" \
  --arg vpnhide_apk_sha256 "$(jq -r '.sha256' <<< "$vpnhide_apk")" \
  --arg bbg_repo "$bbg_repo" \
  --arg bbg_sha "$bbg_sha" \
  --arg loader_repo "$loader_repo" \
  --arg loader_sha "$loader_sha" \
  --argjson configs "$configs" \
  --argjson manifests "$manifests" \
  '{wild_repo:$wild_repo,wild_release:$wild_tag,wild_sha:$wild_sha,wild_published_at:$wild_published_at,susfs_sha:$susfs_sha,
    resukisu_repo:$resukisu_repo,resukisu_sha:$resukisu_sha,
      nomount_repo:$nomount_repo,nomount_tag:$nomount_tag,nomount_sha:$nomount_sha,
      nomount_asset_url:$nomount_asset_url,nomount_asset_sha256:$nomount_asset_sha256,
     kernel_patches_repo:$kernel_patches_repo,kernel_patches_sha:$kernel_patches_sha,
     vpnhide_repo:$vpnhide_repo,vpnhide_tag:$vpnhide_tag,vpnhide_sha:$vpnhide_sha,
     vpnhide_builtin_url:$vpnhide_builtin_url,vpnhide_builtin_sha256:$vpnhide_builtin_sha256,
     vpnhide_apk_url:$vpnhide_apk_url,vpnhide_apk_sha256:$vpnhide_apk_sha256,
     bbg_repo:$bbg_repo,bbg_sha:$bbg_sha,
    loader_repo:$loader_repo,loader_sha:$loader_sha,
    configs:$configs,manifests:$manifests}'
