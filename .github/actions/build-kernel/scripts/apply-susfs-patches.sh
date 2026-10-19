set -euo pipefail
echo "::group::Apply SUSFS patches"
cd "$KERNEL_PLATFORM_FOLDER"
echo "Applying SUSFS patches..."
cp "$SUSFS_FOLDER/kernel_patches/fs/"* "$COMMON_KERNEL_FOLDER/fs/"
cp "$SUSFS_FOLDER/kernel_patches/include/linux/"* "$COMMON_KERNEL_FOLDER/include/linux/"

susfs_version=$(grep '#define SUSFS_VERSION' "$COMMON_KERNEL_FOLDER/include/linux/susfs.h" | awk -F'"' '{print $2}')
echo "SUSVER=$susfs_version" >> $GITHUB_ENV
echo "$susfs_version" >> "${ARTIFACTS_FOLDER}/${OP_MODEL}_${OP_OS_VERSION}.txt"
echo "SusFS Version: $susfs_version"

# Function to compare semantic versions
version_lte() {
  [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$1" ]
}

# The 2026-10-19 susfs4ksu update ("Sync with the official KernelSU
# main repo") regenerated 10_enable_susfs_for_ksu.patch against
# KernelSU main and changed sucompat.c/preinit.c/sulog.  Detect that
# variant by the preinit helpers it adds, so each fix-patch era uses a
# matching set instead of overwriting the previous one.
susfs_enable_is_kmain() {
  grep -q 'ksu_setup_preinit_file' \
    "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
}

# The "Add KernelSU Next" workflow step rewrites Kbuild for 6.12
# (KSUVER > 33095): it expands $(src) to $(abspath $(src)) and adds
# -I$(KSU_KERNEL_DIR)/include/uapi. The SUSFS fix patches were generated
# against the pristine upstream Kbuild, so hunk matching fails while
# those edits are present. Temporarily restore the upstream lines while
# patching and re-apply the workflow edits afterwards.
ksun_kbuild_normalize() {
  local kbuild="$KSUN_FOLDER/kernel/Kbuild"
  [ -f "$kbuild" ] || return 0
  KSU_KBUILD_SED_APPLIED=0
  if [ "$KERNEL_VER" = "6.12" ] && [ "$KSUVER" -gt 33095 ]; then
    if grep -qF '$(abspath $(src))' "$kbuild" || grep -qF ' -I$(KSU_KERNEL_DIR)/include/uapi' "$kbuild"; then
      sed -i 's|$(abspath $(src))|$(src)|g; s| -I$(KSU_KERNEL_DIR)/include/uapi||g' "$kbuild"
      KSU_KBUILD_SED_APPLIED=1
    fi
  fi
}

ksun_kbuild_finalize() {
  local kbuild="$KSUN_FOLDER/kernel/Kbuild"
  [ "${KSU_KBUILD_SED_APPLIED:-0}" = "1" ] || return 0
  sed -i 's|ccflags-y += -I$(KSU_KERNEL_DIR) -I$(KSU_KERNEL_DIR)/include|ccflags-y += -I$(KSU_KERNEL_DIR) -I$(KSU_KERNEL_DIR)/include -I$(KSU_KERNEL_DIR)/include/uapi|' "$kbuild"
  sed -i 's|$(src)|$(abspath $(src))|' "$kbuild"
  sed -i 's|$(srctree)/$(src)|$(abspath $(srctree)/$(src))|' "$kbuild"
  KSU_KBUILD_SED_APPLIED=0
}

if version_lte "${susfs_version:1}" "1.5.12"; then
  echo "NEED_HOOKS=true" >> $GITHUB_ENV
else
  echo "NEED_HOOKS=false" >> $GITHUB_ENV
fi

case "$susfs_version" in
  "v1.5.8")
    if [ "$KSU_TYPE" = "KSUN" ]; then
      patch -p1 --forward --fuzz=3 < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
      patch -p1 --forward --fuzz=3 < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_apk_sign.c.patch"
      patch -p1 --forward --fuzz=3 < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_core_hook.c.patch"
      patch -p1 --forward --fuzz=3 < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_selinux.c.patch"
      patch -p1 --forward --fuzz=3 < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_ksud.c.patch"
    else
      cd "$KSU_FOLDER"
      patch -p1 --forward --fuzz=3 < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    fi
    ;;
  "v1.5.9"|"v1.5.10"|"v1.5.11"|"v1.5.12")
    if [ "$KSU_TYPE" = "KSUN" ]; then
      cd "$KSUN_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
      for file in $(find ./kernel -maxdepth 2 -name "*.rej" -printf "%f\n" | cut -d'.' -f1); do
        echo "Patching file: $file.c with fix_$file.c.patch"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_$file.c.patch"
      done
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_kernel_compat.c.patch"
    else
      cd "$KSU_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    fi
    ;;
  "v2.0.0")
    if [ "$KSU_TYPE" = "KSUN" ]; then
      cd "$KSUN_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
      for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \;); do
        echo "Patching file: $file with fix_$file.patch"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_$file.patch"
      done
      echo "Patching Hook Mode!"
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/overwrite_hook_mode.patch"
      echo "Patching KSU_TOOLKIT Support for SusFS kernel!"
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/ksu_toolkit.patch"
      if [ "$KSUVER" -le 33095 ]; then
        echo "Patching Multi-manager Support for SusFS kernel!"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/multi_manager.patch"
      fi
      if [ "$KSUVER" -ge 33068 ] && [ "$KSUVER" -lt 33070 ]; then
        echo "Patching Multi-manager sepolicy Support for SusFS kernel!"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/multi_sepolicy_fix.patch"
      fi
    else
      cd "$KSU_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
    fi
    ;;
  "v2.1.0")
    if [ "$KSU_TYPE" = "KSUN" ]; then
      cd "$KSUN_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
      for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \;); do
        echo "Patching file: $file with fix_$file.patch"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_$file.patch"
      done
      echo "Patching Hook Mode!"
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/overwrite_hook_mode.patch"
      echo "Patching KSU_TOOLKIT Support for SusFS kernel!"
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/ksu_toolkit.patch"
      if [ "$KSUVER" -le 33095 ]; then
        echo "Patching Multi-manager Support for SusFS kernel!"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/multi_manager.patch"
      fi
      if [ "$KSUVER" -ge 33068 ] && [ "$KSUVER" -lt 33070 ]; then
        echo "Patching Multi-manager sepolicy Support for SusFS kernel!"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/multi_sepolicy_fix.patch"
      fi
    else
      cd "$KSU_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
    fi
    ;;
  "v2.2.0")
    if [ "$KSU_TYPE" = "KSUN" ]; then
      cd "$KSUN_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
      for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \;); do
        echo "Patching file: $file with fix_$file.patch"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_$file.patch"
      done
      echo "Patching Hook Mode!"
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/overwrite_hook_mode.patch"
      echo "Patching KSU_TOOLKIT Support for SusFS kernel!"
      patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/ksu_toolkit.patch"
    else
      cd "$KSU_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
    fi
    ;;
  "v2.3.0"|"v2.3"*)
    # SUSFS v2.3.0 refactored SUS_MOUNT/SUS_KSTAT/OPEN_REDIRECT and
    # changed the KernelSU integration. KSUN builds apply the enable
    # patch (tolerating rejects), resolve every reject with the
    # per-file fix patches and finish with the extras patch, all from
    # the kernel_patches repo (next/susfs_fix_patches/v2.3.0/).
    #
    # KernelSU-Next dev keeps moving, so three patch eras are needed:
    #   - KSUVER <= 33333: era-matched enable patch + fix patches
    #     generated against dev @ 2026-10-08 (old era).
    #   - KSUVER 33341..33390: enable patch from the SUSFS archive
    #     + fix patches in high-33341/ (dev @ 2026-10-15,
    #     compile-verified).
    #   - KSUVER >= 33397: enable patch from the SUSFS archive
    #     + fix patches in high/ (dev @ 2026-10-17, compile-verified).
    #   - 33334..33340 and 33391..33396: unsupported transition windows.
    if [ "$KSU_TYPE" = "KSUN" ]; then
      ksun_kbuild_normalize
      cd "$KSUN_FOLDER"
      if [ "$KSUVER" -ge 33397 ]; then
        if susfs_enable_is_kmain; then
          SUSFS_FIX_ERA="high-kmain"
        else
          SUSFS_FIX_ERA="high"
        fi
        echo "KSUVER=$KSUVER >= 33397: using $SUSFS_FIX_ERA/ SUSFS v2.3.0 fix patches"
        HIGH_DIR="$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/$SUSFS_FIX_ERA"
        if [ ! -f "$HIGH_DIR/susfs_extras.patch" ]; then
          echo "::error::Missing $HIGH_DIR - push FRTI64/kernel_patches (main) with the $SUSFS_FIX_ERA/ SUSFS v2.3.0 patch set first."
          exit 1
        fi
        patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
        for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \;); do
          fix="$HIGH_DIR/fix_$file.patch"
          if [ ! -f "$fix" ]; then
            echo "::error::Missing $fix - the high/ patch set in FRTI64/kernel_patches is incomplete or outdated for this KernelSU-Next commit."
            exit 1
          fi
          echo "Patching file: $file with fix_$file.patch ($SUSFS_FIX_ERA)"
          patch -p1 --forward < "$fix"
        done
        echo "Patching SUSFS extras ($SUSFS_FIX_ERA)!"
        patch -p1 --forward < "$HIGH_DIR/susfs_extras.patch"
      elif [ "$KSUVER" -ge 33341 ] && [ "$KSUVER" -le 33390 ]; then
        if susfs_enable_is_kmain; then
          echo "::error::KSUVER $KSUVER is too old for the KernelSU-main SUSFS sync. Pin SUSFS to a pre-2026-10-19 ref for this KernelSU-Next version, or move to KSUVER >= 33397."
          exit 1
        fi
        echo "KSUVER=$KSUVER in 33341..33390: using high-33341/ SUSFS v2.3.0 fix patches"
        HIGH_DIR="$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/high-33341"
        if [ ! -f "$HIGH_DIR/susfs_extras.patch" ]; then
          echo "::error::Missing $HIGH_DIR - push FRTI64/kernel_patches (main) with the high-33341/ SUSFS v2.3.0 patch set first."
          exit 1
        fi
        patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
        for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \;); do
          fix="$HIGH_DIR/fix_$file.patch"
          if [ ! -f "$fix" ]; then
            echo "::error::Missing $fix - the high-33341/ patch set in FRTI64/kernel_patches is incomplete or outdated for this KernelSU-Next commit."
            exit 1
          fi
          echo "Patching file: $file with fix_$file.patch (high-33341)"
          patch -p1 --forward < "$fix"
        done
        echo "Patching SUSFS extras (high-33341)!"
        patch -p1 --forward < "$HIGH_DIR/susfs_extras.patch"
      elif [ "$KSUVER" -le 33333 ]; then
        if susfs_enable_is_kmain; then
          echo "::error::KSUVER $KSUVER is too old for the KernelSU-main SUSFS sync. Pin SUSFS to a pre-2026-10-19 ref for this KernelSU-Next version, or move to KSUVER >= 33397."
          exit 1
        fi
        echo "KSUVER=$KSUVER <= 33333: using era-matched enable patch and SUSFS v2.3.0 fix patches"
        # The SUSFS archive's enable patch moved on with the Oct 12
        # KernelSU syncs; use the era-matched one stored in kernel_patches.
        OLD_ENABLE="$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/10_enable_susfs_for_ksu.patch"
        if [ ! -f "$OLD_ENABLE" ]; then
          echo "::error::Missing $OLD_ENABLE - push FRTI64/kernel_patches (main) with the era-matched SUSFS v2.3.0 enable patch first."
          exit 1
        fi
        patch -p1 --forward < "$OLD_ENABLE" || true
        for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \;); do
          echo "Patching file: $file with fix_$file.patch"
          patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_$file.patch"
        done
        echo "Patching SUSFS extras!"
        patch -p1 --forward < "$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/susfs_extras.patch"
      else
        echo "::error::KSUVER $KSUVER is in an unsupported SUSFS v2.3.0 transition window (33334-33340 or 33391-33396). Pin KernelSU-Next to KSUVER <= 33333, 33341..33390, or >= 33397."
        exit 1
      fi
      ksun_kbuild_finalize
      if ! grep -q 'config KSU_SUSFS' kernel/Kconfig; then
        echo "::error::SUSFS integration incomplete: KSU_SUSFS missing from KernelSU-Next Kconfig after patching."
        exit 1
      fi
    else
      cd "$KSU_FOLDER"
      patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    fi
    ;;
  *)
    echo "::error::Unsupported SUSFS version: $susfs_version"
    exit 1
    ;;
esac

cd "$COMMON_KERNEL_FOLDER"
if [ "$ANDROID_VER" = "android15" ] && [ "$KERNEL_VER" = "6.6" ]; then
  if ! grep -qxF '#include <trace/hooks/fs.h>' ./fs/namespace.c; then
    sed -i '/#include <trace\/hooks\/blk.h>/a #include <trace\/hooks\/fs.h>' ./fs/namespace.c
  fi
  if ! grep -qxF 'extern void __fold_filemap_fixup_entry(struct vma_iterator *iter, unsigned long *end);' ./include/linux/page_size_compat.h; then
    patch -p1 < "$KERNEL_PATCHES_FOLDER/common/backports/fold_fixup_entries.patch"
  fi
fi

# Fake kernel patch to fix failures
fake_patched=0
fake_patched_expand=0
fake_blk_hook_added=0
if [ "$ANDROID_VER" = "android15" ] && [ "$KERNEL_VER" = "6.6" ]; then
  if ! grep -qxF $'\tunsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;' ./fs/proc/task_mmu.c; then
    echo "nr_subpages Line not found. Fake Patching!"
    sed -i -e '/int ret = 0, copied = 0;/a \\tunsigned int nr_subpages \= __PAGE_SIZE \/ PAGE_SIZE;' -e '/int ret = 0, copied = 0;/a \\tpagemap_entry_t \*res = NULL;' ./fs/proc/task_mmu.c
    fake_patched=1
  fi
  
  if ! grep -qxF '#include <linux/dma-buf.h>' ./fs/proc/base.c; then
    echo "#include <linux/dma-buf.h> Line not found. Adding missing header"
    sed -i '/#include <linux\/cpufreq_times.h>/a #include <linux\/dma-buf.h>' ./fs/proc/base.c
  fi
  
  if ! grep -qxF '#include <linux/zswap.h>' ./mm/memory.c; then
    echo "#include <linux/zswap.h> Line not found. Adding missing header"
    sed -i '/#include <linux\/sched\/sysctl.h>/a #include <linux\/zswap.h>' ./mm/memory.c
  fi
  
  if grep -qF 'if (vma->vm_end > last_vma_end)' ./fs/proc/task_mmu.c && ! grep -qxF 'SUSFS_IS_INODE_SUS_MAP' ./fs/proc/task_mmu.c; then
    echo "Temporarily expand the last_vma_end if block to fix a matching issue."
    perl -i -0pe 's/\t\t\tif \(vma->vm_end > last_vma_end\)\n\t\t\t\tsmap_gather_stats\(vma, &mss, last_vma_end\);/\t\t\tif (vma->vm_end > last_vma_end) {\n\t\t\t\tsmap_gather_stats(vma, \&mss, last_vma_end);\n\t\t\t\tlast_vma_end = vma->vm_end;\n\t\t\t}/' ./fs/proc/task_mmu.c
    fake_patched_expand=1
  fi
fi
if [ "$ANDROID_VER" = "android12" ] && [ "$KERNEL_VER" = "5.10" ]; then
  if ! grep -qxF $'\tif (!vma_pages(vma))' ./fs/proc/task_mmu.c; then
    echo "vma_pages Line not found. Fake Patching!"
    fake_patched=1
  fi
fi
if [ "$ANDROID_VER" = "android13" ] && [ "$KERNEL_VER" = "5.15" ]; then
  if ! grep -qxF $'\tif (!vma_pages(vma))' ./fs/proc/task_mmu.c; then
    echo "vma_pages Line not found. Fake Patching!"
    fake_patched=1
  fi
  
  if grep -qxF '#include <linux/swap_slots.h>' ./mm/memory.c; then
    echo "#include swap_slots.h> Line found. Deleting header."
    sed -i '/#include <linux\/swap_slots.h>/d' ./mm/memory.c
    fake_patched=1
  fi
  
  # The gki-android13-5.15 susfs patch was rebased onto
  # android13-5.15.211 (2026-10-18); its anchors are the GKI
  # trace-hook includes that the OnePlus 5.15 vendor kernels lack.
  if ! grep -qxF '#include <trace/hooks/mm.h>' ./fs/proc/task_mmu.c; then
    echo "#include <trace/hooks/mm.h> Line not found. Fake Patching!"
    sed -i '/#include <linux\/pkeys.h>/a #include <trace\/hooks\/mm.h>' ./fs/proc/task_mmu.c
    fake_patched=1
  fi
  if ! grep -qxF '#include <trace/hooks/blk.h>' ./fs/namespace.c; then
    echo "#include <trace/hooks/blk.h> Line not found. Fake Patching!"
    sed -i '/#include "internal.h"/a #include <trace\/hooks\/blk.h>' ./fs/namespace.c
    fake_patched=1
  fi
fi
if [ "$ANDROID_VER" = "android16" ] && [ "$KERNEL_VER" = "6.12" ]; then
  # The gki-android16-6.12 susfs patch was rebased onto
  # android16-6.12.92 (2026-10-18). OnePlus 6.12 vendor kernels:
  # - exec.c lacks the dma-buf.h include the patch anchors on;
  # - task_mmu.c's show_smap/show_smaps_rollup use a different
  #   structure than 6.12.92, so the SUS_MAP hunks cannot match.
  #   Insert the SUS_MAP blocks ourselves; the patch's remaining
  #   hunks apply normally (their failures are tolerated below).
  if ! grep -qxF '#include <linux/dma-buf.h>' ./fs/exec.c; then
    echo "#include <linux/dma-buf.h> Line not found in exec.c. Fake Patching!"
    sed -i '/#include <linux\/ksm.h>/a #include <linux\/dma-buf.h>' ./fs/exec.c
  fi
  if ! grep -q 'SUSFS_IS_INODE_SUS_MAP' ./fs/proc/task_mmu.c; then
    echo "SUS_MAP blocks missing in task_mmu.c. Fake Patching!"
    perl -i -0pe 's/(static int show_smap\(struct seq_file \*m, void \*v\)\n\{\n\tstruct vm_area_struct \*vma = v;\n\tstruct mem_size_stats mss = \{\};\n)/$1#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\n/' ./fs/proc/task_mmu.c
    perl -i -0pe 's/(\tdo \{\n\t\tsmap_gather_stats\(vma, &mss, 0\);\n\t\tlast_vma_end = vma->vm_end;)/\tdo {\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tif (vma->vm_file \&\& SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n#endif\n\t\tsmap_gather_stats(vma, \&mss, 0);\n\t\tlast_vma_end = vma->vm_end;\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif/' ./fs/proc/task_mmu.c
    fake_patched=1
  fi
fi

if [ "$ANDROID_VER" = "android14" ] && [ "$KERNEL_VER" = "6.1" ]; then
  if ! grep -qxF $'\tif (!vma_pages(vma))' ./fs/proc/task_mmu.c; then
    echo "vma_pages Line not found. Fake Patching!"
    fake_patched=1
  fi
  
  if ! grep -qxF '#include <linux/dma-buf.h>' ./fs/proc/base.c; then
    echo "#include <linux/dma-buf.h> Line not found. Adding missing header"
    sed -i '/#include <linux\/cpufreq_times.h>/a #include <linux\/dma-buf.h>' ./fs/proc/base.c
  fi

  # The gki-android14-6.1 50_add_susfs patch anchors its first
  # fs/namespace.c hunk on <trace/hooks/blk.h>, a GKI-only include that
  # the OnePlus mt6897 vendor tree does not ship. Insert a temporary
  # anchor so the hunk matches, then drop it again after patching so the
  # build does not fail on the missing header.
  if ! grep -qxF '#include <trace/hooks/blk.h>' ./fs/namespace.c; then
    echo "#include <trace/hooks/blk.h> Line not found. Fake Patching!"
    sed -i '/#include "internal.h"/a #include <trace\/hooks\/blk.h>' ./fs/namespace.c
    fake_blk_hook_added=1
  fi
fi

# android16-6.12 vendor kernels pre-insert the SUS_MAP blocks via the
# fake patches above, so the rebased patch's corresponding hunks are
# expected to reject; tolerate the failure there and verify instead.
if [ "$ANDROID_VER" = "android16" ] && [ "$KERNEL_VER" = "6.12" ]; then
  patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/50_add_susfs_in_$SUSFS_KERNEL_BRANCH.patch" || true
  grep -q 'SUSFS_IS_INODE_SUS_MAP' ./fs/proc/task_mmu.c || { echo "::error::6.12 SUS_MAP fake patches did not apply to task_mmu.c."; exit 1; }
  grep -q 'bypass_orig_flow' ./fs/proc/task_mmu.c || { echo "::error::6.12 SUS_MAP rollup fake patch did not apply to task_mmu.c."; exit 1; }
  grep -q '#include <linux/dma-buf.h>' ./fs/exec.c || { echo "::error::6.12 exec.c dma-buf.h fake patch did not apply."; exit 1; }
else
  patch -p1 --forward < "$SUSFS_FOLDER/kernel_patches/50_add_susfs_in_$SUSFS_KERNEL_BRANCH.patch"
fi

# SUSFS's OPEN_REDIRECT code unconditionally calls VMA_PAD_START(), which
# only exists on GKI branches that carry Google's page-size-migration
# feature (added to each android version's kernel/common branch at a
# different, sometime later, os_patch_level). Older os_patch_levels in
# our build matrix predate it, so fall back to a no-padding definition
# when the real header/macro isn't present. This is version-agnostic and
# a no-op wherever the real header already provides it.
if grep -q 'VMA_PAD_START(' ./fs/proc/task_mmu.c && ! grep -qE '#include <linux/pgsize_migration(_inline)?\.h>|define VMA_PAD_START' ./fs/proc/task_mmu.c; then
  sed -i '\|#include "internal.h"|a\\n#undef VMA_PAD_START\n#ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif' fs/proc/task_mmu.c
  echo "Added VMA_PAD_START fallback definition to fs/proc/task_mmu.c"
fi

# Revert Fake kernel patch
if [ "$fake_patched_expand" = 1 ]; then
  if [ "$ANDROID_VER" = "android15" ] && [ "$KERNEL_VER" = "6.6" ]; then
    if grep -qF 'if (vma->vm_end > last_vma_end) {' ./fs/proc/task_mmu.c && ! grep -qxF 'SUSFS_IS_INODE_SUS_MAP' ./fs/proc/task_mmu.c; then
      perl -i -0pe 's/\t\t\tif \(vma->vm_end > last_vma_end\) \{\n\t\t\t\tsmap_gather_stats\(vma, &mss, last_vma_end\);\n\t\t\t\tlast_vma_end = vma->vm_end;\n\t\t\t\}/\t\t\tif (vma->vm_end > last_vma_end)\n\t\t\t\tsmap_gather_stats(vma, \&mss, last_vma_end);/' ./fs/proc/task_mmu.c
    fi
  fi
fi

if [ "$fake_patched" = 1 ]; then
  if [ "$ANDROID_VER" = "android15" ] && [ "$KERNEL_VER" = "6.6" ]; then
    if grep -qxF $'\tunsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;' ./fs/proc/task_mmu.c; then
      echo "nr_subpages Line found. Revert Fake Patching!"
      sed -i -e '/unsigned int nr_subpages \= __PAGE_SIZE \/ PAGE_SIZE;/d' -e '/pagemap_entry_t \*res = NULL;/d' ./fs/proc/task_mmu.c
    fi
  fi
  if [ "$ANDROID_VER" = "android12" ] && [ "$KERNEL_VER" = "5.10" ]; then
    if grep -qxF $'\t\t\tgoto show_pad;' ./fs/proc/task_mmu.c; then
      echo "vma_pages Line found. Revert Fake Patching!"
      sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c
    fi
  fi
  if [ "$ANDROID_VER" = "android13" ] && [ "$KERNEL_VER" = "5.15" ]; then
    if grep -qxF $'\t\t\tgoto show_pad;' ./fs/proc/task_mmu.c; then
      echo "vma_pages Line found. Revert Fake Patching!"
      sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c
    fi
    
    if ! grep -qxF '#include <linux/swap_slots.h>' ./mm/memory.c; then
      echo "#include <linux/swap_slots.h> Line not found. Adding missing header"
      sed -i '/#include <linux\/vmalloc.h>/a #include <linux\/swap_slots.h>' ./mm/memory.c
    fi

    # OnePlus 5.15 vendor kernels ship include/trace/hooks/block.h, not
    # blk.h. The fake blk.h include inserted above exists only to anchor
    # the rebased 50_add_susfs patch hunks; leaving it in makes
    # fs/namespace.o fail with "trace/hooks/blk.h: file not found".
    if grep -qxF '#include <trace/hooks/blk.h>' ./fs/namespace.c; then
      echo "Removing fake trace/hooks/blk.h anchor include from fs/namespace.c"
      sed -i '/#include <trace\/hooks\/blk.h>/d' ./fs/namespace.c
    fi
  fi
  if [ "$ANDROID_VER" = "android14" ] && [ "$KERNEL_VER" = "6.1" ]; then
    if grep -qxF $'\t\t\tgoto show_pad;' ./fs/proc/task_mmu.c; then
      echo "vma_pages Line found. Revert Fake Patching!"
      sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c
    fi
  fi
fi

# Drop the temporary blk.h anchor added for the android14-6.1 vendor tree.
# OnePlus kernels do not provide include/trace/hooks/blk.h, so leaving it
# in place would break the fs/namespace.o compile.
if [ "$fake_blk_hook_added" = 1 ]; then
  if grep -qxF '#include <trace/hooks/blk.h>' ./fs/namespace.c; then
    echo "Removing fake trace/hooks/blk.h anchor include from fs/namespace.c"
    sed -i '/#include <trace\/hooks\/blk.h>/d' ./fs/namespace.c
  fi
fi
echo "✅ SUSFS patches applied"

echo "Add SUSFS Configuration Settings"
case "$susfs_version" in
  "v2.1.0"|"v2.2.0"|"v2.3.0"|"v2.3"*)
    # v2.1.0+ unified Kconfig option set
    cat >> "$COMMON_KERNEL_FOLDER/arch/arm64/configs/gki_defconfig" <<EOF
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
    ;;
  "v2.0.0")
    cat >> "$COMMON_KERNEL_FOLDER/arch/arm64/configs/gki_defconfig" <<EOF
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
    ;;
  *)
    # v1.5.x legacy option set
    cat >> "$COMMON_KERNEL_FOLDER/arch/arm64/configs/gki_defconfig" <<EOF
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SUS_SU=n
EOF
    ;;
esac

echo "::endgroup::"
