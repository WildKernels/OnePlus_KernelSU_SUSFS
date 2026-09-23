# NetHunter Kernel Module Build Evidence

## Build location

NetHunter modules build in same GitHub Actions matrix job and source workspace as kernel Image. Workflow no longer passes `.config` and `Module.symvers` alone to a separate job.

The build action receives:

- Source root populated by `kernel-source-sync` (`CONFIG_FOLDER`).
- Common kernel output (`COMMON_KERNEL_FOLDER/out`).
- Target name from Ace 5 matrix.
- Output directory under that target's `artifacts/nethunter` folder.

The kernel action enables `CONFIG_BT=m`, `CONFIG_BT_HCIVHCI=m`, and `CONFIG_MODVERSIONS=y` only for NetHunter workflow, then runs `make Image modules`. Other workflows keep existing Image-only build behavior.

## Source identity

Manifest sync expands remote source archives. Extracted kernel tree does not contain `.git`; `git rev-parse` is not a valid revision check there. Build gate reads `manifest.xml` and requires exact target entries:

| Target | Common revision | Modules/device-tree revision |
| --- | --- | --- |
| `OP-ACE-5` | `086936b3387b4018805500fa4069d09637fdb89b` | `21a5694f721d3826ac9e101e5d65919f2a8e739e` |
| `OP-ACE-5-6.1.118` | `7499247fd6e0669a062ec44cce948ec1e9d4c75e` | `d5323ede4f2059880c54818abfc1ac22d7e8bd5f` |

The module builder rejects missing manifest, mismatched revisions or paths, absent `.config`, absent/empty `Module.symvers`, disabled `CONFIG_MODVERSIONS`, missing VHCI config, and wrong-architecture module artifacts.

## Outputs

The current deliverable is baseline only:

- `hci_vhci.ko`, built by the same Kbuild output as Image.
- Unmodified `qca_cld3_kiwi_v2.ko`, built from exact target modules source.
- `hci-vhci-evidence.json` and `wifi-stock-evidence.json`.
- Combined `build-evidence.json` with source revisions, `.config` hash, `Module.symvers` hash, module names, vermagic, dependencies, and hashes.

The stock Wi-Fi module is for build/KMI/restore baseline. It has no injection patch and must not be labeled as injection support.

`nxp_nci.ko` build is optional until exact NFC driver source path is mapped for target. Set `NH_NXP_NCI_DIR` to the target driver source directory to run its baseline Kbuild. Missing source does not fabricate an NFC module artifact.

## Local validation

```bash
bash tests/nethunter/test_build_contract.sh
bash scripts/nethunter/build_target_modules.sh --validate-only \
  OP-ACE-5 "$KERNEL_SOURCE_ROOT" "$COMMON_OUT" /tmp/nh-build/OP-ACE-5
```

Validation-only checks pinned manifest and build prerequisites. Full module build needs synced source, compiled `Image modules` output, toolchain, `Module.symvers`, and the Qualcomm WLAN module build inputs.
