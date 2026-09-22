#!/usr/bin/env python3
"""Fix block-scope extern in task_mmu.c for ThinLTO+CFI compatibility.

The NoMount Suite integration patch adds:
    { extern void vfs_map_meta_override(const struct inode *,
                        dev_t *, unsigned long *);
      vfs_map_meta_override(inode, &dev, &ino); }

With CONFIG_LTO_CLANG_THIN + CONFIG_CFI_CLANG this generates GOT/PLT
entries that ld.lld rejects ("Unexpected GOT/PLT entries detected!").

This script replaces the block-scope extern with a direct call and adds
a file-scope extern declaration before show_map_vma().

--verify-placement: only check that the vfs_map_meta_override call sits
inside show_map_vma() (not a sibling function with identical context),
without modifying the file. Exits 1 on any mismatch.
"""
import re
import sys

args = [a for a in sys.argv[1:] if a != '--verify-placement']
verify_only = '--verify-placement' in sys.argv[1:]
path = args[0] if args else 'fs/proc/task_mmu.c'
content = open(path).read()


def find_show_map_vma(content):
    # Signature may span multiple lines (GKI 6.1: "static void\nshow_map_vma(...)")
    return re.search(r'\n(static\s+\w[\w\s\n]*?show_map_vma\s*\()', content)


def hook_inside_show_map_vma(content):
    m = find_show_map_vma(content)
    if m is None:
        print('ERROR: show_map_vma definition not found', file=sys.stderr)
        return False
    start = content.index('{', m.end())
    depth = 0
    for i in range(start, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0:
                return 'vfs_map_meta_override' in content[start:i + 1]
    print('ERROR: unbalanced braces in show_map_vma()', file=sys.stderr)
    return False


if verify_only:
    if not hook_inside_show_map_vma(content):
        print('ERROR: vfs_map_meta_override not inside show_map_vma() — hook landed in wrong function', file=sys.stderr)
        sys.exit(1)
    print('hook placement verified: inside show_map_vma()')
    sys.exit(0)

pattern = (
    r'\{\s*extern\s+void\s+vfs_map_meta_override\s*\([^)]*\)\s*;'
    r'\s*vfs_map_meta_override\s*\(\s*inode\s*,\s*&dev\s*,\s*&ino\s*\)\s*;\s*\}'
)
content, count = re.subn(pattern, 'vfs_map_meta_override(inode, &dev, &ino);',
                         content, flags=re.DOTALL)
if count == 0:
    print('ERROR: block-scope extern not found in task_mmu.c', file=sys.stderr)
    sys.exit(1)

m = find_show_map_vma(content)
if m is None:
    print('ERROR: show_map_vma definition not found', file=sys.stderr)
    sys.exit(1)
idx = m.start(1)

decl = ('#ifdef CONFIG_NOMOUNT\n'
        'extern void vfs_map_meta_override(const struct inode *, dev_t *, unsigned long *);\n'
        '#endif\n\n')
content = content[:idx] + decl + content[idx:]
open(path, 'w').write(content)
print(f'Fixed task_mmu.c: block-scope extern removed ({count}), file-scope extern added')