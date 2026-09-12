#!/usr/bin/env bash
# sidecarsymlinkcheck.sh — CWE-59: a sidecar writer must REFUSE a symlink at its own fixed name.
#
# THE DEFECT THIS GATE OWNS (reported externally, reproduced on the shipped v0.6.0 binary). Three sidecar
# writers opened a FIXED-NAME destination with a TRUNCATING open that resolves the final path component
# through the filesystem's symlink layer — no O_NOFOLLOW, no lstat/S_ISLNK check:
#
#     .ripwire_quality_baseline   quality::writeBaseline     ofstream( path, trunc )
#     .ripwire_notes              notes::writeNotes          ofstream( path, trunc )
#     .ripwire_arch_baseline      archWriteBaseline          fopen( path, "w" )
#
# A repository carrying a symlink at one of those names turned ripwire's own write into an arbitrary-file
# truncate/overwrite ANYWHERE the invoking user can write. The reporter's proof-of-concept, reproduced here
# verbatim: a victim file holding `important user data` came back holding ripwire's baseline content, and
# `.ripwire_quality_baseline` was STILL A SYMLINK afterwards — the link was followed and its target
# destroyed, not replaced. Indexing a repository is a read-only-feeling act; it must not be able to eat a
# file outside the tree.
#
# WHY THE SYMLINK SURVIVING IS THE TELL, and why this gate asserts it. A tmp+rename publish (what the fourth
# sidecar, .ripwire_quality_acks, already uses) REPLACES the link entry with a regular file and leaves the
# target alone — data-losing in its own way, but not an arbitrary write. A truncating open does the exact
# opposite. So "the link is still a link and the target changed" is the signature of the vulnerable shape,
# and "the link is still a link and the target did NOT change" is the fixed shape. Both are asserted below.
#
# ARM MAP — six discriminating arms, all six observed RED against a pristine origin/main build (4725adce)
# before the fix, all six green after:
#
#     per sidecar:  (a) the victim's bytes are UNTOUCHED after the verb runs
#                   (b) the tool REFUSED — non-zero exit AND a stderr line naming the symlink
#
# Two further arms per sidecar are NOT discriminating and are labelled so rather than left to look like
# coverage they are not (CONTRIBUTING §2, shape 7 — an arm asserting something strictly weaker than its
# name implies). They still assert real properties worth holding:
#
#     (c) the planted symlink is still there, still pointing at the victim — refusing must not quietly
#         unlink or replace the user's own entry. Green before AND after; it pins the no-side-effect half.
#     (d) NEGATIVE CONTROL (the reporter's own): with NO symlink present, the verb writes the sidecar
#         normally, as a REGULAR file with real content. Green before and after by design — it is what
#         stops the fix from being "refuse always", which would pass every (a)/(b) arm and break the tool.
#
# Usage:
#   bash test/sidecarsymlinkcheck.sh                 |  bash test/sidecarsymlinkcheck.sh asan/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/sidecarsymlinkcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams: regression.sh and every differential run pass the binary POSITIONALLY; RIPWIRE_BIN is the
# env form. A gate reading only one of them comes back ALL PASS against whatever is in build/ during a
# red-first run against a BASE binary — the exact way a red-first check fakes itself green (archcheck.sh
# carries the same note for the same reason).
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "sidecarsymlinkcheck: BIN=$BIN  TMP=$TMP"

# The sentinel the reporter used. Its exact bytes are the thing every (a) arm compares against, so the
# comparison can never degrade into "empty matches empty" (CONTRIBUTING §2, shape 3).
VICTIM_BYTES='important user data'

# ── fixture: a tiny indexable tree, deliberately NOT a git checkout ───────────────────────────────────
# Both --quality-baseline and --note-add degrade cleanly on a non-git root (undated note, empty HEAD
# stamp) and still write their sidecar, so the gate owes nothing to git config, committer identity or
# clone depth. The arch rules file produces a real layer pair so --baseline has something to accept.
mkTree()
{
    local dir="$1"
    rm -rf "$dir"; mkdir -p "$dir/sub"
    printf '#include <stdio.h>\nint helper( int x ) { return x + 1; }\nint main( void ) { printf( "%%d\\n", helper( 1 ) ); return 0; }\n' >"$dir/a.c"
    printf 'int other( int y ) { return y * 2; }\n' >"$dir/sub/b.c"
    printf 'layer core = a.c\nlayer consumer = sub/\ndeny consumer -> core\n' >"$dir/rules.txt"
}

# ── one full symlink arm, run for each of the three sidecars ──────────────────────────────────────────
# `label`     — human name for the rows
# `sidecar`   — the fixed file name the writer opens
# `runner`    — a function name; called with the tree dir, must invoke the verb that writes `sidecar`
#
# The victim lives OUTSIDE the indexed tree on purpose: that is the whole claim — a repository reaching a
# file the repository does not contain.
symlinkArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/$label/tree" victim="$TMP/$label/outside/victim.txt"

    mkTree "$tree"
    mkdir -p "$( dirname "$victim" )"
    printf '%s\n' "$VICTIM_BYTES" >"$victim"
    cp "$victim" "$TMP/$label.pristine"

    # PRESENCE GUARDS — assert the things the arm is about to measure actually exist, before trusting any
    # verdict over them. A vanished victim or an un-planted symlink would make (a) pass while proving
    # nothing (CONTRIBUTING §2, "a vanishing probe target").
    if [ -s "$victim" ] && grep -q "$VICTIM_BYTES" "$victim"; then
        ok "$label: (guard) victim file exists outside the tree, holding the sentinel bytes"
    else
        no "$label: (guard) victim file was not created with the sentinel bytes — every arm below is void"
        return
    fi

    ln -s "$victim" "$tree/$sidecar"
    if [ -L "$tree/$sidecar" ] && [ "$( readlink "$tree/$sidecar" )" = "$victim" ]; then
        ok "$label: (guard) symlink planted at $sidecar → the victim"
    else
        no "$label: (guard) could not plant the symlink at $sidecar — every arm below is void"
        return
    fi

    local rc=0
    "$runner" "$tree" >"$TMP/$label.out" 2>"$TMP/$label.err" || rc=$?

    # ── (a) DISCRIMINATING: the victim's bytes survive ────────────────────────────────────────────────
    if cmp -s "$TMP/$label.pristine" "$victim"; then
        ok "$label: (a) victim file is byte-identical after the verb ran"
    else
        no "$label: (a) VICTIM OVERWRITTEN through the symlink — $( wc -c <"$TMP/$label.pristine" | tr -d ' ' ) B became $( wc -c <"$victim" | tr -d ' ' ) B: $( head -c 60 "$victim" )"
    fi

    # ── (b) DISCRIMINATING: the refusal is LOUD ───────────────────────────────────────────────────────
    # Not writing is not enough. A silent skip leaves the user believing a sidecar exists that does not,
    # which is its own defect — so the verb must exit non-zero AND say on stderr that it refused and why.
    if [ "$rc" -ne 0 ]; then
        ok "$label: (b1) verb exited non-zero ($rc) rather than reporting success"
    else
        no "$label: (b1) verb exited 0 — a write that was refused (or worse, redirected) reported success"
    fi
    if grep -q 'refusing to write' "$TMP/$label.err" && grep -q 'symlink' "$TMP/$label.err"; then
        ok "$label: (b2) stderr names the refusal and the reason (symlink)"
    else
        no "$label: (b2) stderr carries no symlink refusal — user is not told why the sidecar is missing: $( head -c 120 "$TMP/$label.err" )"
    fi

    # ── (c) NOT DISCRIMINATING (green before and after): refusing has no side effect on the entry ─────
    if [ -L "$tree/$sidecar" ] && [ "$( readlink "$tree/$sidecar" )" = "$victim" ]; then
        ok "$label: (c) the user's symlink entry is left exactly as it was (not unlinked, not replaced)"
    else
        no "$label: (c) the symlink entry was modified — refusing must not touch the user's own entry"
    fi
}

# ── (d) NEGATIVE CONTROL, run for each sidecar: no symlink → normal write ─────────────────────────────
# This is the arm that keeps the fix honest. "Refuse whenever the destination exists", or "refuse always",
# satisfies every (a) and (b) arm above and breaks the three verbs completely; only this arm notices.
controlArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_ctl/tree"

    mkTree "$tree"
    local rc=0
    "$runner" "$tree" >"$TMP/${label}_ctl.out" 2>"$TMP/${label}_ctl.err" || rc=$?

    if [ "$rc" -eq 0 ]; then
        ok "$label: (d1) no symlink present → verb exits 0"
    else
        no "$label: (d1) no symlink present → verb exited $rc: $( head -c 120 "$TMP/${label}_ctl.err" )"
    fi
    if [ -f "$tree/$sidecar" ] && [ ! -L "$tree/$sidecar" ] && [ -s "$tree/$sidecar" ]; then
        ok "$label: (d2) sidecar written normally as a regular, non-empty file"
    else
        no "$label: (d2) sidecar not written as a regular non-empty file — the guard broke the normal path"
    fi
}

# ── the three runners ─────────────────────────────────────────────────────────────────────────────────
runQualityBaseline(){ "$BIN" "$1" --quality-baseline --no-cache; }
runNoteAdd(){ "$BIN" "$1" --note-add="a.c: sidecar symlink gate" --no-cache; }
# archBaselinePath() returns a BARE file name, resolved against the process CWD rather than the crawl
# root — so this runner must cd into the tree for the sidecar to land there at all. That is current,
# deliberate behaviour (the sidecar is rules-file-independent and repo-committable); the arm is written
# around it rather than against it. If the destination is ever root-qualified, delete the subshell cd
# and nothing else here changes.
runArchBaseline(){ ( cd "$1" && "$BIN" "$1" --arch=rules.txt --baseline --no-cache ); }

symlinkArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
symlinkArm notes           .ripwire_notes            runNoteAdd
symlinkArm archbaseline    .ripwire_arch_baseline    runArchBaseline

controlArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
controlArm notes           .ripwire_notes            runNoteAdd
controlArm archbaseline    .ripwire_arch_baseline    runArchBaseline

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
