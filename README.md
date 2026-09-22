# OnePlus Ace 5 Kernel

Manual build fork for OnePlus Ace 5 `PKG110` on Android 16. It builds every
Ace 5 A16 target published by the latest stable WildKernel release, currently
`android14-6.1.118` and `android14-6.1.141`.

## Included

- ReSukiSU from current `main`, resolved to a full commit before each run.
- SUSFS from the matching `android14-6.1` commit recorded in that WildKernel release.
- NoMount built into the kernel from the latest stable upstream release tag.
- VPNHide built-in backend from latest stable release, with full network and filesystem hiding.
- WildKernel BBG, BBRv1/BBRv3, CAKE/PIE, WireGuard, IP Set, IPv6 NAT, TTL,
  ThinLTO, TMPFS XATTR/ACL, Unicode fix, Droidspaces, and NTSync features.

## Run

Use **Actions > Build OnePlus Ace 5 A16 > Run workflow**.

- `publish_release=false` only uploads run artifacts.
- `publish_release=true` creates a prerelease after both kernel targets and the
  NoMount module package and VPNHide integration complete successfully.
- No workflow runs on push, pull request, schedule, tag, or upstream update.

Each run writes `resolved-sources.json` containing every full source commit,
the selected WildKernel release, the NoMount stable release tag and asset
digest, the latest stable VPNHide release and asset digests, and target matrix.

## WildKernel Updates

The fork only compiles a new stable WildKernel release when it matches the
reviewed contract in `config/wild-reviewed.json`. Before matrix builds begin,
the resolver audits the selected tag and uploads `wild-audit.json` and
`wild-audit.md` in the `resolved-sources` artifact.

The audit fails closed before compilation if WildKernel changes its build
action, source-sync action, release workflow, SUSFS release commit,
`kernel_patches` commit, Ace 5 config schema, feature contract, or target
paths. It also verifies that the audited commits match the earlier immutable
source snapshot.

To adopt a new stable release:

1. Start a branch and run the manual workflow once to get the audit report.
2. Review the upstream compare URL and port only Ace 5-relevant build changes
   into this fork's local actions. Do not execute the upstream action directly.
3. Extend `scripts/verify_kernel_config.sh` for any approved feature contract.
4. Update `config/wild-reviewed.json` with reviewed full SHAs and schema.
5. Run `GH_TOKEN="$(gh auth token)" bash tests/test_audit_wild_release.sh`.
6. Run both Ace 5 targets with `publish_release=false`; merge only when both
   kernels and the NoMount package pass.

## Artifacts

Each target has a flashable AnyKernel3 ZIP, raw `Image`, final `.config`,
summary, and SHA256 values. Releases also contain official `vpnhide-builtin.zip`
and `vpnhide.apk` assets verified against upstream SHA256 digests.

## Flashing

Flash manually only after checking firmware/KMI compatibility. Install the
VPNHide companion ZIP and APK after boot, enable its LSPosed System Framework
scope, and do not install another VPNHide native backend. Test the
`6.1.118` artifact first on a device currently running that kernel series.
Keep a known-good boot image for rollback. CI validates compilation and static
feature gates; it cannot prove boot, radio, camera, biometric, or sleep health.
