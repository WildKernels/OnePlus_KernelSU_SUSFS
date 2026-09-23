# NetHunter Reversible Hardware Control Design

**Status:** Proposed replacement for the 2026-09-03 design

**Target:** OnePlus Ace 5 / OP-ACE-5 NetHunter deployment

**Date:** 2026-09-23

## 1. Purpose

This design defines a reversible way to use as much built-in OnePlus Ace 5 hardware as the device exposes safely to NetHunter while preserving Android recovery without routine reboot.

The design has three priorities:

1. Use built-in Wi-Fi, Bluetooth, NFC, USB, and GNSS capabilities instead of requiring external adapters where technically possible.
2. Switch hardware ownership between Android and NetHunter through explicit acquire/release sessions.
3. Allow kernel and vendor-driver changes when required by NetHunter patches, while escalating from temporary modules to an Image change only when a module-only solution cannot work.

A successful build is not sufficient for support. Hardware support requires exact-target runtime evidence and a passing restore cycle.

## 2. Relationship to Earlier Documents

This document supersedes:

- `docs/superpowers/specs/2026-09-03-nethunter-reversible-takeover-design.md`
- `docs/superpowers/plans/2026-09-03-nethunter-reversible-takeover.md`

The earlier documents remain historical records. Their assumptions about Wi-Fi patches, module names, module metadata, vendor partition writes, NFC locking, CI source layout, and reboot recovery are not authoritative.

The implementation already present on branch `nethunter` is a foundation, not a release. At this design revision the latest known NetHunter commit is `7a3bf11`; host mock tests pass, but exact-device validation is incomplete because ADB was unavailable during the last probe.

## 3. Current Evidence and Known Gaps

### 3.1 Existing foundation

The branch currently contains:

- Journaled state and recovery primitives in `nethunter/framework/nh-state.sh`.
- Fingerprint checks in `nethunter/framework/nh-fingerprint.sh`.
- Wi-Fi acquire/release scripts with a no-`/vendor_dlkm`-write policy.
- Bluetooth acquire/release scripts using the real kernel module name `hci_vhci.ko`.
- NFC acquire/release scripts and a small `nci_raw_tool`.
- Read-only device probing in `scripts/nethunter/probe_device.sh`.
- Fail-closed package checks in `scripts/nethunter/pack_takeover_zip.sh`.
- Build helpers for Wi-Fi baseline, VHCI, bluebinder, and AArch64 NFC tooling.
- Host tests for state, package gates, device probing, and mocked Wi-Fi/Bluetooth/NFC sessions.

### 3.2 Unresolved facts

The following facts must be collected from the exact target before supported artifacts are produced:

- The running device build fingerprint and model/device identifiers.
- The exact source revision that produced the installed Wi-Fi module.
- The exact KMI and symbol CRC set accepted by the running kernel.
- The actual module signing policy and signing key compatibility.
- Whether the vendor Wi-Fi module can be unloaded after all Android references are stopped.
- Whether `hci_vhci.ko` can be loaded and unloaded without changing the stock Bluetooth driver state.
- Whether the NXP NFC driver can enforce exclusive ownership.
- Whether USB ConfigFS profile changes survive Android framework reconfiguration.
- Whether the Android GNSS AIDL service exposes a usable bridge path without taking over the HAL.

### 3.3 Known stale assumptions removed by this design

- Wi-Fi injection patches are not considered ported. Placeholder patches were removed.
- `hci_vhci.ko` is the module name. `bt_vhci.ko` is not used.
- `uname -r` is not compared to a complete module vermagic string.
- Missing runtime scmversion data is not treated as proof that a module is safe.
- `/vendor_dlkm` is never used as a writable staging area.
- A userspace `flock` is not treated as an exclusive NFC device lock when the driver allows multiple `open()` calls.
- The CI takeover job cannot assume that a kernel source tree exists merely because `.config` and `Module.symvers` were uploaded.
- A package containing only scripts is not a valid takeover artifact.

## 4. Scope

### 4.1 In scope

- Wi-Fi monitor-mode receive and NetHunter injection support where exact-target firmware and driver validation pass.
- Bluetooth raw HCI through `hci_vhci.ko` and bluebinder where the stock Android Bluetooth HAL can be safely quiesced and restored.
- NFC raw NCI access through `/dev/nq-nci`, preferably with driver-enforced ownership.
- USB gadget profiles using the existing DWC3 and ConfigFS support.
- GNSS access through the stock Android GNSS AIDL service and a NetHunter bridge where available.
- Temporary module loading from `/data/adb`.
- Optional vendor-driver or kernel-source changes required to support the above.
- Reversible acquire/release sessions, recovery journals, and device endurance testing.

### 4.2 Explicitly out of scope

- Cellular or baseband takeover.
- NFC card emulation, eSE takeover, and MIFARE emulation.
- GPU, camera, and sensor raw takeover.
- Qualcomm vendor Bluetooth offload features such as LE Audio, LHDC, and proprietary bttpi control.
- Automatic takeover during boot.
- Writing replacement modules into `/vendor_dlkm`.
- Calling data-frame Wi-Fi injection supported merely because management-frame injection works.

## 5. Capability Contract

Support is reported per capability, not per build.

| Resource | Planned capability | Ownership model | Minimum release evidence |
| --- | --- | --- | --- |
| Wi-Fi | Monitor RX with radiotap | Temporary patched module | Monitor capture and stock restore |
| Wi-Fi | Management-frame injection | Temporary patched module | External-sniffer confirmation |
| Wi-Fi | Data-frame injection | Same module path | Separate best-effort result |
| Bluetooth | Raw HCI through VHCI and bluebinder | Exclusive Android HAL quiesce | `hci0` operation and Android restore |
| NFC | Raw NCI reset/init/send/capture | Exclusive driver/session preferred | Raw NCI operation and HAL reopen |
| USB | NCM/ECM/RNDIS/HID/FunctionFS profiles | ConfigFS transaction | Host enumeration and Android restore |
| GNSS | Location/NMEA bridge to NetHunter | Shared stock HAL, read-only first | NetHunter receives data and Android remains functional |

Each capability receives one of these labels:

- `SUPPORTED`: exact target passed build, runtime, restore, and endurance gates.
- `EXPERIMENTAL`: works in a controlled test but lacks one mandatory release gate.
- `BEST_EFFORT`: firmware or Android behavior can cause target-specific failure.
- `NOT_TESTED`: no exact-device evidence.
- `UNAVAILABLE`: no safe usable interface was found.

The project must not label a capability `SUPPORTED` from compilation alone.

## 6. Ownership and Session Architecture

### 6.1 Resource classes

The session manager handles two classes:

1. **Exclusive resources:** Wi-Fi, Bluetooth, NFC, and USB gadget profile changes. Only one exclusive session may be active at a time in v1.
2. **Shared bridge resources:** GNSS status/data bridge. The Android HAL remains the owner unless later device evidence proves a safe raw handoff.

The global exclusion rule is conservative. It avoids a Wi-Fi/Bluetooth/NFC/USB HAL transition racing another transition and makes recovery deterministic.

### 6.2 State machine

Every exclusive resource uses the following states:

```text
IDLE
  -> PREPARE
  -> QUIESCE_ANDROID
  -> TAKEOVER
  -> RESTORE
  -> IDLE

Any failed restore
  -> RECOVERY_REQUIRED
```

`RECOVERY_REQUIRED` blocks new sessions until a recovery operation verifies the resource and clears the journal.

### 6.3 Acquire transaction

Acquire performs these operations in order:

1. Resolve the package root and target metadata.
2. Verify target identity, kernel release, module architecture, module hash, and available KMI evidence.
3. Check that no other exclusive session or recovery journal exists.
4. Create the journal and persist all pre-session state before making changes.
5. Quiesce the Android service or gadget owner with bounded timeouts.
6. Load or attach the NetHunter resource.
7. Run a resource-specific smoke test.
8. Mark `TAKEOVER` only after the smoke test passes.

If any operation fails, the script attempts an automatic rollback. A successful rollback removes the journal and returns to `IDLE`. A failed rollback writes a reason and leaves `RECOVERY_REQUIRED`.

### 6.4 Release transaction

Release performs these operations in order:

1. Require `TAKEOVER`; refuse to silently handle an ambiguous state.
2. Stop NetHunter processes and detach interfaces.
3. Unload temporary modules where safe.
4. Restore the exact pre-session service, rfkill, USB, and configuration state.
5. Verify Android functionality and module ownership.
6. Remove the journal and lock only after verification passes.

### 6.5 Reboot behavior

Reboot is not part of normal switching. A reboot is the fallback when a driver or HAL cannot be restored in userspace.

On boot:

- No takeover module is auto-loaded.
- No stale journal is blindly converted to `IDLE`.
- The boot hook probes module ownership and Android service state.
- It marks the session `BOOT_RECOVERED` only after stock verification.
- It keeps `RECOVERY_REQUIRED` when stock state cannot be proven.

## 7. Fingerprint, KMI, and Metadata Contract

### 7.1 Device identity

`module.prop` must contain separate fields for:

- `device`: Android device codename.
- `model`: Android model.
- `build_fingerprint`: exact build or an explicitly approved fingerprint family.
- `kernel_release`: `uname -r` value.
- `config_sha256`: hash of the kernel configuration used to build the module.
- Per-component SHA-256 values.

The package target label, such as `OP-ACE-5`, is a build identifier. It must not be compared directly to `ro.product.model`.

### 7.2 Runtime checks

Before loading a temporary module the runtime gate checks:

- Device codename and model.
- Build fingerprint policy.
- `uname -r` against the version token of module vermagic.
- Module architecture.
- Module SHA-256.
- Dependency presence.
- Kernel loader result and symbol CRC validation during the actual load.

`scmversion` is recorded as provenance when available. It is not treated as a safe substitute for KMI validation because many Android kernels do not expose it consistently at runtime.

### 7.3 Build-time KMI checks

Build gates require:

- Exact source revision.
- Exact target `.config` plus a documented NetHunter config delta.
- Full `Module.symvers`, not only `modules_prepare` output.
- Matching exported symbol CRCs.
- Matching module signing policy.
- `modinfo` vermagic and dependencies.
- AArch64 ELF output.

The actual kernel module loader remains the final runtime authority. A string comparison alone cannot prove KMI compatibility.

## 8. Kernel Modification Strategy

Kernel changes follow an escalation order.

### Level 1: Temporary external modules

Use when the existing kernel exports the required symbols and the vendor driver can be rebuilt independently.

Examples:

- `hci_vhci.ko`.
- Patched `qca_cld3_kiwi_v2.ko`.
- Patched `nxp_nci.ko` if its source/build boundary permits it.

### Level 2: In-tree vendor-driver patches

Use when a feature requires vendor-driver changes but the result can still be loaded as a module.

Examples:

- Wi-Fi monitor TX/injection path.
- NXP NFC exclusive-open ownership.

### Level 3: Kernel Image changes

Use only when a required hook or symbol cannot be provided by a module.

An Image change requires a separate output and evidence for:

- Config delta.
- Source revision.
- KMI impact.
- Boot success.
- Module load compatibility.
- Userspace release and reboot recovery.

No kernel Image change is justified only because a module build script is inconvenient.

## 9. Resource Designs

### 9.1 Wi-Fi

The Wi-Fi driver is the critical path.

The implementation must first build and test the unmodified module. Only then may it port real upstream changes. The upstream references are starting points, not drop-in patches:

- Loukious frame-injection work: `25875eb1a65e94fae404c6e9188c7a1fe679e0f5`.
- brokestar233 monitor TX work: `be87f121e5c53b1693662248da8a28a37f6b19db`.

Porting rules:

- Compare source layout and function signatures against the exact target tree.
- Port only hunks that compile against the target tree.
- Do not retain invented symbols, fake patch indexes, or placeholder returns.
- Preserve the stock module as a read-only vendor artifact.
- Load the patched module from `/data/adb` only.

Acquire:

1. Snapshot Wi-Fi enabled state, HAL state, module hash, and relevant driver parameters.
2. Disable Android Wi-Fi and stop the vendor HAL.
3. Remove the stock module only after dependency and reference checks pass.
4. Load patched `qca_cld3_kiwi_v2.ko` from the module package.
5. Create `mon0` and verify monitor RX.
6. Mark `TAKEOVER`.

Release:

1. Remove `mon0`.
2. Unload the patched module.
3. Load the original read-only vendor module path.
4. Restore the saved Android state.
5. Verify Wi-Fi service and interface health.

Management-frame injection requires external-sniffer confirmation. Data-frame injection remains a separate best-effort result.

### 9.2 Bluetooth

The module name is `hci_vhci.ko`, produced by `CONFIG_BT_HCIVHCI=m`.

Bluebinder is pinned to commit `c3e1b155e308f6df9c9a02dbd909a44e7319ab7d` and must be built for AArch64 Android with its actual `libgbinder` and GLib dependencies.

Acquire:

1. Snapshot Bluetooth enabled state, HAL state, and rfkill state.
2. Disable/quiesce Android Bluetooth.
3. Block rfkill if required.
4. Load `hci_vhci.ko` from `/data/adb`.
5. Start bluebinder with a journaled PID.
6. Wait for `hci0` with a bounded timeout.
7. Bring `hci0` up and mark `TAKEOVER`.

Release restores the original Bluetooth enabled state rather than forcing Bluetooth on. It stops bluebinder, unloads VHCI, restores rfkill, restarts Android services, and verifies the resulting state.

### 9.3 NFC

The first implementation uses a small native NCI tool rather than the obsolete NCIHost approach. The tool must:

- Open `/dev/nq-nci`.
- Send and parse CORE_RESET and CORE_INIT.
- Support raw send and capture.
- Handle SIGINT/SIGTERM.
- Keep the device descriptor open for the complete ownership session.

Because the current NXP driver allows multiple opens, userspace locking alone is not an exclusive guarantee. The preferred solution is a small `nxp_nci` driver change that tracks one owner and returns `-EBUSY` to concurrent opens. If that driver change cannot be built and loaded safely, the package must label NFC as shared/cooperative experimental mode.

Acquire stops the NFC framework and HAL, opens the raw session, runs NCI initialization, and records the session PID/socket. Release closes the raw session, restores the prior NFC state, and verifies `dumpsys nfc`.

### 9.4 USB

USB uses existing DWC3 and ConfigFS functionality; no kernel module replacement is planned initially.

The USB session layer snapshots:

- `sys.usb.config`.
- Current UDC binding.
- ConfigFS gadget functions and links.
- Android USB service state.

Acquire unbinds the current gadget, configures a selected NetHunter profile, binds the UDC, and verifies host enumeration. Release unbinds the NetHunter gadget and restores the exact snapshot. Any partial ConfigFS change enters recovery instead of being silently ignored.

### 9.5 GNSS

GNSS remains owned by the Android AIDL HAL in the first supported mode. NetHunter consumes a bridge, preferably an NMEA/location stream routed to UDP 10110 or a `gpsd`-compatible endpoint.

Raw GNSS takeover is not promised without an exact-device low-level interface and a tested restore path. The bridge must not stop Android location services by default.

## 10. Build and Packaging Architecture

### 10.1 Single coherent source workspace

Kernel modules must be built from the same target source workspace and build outputs as the Image. The CI job must not build modules in a separate checkout that only contains `.config` and `Module.symvers`.

The build interface must explicitly pass:

- Target name.
- Kernel source root.
- Common kernel output directory.
- Modules/devicetree source revision.
- Common kernel source revision.
- Target `.config`.
- `Module.symvers`.
- Module signing inputs.

### 10.2 Artifact contents

A supported package contains the runtime scripts, framework, metadata, and every component required by its claimed capability set.

Required component names:

- `qca_cld3_kiwi_v2.ko` for Wi-Fi takeover support.
- `hci_vhci.ko` and bluebinder for Bluetooth support.
- AArch64 `nci_raw_tool` for NFC support.
- Patched `nxp_nci.ko` when exclusive NFC mode is claimed.

USB and GNSS bridge scripts are included when their profile/bridge tests pass.

The package gate rejects:

- Scripts-only packages.
- Wrong-architecture binaries.
- Missing required modules.
- Metadata with unknown target identity.
- Missing source provenance.
- A Wi-Fi component marked supported before the injection gate passes.

### 10.3 Runtime path

Scripts must derive their package root from their installed location or an explicit package-root variable. They must not assume a generic module directory that differs from the actual ReSukiSU `MODPATH`.

## 11. Recovery and Safety Rules

- Never write to `/vendor_dlkm`.
- Never delete a recovery journal before stock verification.
- Never start a second exclusive resource session over an existing session.
- Never treat a build pass as hardware support.
- Never silently ignore module unload, HAL stop, ConfigFS restore, or service verification failure.
- On rollback failure, stop and expose the exact recovery command and reason.
- On reboot, verify stock state instead of blindly cleaning stale files.
- Keep Android control available where possible; document when USB takeover removes ADB.

## 12. Verification Matrix

### Host verification

- Shell syntax for every script.
- State/journal tests.
- Fingerprint and metadata tests.
- Mocked acquire/release tests for Wi-Fi, Bluetooth, NFC, and USB.
- Package layout and architecture gates.
- YAML and composite-action validation.

### Build verification

- Unmodified module build.
- Patched module build.
- AArch64 ELF checks.
- `modinfo` checks.
- `Module.symvers` and symbol CRC checks.
- Signing checks.
- Provenance hash checks.

### Exact-device verification

For every exclusive resource:

1. Acquire.
2. Run resource smoke test.
3. Release.
4. Verify Android functionality.
5. Verify vendor module and configuration hashes.

Run at least 20 sequential acquire/release cycles per supported resource. Normal release target is 30 seconds or less without reboot.

Failure tests:

- Fingerprint mismatch.
- Missing or wrong-architecture module.
- HAL quiesce timeout.
- Failed module load.
- bluebinder termination during takeover.
- NFC tool termination during takeover.
- Wi-Fi release interruption.
- USB ConfigFS partial failure.
- Reboot during takeover.

## 13. Phase Gates

### Gate 0: Device baseline

Exact device profile, source mapping, KMI evidence, and USB/GNSS capability evidence exist.

### Gate 1: Stock module reproducibility

Unmodified module builds and loads against the exact target KMI. No vendor partition writes occur.

### Gate 2: Reversible session foundation

Journal, recovery, package paths, metadata, and boot verification pass host tests and stock handoff cycles.

### Gate 3: Bluetooth and NFC

Raw HCI and raw NCI work with Android restore. NFC is labeled exclusive only if driver ownership is enforced or independently proven.

### Gate 4: Wi-Fi injection

Monitor RX and management injection pass exact-device tests with external-sniffer evidence. Data injection is recorded separately.

### Gate 5: USB/GNSS

USB profile switching and GNSS bridge pass restore and Android coexistence tests.

### Gate 6: Release

CI builds coherent artifacts, provenance is complete, all claimed capabilities have the correct labels, and endurance/recovery tests pass.

## 14. Success Criteria

The project is complete only when all of the following are true:

- Built-in Wi-Fi monitor RX works on the exact target.
- Management-frame injection is externally confirmed or explicitly marked unavailable.
- Bluetooth raw HCI works through VHCI/bluebinder or is explicitly marked unavailable.
- NFC raw NCI works; exclusive status is accurately labeled.
- USB built-in gadget profiles switch and restore without reboot.
- GNSS data reaches NetHunter through a documented bridge without breaking Android location.
- Every supported exclusive resource passes 20 acquire/release cycles.
- Normal release needs no reboot and completes within 30 seconds.
- Forced failure leaves a recoverable journal and never claims success.
- Reboot during takeover returns to verified stock behavior or clearly enters recovery.
- `/vendor_dlkm` remains unchanged.
- CI rejects incomplete, unsigned, wrong-architecture, or falsely labeled artifacts.

## 15. Final Non-Goals

The following remain outside this project even if the hardware contains the capability:

- Cellular baseband control.
- NFC eSE/card emulation.
- Camera, sensor, and GPU takeover.
- Unsupported proprietary Bluetooth offload functions.
- Automatic boot-time NetHunter ownership.
