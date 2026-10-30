# SUSFS Compatibility Patch Framework

Replaces ad-hoc bash `grep`/`sed`/`patch` blocks with a declarative,
idempotent, per-KMI/sublevel compatibility system for applying SUSFS onto
GKI common kernel trees of various ages.

```
scripts/
├── fix_susfs_compatibility_patches.py   # this framework
└── README.md                            # this file
```

---

## 1. Pipeline shape

```
stage 1 (pre)  ──►  GitHub Actions applies 50_add_susfs_...patch
                     (or a complete fixed/alternate variant of it)
                                 │
                                 ▼
stage 2 (post) ──►  re-inspect the FINAL tree, finish/undo edits
```

The Python script **never calls `patch` itself**. GitHub Actions is
responsible for choosing and running the actual SUSFS patch between stage 1
and stage 2. This keeps patch-selection logic (dry-run, fallback-on-failure)
in the CI step where it belongs, and keeps this script purely about
file-level C source edits.

### Why stage 2 never trusts stage-1 line numbers

`50_add_susfs_in_X.patch` or a fixed/alternate variant of it can shift line
numbers, reorder code, or produce a different final shape. Stage 2 rules
**re-scan the current file from scratch** using anchors/regex/predicates —
they never assume anything about where stage 1 left things.

---

## 2. CLI usage

```bash
python3 scripts/fix_susfs_compatibility_patches.py \
  --stage 1 \
  --root "$COMMON_KERNEL_FOLDER" \
  --kmi "$KMI" \
  --sublevel "$SUBLEVEL" \
  --state "$RUNNER_TEMP/susfs-compat-${KMI}-${SUBLEVEL}.json"

# ... GitHub Actions applies 50_add_susfs_...patch (or a fixed variant) here ...

python3 scripts/fix_susfs_compatibility_patches.py \
  --stage 2 \
  --root "$COMMON_KERNEL_FOLDER" \
  --kmi "$KMI" \
  --sublevel "$SUBLEVEL" \
  --state "$RUNNER_TEMP/susfs-compat-${KMI}-${SUBLEVEL}.json"
```

| Flag | Required | Meaning |
|---|---|---|
| `--stage` | yes | `1`/`pre` = before the SUSFS patch; `2`/`post` = after |
| `--root` | yes | Path to the kernel source tree (`common/`) |
| `--kmi` | yes | e.g. `android15-6.6` — must match `Target.kmi` |
| `--sublevel` | yes | Integer, e.g. `30` — matched against `Target.min_sublevel`/`max_sublevel` |
| `--state` | no | JSON file tracking which stage-1 rules actually changed something. Defaults to `<root>/.susfs-compat-state.json`. **Use a path outside the kernel tree** (e.g. `$RUNNER_TEMP`) so it isn't accidentally included in build artifacts or git-added. |
| `--dry-run` | no | Logs what would happen; writes nothing; state file is not updated |

Exit code `0` = success, `1` = a `CompatError` was raised (handled failure,
message explains why), `2` = bad `--root`.

### Recommended GitHub Actions wiring

```bash
set -Eeuo pipefail

KMI="${{ env.ANDROID_VER }}-${{ env.KERNEL_VER }}"
SUBLEVEL="${{ env.SUBLEVEL }}"
STATE_FILE="$RUNNER_TEMP/susfs-compat-${KMI}-${SUBLEVEL}.json"

cd "$COMMON_KERNEL_FOLDER"

python3 "$GITHUB_WORKSPACE/scripts/fix_susfs_compatibility_patches.py" \
  --stage 1 --root "$COMMON_KERNEL_FOLDER" --kmi "$KMI" --sublevel "$SUBLEVEL" \
  --state "$STATE_FILE"

MAIN_PATCH="$SUSFS_FOLDER/kernel_patches/50_add_susfs_in_${{ env.SUSFS_KERNEL_BRANCH }}.patch"
FIX_PATCH="$KERNEL_PATCHES_FOLDER/next/susfs_fix_patches/$susfs_version/fix_50_add_susfs_in_${{ env.SUSFS_KERNEL_BRANCH }}.patch"

can_apply() { patch --dry-run --batch --forward --fuzz=0 -p1 < "$1"; }
apply()     { patch --batch --forward --fuzz=0 -p1 < "$1"; }

if can_apply "$MAIN_PATCH"; then
  apply "$MAIN_PATCH"
elif [[ -f "$FIX_PATCH" ]] && can_apply "$FIX_PATCH"; then
  apply "$FIX_PATCH"
else
  echo "::error::Neither the normal nor fixed SUSFS patch applies cleanly."
  exit 1
fi

python3 "$GITHUB_WORKSPACE/scripts/fix_susfs_compatibility_patches.py" \
  --stage 2 --root "$COMMON_KERNEL_FOLDER" --kmi "$KMI" --sublevel "$SUBLEVEL" \
  --state "$STATE_FILE"
```

`FIX_PATCH` here is treated as a **complete alternate** `50_add_susfs...patch`
for this baseline — not a partial "repair the rejects" patch. Dry-run both,
apply exactly one. Never apply the main patch partially and then layer a fix
patch on top of a half-patched tree.

---

## 3. `Target` — matching KMI/sublevel

```python
Target(kmi: str = "*", min_sublevel: int | None = None, max_sublevel: int | None = None)
```

| Field | Meaning |
|---|---|
| `kmi` | Exact match string, or `"*"` for any KMI |
| `min_sublevel` | Rule requires `sublevel >= min_sublevel` |
| `max_sublevel` | Rule requires `sublevel <= max_sublevel` |

```python
Target("android15-6.6")                                  # any sublevel
Target("android15-6.6", max_sublevel=30)                  # sublevel <= 30
Target("android13-5.15", min_sublevel=123)                # sublevel >= 123
Target("android12-5.10", min_sublevel=50, max_sublevel=100)
Target("*")                                               # every KMI/sublevel
```

`Rule.targets` is a tuple — matches are OR'd:

```python
targets=(Target("android14-6.1"), Target("android15-6.6", max_sublevel=30))
```

---

## 4. `Rule` — full field reference

```python
Rule(
    rule_id: str,
    stage: int,
    targets: tuple[Target, ...],
    edit: Edit,
    when: Callable[[Context], bool] | None = None,
    track_pre_change: bool = False,
    requires_pre_change: str | None = None,
    description: str = "",
)
```

| Field | Meaning |
|---|---|
| `rule_id` | Globally unique ID. Used as the state-file key and referenced by `requires_pre_change`. Convention: `"<kmi-short>-<what>"`, e.g. `"a15-66-zswap-header"`; use `"all-..."` for `Target("*")` rules. |
| `stage` | `1` = before SUSFS patch, `2` = after. |
| `targets` | Tuple of `Target`, OR'd. |
| `edit` | An `Edit` instance (see §5). |
| `when` | Extra guard evaluated against the **current** file content, independent of KMI/sublevel. Use this to react to what the applied patch actually produced. |
| `track_pre_change` | Stage-1 only. If `edit.apply()` returns `True`, record `rule_id → True` in the state file. |
| `requires_pre_change` | Stage-2 only. Skip this rule unless the named stage-1 rule actually changed something. Prevents reverting code that was never added. |
| `description` | Human-readable log line. |

### Why both `targets` and `when` matter

`targets` answers *"does this KMI/sublevel need this kind of fix at all."*
`when` answers *"given what the file actually looks like right now, is the
fix still needed."* You need both because:

- the same KMI/sublevel might get fixed by either the normal or the fixed
  `50` patch, producing two different final shapes;
- a cached/reused workspace might already have the fix applied;
- some facts (does this header already declare this symbol?) can't be
  derived from KMI/sublevel alone.

---

## 5. `Edit` types — full reference

### 5.1 `InsertRelative`

```python
InsertRelative(
    relative_path: str,
    anchors: tuple[str, ...],
    payload: tuple[str, ...],
    before: bool = False,
    occurrence: str = "first",   # "first" | "last"
    adjacent: bool = False,
)
```

| Field | Meaning |
|---|---|
| `relative_path` | File, relative to kernel root |
| `anchors` | Regexes tried **in order**; first one with any match wins |
| `payload` | One or more exact lines to insert, as a contiguous block |
| `before` | Insert before the anchor line instead of after |
| `occurrence` | If the anchor matches multiple lines, use `"first"` or `"last"` match |
| `adjacent` | If `True`, "already applied" requires the payload to sit immediately next to the anchor — not just exist anywhere in the file. Use this when a payload line could plausibly appear elsewhere too (so a naive existence check would false-positive). |

**Idempotency rule:** if *all* payload lines already exist (or, with
`adjacent=True`, exist in the right spot), nothing happens. If *some but not
all* exist, it raises `CompatError` — a partial match usually means the
source drifted in a way you haven't accounted for, and silently proceeding
could produce a broken half-insert.

**Examples**

Single header:
```python
InsertRelative(
    relative_path="fs/proc/base.c",
    anchors=(r"^#include <linux/cpufreq_times\.h>$",),
    payload=("#include <linux/dma-buf.h>",),
)
```

Insert before, instead of after:
```python
InsertRelative(
    relative_path="mm/memory.c",
    anchors=(r"^#ifdef CONFIG_KSU_SUSFS_SUS_MAP$",),
    payload=("#include <linux/swap_slots.h>",),
    before=True,
)
```

Multiple fallback anchors (normal patch vs. fixed patch differ):
```python
InsertRelative(
    relative_path="mm/memory.c",
    anchors=(
        r"^#ifdef CONFIG_KSU_SUSFS_SUS_MAP$",   # present if normal 50 applied
        r"^#ifdef CONFIG_KSU_SUSFS$",            # present if fix_50 used a coarser guard
        r"^#include <linux/vmalloc\.h>$",        # last-resort anchor always present
    ),
    payload=("#include <linux/swap_slots.h>",),
    before=True,
)
```

Multi-line payload (new helper function):
```python
InsertRelative(
    relative_path="fs/notify/fdinfo.c",
    anchors=(r"^static void inotify_fdinfo\(struct seq_file \*m, struct fsnotify_mark \*mark\)$",),
    before=True,
    payload=(
        "static inline u32 inotify_mark_user_mask(struct fsnotify_mark *mark)",
        "{",
        "\treturn mark->mask & IN_ALL_EVENTS;",
        "}",
        "",
    ),
)
```

`occurrence="last"`, landing after the last of several similar lines:
```python
InsertRelative(
    relative_path="fs/namespace.c",
    anchors=(r"^#include <trace/hooks/.*\.h>$",),
    occurrence="last",
    payload=("#include <trace/hooks/fs.h>",),
)
```

---

### 5.2 `RemoveExactLines` (updated)

```python
RemoveExactLines(
    relative_path: str,
    lines_to_remove: tuple[str, ...],
    occurrence: str = "all",        # "all" | "first" | "last"
    expected_count: int | None = None,
    within: Scope | None = None,
)
```

| Field | Meaning |
|---|---|
| `relative_path` | File to edit |
| `lines_to_remove` | One or more exact, whitespace-sensitive lines |
| `occurrence` | Which match(es), after `within` filtering, to actually remove |
| `expected_count` | **Strongly recommended.** Raise `CompatError` unless exactly this many matches are found. The single biggest safety net against accidentally nuking every occurrence of a generic line. |
| `within` | A `Scope` (see below) restricting which matches are even eligible. Matches outside scope ranges are ignored entirely — not counted, not removed. |

⚠️ **Without `expected_count` or `within`, this removes every line in the
whole file that equals one of `lines_to_remove`.** That's fine for something
like a full `#include` path, but dangerous for generic lines such as
`\treturn 0;`. Always add at least one of `expected_count` / `within` unless
the line is unmistakably unique.

#### `Scope` — restricting *where* a match counts

```python
class Scope(ABC):
    def ranges(self, lines: list[str]) -> list[tuple[int, int]]: ...
```

Two implementations:

##### `BraceScope(start_anchor: str)` — brace-depth aware, safe for C blocks

Finds the first `{` at or after each line matching `start_anchor`, then
locates its **true matching** `}` using a comment/string-literal-aware
brace-depth scanner (`_find_matching_brace`). This means nested blocks,
nested struct/array initializers, and braces inside `//`/`/* */` comments or
`"..."`/`'...'` literals do **not** get mistaken for the enclosing block's
closing brace.

```python
# Scope = the entire body of pagemap_read(), regardless of what's nested
# inside it (structs, arrays, if-blocks, etc.)
BraceScope(r"^static ssize_t pagemap_read\(")
```

This specifically fixes the earlier naive-regex bug: something like

```c
static ssize_t pagemap_read(...)
{
	int values[] = {
		1, 2, 3
	};
	pagemap_entry_t *res = NULL;
	...
}
```

is handled correctly — the inner `}` of the array initializer is counted at
depth 2 and does not terminate the scope early; only the real function-level
`}` (depth back to 0) does.

Known limitations (acceptable for kernel C in practice):
- does not evaluate `#if`/`#ifdef`/`#endif` — braces inside a disabled
  `#if 0` block are still counted literally;
- does not expand macros; a macro that textually contains unbalanced braces
  would confuse it (effectively never happens in GKI-style kernel code).

##### `LineRangeScope(start_anchor: str, end_anchor: str)` — naive, use sparingly

Simple forward line scan from `start_anchor` to the next `end_anchor`,
**not** brace-depth aware. Only safe for markers that genuinely cannot
nest/repeat inside the region (e.g. your own unique comment markers, or a
flat `#include` block).

```python
LineRangeScope(r"^/\* SUSFS_BLOCK_START \*/$", r"^/\* SUSFS_BLOCK_END \*/$")
```

Do **not** use `LineRangeScope` to bound a C function/struct body — use
`BraceScope` for that.

**Examples**

Unique include, still defensively counted:
```python
RemoveExactLines(
    relative_path="mm/memory.c",
    lines_to_remove=("#include <linux/swap_slots.h>",),
    expected_count=1,
)
```

Generic-looking variable declarations, scoped to one function:
```python
RemoveExactLines(
    relative_path="fs/proc/task_mmu.c",
    lines_to_remove=(
        "\tunsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;",
        "\tpagemap_entry_t *res = NULL;",
    ),
    within=BraceScope(r"^static ssize_t pagemap_read\("),
    expected_count=2,
)
```

For truly generic lines (`\treturn 0;`, `}` alone, etc.), **don't use
`RemoveExactLines` at all** — fold enough surrounding context into a
`ReplaceRegex` pattern instead (see §5.4).

---

### 5.3 `RemoveBlock`

```python
RemoveBlock(relative_path: str, start: str, end: str)
```

Deletes every line from the first line matching `start` through the next
line matching `end` (inclusive), for all non-overlapping occurrences.
Mirrors `sed '/start/,/end/d'`. Same "not brace-depth aware" caveat as
`LineRangeScope` — use for comment blocks or clearly delimited regions, not
for C code blocks.

```python
RemoveBlock(
    relative_path="fs/notify/fdinfo.c",
    start=r"^[ \t]*/\*$",
    end=r"^[ \t]*u32 mask = mark->mask & IN_ALL_EVENTS;$",
)
```

Naturally idempotent: if `start` no longer matches anywhere (block already
removed), nothing happens.

---

### 5.4 `ReplaceRegex`

```python
ReplaceRegex(
    relative_path: str,
    pattern: str,
    replacement: str,
    must_find: bool = False,
    expected_count: int | None = None,
    flags: int = re.MULTILINE,
)
```

| Field | Meaning |
|---|---|
| `pattern` | Regex matched against the **whole file content** |
| `replacement` | Replacement string; supports `\1`, `\2`, ... backreferences |
| `must_find` | Raise if the pattern matches **zero** times — use for rewrites that must never silently no-op |
| `expected_count` | Raise unless the substitution count equals exactly this |
| `flags` | Default `re.MULTILINE`; add `re.DOTALL` for patterns spanning blank lines |

**Examples**

Single-line, preserve indentation via capture group:
```python
ReplaceRegex(
    relative_path="fs/proc/task_mmu.c",
    pattern=r"^(\s*)goto show_pad;$",
    replacement=r"\1return 0;",
)
```

Multi-line structural rewrite:
```python
ReplaceRegex(
    relative_path="fs/proc/task_mmu.c",
    pattern=(
        r"\t\t\tif \(vma->vm_end > last_vma_end\)\n"
        r"\t\t\t\tsmap_gather_stats\(vma, &mss, last_vma_end\);"
    ),
    replacement=(
        "\t\t\tif (vma->vm_end > last_vma_end) {\n"
        "\t\t\t\tsmap_gather_stats(vma, &mss, last_vma_end);\n"
        "\t\t\t\tlast_vma_end = vma->vm_end;\n"
        "\t\t\t}"
    ),
)
```

Context-anchored removal of a generic-looking line (safer than
`RemoveExactLines` for this case, because the surrounding function signature
is baked right into the pattern):
```python
ReplaceRegex(
    relative_path="fs/proc/task_mmu.c",
    pattern=r"(pagemap_read\([^\n]*\n(?:.*\n)*?)\tpagemap_entry_t \*res = NULL;\n",
    replacement=r"\1",
    must_find=True,
    expected_count=1,
)
```

`must_find=True` for a required rewrite:
```python
ReplaceRegex(
    relative_path="fs/exec.c",
    pattern=r"\bgetname_flags\(filename, lookup_flags, NULL\)",
    replacement="getname_flags(filename, lookup_flags)",
    must_find=True,
)
```

`expected_count` to catch a rename matching more/fewer places than audited:
```python
ReplaceRegex(
    relative_path="fs/proc/task_mmu.c",
    pattern=r"\bvma_data_pages\b",
    replacement="vma_pages",
    expected_count=3,
)
```

`re.DOTALL` for a pattern spanning blank lines:
```python
ReplaceRegex(
    relative_path="fs/proc/base.c",
    pattern=r"int this_len = min_t\(int,.*?PAGE_SIZE\);",
    replacement="size_t this_len = min_t(size_t, count, PAGE_SIZE);",
    flags=re.MULTILINE | re.DOTALL,
)
```

---

### 5.5 `ReplaceExactLine`

```python
ReplaceExactLine(
    relative_path: str,
    old_line: str,
    new_line: str,
    occurrence: str = "all",   # "all" | "first" | "last"
)
```

Literal whole-line swap, no regex escaping needed on either side. Prefer
this over `ReplaceRegex` whenever both old and new text are fixed strings —
it avoids subtle `re.escape()` mistakes.

```python
ReplaceExactLine(
    relative_path="fs/namei.c",
    old_line="\tset_nameidata(nd, old_dfd, fake_filename, NULL);",
    new_line="\tset_nameidata(nd, old_dfd, fake_filename);",
)
```

---

### 5.6 `Composite`

```python
Composite(edits: tuple[Edit, ...])
```

Groups multiple edits under one `rule_id`, so they're tracked/reverted as a
single logical change (useful for `requires_pre_change` referencing the
whole bundle, not just one half).

**Not transactional** — if a later sub-edit raises `CompatError`, earlier
sub-edits in the same `Composite` have already been written. Acceptable in
CI since a raised error aborts the whole job and the checkout is discarded
on the next run; don't rely on it anywhere partial application would be
silently tolerated.

```python
Composite((
    RemoveBlock(
        relative_path="fs/notify/fdinfo.c",
        start=r"^[ \t]*/\*$",
        end=r"^[ \t]*u32 mask = mark->mask & IN_ALL_EVENTS;$",
    ),
    ReplaceRegex(
        relative_path="fs/notify/fdinfo.c",
        pattern=r"\bmask,\s*mark->ignored_mask\b",
        replacement="inotify_mark_user_mask(mark)",
    ),
    InsertRelative(
        relative_path="fs/notify/fdinfo.c",
        anchors=(r"^static void inotify_fdinfo\(struct seq_file \*m, struct fsnotify_mark \*mark\)$",),
        before=True,
        payload=(
            "static inline u32 inotify_mark_user_mask(struct fsnotify_mark *mark)",
            "{",
            "\treturn mark->mask & IN_ALL_EVENTS;",
            "}",
            "",
        ),
    ),
))
```

---

## 6. Decision table — which `Edit` to pick

| You need to... | Use |
|---|---|
| Add fixed lines near an anchor, permanently | `InsertRelative` |
| Add lines near an anchor that may shift between patch variants | `InsertRelative` with multiple `anchors` |
| Remove exact, uniquely-identifiable lines | `RemoveExactLines` + `expected_count` |
| Remove generic-looking lines, but only within one function/struct | `RemoveExactLines` + `within=BraceScope(...)` + `expected_count` |
| Remove generic-looking lines, truly file-wide | **Don't.** Use `ReplaceRegex` with enough baked-in surrounding context |
| Remove a comment/code block between two unique markers | `RemoveBlock` |
| Rewrite a structural, possibly multi-line pattern | `ReplaceRegex` |
| Swap one exact literal line for another | `ReplaceExactLine` |
| Rename a symbol/token file-wide | `ReplaceRegex` with `\b...\b`, plus `expected_count` if auditable |
| Bundle 2+ edits as one logical/trackable change | `Composite` |
| React to actual file content rather than KMI/sublevel | add `when=...`, often with `targets=(Target("*"),)` |
| Undo something only if you added it, and only if the patch didn't finalize it there itself | `track_pre_change=True` (stage 1) + `requires_pre_change="<id>"` + a `when` guard (stage 2) |

---

## 7. Full case catalog

### A — Permanent missing header
```python
Rule(
    rule_id="a14-61-dma-buf-header",
    stage=1,
    targets=(Target("android14-6.1", max_sublevel=141),),
    edit=InsertRelative(
        relative_path="fs/proc/base.c",
        anchors=(r"^#include <linux/cpufreq_times\.h>$",),
        payload=("#include <linux/dma-buf.h>",),
    ),
)
```
No stage-2 counterpart needed.

### B — Permanent fix, bounded by sublevel where upstream later fixed it
```python
Rule(
    rule_id="a15-66-dma-buf-header",
    stage=1,
    targets=(Target("android15-6.6", max_sublevel=92),),  # fixed upstream at 93+
    edit=InsertRelative(
        relative_path="fs/proc/base.c",
        anchors=(r"^#include <linux/cpufreq_times\.h>$",),
        payload=("#include <linux/dma-buf.h>",),
    ),
)
```

### C — Remove-then-restore (temporary removal, scoped restore)
```python
Rule(
    rule_id="a13-515-swap-slots-remove-temporarily",
    stage=1,
    targets=(Target("android13-5.15", min_sublevel=123),),
    track_pre_change=True,
    description="Patch context doesn't expect swap_slots.h yet; remove temporarily",
    edit=RemoveExactLines(
        relative_path="mm/memory.c",
        lines_to_remove=("#include <linux/swap_slots.h>",),
        expected_count=1,
    ),
),
Rule(
    rule_id="a13-515-swap-slots-restore",
    stage=2,
    targets=(Target("android13-5.15", min_sublevel=123),),
    requires_pre_change="a13-515-swap-slots-remove-temporarily",
    description="Restore header at its final location after patch",
    edit=InsertRelative(
        relative_path="mm/memory.c",
        anchors=(
            r"^#ifdef CONFIG_KSU_SUSFS_SUS_MAP$",
            r"^#include <linux/vmalloc\.h>$",
        ),
        payload=("#include <linux/swap_slots.h>",),
        before=True,
    ),
),
```
The stage-2 rule only runs if `requires_pre_change` recorded a real
stage-1 change on this tree. It tries the normal-patch anchor first, then
falls back to a last-resort anchor that should always exist.

### D — Multiple fallback anchors for divergent patch variants
See §5.1 "Multiple fallback anchors" example.

### E — New helper function insertion (multi-line payload)
See §5.1 "Multi-line payload" example.

### F — Temporary structural reshape + conditional stage-2 revert
```python
Rule(
    rule_id="a15-66-expand-last-vma-block",
    stage=1,
    targets=(Target("android15-6.6", max_sublevel=30),),
    track_pre_change=True,
    description="Temporarily brace-wrap if-block so patch context matches",
    edit=ReplaceRegex(
        relative_path="fs/proc/task_mmu.c",
        pattern=(
            r"\t\t\tif \(vma->vm_end > last_vma_end\)\n"
            r"\t\t\t\tsmap_gather_stats\(vma, &mss, last_vma_end\);"
        ),
        replacement=(
            "\t\t\tif (vma->vm_end > last_vma_end) {\n"
            "\t\t\t\tsmap_gather_stats(vma, &mss, last_vma_end);\n"
            "\t\t\t\tlast_vma_end = vma->vm_end;\n"
            "\t\t\t}"
        ),
    ),
),
Rule(
    rule_id="a15-66-restore-last-vma-block",
    stage=2,
    targets=(Target("android15-6.6", max_sublevel=30),),
    requires_pre_change="a15-66-expand-last-vma-block",
    when=lambda ctx: lacks_regex(ctx, "fs/proc/task_mmu.c", r"\bSUSFS_IS_INODE_SUS_MAP\b"),
    description="Undo temporary expansion unless final SUSFS code subsumed it",
    edit=ReplaceRegex(
        relative_path="fs/proc/task_mmu.c",
        pattern=(
            r"\t\t\tif \(vma->vm_end > last_vma_end\) \{\n"
            r"\t\t\t\tsmap_gather_stats\(vma, &mss, last_vma_end\);\n"
            r"\t\t\t\tlast_vma_end = vma->vm_end;\n"
            r"\t\t\t\}"
        ),
        replacement=(
            "\t\t\tif (vma->vm_end > last_vma_end)\n"
            "\t\t\t\tsmap_gather_stats(vma, &mss, last_vma_end);"
        ),
    ),
),
```
The `when` guard on the stage-2 rule is the real safety net: it checks the
**final** source for `SUSFS_IS_INODE_SUS_MAP` wrapping that block. If the
SUSFS patch itself embedded real logic inside the brace-expanded shape, the
revert is skipped — reverting would strip real code, not a leftover shim.

### G — Scoped generic-line removal
```python
def temporary_pagemap_locals_are_unused(ctx: Context) -> bool:
    lines = ctx.read_lines("fs/proc/task_mmu.c")
    start, end = BraceScope(r"^static ssize_t pagemap_read\(").ranges(lines)[0]
    body = "\n".join(lines[start:end])
    stripped = re.sub(r"^\s*unsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;\n?", "", body, flags=re.MULTILINE)
    stripped = re.sub(r"^\s*pagemap_entry_t \*res = NULL;\n?", "", stripped, flags=re.MULTILINE)
    return (
        re.search(r"\bnr_subpages\b", stripped) is None
        and re.search(r"\bres\b", stripped) is None
    )

Rule(
    rule_id="a15-66-temporary-pagemap-locals",
    stage=1,
    targets=(Target("android15-6.6", max_sublevel=30),),
    track_pre_change=True,
    description="Temporary declarations required for old pagemap patch context",
    edit=InsertRelative(
        relative_path="fs/proc/task_mmu.c",
        anchors=(r"^\s*int ret = 0, copied = 0;$",),
        payload=(
            "\tunsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;",
            "\tpagemap_entry_t *res = NULL;",
        ),
    ),
),
Rule(
    rule_id="a15-66-remove-unused-temporary-pagemap-locals",
    stage=2,
    targets=(Target("android15-6.6", max_sublevel=30),),
    requires_pre_change="a15-66-temporary-pagemap-locals",
    when=temporary_pagemap_locals_are_unused,
    description="Remove temporary locals, scoped to pagemap_read() only",
    edit=RemoveExactLines(
        relative_path="fs/proc/task_mmu.c",
        lines_to_remove=(
            "\tunsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;",
            "\tpagemap_entry_t *res = NULL;",
        ),
        within=BraceScope(r"^static ssize_t pagemap_read\("),
        expected_count=2,
    ),
),
```
`BraceScope` + `expected_count` together make this safe even though the
line text alone (`pagemap_entry_t *res = NULL;`) is not unique-looking —
without scoping, a file-wide removal could delete an unrelated local in a
different function that happens to share the same declaration text.

### H — Comment/code block deletion
```python
Rule(
    rule_id="fdinfo-remove-inline-mask-comment",
    stage=1,
    targets=(Target("android12-5.10", max_sublevel=117),),
    edit=RemoveBlock(
        relative_path="fs/notify/fdinfo.c",
        start=r"^[ \t]*/\*$",
        end=r"^[ \t]*u32 mask = mark->mask & IN_ALL_EVENTS;$",
    ),
)
```

### I — Exact API-signature differences across kernel versions
```python
Rule(
    rule_id="namei-set-nameidata-3arg",
    stage=2,
    targets=(Target("android12-5.10"), Target("android13-5.10")),
    description="Old 5.10 baseline has 3-arg set_nameidata(), not 4-arg",
    edit=ReplaceExactLine(
        relative_path="fs/namei.c",
        old_line="\tset_nameidata(nd, old_dfd, fake_filename, NULL);",
        new_line="\tset_nameidata(nd, old_dfd, fake_filename);",
    ),
)
```

### J — Whole-file symbol rename
```python
Rule(
    rule_id="a16-612-rename-vma-pages",
    stage=2,
    targets=(Target("android16-6.12", min_sublevel=69),),
    edit=ReplaceRegex(
        relative_path="fs/proc/task_mmu.c",
        pattern=r"\bvma_data_pages\b",
        replacement="vma_pages",
    ),
)
```
Leave `expected_count=None` unless you've audited the exact call-site count
for every SUSFS version you support — otherwise a future SUSFS revision
adding one more call site would trip a false alarm.

### K — Mutually exclusive stage-2 rules based on final header content
```python
def header_declares_fold_fixup(ctx: Context) -> bool:
    header = ctx.root / "include/linux/page_size_compat.h"
    return header.is_file() and "__fold_filemap_fixup_entry" in header.read_text()

Rule(
    rule_id="fold-fixup-use-real-header",
    stage=2,
    targets=(Target("*"),),
    when=lambda ctx: (
        "__fold_filemap_fixup_entry(" in ctx.read_text("fs/proc/task_mmu.c")
        and header_declares_fold_fixup(ctx)
        and lacks_regex(ctx, "fs/proc/task_mmu.c", r"#include <linux/page_size_compat\.h>")
    ),
    edit=InsertRelative(
        relative_path="fs/proc/task_mmu.c",
        anchors=(r'^#include "internal\.h"$',),
        before=True,
        payload=("#include <linux/page_size_compat.h>",),
    ),
),
Rule(
    rule_id="fold-fixup-use-stub",
    stage=2,
    targets=(Target("*"),),
    when=lambda ctx: (
        "__fold_filemap_fixup_entry(" in ctx.read_text("fs/proc/task_mmu.c")
        and not header_declares_fold_fixup(ctx)
        and lacks_regex(ctx, "fs/proc/task_mmu.c", r"static inline void __fold_filemap_fixup_entry")
    ),
    edit=InsertRelative(
        relative_path="fs/proc/task_mmu.c",
        anchors=(r'^#include "internal\.h"$',),
        payload=(
            "#ifndef __fold_filemap_fixup_entry",
            "static inline void __fold_filemap_fixup_entry(struct vma_iterator *iter, unsigned long *end) { }",
            "#endif",
        ),
    ),
)
```

### L — Version-agnostic, purely `when`-driven rule
```python
def needs_vma_pad_start_fallback(ctx: Context) -> bool:
    content = ctx.read_text("fs/proc/task_mmu.c")
    uses_macro = "VMA_PAD_START(" in content
    has_real_def = re.search(
        r"#include <linux/pgsize_migration(_inline)?\.h>|#define\s+VMA_PAD_START\b",
        content,
        flags=re.MULTILINE,
    )
    return uses_macro and not has_real_def

Rule(
    rule_id="vma-pad-start-fallback",
    stage=2,
    targets=(Target("*"),),
    when=needs_vma_pad_start_fallback,
    description="Provide no-padding VMA_PAD_START fallback on old branches",
    edit=InsertRelative(
        relative_path="fs/proc/task_mmu.c",
        anchors=(r'^#include "internal\.h"$',),
        payload=(
            "#ifndef VMA_PAD_START",
            "#define VMA_PAD_START(vma) ((vma)->vm_end)",
            "#endif",
        ),
    ),
)
```

### M — Same fix across multiple unrelated KMIs
```python
Rule(
    rule_id="old-kernel-show-pad-return",
    stage=2,
    targets=(
        Target("android12-5.10"),
        Target("android13-5.15"),
        Target("android14-6.1"),
    ),
    when=lambda ctx: lacks_regex(ctx, "fs/proc/task_mmu.c", r"^\s*show_pad:\s*$"),
    description="Old kernels lack show_pad label; return instead",
    edit=ReplaceRegex(
        relative_path="fs/proc/task_mmu.c",
        pattern=r"^(\s*)goto show_pad;$",
        replacement=r"\1return 0;",
    ),
)
```

### N — Handling "don't know which 50 variant ran" generically
Synthesis of D + K + L:
1. `targets` narrows to the band where *some* fix might be needed.
2. `when` inspects the actual file for a distinguishing marker.
3. Anchors/patterns are written to match both possible final shapes, or you
   split into mutually-exclusive rules (pattern K) when shapes diverge too
   much for one regex.

Never gate stage-2 behavior on "which patch file did CI apply" — that
information isn't passed to the script and shouldn't need to be. Everything
stage 2 decides is derived from reading the tree.

### O — Dependent sub-edits bundled together
See `Composite` example in §5.6.

### P — Safety nets on rewrites
```python
ReplaceRegex(..., must_find=True)       # fail loudly if it stops matching
ReplaceRegex(..., expected_count=4)     # fail loudly if match count drifts
RemoveExactLines(..., expected_count=1) # fail loudly instead of guessing
```
Use these liberally on anything where silently doing nothing (or doing too
much) would leave code that compiles but behaves wrong.

---

## 8. State file format

```json
{
  "changed": {
    "a15-66-expand-last-vma-block": true,
    "a15-66-temporary-pagemap-locals": true,
    "a13-515-swap-slots-remove-temporarily": true
  }
}
```

- Only stage-1 rules with `track_pre_change=True` ever write an entry.
- Stage-2 rules with `requires_pre_change="<id>"` read this to decide
  whether to run at all.
- Store it **outside** the kernel tree (`$RUNNER_TEMP/...`) so it's never
  mistaken for kernel source and never needs `.gitignore` handling.
- Safe to delete between runs — worst case, stage-2 rules gated by
  `requires_pre_change` simply won't fire (they'll assume stage 1 never ran),
  which just means temporary edits that were actually made won't be reverted
  in this script. The next full rebuild (fresh checkout + fresh stage-1 run)
  recreates it correctly.

---

## 9. Adding a new case — checklist

1. Identify the exact `KMI` string and `sublevel` boundary from CI env vars.
2. Decide: permanent fix (§Case A/B) or temporary-with-revert (§Case F/G)?
3. Pick the right `Edit` type from §6's decision table.
4. If removing/replacing something not obviously unique, add
   `expected_count` and/or `within=BraceScope(...)`.
5. If it's a stage-2 rule reverting a stage-1 edit, set
   `requires_pre_change` to the stage-1 `rule_id`, and add a `when` guard
   that checks the **final** source for whether the revert is still safe.
6. Give it a unique, descriptive `rule_id`.
7. Add it to `RULES`.
8. Run with `--dry-run` once against a real checkout to confirm the log
   output matches expectations before letting it write files.