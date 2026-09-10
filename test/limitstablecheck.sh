#!/usr/bin/env bash
# limitstablecheck.sh — docs/LIMITS.md is a BUILD PRODUCT of src/, and this gate says so.
#
# WHY. A cap is a routing decision: it decides what an agent can and cannot find. This tree has 120 of
# them across 51 files and, before 2026-09-09, nothing listed them together — so kMaxExpandSibs could sit
# at 8, fire on 68.5% of bodies and hide 89.3% of every sibling name, justified by a cost ("~3.5 KB per
# --pack-task bundle") that was not reproducible, because --pack-task emits no sibs= at all. Nobody was
# wrong on purpose; the caps were simply never visible next to each other.
#
# A hand-kept table of 120 constants rots. The same round found a published figure that had been stale
# for four days because one number lived in SIX artifacts and only FOUR were wired together. So the table
# is generated and this gate fails when it drifts.
#
# ARMS
#   (A) the generator exists and parses a non-zero number of caps (its own shape-change guard).
#   (B) THE GATE: docs/LIMITS.md matches what the generator produces from src/ right now.
#   (C) CAN-GO-RED, on the REAL mechanism: a synthetic tree with one EXTRA cap must make --check fail.
#       It runs against --root on a temp tree, never against src/ — dropping a probe file into src/ would
#       perturb the crawl other gates measure (see test/README notes on probe-copy artifacts).
#   (D) the generator refuses a tree it cannot parse instead of writing an empty table.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/docs/limits_build.py"
DOC="$ROOT/docs/LIMITS.md"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$GEN" ] || { echo "limitstablecheck: no docs/limits_build.py"; exit 2; }
[ -f "$DOC" ] || { echo "limitstablecheck: no docs/LIMITS.md — run: python3 docs/limits_build.py"; exit 2; }

# ── (A) the generator runs and finds caps ───────────────────────────────────────────────────────────
n="$( python3 "$GEN" --out "$TMP/a.md" 2>&1 | grep -oE '[0-9]+ caps' | head -1 )"
if [ -n "$n" ]; then ok "(A) generator parsed $n from src/"; else no "(A) generator produced no cap count"; fi

# ── (B) the committed table matches src/ ────────────────────────────────────────────────────────────
if out="$( python3 "$GEN" --check 2>&1 )"; then
    ok "(B) docs/LIMITS.md matches src/ — ${out#*: }"
else
    no "(B) docs/LIMITS.md is STALE: $out — run: python3 docs/limits_build.py"
fi

# ── (C) CAN-GO-RED on a real source change, in a synthetic tree ─────────────────────────────────────
mkdir -p "$TMP/synth/src" "$TMP/synth/docs"
cp "$GEN" "$TMP/synth/docs/limits_build.py"
printf 'inline constexpr std::size_t kSynthRowCap = 7;\n' > "$TMP/synth/src/synth.h"
python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" >/dev/null 2>&1
printf 'inline constexpr std::size_t kSynthOtherCap = 9;\n' >> "$TMP/synth/src/synth.h"
if python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" --check >/dev/null 2>&1; then
    no "(C) mutation control: an ADDED cap did not make --check fail — this gate cannot go red"
else
    python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" >/dev/null 2>&1
    if python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" --check >/dev/null 2>&1; then
        ok "(C) mutation control: an added cap goes RED, and regenerating clears it"
    else
        no "(C) mutation control: regenerating the synthetic table did not clear the failure"
    fi
fi

# ── (D) a tree with no caps is a refusal, not an empty table ────────────────────────────────────────
mkdir -p "$TMP/empty/src" "$TMP/empty/docs"
cp "$GEN" "$TMP/empty/docs/limits_build.py"
printf '// no caps here\n' > "$TMP/empty/src/none.h"
if python3 "$TMP/empty/docs/limits_build.py" --root "$TMP/empty" --out "$TMP/empty/docs/LIMITS.md" >/dev/null 2>&1; then
    no "(D) generator wrote a table for a tree with ZERO caps instead of refusing"
else
    ok "(D) generator refuses a tree it parses no caps from"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
