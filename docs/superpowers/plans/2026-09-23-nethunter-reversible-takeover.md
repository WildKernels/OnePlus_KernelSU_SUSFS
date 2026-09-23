# NetHunter Reversible Hardware Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a reversible NetHunter hardware-control package for OnePlus Ace 5 that uses built-in Wi-Fi, Bluetooth, NFC, USB, and GNSS capabilities while restoring Android ownership without routine reboot.

**Architecture:** Wi-Fi, Bluetooth, NFC, and USB use one journaled exclusive-session manager. GNSS remains an Android-owned shared bridge until an exact-device low-level handoff is proven. Temporary modules are preferred; vendor-driver patches are next; a kernel Image change is used only when a module cannot provide the required hook. Every claimed capability is gated by exact-device evidence rather than compilation alone.

**Tech Stack:** Android/Linux shell, C, Linux kernel Kbuild, Clang/LLD, `Module.symvers`, AArch64 Android NDK, ReSukiSU module format, GitHub Actions, `jq`, `modinfo`, `file`, ConfigFS, Android `dumpsys`/`cmd`/`svc`.

**Spec:** `docs/superpowers/specs/2026-09-23-nethunter-reversible-takeover-design.md`

## Global Constraints

- Do not write replacement modules into `/vendor_dlkm`.
- Normal acquire/release must not reboot and normal release target is 30 seconds or less.
- Reboot is recovery fallback only; no boot-time auto-acquire.
- Wi-Fi, Bluetooth, NFC, and USB exclusive sessions share one global exclusion lock in v1.
- GNSS remains Android-owned in the first bridge mode.
- Build modules from the same target source workspace and KMI evidence as the Image.
- `Module.symvers` from a full build is required; `modules_prepare` alone is invalid.
- The real Bluetooth module name is `hci_vhci.ko`; `bt_vhci.ko` must not appear in new runtime/build paths.
- Wi-Fi injection patches must be ported against the exact target source; upstream commits are references, not drop-in patches.
- NFC is labeled exclusive only when driver ownership or an equivalent exact-device proof prevents concurrent opens.
- Package metadata must distinguish build target from Android model and must contain real component hashes.
- A package cannot claim `SUPPORTED` from a successful build without exact-device runtime and restore evidence.
- Cellular/baseband, GPU, camera, sensor, NFC eSE/card emulation, and unsupported proprietary Bluetooth offload remain out of scope.

## Review Focus

1. **Installed package root and metadata identity:** a package installed under a target-specific `MODPATH` must load modules and compare metadata against the actual device model/codename. Pin this in Task 1 and Task 9 package-layout tests.
2. **KMI/source mismatch:** a module built from the wrong source or incomplete `Module.symvers` must fail before packaging. Pin this in Task 3 build-contract tests.
3. **Partial acquire failure:** a failure after service stop or module load must restore every snapshot, or leave `RECOVERY_REQUIRED` with the journal intact. Pin this in Task 2 and each radio session test.
4. **NFC concurrent open:** a second owner must receive `EBUSY` when exclusive mode is claimed. Pin this in Task 5 with two independent open processes.
5. **Android reconfiguration race:** USB or GNSS framework activity must not silently overwrite a NetHunter session; the session must detect mismatch and restore or enter recovery. Pin this in Task 7 and Task 8.

---

## Task 1: Establish Exact-Device Baseline and Metadata Contract

**Files:**
- Modify: `scripts/nethunter/probe_device.sh`
- Create: `scripts/nethunter/validate_device_profile.sh`
- Create: `tests/nethunter/test_device_profile_contract.sh`
- Create: `docs/nethunter/device-profile.schema.json`
- Modify: `nethunter/module/module.prop.template`
- Create: `docs/nethunter/device-profile.example.json`

**Interfaces:**
- Consumes: ADB device, `jq`, Android `getprop`, `uname`, `modinfo`, `dumpsys`, `iw`, `rfkill`, ConfigFS, service list.
- Produces: `device-profile.json` with `schema_version: 2`; validator exit code 0/1; module metadata fields `device`, `model`, `build_fingerprint`, `kernel_release`, and `config_sha256`.

- [ ] **Step 1: Write the failing profile contract test.**

Create a fixture with these required JSON paths:

```json
{
  "schema_version": 2,
  "device": {
    "model": "ONEPLUS PKG110",
    "codename": "pineapple",
    "build_fingerprint": "oneplus/PKG110/PKG110:16/TEST/release-keys"
  },
  "kernel": {
    "release": "6.1.174-g638ecc425319",
    "architecture": "aarch64"
  },
  "modules": {
    "wifi": {"path": "/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko", "sha256": "fixture"},
    "bluetooth": {"vhci_name": "hci_vhci.ko"},
    "nfc": {"path": "/vendor_dlkm/lib/modules/nxp-nci.ko"}
  },
  "usb": {"config": "mtp,adb"},
  "gnss": {"service": "android.hardware.gnss.IGnss/default"}
}
```

Run `bash tests/nethunter/test_device_profile_contract.sh` before creating the validator. It must fail because `validate_device_profile.sh` does not exist.

- [ ] **Step 2: Implement the validator.**

`validate_device_profile.sh <profile>` must:

```bash
set -euo pipefail
profile=${1:?usage: validate_device_profile.sh <profile.json>}
jq -e '
  .schema_version == 2 and
  (.device.model | length > 0) and
  (.device.codename | length > 0) and
  (.device.build_fingerprint | length > 0) and
  (.kernel.release | length > 0) and
  .kernel.architecture == "aarch64" and
  .modules.wifi.path == "/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko" and
  .modules.bluetooth.vhci_name == "hci_vhci.ko" and
  (.usb.config | type == "string") and
  (.gnss.service | length > 0)
' "$profile" >/dev/null
```

Also reject malformed JSON, a non-AArch64 architecture, or an empty kernel release. Print one failing JSON path to stderr and exit non-zero.

- [ ] **Step 3: Extend the read-only probe.**

Update `probe_device.sh` to emit schema version 2 and collect:

- `ro.product.model`, `ro.product.device`, build fingerprints, incremental version, and slot.
- `uname -r`, `uname -m`, `/proc/version`, SELinux mode.
- Wi-Fi module SHA-256, `modinfo`, loaded dependencies, interfaces, phys, and `con_mode`.
- Bluetooth HAL registrations, rfkill, `/dev/vhci`, and `dumpsys bluetooth_manager`.
- NFC node, driver/module info, `dumpsys nfc`, NFC properties, and HAL service state.
- USB config, roles, ConfigFS gadgets, active UDCs, and available functions.
- GNSS service registration and `dumpsys location` summary.

Use atomic output (`mktemp` plus `mv`) and keep the command read-only. A missing optional probe must produce an empty field with an explicit `availability` value, not abort the complete profile.

- [ ] **Step 4: Define module metadata fields.**

Replace the ambiguous template fields with:

```text
id=nethunter_takeover_@@TARGET@@
name=NetHunter Hardware Control @@TARGET@@
version=@@VERSION@@
versionCode=@@VERSION_CODE@@
target=@@TARGET@@
device=@@DEVICE_CODENAME@@
model=@@DEVICE_MODEL@@
build_fingerprint=@@BUILD_FINGERPRINT@@
kernel_release=@@KERNEL_RELEASE@@
config_sha256=@@CONFIG_SHA256@@
sha256_wifi=@@SHA_QCA@@
sha256_btvhci=@@SHA_BTVHCI@@
sha256_nxp_nci=@@SHA_NXP_NCI@@
capability_wifi=@@CAPABILITY_WIFI@@
capability_bt=@@CAPABILITY_BT@@
capability_nfc=@@CAPABILITY_NFC@@
capability_usb=@@CAPABILITY_USB@@
capability_gnss=@@CAPABILITY_GNSS@@
```

- [ ] **Step 5: Run the contract tests.**

Run:

```bash
bash tests/nethunter/test_device_profile_contract.sh
bash tests/nethunter/test_probe_device.sh
bash -n scripts/nethunter/probe_device.sh scripts/nethunter/validate_device_profile.sh
```

Expected: all pass. Run the real probe only after ADB reports a connected device:

```bash
ADB=/mnt/c/Users/Administrator/scoop/shims/adb.exe \
  bash scripts/nethunter/probe_device.sh docs/nethunter/device-profile.json
bash scripts/nethunter/validate_device_profile.sh docs/nethunter/device-profile.json
```

- [ ] **Step 6: Commit the baseline contract.**

```bash
git add scripts/nethunter/probe_device.sh scripts/nethunter/validate_device_profile.sh \
  tests/nethunter/test_device_profile_contract.sh docs/nethunter \
  nethunter/module/module.prop.template
git commit -m "feat(nethunter): define exact-device profile and metadata contract"
```

---

## Task 2: Harden Session, Recovery, and Package-Root Handling

**Files:**
- Modify: `nethunter/framework/nh-state.sh`
- Modify: `nethunter/framework/nh-fingerprint.sh`
- Create: `nethunter/framework/nh-runtime.sh`
- Create: `nethunter/framework/nh-recover.sh`
- Modify: `nethunter/wifi/nh-wifi-acquire.sh`
- Modify: `nethunter/wifi/nh-wifi-release.sh`
- Modify: `nethunter/bt/nh-bt-acquire.sh`
- Modify: `nethunter/bt/nh-bt-release.sh`
- Modify: `nethunter/nfc/nh-nfc-acquire.sh`
- Modify: `nethunter/nfc/nh-nfc-release.sh`
- Modify: `nethunter/module/post-fs-data.sh`
- Modify: `nethunter/module/customize.sh`
- Create: `tests/nethunter/test_recovery_contract.sh`
- Modify: `tests/nethunter/test_nh_state.sh`

**Interfaces:**
- Consumes: profile metadata from Task 1.
- Produces: `nh_begin_session`, `nh_snapshot_put`, `nh_snapshot_get`, `nh_mark_takeover`, `nh_mark_recovery_required`, `nh_finish_session`, `nh_recover_status`, `nh_recover_restore`, `nh_recover_verify`, `nh_package_root`, and `nh_log`.

- [ ] **Step 1: Add failing recovery tests.**

Extend state tests with these cases:

```bash
begin_session wifi
mark_takeover wifi
mark_recovery_required wifi "module unload failed"
! begin_session bt
recover_status wifi | grep -q RECOVERY_REQUIRED
```

Add a boot-recovery fixture where a stale journal exists but all resource probes report stock. The test must require an explicit `BOOT_RECOVERED` transition before journal deletion. Add a second fixture where a patched module is still loaded; the test must retain `RECOVERY_REQUIRED`.

Run `bash tests/nethunter/test_recovery_contract.sh`; it must fail before implementation.

- [ ] **Step 2: Implement common runtime paths.**

`nh-runtime.sh` must provide:

```sh
nh_package_root() {
  printf '%s\n' "${NH_PACKAGE_ROOT:?NH_PACKAGE_ROOT must be set by the caller}"
}

nh_log() {
  radio="$1"
  shift
  mkdir -p "$NH_STATE_DIR"
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$NH_STATE_DIR/$radio.log"
}

nh_require_state() {
  radio="$1"
  expected="$2"
  [ "$(nh_get_state "$radio")" = "$expected" ] || {
    echo "ERROR: $radio state is $(nh_get_state "$radio"), expected $expected" >&2
    return 1
  }
}
```

Radio scripts must set `NH_PACKAGE_ROOT` from their installed directory before sourcing runtime helpers. The default module binary path must derive from `NH_PACKAGE_ROOT/system/bin` or `NH_PACKAGE_ROOT/vendor_dlkm_override`, never from a guessed generic module directory.

- [ ] **Step 3: Make recovery state explicit.**

Add `nh_recover_status`, `nh_recover_verify`, and `nh_recover_restore` to the framework. `nh_recover_verify` must check:

- No NetHunter takeover module remains loaded.
- Relevant Android service is running.
- Saved enabled/disabled state matches the journal.
- Resource-specific health command succeeds.

`nh_recover_restore` may perform only the resource-specific release path and must leave the journal when verification fails. It may remove the journal only after `nh_recover_verify` returns zero.

- [ ] **Step 4: Replace unsafe boot cleanup.**

Rewrite `post-fs-data.sh` so it calls recovery verification for every journaled resource. It must never do this unconditionally:

```sh
rm -f /data/adb/nethunter/*.lock
echo IDLE > /data/adb/nethunter/*.state
```

A stale journal with unverified state must become `RECOVERY_REQUIRED`, not `IDLE`.

- [ ] **Step 5: Correct fingerprint behavior.**

Update `nh-fingerprint.sh` to compare:

- Metadata `model` to `getprop ro.product.model`.
- Metadata `device` to `getprop ro.product.device`.
- Metadata `build_fingerprint` according to exact or approved-family policy.
- Metadata `kernel_release` to `uname -r`.
- Component SHA-256 to the packaged file.

Use the module loader and symbol CRC result as the KMI gate. Record unavailable runtime scmversion as `unknown` provenance instead of treating it as a successful match.

- [ ] **Step 6: Update Wi-Fi, Bluetooth, and NFC scripts to the common paths.**

Each script must:

1. Resolve `NH_PACKAGE_ROOT`.
2. Source `nh-state.sh`, `nh-runtime.sh`, and fingerprint helpers.
3. Snapshot before touching Android.
4. Keep the journal until restore verification passes.
5. Leave `RECOVERY_REQUIRED` on failed restore.

- [ ] **Step 7: Run recovery tests and all existing host tests.**

```bash
bash tests/nethunter/test_recovery_contract.sh
bash tests/nethunter/test_nh_state.sh
bash tests/nethunter/test_wifi_session.sh
bash tests/nethunter/test_bt_session.sh
bash tests/nethunter/test_nfc_session.sh
```

- [ ] **Step 8: Commit the recovery foundation.**

```bash
  nethunter/nfc tests/nethunter
git commit -m "feat(nethunter): harden journal recovery and package paths"
```

---

## Task 3: Build Modules from One Exact Kernel Workspace

**Files:**
- Create: `scripts/nethunter/build_target_modules.sh`
- Modify: `scripts/nethunter/build_stock_wifi.sh`
- Modify: `scripts/nethunter/build_btvhci.sh`
- Create: `scripts/nethunter/build_nxp_nci.sh`
- Modify: `.github/actions/build-nethunter-takeover/action.yml`
- Modify: `.github/workflows/build-nethunter.yml`
- Create: `tests/nethunter/test_build_contract.sh`
- Create: `docs/nethunter/build-evidence.md`

**Interfaces:**
- Consumes: target source root, common kernel output, target `.config`, full `Module.symvers`, target revision map.
- Produces: `/tmp/nh-build/<target>/qca_cld3_kiwi_v2.ko`, `hci_vhci.ko`, optional `nxp-nci.ko`, build evidence JSON, and explicit failure codes.

- [ ] **Step 1: Write failing build-contract tests.**

`test_build_contract.sh` must create fake workspaces and verify the build entrypoint rejects:

- Missing `KERNEL_SRC`.
- Missing `.config`.
- Missing `Module.symvers`.
- Non-git source tree.
- Wrong target revision.
- Wrong-architecture module artifact.
- A package request with no required component.

It must also accept a fixture with:

```text
KERNEL_SRC=/fixture/kernel
COMMON_OUT=/fixture/kernel/kernel_platform/common/out
TARGET=OP-ACE-5
MODULES_REV=fixture-modules-rev
COMMON_REV=fixture-common-rev
```

- [ ] **Step 2: Define the module build entrypoint.**

`build_target_modules.sh` must accept exactly:

```text
build_target_modules.sh <target> <kernel_src> <common_out> <output_dir>
```

It must verify:

```bash
test -f "$common_out/.config"
test -f "$common_out/Module.symvers"
git -C "$kernel_src" rev-parse HEAD
```

The target revision table must contain the two known targets and their common/modules revisions. A mismatched revision exits before any build.

- [ ] **Step 3: Build `hci_vhci.ko` in an isolated module output.**

Copy the production `.config` to a NetHunter module output directory, set `CONFIG_BT_HCIVHCI=m`, run `olddefconfig`, and build only `drivers/bluetooth`. Do not mutate the production output in place. Verify the result exists at:

```text
<output_dir>/hci_vhci.ko
```

Verify `modinfo -F name` returns `hci_vhci` and reject any output named `bt_vhci.ko`.

- [ ] **Step 4: Build the unmodified Wi-Fi module.**

Update `build_stock_wifi.sh` to consume the explicit workspace arguments and use the full target `Module.symvers`. Verify the source revision before Kbuild. Output only the copied artifact and a JSON record containing source revision, config hash, vermagic, dependencies, and SHA-256.

- [ ] **Step 5: Add the NFC driver build entrypoint.**

`build_nxp_nci.sh` must accept the same target/workspace arguments, build the unmodified driver first, and reject missing `Module.symvers`. The pinned source path is `$KERNEL_SRC/vendor/nxp/opensource/driver`; its Kbuild emits `nxp-nci.ko`. With `--patched-source <patch_file>`, build stock baseline as `nxp-nci-stock.ko`, then apply the patch to a temporary source copy and build patched artifact as `nxp-nci.ko`.

- [ ] **Step 6: Move takeover build into the kernel build workspace.**

Modify the workflow so the takeover action runs after the kernel action in the same matrix job, or explicitly re-syncs the exact source revision before module build. The action must receive:

```yaml
target: ${{ matrix.model }}
kernel_src: <same source root used by build-kernel>
common_out: <same common output used by build-kernel>
version: ${{ github.run_number }}
```

Remove the current assumption that downloading only `.config`, `Module.symvers`, and Image supplies enough source to build modules.

- [ ] **Step 7: Run build-contract and YAML checks.**

```bash
bash tests/nethunter/test_build_contract.sh
bash -n scripts/nethunter/build_target_modules.sh \
  scripts/nethunter/build_stock_wifi.sh \
  scripts/nethunter/build_btvhci.sh \
  scripts/nethunter/build_nxp_nci.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build-nethunter.yml"); YAML.load_file(".github/actions/build-nethunter-takeover/action.yml")'
```

- [ ] **Step 8: Commit the coherent build contract.**

```bash
  .github/workflows/build-nethunter.yml tests/nethunter/test_build_contract.sh \
  docs/nethunter/build-evidence.md
```

---

## Task 4: Complete Bluetooth VHCI and Bluebinder Production Gates

**Files:**
- Modify: `nethunter/bt/nh-bt-acquire.sh`
- Modify: `nethunter/bt/nh-bt-release.sh`
- Modify: `scripts/nethunter/build_bluebinder.sh`
- Modify: `tests/nethunter/test_bt_session.sh`
- Create: `tests/nethunter/test_bluebinder_contract.sh`

**Interfaces:**
- Consumes: Task 2 session/recovery API and Task 3 `hci_vhci.ko` artifact.
- Produces: raw HCI session with journaled bluebinder PID, target Bluebinder shared libraries in `system/lib64`, and exact pre-session Bluetooth state restoration.

- [ ] **Step 1: Add failing bluebinder artifact tests.**

Reject a bluebinder binary when:

- `file` is not AArch64.
- The pinned commit is not `c3e1b155e308f6df9c9a02dbd909a44e7319ab7d`.
- Required `libgbinder`/GLib link inputs are missing.
- The binary is dynamically linked against a host-only path.

- [ ] **Step 2: Make the build script reproducible.**

`build_bluebinder.sh` must:

1. Clone or fetch the exact commit into a content-addressed source directory.
2. Verify `git rev-parse HEAD`.
3. Require the AArch64 Android toolchain.
4. Require prebuilt target libraries and headers.
5. Build with an explicit sysroot.
6. Bundle target `.so` files from the dependency prefix into output `lib64/`.
7. Verify executable/library architecture, NEEDED entries, no host RPATH/RUNPATH, and SHA-256.

- [ ] **Step 3: Verify `/dev/vhci` during acquire.**

After loading `hci_vhci.ko`, require `/dev/vhci` to exist before starting bluebinder. If it does not appear, rollback module, rfkill, service, and journal state.

- [ ] **Step 4: Verify the exact Bluetooth snapshot on release.**

If Bluetooth was disabled before acquire, release must leave it disabled. If it was enabled, release must restore enabled state and verify `dumpsys bluetooth_manager`. Do not force Bluetooth on unconditionally.

- [ ] **Step 5: Extend mocked tests.**

Add cases for:

- `/dev/vhci` missing.
- bluebinder process exit during wait.
- bluebinder PID file pointing to a dead process.
- Bluetooth initially disabled.
- Bluetooth initially enabled.
- module unload failure causing `RECOVERY_REQUIRED`.

- [ ] **Step 6: Run tests and commit.**

```bash
bash tests/nethunter/test_bluebinder_contract.sh
bash tests/nethunter/test_bt_session.sh
git add scripts/nethunter/build_bluebinder.sh nethunter/bt tests/nethunter
git commit -m "feat(nethunter): complete Bluetooth VHCI production gates"
```

---

## Task 5: Make NFC Ownership Real and Testable

**Files:**
- Modify: `nethunter/nfc/nci_raw_tool.c`
- Modify: `nethunter/nfc/Makefile`
- Create: `patches/nfc/0001-exclusive-open.patch`
- Modify: `scripts/nethunter/build_nxp_nci.sh`
- Modify: `nethunter/nfc/nh-nfc-acquire.sh`
- Modify: `nethunter/nfc/nh-nfc-release.sh`
- Create: `tests/nethunter/test_nci_tool_contract.sh`
- Create: `tests/nethunter/test_nfc_exclusive_open.sh`
- Modify: `tests/nethunter/test_nfc_session.sh`

**Interfaces:**
- Consumes: Task 1 exact NFC module source and Task 3 module build workspace.
- Produces: `nci_raw_tool probe|session|send|capture`, optional patched `nxp-nci.ko`, and an accurately labeled NFC capability.

- [ ] **Step 1: Add failing native-tool tests.**

Compile the host tool with `-Wall -Werror` and test:

- Invalid command returns non-zero.
- Odd-length hex is rejected.
- Non-hex input is rejected.
- SIGTERM exits capture cleanly.
- `session` keeps its device descriptor until SIGTERM.
- A session socket or command channel rejects a second session owner.

The tests use a fixture device backend or a compile-time `NQ_NCI_DEV` override; they must not require `/dev/nq-nci` on the host.

- [ ] **Step 2: Implement the session-owning tool.**

The tool interface is:

```text
nci_raw_tool probe
nci_raw_tool session --socket <unix-socket>
nci_raw_tool send --socket <unix-socket> <hex>
nci_raw_tool capture --socket <unix-socket> <seconds>
```

`session` opens the device once, installs SIGINT/SIGTERM handlers, holds the descriptor, and serves only one owner. The Unix socket protocol is line-oriented: `SEND <hex>\n` returns `OK <hex>\n`; `CAPTURE <seconds>\n` emits `FRAME <hex>\n` records followed by `END\n`; malformed commands return `ERROR <reason>\n`. The socket accepts one client at a time. `send` and `capture` connect to the named socket and use the active session channel. Remove the misleading `close` command that opens no persistent descriptor.

- [ ] **Step 3: Add the driver-exclusive-open patch.**

Pinned source path is `vendor/nxp/opensource/driver/nfc`; Kbuild target is `nxp-nci.ko` and device structure is `struct nfc_dev` in `common.h`. Add `int nh_owner_tgid` to this per-device structure. Reuse `dev_ref_mutex` and the existing `dev_ref_count` so multiple descriptors from NFC HAL process (one TGID) remain valid, while another process gets `-EBUSY`:

```c
if (nfc_dev->dev_ref_count > 0 &&
    nfc_dev->nh_owner_tgid != current->tgid) {
    mutex_unlock(&nfc_dev->dev_ref_mutex);
    return -EBUSY;
}
if (nfc_dev->dev_ref_count == 0)
    nfc_dev->nh_owner_tgid = current->tgid;
```

When the second process is rejected, undo `PF_NOFREEZE` only if this open set it. In `nfc_dev_close`, clear `nh_owner_tgid` when the protected reference count reaches zero. Do not use a global flag when multiple NFC controller instances are possible. Keep the patch isolated and compile it first against the unmodified driver.

- [ ] **Step 4: Build and verify the patched NFC module.**

Run:

```bash
git apply --check patches/nfc/0001-exclusive-open.patch
bash scripts/nethunter/build_nxp_nci.sh OP-ACE-5 "$KERNEL_SRC" "$COMMON_OUT" "$OUT" \
  --patched-source patches/nfc/0001-exclusive-open.patch
modinfo "$OUT/nxp-nci.ko"
file "$OUT/nxp-nci.ko" | grep -q 'ARM aarch64'
```

- [ ] **Step 5: Add the two-owner device test.**

On the exact device:

1. Stop Android NFC HAL.
2. Start session owner A.
3. Attempt a second raw open from owner B.
4. Require `EBUSY`.
5. Stop owner A.
6. Require owner B can open.
7. Restart Android NFC and verify `dumpsys nfc`.

Record the result in the device profile and capability provenance.

- [ ] **Step 6: Update NFC acquire/release.**

Acquire must start the persistent session only after HAL quiesce. Release must stop the session before restarting Android NFC. A session process death must invoke recovery rather than clearing the journal.

- [ ] **Step 7: Run host tests and commit.**

```bash
bash tests/nethunter/test_nci_tool_contract.sh
bash tests/nethunter/test_nfc_exclusive_open.sh
bash tests/nethunter/test_nfc_session.sh
git add nethunter/nfc patches/nfc scripts/nethunter/build_nxp_nci.sh tests/nethunter
git commit -m "feat(nethunter): enforce journaled NFC ownership"
```

---

## Task 6: Port Wi-Fi Injection Against the Exact Target Tree

**Files:**
- Create: `patches/wifi/0001-frame-injection-target.patch`
- Create: `patches/wifi/0002-monitor-tx-target.patch`
- Create: `scripts/nethunter/build_patched_wifi.sh`
- Modify: `scripts/nethunter/spike_injection_test.sh`
- Create: `tests/nethunter/test_wifi_patch_contract.sh`
- Create: `docs/nethunter/wifi-patch-evidence.json`
- Create: `docs/nethunter/wifi-patch-evidence.md`
- Modify: `.github/actions/build-nethunter-takeover/action.yml`

**Interfaces:**
- Consumes: Task 1 live source mapping and Task 3 exact KMI workspace.
- Produces: patched `qca_cld3_kiwi_v2.ko`, a patch provenance record, and a device spike result with separate monitor, management-injection, and data-injection verdicts.

- [ ] **Step 1: Prove the unmodified Wi-Fi module build first.**

Run the stock build against both configured targets. Record:

- source revision.
- config hash.
- `Module.symvers` hash.
- vermagic.
- dependencies.
- module SHA-256.

Do not begin patch work if the unmodified module cannot load on the exact target.

- [ ] **Step 2: Extract and inspect upstream diffs.**

Use immutable commits:

```bash
git show --format=fuller be87f121e5c53b1693662248da8a28a37f6b19db
```

For every hunk, record the target-tree file, function signature, config symbol, and reason it is compatible. Reject a hunk when the target tree does not contain its required API; do not invent a replacement symbol silently.

- [ ] **Step 3: Add patch contract tests.**

`test_wifi_patch_contract.sh` must reject any patch containing:

```text
1234567..abcdefg
placeholder
return 0; /* placeholder */
bt_vhci
```

It must require the final patch set to enable the required target Kconfig symbols and to match the monitor TX/injection symbol list recorded in `docs/nethunter/wifi-patch-evidence.json`. The test must also run `git apply --check` against a fixture target tree.

- [ ] **Step 4: Write target-specific patches.**

Port only the compatible upstream logic into the target source layout. The resulting patches must:

- Enable the target frame-injection config.
- Register the monitor TX operation.
- Preserve existing monitor RX behavior.
- Add the required WCN7750 monitor filter/descriptor behavior.
- Avoid unrelated vendor-driver changes.

- [ ] **Step 5: Build the patched module.**

`build_patched_wifi.sh` must:

1. Verify the target source revision.
2. Copy source into a clean worktree.
3. Apply both patches with `git apply --check` first.
4. Build with the exact target `.config` and full `Module.symvers`.
5. Verify AArch64 ELF, vermagic, dependencies, signature, and SHA-256.
6. Emit `wifi-patch-evidence.json`.

- [ ] **Step 6: Rewrite the device spike to avoid vendor writes.**

The spike must:

- Capture stock module hash and service state.
- Push patched module to `/data/local/tmp` or package storage.
- Stop Android Wi-Fi HAL.
- Unload stock module only after dependency checks.
- Load patched module from temporary storage.
- Create `mon0`.
- Test monitor RX.
- Test management injection with an external sniffer.
- Test data injection separately.
- Remove `mon0`, unload patched module, reload stock module from the original read-only vendor path, and verify Android Wi-Fi.

It must never execute `cp <patched> /vendor_dlkm/...`.

- [ ] **Step 7: Record the three Wi-Fi verdicts.**

Write:

```json
{
  "monitor_rx": "PASS|FAIL",
  "management_injection": "PASS|FAIL|NOT_TESTED",
  "data_injection": "PASS|FAIL|NOT_TESTED",
  "external_sniffer_confirmed": true,
  "restore_verified": true
}
```

Management injection is required for the Wi-Fi injection capability to become `SUPPORTED`. Data injection remains `BEST_EFFORT`.

- [ ] **Step 8: Run host contract tests and commit the port.**

```bash
bash tests/nethunter/test_wifi_patch_contract.sh
bash -n scripts/nethunter/build_patched_wifi.sh scripts/nethunter/spike_injection_test.sh
git add patches/wifi scripts/nethunter tests/nethunter \
  docs/nethunter/wifi-patch-evidence.json docs/nethunter/wifi-patch-evidence.md \
  .github/actions/build-nethunter-takeover/action.yml
git commit -m "feat(nethunter): port and gate exact-target Wi-Fi injection"
```

---

## Task 7: Add Reversible USB ConfigFS Profiles

**Files:**
- Create: `nethunter/usb/nh-usb-acquire.sh`
- Create: `nethunter/usb/nh-usb-release.sh`
- Create: `nethunter/usb/nh-usb-status.sh`
- Create: `nethunter/usb/nh-usb-profiles.sh`
- Create: `tests/nethunter/test_usb_session.sh`
- Modify: `nethunter/framework/nh-state.sh`

**Interfaces:**
- Consumes: Task 2 session/recovery API.
- Produces: `nh-usb-acquire.sh <ncm|ecm|rndis|hid|functionfs>`, `nh-usb-release.sh`, and status output.

- [ ] **Step 1: Write failing ConfigFS mock tests.**

Create a fake `/sys/class/udc`, `/config/usb_gadget/g1`, function directory, UDC file, and Android `sys.usb.config` property. Test that acquire snapshots every path before changing it.

- [ ] **Step 2: Define the allowed profile table.**

`nh-usb-profiles.sh` must accept only:

```text
ncm
ecm
rndis
hid
functionfs
```

Unknown profiles return non-zero without changing ConfigFS.

- [ ] **Step 3: Implement snapshot and acquire.**

Acquire must:

1. Begin an exclusive USB session.
2. Snapshot `sys.usb.config`, UDC binding, gadget functions, and symlinks.
3. Unbind the current UDC.
4. Configure only the selected profile.
5. Bind the UDC.
6. Verify the profile is present and the host-facing state is consistent.

- [ ] **Step 4: Implement release and recovery.**

Release must unbind the NetHunter gadget, restore every saved ConfigFS link and Android property, verify the original profile, and retain `RECOVERY_REQUIRED` on any failed restore.

- [ ] **Step 5: Add race tests.**

Mock an Android property change during takeover. The release path must detect the mismatch, restore the journal snapshot, and report the event. Mock a failed UDC bind and verify rollback.

- [ ] **Step 6: Run tests and commit.**

```bash
bash tests/nethunter/test_usb_session.sh
bash -n nethunter/usb/*.sh
git add nethunter/usb nethunter/framework/nh-state.sh tests/nethunter/test_usb_session.sh
git commit -m "feat(nethunter): add reversible USB ConfigFS profiles"
```

---

## Task 8: Add GNSS Probe and Android-Owned Bridge

**Files:**
- Create: `nethunter/gnss/nh-gnss-status.sh`
- Create: `nethunter/gnss/nh-gnss-bridge.sh`
- Create: `nethunter/gnss/nh-gnss-stop.sh`
- Modify: `scripts/nethunter/probe_device.sh`
- Create: `tests/nethunter/test_gnss_contract.sh`
- Create: `docs/nethunter/gnss-capability.md`

**Interfaces:**
- Consumes: Android GNSS AIDL service and an exact-device readable NMEA/location endpoint discovered by Task 1.
- Produces: status output and a bridge process with journaled PID; it does not stop Android GNSS by default.

- [ ] **Step 1: Write the GNSS availability test.**

The test must classify fixtures as:

- `AIDL_ONLY`: service exists but no readable stream.
- `NMEA_SOCKET`: readable source can be copied to UDP.
- `GPSD_DEVICE`: `gpsd`-compatible device exists.
- `UNAVAILABLE`: no usable service or source.

- [ ] **Step 2: Implement status detection.**

`nh-gnss-status.sh` must inspect `dumpsys location`, service registration, and the profile’s GNSS evidence. It must return a machine-readable status and must not stop or reconfigure Android location.

- [ ] **Step 3: Implement the bridge only for a verified source.**

`nh-gnss-bridge.sh --source <path> --host <ip> --port 10110` must:

- Reject a non-readable source.
- Refuse to run without a validated source path.
- Record PID and source in the session journal.
- Forward bytes without modifying them.
- Stop cleanly and remove its PID only after exit.

When the exact device exposes only the AIDL service and no raw stream, mark GNSS `AIDL_ONLY` and do not create a fake raw bridge.

- [ ] **Step 4: Add process and Android coexistence tests.**

Test bridge startup, SIGTERM cleanup, unreadable source failure, UDP forwarding, and unchanged Android GNSS status.

- [ ] **Step 5: Run tests and commit.**

```bash
bash tests/nethunter/test_gnss_contract.sh
bash -n nethunter/gnss/*.sh
git add nethunter/gnss scripts/nethunter/probe_device.sh tests/nethunter/test_gnss_contract.sh \
  docs/nethunter/gnss-capability.md
git commit -m "feat(nethunter): add Android-owned GNSS bridge contract"
```

---

## Task 9: Rebuild Package Layout, Metadata, and CI Artifacts

**Files:**
- Modify: `scripts/nethunter/pack_takeover_zip.sh`
- Modify: `nethunter/module/module.prop.template`
- Modify: `nethunter/module/customize.sh`
- Modify: `nethunter/module/post-fs-data.sh`
- Modify: `nethunter/module/service.sh`
- Modify: `.github/actions/build-nethunter-takeover/action.yml`
- Modify: `.github/workflows/build-nethunter.yml`
- Create: `tests/nethunter/test_package_layout.sh`
- Create: `tests/nethunter/test_provenance_contract.sh`

**Interfaces:**
- Consumes: Tasks 1-8 artifacts and capability verdicts.
- Produces: a target-specific ReSukiSU ZIP with runtime-relative paths, exact metadata, provenance, and no unverified capability claims.

- [ ] **Step 1: Write failing package-layout tests.**

Build a fixture package and require:

```text
module.prop
customize.sh
post-fs-data.sh
service.sh
framework/
wifi/
bt/
nfc/
usb/
gnss/
vendor_dlkm_override/
system/bin/
system/lib64/
provenance.json
```

Reject a package when scripts reference the old generic module root, when `bt_vhci.ko` appears, or when `target` is used as the Android model.

- [ ] **Step 2: Make package root runtime-relative.**

The installed scripts must derive:

```sh
NH_PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0")")/.." && pwd)"
```

or use an equivalent path that resolves correctly for each resource directory. Every module binary lookup must be rooted there.

- [ ] **Step 3: Make packaging all-or-nothing by capability set.**

The packer must require the exact required set:

- Wi-Fi capability: patched Wi-Fi module.
- Bluetooth capability: `hci_vhci.ko` and bluebinder.
- Bluetooth capability: bundled AArch64 runtime libraries in `system/lib64`, with bluebinder launched under that package library path.
- NFC raw capability: AArch64 `nci_raw_tool`.
- NFC exclusive capability: patched `nxp-nci.ko` or an exact-device ownership proof recorded in provenance.
- USB capability: USB scripts.
- GNSS bridge capability: GNSS scripts plus a valid capability record.

If a component is absent, the package may only be labeled with a lower capability state; it must not silently claim supported takeover.

- [ ] **Step 4: Generate metadata from the device profile and artifacts.**

The packer must populate every field from Task 1 and emit `provenance.json` containing:

- Target and device identifiers.
- Source revisions.
- Config hash.
- Module SHA-256, vermagic, dependencies, and signature state.
- Bluebinder commit and SHA-256.
- Bluebinder bundled shared-library names and SHA-256 values.
- NCI tool SHA-256.
- Wi-Fi patch commit list and spike verdict.
- Capability labels.

For NFC, the packer may set `capability_nfc=SUPPORTED` with `nfc_mode=exclusive` only when either the patched driver artifact is present or the exact-device two-owner test has passed and its result is referenced. Otherwise it must use `EXPERIMENTAL_SHARED` or `NOT_TESTED`.

- [ ] **Step 5: Enforce AArch64 and signing gates.**

Reject every non-AArch64 `.ko` or binary. Reject a module whose signing state does not match the target policy. Reject unknown target metadata.

- [ ] **Step 6: Run package tests.**

```bash
bash tests/nethunter/test_package_layout.sh
bash tests/nethunter/test_provenance_contract.sh
bash tests/nethunter/test_pack_gate.sh
```

- [ ] **Step 7: Commit package and CI changes.**

```bash
  .github/actions/build-nethunter-takeover/action.yml \
  .github/workflows/build-nethunter.yml tests/nethunter
git commit -m "ci(nethunter): package verified hardware capabilities only"
```

---

## Task 10: Exact-Device Runtime, Endurance, and Release Documentation

**Files:**
- Modify: `tests/nethunter/runtime/test_all_radios.sh`
- Create: `tests/nethunter/runtime/test_recovery_cycles.sh`
- Create: `docs/nethunter/README.md`
- Create: `docs/nethunter/TROUBLESHOOTING.md`
- Create: `docs/nethunter/capability-matrix.json`
- Create: `docs/nethunter/device-test-results.md`

**Interfaces:**
- Consumes: all supported scripts, package, device profile, and capability provenance.
- Produces: auditable exact-device results and user-facing install/use/recovery documentation.

- [ ] **Step 1: Replace the stale runtime test.**

The runtime test must not hardcode `nethunter_takeover_OP-ACE-5` or assume every feature is present. It must accept:

```text
test_all_radios.sh <package-root> <device-profile> <result-file>
```

It must select tests from capability labels and report `SKIP` for `NOT_TESTED`, never count a skip as pass.

- [ ] **Step 2: Implement one-cycle tests.**

For every claimed exclusive capability, run:

```text
preflight
acquire
smoke
release
stock verification
journal verification
vendor/config hash verification
```

For GNSS, run status and bridge tests without stopping Android GNSS. For USB, verify host enumeration and exact profile restore.

- [ ] **Step 3: Implement 20-cycle endurance.**

`test_recovery_cycles.sh` must run 20 sequential cycles per supported resource, record start/end timestamps, and fail if:

- Any cycle needs reboot.
- Any journal remains after successful release.
- Any Android health check fails.
- Any vendor module/config hash changes unexpectedly.
- Any cycle exceeds 30 seconds for normal release.

- [ ] **Step 4: Run failure-injection tests.**

Inject and record:

- Fingerprint mismatch.
- Missing module.
- HAL stop timeout.
- Module load failure.
- bluebinder death.
- NFC session death.
- Wi-Fi release interruption.
- USB UDC bind failure.
- Reboot during takeover.

Every failure must either fully restore or produce `RECOVERY_REQUIRED` with an actionable journal.

- [ ] **Step 5: Write user documentation.**

`README.md` must cover installation, profile discovery, acquire/release commands, capability labels, USB profiles, GNSS bridge usage, and the no-auto-acquire rule.

`TROUBLESHOOTING.md` must cover fingerprint mismatch, KMI/module load failure, HAL timeout, stale recovery journal, bluebinder crash, NFC `EBUSY`, USB ConfigFS recovery, and reboot fallback.

- [ ] **Step 6: Publish the capability matrix.**

Create `capability-matrix.json` with one entry per resource containing:

```json
{
  "resource": "wifi",
  "capability": "management_injection",
  "status": "SUPPORTED|EXPERIMENTAL|BEST_EFFORT|NOT_TESTED|UNAVAILABLE",
  "evidence": "docs/nethunter/results/wifi-management-injection.json",
  "reboot_required_for_normal_switch": false
}
```

- [ ] **Step 7: Run the complete verification set.**

```bash
PACKAGE_ROOT=/data/adb/modules/nethunter_takeover_OP-ACE-5
PROFILE=docs/nethunter/device-profile.json
RESULTS=docs/nethunter/device-test-results.md
for test in tests/nethunter/test_*.sh; do bash "$test"; done
bash tests/nethunter/runtime/test_all_radios.sh \
  "$PACKAGE_ROOT" "$PROFILE" "$RESULTS"
bash tests/nethunter/runtime/test_recovery_cycles.sh \
  "$PACKAGE_ROOT" "$PROFILE"
```

Run the exact-device commands only after the profile validator passes and ADB/root access is confirmed.

- [ ] **Step 8: Commit release evidence and documentation.**

```bash
git add tests/nethunter/runtime docs/nethunter
git commit -m "docs(nethunter): publish capability matrix and recovery runbook"
```

---

## Completion Checklist

- [ ] Exact-device profile exists and validates.
- [ ] Unmodified module build is reproducible.
- [ ] KMI, symbol CRC, signing, and architecture gates pass.
- [ ] Session journal and recovery tests pass.
- [ ] Bluetooth raw HCI passes device restore cycles.
- [ ] NFC raw NCI passes; exclusive label matches driver evidence.
- [ ] Wi-Fi monitor RX passes.
- [ ] Wi-Fi management injection has external-sniffer evidence or is explicitly unavailable.
- [ ] USB profiles switch and restore without reboot.
- [ ] GNSS bridge status is honest and Android location remains functional.
- [ ] Package paths resolve from installed `MODPATH`.
- [ ] CI builds from one coherent source workspace.
- [ ] No package writes `/vendor_dlkm`.
- [ ] Twenty cycles pass for every claimed exclusive capability.
- [ ] Reboot recovery is verified.
- [ ] Capability matrix and troubleshooting documentation match actual evidence.

## Commit Order

Use one focused commit per task in this order:

1. `feat(nethunter): define exact-device profile and metadata contract`
2. `feat(nethunter): harden journal recovery and package paths`
3. `ci(nethunter): build takeover modules from exact kernel workspace`
4. `feat(nethunter): complete Bluetooth VHCI production gates`
5. `feat(nethunter): enforce journaled NFC ownership`
6. `feat(nethunter): port and gate exact-target Wi-Fi injection`
7. `feat(nethunter): add reversible USB ConfigFS profiles`
8. `feat(nethunter): add Android-owned GNSS bridge contract`
9. `ci(nethunter): package verified hardware capabilities only`
10. `docs(nethunter): publish capability matrix and recovery runbook`

## Spec Coverage Check

- Spec sections 1-3 (purpose, superseded assumptions, current gaps): Task 1 establishes the evidence contract before later builds.
- Spec section 4 (scope): Tasks 6-8 cover Wi-Fi, USB, and GNSS; Task 4 covers Bluetooth; Task 5 covers NFC; no task adds excluded hardware.
- Spec section 5 (capability labels): Tasks 1, 6, 9, and 10 generate and verify labels.
- Spec section 6 (sessions and recovery): Task 2 owns the shared state/recovery API; Tasks 4-8 exercise resource-specific rollback.
- Spec section 7 (fingerprint/KMI): Tasks 1-3 implement metadata and build/load gates.
- Spec section 8 (kernel escalation): Tasks 3, 5, and 6 implement module, driver, and evidence gates before any Image change.
- Spec section 9 (resource designs): Tasks 4-8 implement each resource path.
- Spec section 10 (CI/package): Tasks 3 and 9 own the source workspace, artifact, metadata, and provenance contract.
- Spec sections 11-12 (safety and verification): Tasks 2 and 10 cover recovery, failure injection, endurance, and reboot verification.
- Spec sections 13-15 (phase gates, success, non-goals): Completion checklist and commit order enforce the final release boundary.
