#!/usr/bin/env python3
"""
SUSFS compatibility file-edit framework.

Stage 1 (pre):  prepare an old kernel source tree so a SUSFS patch
                (50_add_susfs_in_*.patch, or a fixed variant of it) can apply.
Stage 2 (post): re-inspect the FINAL patched tree and finish/undo
                compatibility edits. Never trusts stage-1 line numbers.

This script does NOT invoke `patch`. GitHub Actions remains responsible for
selecting and applying 50_add_susfs...patch (or a fixed replacement) between
stage 1 and stage 2.

See README.md in this directory for full usage documentation.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

class CompatError(RuntimeError):
    pass


def log(message: str) -> None:
    print(f"[susfs-compat] {message}")

@dataclass
class Context:
    root: Path
    kmi: str
    sublevel: int
    state_path: Path
    dry_run: bool = False
    state: dict = field(default_factory=lambda: {"changed": {}})

    def path(self, relative_path: str) -> Path:
        p = self.root / relative_path
        if not p.is_file():
            raise CompatError(f"required source file does not exist: {p}")
        return p

    def read_text(self, relative_path: str) -> str:
        return self.path(relative_path).read_text(encoding="utf-8")

    def read_lines(self, relative_path: str) -> list[str]:
        return self.read_text(relative_path).splitlines()

    def write_text(self, relative_path: str, content: str) -> None:
        p = self.path(relative_path)
        if self.dry_run:
            log(f"[dry-run] would write {relative_path}")
            return
        p.write_text(content, encoding="utf-8")

    def write_lines(self, relative_path: str, lines: list[str]) -> None:
        self.write_text(relative_path, "\n".join(lines) + "\n")

    def was_changed_by_pre_stage(self, rule_id: str) -> bool:
        return bool(self.state.get("changed", {}).get(rule_id))

    def remember_pre_stage_change(self, rule_id: str) -> None:
        self.state.setdefault("changed", {})[rule_id] = True

    def save_state(self) -> None:
        if self.dry_run:
            return
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.state_path.with_suffix(self.state_path.suffix + ".tmp")
        tmp.write_text(json.dumps(self.state, indent=2, sort_keys=True) + "\n")
        tmp.replace(self.state_path)


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"changed": {}}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise CompatError(f"invalid compatibility state file: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise CompatError(f"invalid compatibility state file: {path}")
    value.setdefault("changed", {})
    return value


# =============================================================================
# Target matching
# =============================================================================

@dataclass(frozen=True)
class Target:
    kmi: str = "*"
    min_sublevel: int | None = None
    max_sublevel: int | None = None

    def matches(self, ctx: Context) -> bool:
        if self.kmi != "*" and self.kmi != ctx.kmi:
            return False
        if self.min_sublevel is not None and ctx.sublevel < self.min_sublevel:
            return False
        if self.max_sublevel is not None and ctx.sublevel > self.max_sublevel:
            return False
        return True


# =============================================================================
# Predicates (used as Rule.when)
# =============================================================================

def has_regex(ctx: Context, relative_path: str, pattern: str) -> bool:
    return re.search(pattern, ctx.read_text(relative_path), flags=re.MULTILINE) is not None


def lacks_regex(ctx: Context, relative_path: str, pattern: str) -> bool:
    return not has_regex(ctx, relative_path, pattern)


def needs_vma_pad_start_fallback(ctx: Context) -> bool:
    file = "fs/proc/task_mmu.c"
    content = ctx.read_text(file)
    uses_macro = "VMA_PAD_START(" in content
    has_real_def = re.search(
        r"#include <linux/pgsize_migration(_inline)?\.h>|#define\s+VMA_PAD_START\b",
        content,
        flags=re.MULTILINE,
    )
    return uses_macro and not has_real_def


def temporary_pagemap_locals_are_unused(ctx: Context) -> bool:
    file = "fs/proc/task_mmu.c"
    content = ctx.read_text(file)
    stripped = re.sub(r"(?m)^\tunsigned int nr_subpages = __PAGE_SIZE / PAGE_SIZE;\n?", "", content)
    stripped = re.sub(r"(?m)^\tpagemap_entry_t \*res = NULL;\n?", "", stripped)
    return (
        re.search(r"\bnr_subpages\b", stripped) is None
        and re.search(r"\bres\b", stripped) is None
    )


# =============================================================================
# Brace-depth scanner (comment/string-aware)
# =============================================================================

def _find_matching_brace(text: str, open_index: int) -> int:
    """
    Given the index of an opening '{' in `text`, return the index of its
    matching '}'. Correctly skips over:
      - // line comments
      - /* block comments */
      - "string literals"        (with backslash escapes)
      - 'char literals'          (with backslash escapes)
    so braces that appear inside comments or string/char literals are not
    counted toward nesting depth.

    This means `int values[] = { 1, 2, 3 }` nested inside a function body is
    handled correctly — its '}' is counted at the correct depth and does NOT
    get mistaken for the enclosing function's closing brace.

    Known limitations (acceptable for kernel C source in practice):
      - does not evaluate #if/#ifdef/#endif preprocessor conditionals; braces
        inside disabled #if 0 blocks are still counted literally.
      - does not expand macros; a macro that textually contains unbalanced
        braces would confuse the scanner (practically never happens in
        mainline/GKI kernel style).
    """
    if text[open_index] != "{":
        raise CompatError(f"_find_matching_brace: index {open_index} is not '{{'")

    depth = 0
    i = open_index
    n = len(text)

    while i < n:
        ch = text[i]

        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            end = text.find("\n", i)
            i = n if end == -1 else end
            continue

        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue

        if ch == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue

        if ch == "'":
            i += 1
            while i < n and text[i] != "'":
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue

        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i

        i += 1

    raise CompatError("_find_matching_brace: no matching '}' found (unbalanced braces)")


# =============================================================================
# Scope strategies for RemoveExactLines(within=...)
# =============================================================================

class Scope(ABC):
    """A Scope converts a start anchor into one or more [start, end) line
    index ranges within which a removal/match is allowed to happen."""

    @abstractmethod
    def ranges(self, lines: list[str]) -> list[tuple[int, int]]: ...


class BraceScope(Scope):
    """
    Scope = the brace-balanced block that begins at the first '{' found at or
    after each line matching `start_anchor`, up to and including its
    correctly-matched closing '}'.

    This is brace-depth aware (via _find_matching_brace) and is SAFE against
    nested blocks, nested struct/array initializers, and braces inside
    comments or string/char literals.

    Use this for: "scope to a specific C function/struct/block".

    Example:
        BraceScope(r"^static ssize_t pagemap_read\\(")

    NOTE: `start_anchor` is matched with re.MULTILINE, so '^' and '$' anchor
    to individual line boundaries within the file, not to the start/end of
    the whole file content. Without this, a pattern like
    r"^static ssize_t pagemap_read\\(" would only ever match if that text
    happened to be the very first bytes of the file — which it practically
    never is — causing ranges() to silently return [] instead of finding
    the function. To fail loudly instead of silently when the anchor truly
    isn't found anywhere, ranges() raises CompatError in that case.
    """

    def __init__(self, start_anchor: str):
        self.start_anchor = re.compile(start_anchor, re.MULTILINE)

    def ranges(self, lines: list[str]) -> list[tuple[int, int]]:
        text = "\n".join(lines)

        # Precompute cumulative character offset at the START of each line,
        # so we can map a character offset back to a line index.
        line_start_offsets: list[int] = []
        total = 0
        for line in lines:
            line_start_offsets.append(total)
            total += len(line) + 1  # +1 for the '\n' used by "\n".join

        def offset_to_line(offset: int) -> int:
            lo, hi = 0, len(line_start_offsets) - 1
            while lo < hi:
                mid = (lo + hi + 1) // 2
                if line_start_offsets[mid] <= offset:
                    lo = mid
                else:
                    hi = mid - 1
            return lo

        matches = list(self.start_anchor.finditer(text))
        if not matches:
            raise CompatError(
                f"BraceScope: start anchor not found anywhere in file: "
                f"{self.start_anchor.pattern!r}"
            )

        found_ranges: list[tuple[int, int]] = []
        for match in matches:
            brace_open = text.find("{", match.start())
            if brace_open == -1:
                raise CompatError(
                    f"BraceScope: no '{{' found after anchor match "
                    f"{self.start_anchor.pattern!r}"
                )
            brace_close = _find_matching_brace(text, brace_open)
            start_line = offset_to_line(match.start())
            end_line = offset_to_line(brace_close) + 1  # inclusive -> exclusive
            found_ranges.append((start_line, end_line))

        return found_ranges


class LineRangeScope(Scope):
    """
    Scope = from the first line matching `start_anchor` through the next
    line matching `end_anchor` (inclusive), using simple forward line
    scanning. Repeats for further non-overlapping occurrences.

    WARNING: this is NOT brace-depth aware. Only use it for markers that
    cannot appear nested (e.g. unique comment markers you control, a
    specific unique closing line that is guaranteed not to repeat inside the
    region, or structurally flat regions like a contiguous #include block).
    Do NOT use this to scope to a C function/block body — use BraceScope
    for that instead.

    Example:
        LineRangeScope(r"^/\\* SUSFS_BLOCK_START \\*/$", r"^/\\* SUSFS_BLOCK_END \\*/$")
    """

    def __init__(self, start_anchor: str, end_anchor: str):
        self.start = re.compile(start_anchor)
        self.end = re.compile(end_anchor)

    def ranges(self, lines: list[str]) -> list[tuple[int, int]]:
        found_ranges: list[tuple[int, int]] = []
        i = 0
        while i < len(lines):
            if self.start.search(lines[i]):
                start = i
                j = i + 1
                while j < len(lines) and not self.end.search(lines[j]):
                    j += 1
                end = min(j + 1, len(lines))
                found_ranges.append((start, end))
                i = end
            else:
                i += 1
        return found_ranges


# =============================================================================
# Edit primitives
# =============================================================================

class Edit(ABC):
    @abstractmethod
    def apply(self, ctx: Context) -> bool:
        """Return True if the file was changed, False if already satisfied."""
        ...


@dataclass
class InsertRelative(Edit):
    relative_path: str
    anchors: tuple[str, ...]
    payload: tuple[str, ...]
    before: bool = False
    occurrence: str = "first"   # "first" | "last"
    adjacent: bool = False

    def _find_anchor(self, lines: list[str]) -> int:
        for anchor in self.anchors:
            regex = re.compile(anchor)
            matches = [i for i, line in enumerate(lines) if regex.search(line)]
            if matches:
                return matches[-1] if self.occurrence == "last" else matches[0]
        raise CompatError(
            f"no anchor found in {self.relative_path}: {', '.join(self.anchors)}"
        )

    def apply(self, ctx: Context) -> bool:
        lines = ctx.read_lines(self.relative_path)
        present = [line in lines for line in self.payload]

        if self.adjacent:
            anchor_index = self._find_anchor(lines)
            insert_index = anchor_index if self.before else anchor_index + 1
            if lines[insert_index:insert_index + len(self.payload)] == list(self.payload):
                return False
            if any(present):
                raise CompatError(
                    f"payload exists but not adjacent to anchor in "
                    f"{self.relative_path}: {self.payload}"
                )
        else:
            if all(present):
                return False
            if any(present):
                raise CompatError(
                    f"partial payload already exists in {self.relative_path}: "
                    f"{self.payload}"
                )
            anchor_index = self._find_anchor(lines)
            insert_index = anchor_index if self.before else anchor_index + 1

        lines[insert_index:insert_index] = list(self.payload)
        ctx.write_lines(self.relative_path, lines)
        return True


@dataclass
class RemoveExactLines(Edit):
    """
    Remove exact, literal source lines.

    SAFETY: by default this scans the WHOLE FILE and removes EVERY line that
    exactly equals one of `lines_to_remove`. For a line that's unlikely to
    repeat (e.g. a full #include path) this is fine. For anything even
    slightly generic, use `expected_count` and/or `within` — do not rely on
    the line text alone.

    Fields:
      relative_path   File to edit, relative to kernel root.
      lines_to_remove One or more EXACT lines (whitespace-sensitive).
      occurrence      "all" (default) | "first" | "last" — which matches
                       (after `within` filtering) to actually remove.
      expected_count  If set, raise CompatError unless exactly this many
                       matches are found (pre-occurrence-filtering). This is
                       the single most important safety net — set it
                       whenever you can predict the count.
      within          Optional Scope (BraceScope or LineRangeScope) that
                       restricts which matches are eligible at all. Matches
                       outside the scope's ranges are completely ignored —
                       they do not count toward `expected_count` and are
                       never removed.
    """
    relative_path: str
    lines_to_remove: tuple[str, ...]
    occurrence: str = "all"
    expected_count: int | None = None
    within: Scope | None = None

    def apply(self, ctx: Context) -> bool:
        lines = ctx.read_lines(self.relative_path)
        remove_set = set(self.lines_to_remove)

        if self.within is not None:
            scope_ranges = self.within.ranges(lines)

            def in_scope(index: int) -> bool:
                return any(start <= index < end for start, end in scope_ranges)
        else:
            def in_scope(index: int) -> bool:
                return True

        matching_indices = [
            i for i, line in enumerate(lines)
            if line in remove_set and in_scope(i)
        ]

        if self.expected_count is not None and matching_indices:
            if len(matching_indices) != self.expected_count:
                raise CompatError(
                    f"RemoveExactLines on {self.relative_path} expected "
                    f"{self.expected_count} match(es) but found "
                    f"{len(matching_indices)} at line(s) "
                    f"{[i + 1 for i in matching_indices]} — refusing to guess."
                )

        if self.occurrence == "first" and matching_indices:
            matching_indices = matching_indices[:1]
        elif self.occurrence == "last" and matching_indices:
            matching_indices = matching_indices[-1:]

        if not matching_indices:
            return False

        remove_idx = set(matching_indices)
        output = [line for i, line in enumerate(lines) if i not in remove_idx]
        ctx.write_lines(self.relative_path, output)
        return True


@dataclass
class RemoveBlock(Edit):
    """
    Delete every line from the first line matching `start` through the next
    line matching `end` (inclusive). Mirrors `sed '/start/,/end/d'`.

    NOT brace-depth aware (same caveat as LineRangeScope) — only use this
    for markers that cannot legitimately repeat/nest inside the block you
    intend to delete (comment blocks, clearly delimited regions).
    """
    relative_path: str
    start: str
    end: str

    def apply(self, ctx: Context) -> bool:
        lines = ctx.read_lines(self.relative_path)
        start_re = re.compile(self.start)
        end_re = re.compile(self.end)

        output: list[str] = []
        in_block = False
        removed_any = False

        for line in lines:
            if not in_block and start_re.search(line):
                in_block = True
                removed_any = True
                continue
            if in_block:
                if end_re.search(line):
                    in_block = False
                continue
            output.append(line)

        if not removed_any:
            return False

        ctx.write_lines(self.relative_path, output)
        return True


@dataclass
class ReplaceRegex(Edit):
    """
    Whole-file regex substitution (not line-by-line).

      pattern         Regex matched against the full file content.
      replacement     Replacement string; backreferences (\\1 etc.) allowed.
      must_find       If True, raise CompatError when the pattern matches
                       zero times. Use for rewrites that must never silently
                       no-op.
      expected_count  If set, raise unless the number of substitutions
                       equals exactly this value.
      flags           Default re.MULTILINE. Add re.DOTALL for patterns that
                       must span blank lines.
    """
    relative_path: str
    pattern: str
    replacement: str
    must_find: bool = False
    expected_count: int | None = None
    flags: int = re.MULTILINE

    def apply(self, ctx: Context) -> bool:
        content = ctx.read_text(self.relative_path)
        output, count = re.subn(self.pattern, self.replacement, content, flags=self.flags)

        if count == 0:
            if self.must_find:
                raise CompatError(
                    f"required replacement did not match in "
                    f"{self.relative_path}: {self.pattern}"
                )
            return False

        if self.expected_count is not None and count != self.expected_count:
            raise CompatError(
                f"unexpected replacement count in {self.relative_path}: "
                f"expected {self.expected_count}, got {count}"
            )

        ctx.write_text(self.relative_path, output)
        return True


@dataclass
class ReplaceExactLine(Edit):
    """
    Literal whole-line replacement — no regex involved on either side.
    Safer than ReplaceRegex when both old and new lines are fixed strings.

      occurrence   "all" (default) | "first" | "last"
    """
    relative_path: str
    old_line: str
    new_line: str
    occurrence: str = "all"

    def apply(self, ctx: Context) -> bool:
        lines = ctx.read_lines(self.relative_path)
        indices = [i for i, line in enumerate(lines) if line == self.old_line]

        if not indices:
            return False

        if self.occurrence == "first":
            indices = indices[:1]
        elif self.occurrence == "last":
            indices = indices[-1:]

        for i in indices:
            lines[i] = self.new_line

        ctx.write_lines(self.relative_path, lines)
        return True


@dataclass
class Composite(Edit):
    """Groups multiple edits under one rule_id. NOT transactional: if a
    later sub-edit raises, earlier sub-edits in this Composite have already
    been written to disk. Acceptable in CI since a raised CompatError aborts
    the whole job anyway."""
    edits: tuple[Edit, ...]

    def apply(self, ctx: Context) -> bool:
        changed = False
        for edit in self.edits:
            changed = edit.apply(ctx) or changed
        return changed


# =============================================================================
# Rule
# =============================================================================

Predicate = Callable[[Context], bool]


@dataclass
class Rule:
    rule_id: str
    stage: int                      # 1 or 2
    targets: tuple[Target, ...]
    edit: Edit
    when: Predicate | None = None
    track_pre_change: bool = False
    requires_pre_change: str | None = None
    description: str = ""

    def matches(self, ctx: Context) -> bool:
        return any(t.matches(ctx) for t in self.targets)


# =============================================================================
# Compatibility recipes
# (This is the section you extend for new KMI/sublevel cases. See README.md.)
# =============================================================================

RULES: tuple[Rule, ...] = (

    # --- Permanent header fixes ------------------------------------------
    Rule(
        rule_id="a15-66-trace-fs-header",
        stage=1,
        targets=(Target("android15-6.6"),),
        description="Old android15-6.6 tree lacks trace/hooks/fs.h context",
        edit=InsertRelative(
            relative_path="fs/namespace.c",
            anchors=(r"^#include <trace/hooks/blk\.h>$",),
            payload=("#include <trace/hooks/fs.h>",),
        ),
    ),

    Rule(
        rule_id="a15-66-zswap-header",
        stage=1,
        targets=(Target("android15-6.6", max_sublevel=57),),
        description="zswap declarations needed before patch applies",
        edit=InsertRelative(
            relative_path="mm/memory.c",
            anchors=(r"^#include <linux/sched/sysctl\.h>$",),
            payload=("#include <linux/zswap.h>",),
        ),
    ),

    Rule(
        rule_id="a15-66-dma-buf-header",
        stage=1,
        targets=(Target("android15-6.6", max_sublevel=92),),
        description="Old fs/proc/base.c does not include dma-buf",
        edit=InsertRelative(
            relative_path="fs/proc/base.c",
            anchors=(r"^#include <linux/cpufreq_times\.h>$",),
            payload=("#include <linux/dma-buf.h>",),
        ),
    ),

    Rule(
        rule_id="a14-61-dma-buf-header",
        stage=1,
        targets=(Target("android14-6.1"),),
        description="Old android14-6.1 fs/proc/base.c does not include dma-buf",
        edit=InsertRelative(
            relative_path="fs/proc/base.c",
            anchors=(r"^#include <linux/cpufreq_times\.h>$",),
            payload=("#include <linux/dma-buf.h>",),
        ),
    ),

    # --- Temporary structural reshape + stage-2 conditional revert -------
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
        when=lambda ctx: lacks_regex(ctx, "fs/proc/task_mmu.c", r"^SUSFS_IS_INODE_SUS_MAP$"),
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

    # --- Temporary locals, scoped removal with BraceScope -----------------
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

    # --- Remove-then-restore header ---------------------------------------
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

    # --- Temporary trace/hooks/blk.h (old fake_patched2) -------------------
    Rule(
        rule_id="a13-515-trace-blk-header-temp",
        stage=1,
        targets=(Target("android13-5.15"),),
        track_pre_change=True,
        description="Temporarily add trace/hooks/blk.h so the SUSFS patch context matches",
        edit=InsertRelative(
            relative_path="fs/namespace.c",
            anchors=(r'^#include "internal\.h"$',),
            payload=("#include <trace/hooks/blk.h>",),
        ),
    ),
    Rule(
        rule_id="a13-515-trace-blk-header-revert",
        stage=2,
        targets=(Target("android13-5.15"),),
        requires_pre_change="a13-515-trace-blk-header-temp",
        description="Remove temporary trace/hooks/blk.h if the patch did not consume it",
        edit=RemoveExactLines(
            relative_path="fs/namespace.c",
            lines_to_remove=("#include <trace/hooks/blk.h>",),
            expected_count=1,
        ),
    ),

    Rule(
        rule_id="a14-61-trace-blk-header-temp",
        stage=1,
        targets=(Target("android14-6.1"),),
        track_pre_change=True,
        description="Temporarily add trace/hooks/blk.h so the SUSFS patch context matches",
        edit=InsertRelative(
            relative_path="fs/namespace.c",
            anchors=(r'^#include "internal\.h"$',),
            payload=("#include <trace/hooks/blk.h>",),
        ),
    ),
    Rule(
        rule_id="a14-61-trace-blk-header-revert",
        stage=2,
        targets=(Target("android14-6.1"),),
        requires_pre_change="a14-61-trace-blk-header-temp",
        description="Remove temporary trace/hooks/blk.h if the patch did not consume it",
        edit=RemoveExactLines(
            relative_path="fs/namespace.c",
            lines_to_remove=("#include <trace/hooks/blk.h>",),
            expected_count=1,
        ),
    ),

    # --- Temporary trace/hooks/mm.h (old fake_patched2, a13-5.15 only) -----
    Rule(
        rule_id="a13-515-trace-mm-header-temp",
        stage=1,
        targets=(Target("android13-5.15"),),
        track_pre_change=True,
        description="Temporarily add trace/hooks/mm.h so the SUSFS patch context matches",
        edit=InsertRelative(
            relative_path="fs/proc/task_mmu.c",
            anchors=(r"^#include <linux/pkeys\.h>$",),
            payload=("#include <trace/hooks/mm.h>",),
        ),
    ),
    Rule(
        rule_id="a13-515-trace-mm-header-revert",
        stage=2,
        targets=(Target("android13-5.15"),),
        requires_pre_change="a13-515-trace-mm-header-temp",
        description="Remove temporary trace/hooks/mm.h if the patch did not consume it",
        edit=RemoveExactLines(
            relative_path="fs/proc/task_mmu.c",
            lines_to_remove=("#include <trace/hooks/mm.h>",),
            expected_count=1,
        ),
    ),

    # --- API signature differences across kernel versions -----------------
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
    ),

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
    ),

    # --- Version-agnostic, purely reactive rule ----------------------------
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
    ),
)


# =============================================================================
# Stage runner
# =============================================================================

def run_stage(ctx: Context, stage: int) -> None:
    for rule in RULES:
        if rule.stage != stage:
            continue
        if not rule.matches(ctx):
            continue

        if rule.requires_pre_change is not None and not ctx.was_changed_by_pre_stage(
            rule.requires_pre_change
        ):
            log(f"skip {rule.rule_id}: stage-1 rule {rule.requires_pre_change} made no change")
            continue

        if rule.when is not None and not rule.when(ctx):
            log(f"skip {rule.rule_id}: final-source predicate not satisfied")
            continue

        changed = rule.edit.apply(ctx)

        if changed:
            log(f"apply {rule.rule_id}: {rule.description or 'source updated'}")
            if stage == 1 and rule.track_pre_change and not ctx.dry_run:
                ctx.remember_pre_stage_change(rule.rule_id)
        else:
            log(f"skip {rule.rule_id}: already in desired state")


# =============================================================================
# CLI
# =============================================================================

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("1", "2", "pre", "post"))
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--kmi", required=True)
    parser.add_argument("--sublevel", required=True, type=int)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    stage = 1 if args.stage in ("1", "pre") else 2
    root = args.root.resolve()

    if not root.is_dir():
        print(f"[susfs-compat] invalid kernel root: {root}", file=sys.stderr)
        return 2

    state_path = (args.state or (root / ".susfs-compat-state.json")).resolve()

    ctx = Context(
        root=root,
        kmi=args.kmi,
        sublevel=args.sublevel,
        state_path=state_path,
        dry_run=args.dry_run,
        state=load_state(state_path),
    )

    try:
        log(f"stage={stage}, kmi={ctx.kmi}, sublevel={ctx.sublevel}, root={ctx.root}")
        run_stage(ctx, stage)
        ctx.save_state()
        return 0
    except CompatError as exc:
        print(f"[susfs-compat] ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
