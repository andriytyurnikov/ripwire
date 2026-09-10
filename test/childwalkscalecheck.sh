#!/usr/bin/env bash
# childwalkscalecheck.sh — the SCALING gate for the ten remaining unbounded indexed child walks, and the
# answers each of them must still produce.
#
#   bash test/childwalkscalecheck.sh                       # build/ripwire
#   bash test/childwalkscalecheck.sh .ripwire_pre          # the RED run (pre-change binary, indexed walks)
#   RIPWIRE_BIN=asan/ripwire bash test/childwalkscalecheck.sh
#   RIPWIRE_REF_BIN=/path/to/pre-change/ripwire bash test/childwalkscalecheck.sh   # arm (C)
#
# WHY A THIRD SCALING GATE. test/padscalecheck.sh covers the comment flood through the INGEST walks;
# test/preprocdeadscalecheck.sh covers `collectPreprocDeadRanges` (the include-guard flood the `#if` text
# gate hides from the first). Neither reaches the ten OTHER walks that indexed their children with
# `ts_node_child( n, i )` — five of them live behind a VERB (`--slice`, `--grep`, `--pattern`,
# `--lint --naming-locals`) that no ingest-shaped gate runs, and two more only enter on a file the parser
# had to recover in (`measureFileHealth`) or on an `extern "C"` block (`ffiVisitNode`).
#
# WHAT MAKES THE WALK QUADRATIC — AND WHAT DOES NOT. `ts_node_child( n, i )` restarts tree-sitter's child
# iterator at the first child every call (see the note on src/infra/tschildren.h), so indexing C children
# costs O(C^2) — but ONLY when the child list is FLAT. A grammar REPEAT (16 000 declarations at file
# scope, 16 000 elements in one brace initializer) is stored as a balanced tree of invisible `_repeat`
# nodes, and `ts_node__child` skips a whole invisible subtree in O(1) via `ts_node__relevant_child_count`
# (third_party/deps/tree_sitter/lib/src/node.c). Measured on the pre-change binary, 2026-09-10: a root of
# 128 000 DECLARATIONS is linear (8k/64k/128k = 0.04 / 0.33 / 0.63 s), while a root of 16 000 COMMENTS is
# 117x its own control. Comments are tree-sitter EXTRAS: the parser splices them into the child array
# itself, where no repeat node balances them. Every fixture below is therefore a COMMENT flood — a
# declaration flood of the same width proves nothing and would have shipped a green gate over a live
# defect.
#
# THE FIXTURE SHAPE IS "WIDE NODE, CHEAP CHILDREN". Each fixture makes ONE node's child list N wide and
# every child trivial to process, so what the arm measures is the indexing, not the per-child work. The
# first attempt at these fixtures made the children expensive (16 000 real statements inside the sliced
# definition) and buried the walk under sliceWalkOccurrence — the ratio came out linear with the defect
# still in place.
#
# ARMS
#   (A) ANSWERS — every converted verb still answers correctly ON THE FLOODED FIXTURE, so it is the
#       converted wide walk that produced the answer: the slice's vars, the grep hit, the pattern match,
#       the extern "C" symbol row, `parse_degraded="1"` for the recovered file, and the eight
#       `naming-underscore` LOCAL rows that only --naming-locals can reach. Plus determinism.
#   (B1..B6) SCALING — user CPU, every arm an ISOLATION pair: the SAME fixture width with the walk
#       ENTERED and NOT entered (--slice vs the plain map, --grep vs the plain map, --pattern vs the plain
#       map, --lint --naming-locals vs --lint, an error token present vs absent, `extern "C"` present vs
#       absent). An isolation pair names ONE walk instead of saying "the verb got slower", and it cannot
#       be defeated by a fixed start-up cost the way a 1k-vs-16k ratio can (ffiVisitNode's own 1k arm is
#       0.09 s of C++ ingest, which flattens its ratio to 13x while the walk is 13x its control).
#   (C) BYTE-IDENTICAL vs RIPWIRE_REF_BIN, every fixture x every reaching verb — the conversion must not
#       move one byte. SKIPPED and disclosed when RIPWIRE_REF_BIN is unset.
#   (D) MUTATION — the ratio verdict and the row readers are shown able to fail.
#
# User CPU, never wall, so a loaded box cannot flake the ratios; every ratio floors its divisor so a ~0 s
# small arm cannot manufacture a large one.
#
# NOT CONVERTED, AND WHY (the rest of the audit P1-0 follow-up table, whose class 1 this gate closes):
#   * src/slice.h sliceWalkPreproc IS converted, but has NO scaling arm here and cannot get one YET. Two
#     measurements say why. (i) Its natural isolation control — the identical comment flood inside the
#     same definition with the `#if` removed — routes through sliceWalk's own child loop, which was
#     quadratic too, so the pair reads 0.98x on the pre-change binary AND 0.98x on the fixed one: it can
#     never go red. (ii) A 1k->16k ratio cannot go GREEN, because --slice's rung-3 flow walk
#     (SliceRdWalker, ~11 `ts_node_named_child` loops in this same file) is a LARGER quadratic on the same
#     path and this lane does not own it: --slice over a 16 000-comment definition went 2.38 s -> 1.21 s
#     here (this lane's half), and the residual 1.21 s is `ts_node_named_child` in a `sample` of the fixed
#     binary — dominant even on a fixture whose slice resolves ZERO vars. `ts_node_named_child` is the
#     SAME `ts_node__child` body with include_anonymous=false and the same restart, and a comment is a
#     NAMED extra, so the whole 55-site named-child class has this defect; it is the next lane's, whole,
#     rather than half-converted here. sliceWalkPreproc's conversion is gated by arms (A2) and (C).
#   * src/pattern.h smallestContaining / snapshotNode ARE converted, but have NO arm here and cannot get
#     one: both index the children of the PATTERN's parse tree, and pattern.h:78 caps a pattern at
#     kMaxPatternBytes = 4096 — every path in, --pattern and --lint-rules alike, goes through that one
#     check (pattern.h:683). 4096 bytes is ~2 000 children, i.e. ~2e6 iterator steps, ~1 ms. The cap is
#     why the site was never hot; the conversion is for uniformity and is covered by arm (C).
#   * src/ingest_binds.h:1343 (bindsVisitNode) keeps the indexed form: its body needs the INDEX for
#     `ts_node_field_name_for_child( n, i )`, which is itself index-based, so collecting the children
#     would leave the loop quadratic in the field lookup. The cursor's own O(1)
#     `ts_tree_cursor_current_field_name` is the real fix and is a SEMANTIC change (alias/extra handling)
#     that needs its own gate — not folded into a no-output-change lane.
#   * src/ingest_names.h:61 (firstChildOfType) keeps the indexed form: both callers pass a
#     `using_declaration` / `qualified_identifier`, whose width comes from the grammar, and a per-call
#     cursor allocation would cost more than the scan it replaces. Class 3 in practice, not class 2.
#   * The ~37 class-3 sites (base clauses, parameter/argument lists, attribute lists, fixed-index probes)
#     keep the indexed form on purpose — see the note on src/infra/tschildren.h.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
REF="${RIPWIRE_REF_BIN:-}"
[ -n "$REF" ] && [ "${REF#/}" = "$REF" ] && REF="$ROOT/$REF"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "childwalkscalecheck: python3 required"; exit 2; }
echo "childwalkscalecheck: BIN=$BIN"
[ -n "$REF" ] && echo "childwalkscalecheck: REF=$REF"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
# Generated, never committed: a committed 1 MB comment flood would join every OTHER gate's view of test/
# (trap: a gate fixture that is also part of the live tree the tool indexes).
python3 - "$TMP" <<'PY'
import os, sys
base = sys.argv[ 1 ]
C = "// pad " + "x" * 40

def w( rel, lines ):
    p = os.path.join( base, rel )
    os.makedirs( os.path.dirname( p ), exist_ok = True )
    open( p, 'w' ).write( "\n".join( lines ) + "\n" )

for n in ( 1000, 16000 ):
    # sliceWalk — N comments as children of the ROOT, the sliced definition tiny and early
    w( "slicew/n%d/big.c" % n,
       [ "int helper( int x );", "int target( int x )", "{", "    int acc = x;",
         "    return helper( acc );", "}" ] + [ C ] * n )
    # sliceWalkPreproc — N comments as children of ONE `#if` block INSIDE the sliced definition
    w( "slicepp/n%d/big.c" % n,
       [ "int helper( int x );", "int target( int x )", "{", "    int acc = x;", "#if 1" ]
       + [ C ] * n + [ "#endif", "    return helper( acc );", "}" ] )
    # collectSpanTiers — N comments as children of the ROOT, reached by --grep's span-tier pass
    w( "span/n%d/big.c" % n, [ C ] * n + [ "// needle_marker", "int s0;" ] )
    # measureFileHealth — the same flood, plus ONE token the parser must recover from (walk ENTERED)
    w( "health/n%d/big.c" % n, [ C ] * n + [ "@ @ @", "int e0;" ] )
    # …and its control: byte-for-byte the same flood with no error token (walk RETURNS at the has_error check)
    w( "health_off/n%d/big.c" % n, [ C ] * n + [ "int e0;" ] )
    # ffiVisitNode — N comments as children of an `extern "C"` block's declaration list (walk ENTERED)
    w( "ffi/n%d/big.cpp" % n,
       [ 'extern "C" {' ] + [ C ] * n + [ 'int f0( int a );', '}', 'int useit( void ) { return f0( 1 ); }' ] )
    # …and its control: the same flood and the same declarations, no linkage_specification
    w( "ffi_off/n%d/big.cpp" % n,
       [ C ] * n + [ 'int f0( int a );', 'int useit( void ) { return f0( 1 ); }' ] )
    # ln_collectLocalDecls — N comments in a function body wide enough to clear namingLocalsGate
    # (loc bar AND locals >= 8); the eight locals carry a shape the naming rules report, so arm (A) can
    # prove the re-parse walk ran at all.
    w( "locals/n%d/big.c" % n,
       [ "int bigfun( int x )", "{", "    if( x > 0 )", "    {" ]
       + [ "        int loc__%d = x + %d;" % ( i, i ) for i in range( 8 ) ]
       + [ "        x = loc__0;", "    }" ] + [ C ] * n + [ "    return x;", "}" ] )
    # findMatches (root flood) + matchChildren (the candidate compound_statement's own flood)
    w( "pat/n%d/big.c" % n, [ "void f( void )", "{", "    int a;" ] + [ C ] * n + [ "}" ] + [ C ] * n )
PY

# user-CPU seconds (user+sys) of one cold run of "$@" against corpus $1
usercpu(){ # $1 = corpus dir, rest = binary + flags
    local dir="$1"; shift
    { /usr/bin/time -p "$@" "$dir" --no-cache >/dev/null; } 2>"$TMP/t" || { echo FAIL; return; }
    awk '/^user/ { u = $2 } /^sys/ { s = $2 } END { printf "%.2f", u + s }' "$TMP/t"
}

# The one ratio verdict, so no arm hand-rolls a second arithmetic for the same job. Prints
# "fast" | "linear" | "quad <ratio>". $1 small/control, $2 big, $3 ratio ceiling, $4 absolute short-circuit.
verdict(){ awk -v s="$1" -v b="$2" -v cap="$3" -v floor="$4" 'BEGIN {
    if( b + 0 < floor + 0 ) { print "fast"; exit }        # absolute cost already fine — scaling is moot
    if( s + 0 < 0.02 ) { s = 0.02 }                       # floor the divisor: a ~0 arm cannot invent a ratio
    if( b / s < cap + 0 ) { printf "linear %.1f", b / s } else { printf "quad %.1f", b / s }
}'; }

# One scaling arm. $1 = label, $2 = control CPU, $3 = walk CPU, $4 ceiling, $5 floor, $6 = what the pair is
arm(){
    local label="$1" c="$2" w="$3" cap="$4" fl="$5" what="$6"
    if [ "$c" = FAIL ] || [ "$w" = FAIL ] || [ -z "$c" ] || [ -z "$w" ]; then
        no "$label a timed run failed outright"; return
    fi
    local v; v="$( verdict "$c" "$w" "$cap" "$fl" )"
    case "$v" in
        fast)      ok "$label ${w}s CPU < ${fl}s — the O(C^2) walk is absent ($what, control ${c}s)";;
        linear\ *) ok "$label ${v#linear } x its control (walk=${w}s control=${c}s) — under the ${cap}x ceiling";;
        *)         no "$label ${v#quad } x its control — $what is quadratic in child count (walk=${w}s control=${c}s)";;
    esac
}

count_rows(){ python3 -c '
import re,sys
sys.stdout.write( str( len( re.findall( sys.argv[2], open( sys.argv[1] ).read() ) ) ) )' "$1" "$2"; }

# ── (A) the answers, on the FLOODED fixtures ─────────────────────────────────────────────────────────
echo
echo "=== (A) every converted walk still answers, on a 1000-comment-wide node ==="

"$BIN" "$TMP/slicew/n1000" --no-cache --slice=target >"$TMP/a_slice.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_slice.xml" '<v n="acc"' )" = 1 ] && [ "$( count_rows "$TMP/a_slice.xml" '<v n="x"' )" = 1 ]; then
    ok "(A1) sliceWalk: --slice=target still finds both vars (param x, decl acc) past a 1000-comment root"
else
    no "(A1) sliceWalk: --slice=target lost a var on the flooded fixture"
fi
"$BIN" "$TMP/slicepp/n1000" --no-cache --slice=target >"$TMP/a_slicepp.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_slicepp.xml" '<v n="acc"' )" = 1 ]; then
    ok "(A2) sliceWalkPreproc: --slice=target still finds acc across a 1000-comment \`#if\` block"
else
    no "(A2) sliceWalkPreproc: --slice=target lost acc across the flooded \`#if\` block"
fi
"$BIN" "$TMP/span/n1000" --no-cache --grep=needle_marker >"$TMP/a_grep.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_grep.xml" 'tier="comment"' )" = 1 ] && [ "$( count_rows "$TMP/a_grep.xml" '<hit ' )" = 1 ]; then
    ok "(A3) collectSpanTiers: --grep still finds the hit AND still classifies it tier=comment"
else
    no "(A3) collectSpanTiers: --grep lost the hit or its comment tier on the flooded fixture"
fi
"$BIN" "$TMP/health/n1000" --no-cache --grep=pad >"$TMP/a_health.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_health.xml" '<f p="big[.]c" parse_degraded="1"' )" = 1 ]; then
    ok "(A4) measureFileHealth: the recovered file is still flagged parse_degraded=\"1\""
else
    no "(A4) measureFileHealth: the recovered file lost its parse_degraded flag"
fi
"$BIN" "$TMP/ffi/n1000" --no-cache --top-k=100000 >"$TMP/a_ffi.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_ffi.xml" '<c n="f0"/>' )" = 1 ]; then
    ok "(A5) ffiVisitNode: the extern \"C\" declaration is still resolved as a call target"
else
    no "(A5) ffiVisitNode: the extern \"C\" call edge is gone on the flooded fixture"
fi
"$BIN" "$TMP/locals/n1000" --no-cache --lint --naming-locals >"$TMP/a_loc_on.xml" 2>/dev/null
"$BIN" "$TMP/locals/n1000" --no-cache --lint                 >"$TMP/a_loc_off.xml" 2>/dev/null
A_ON="$(  count_rows "$TMP/a_loc_on.xml"  '<f rule="naming-underscore"' )"
A_OFF="$( count_rows "$TMP/a_loc_off.xml" '<f rule="naming-underscore"' )"
if [ "$A_ON" = 8 ] && [ "$A_OFF" = 0 ]; then
    ok "(A6) ln_collectLocalDecls: all 8 local naming rows are still served (and 0 without --naming-locals)"
else
    no "(A6) ln_collectLocalDecls: expected 8 local rows with --naming-locals and 0 without; got $A_ON / $A_OFF"
fi
"$BIN" "$TMP/pat/n1000" --no-cache --pattern='{ int a; ... }' >"$TMP/a_pat.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_pat.xml" '<m p="big.c:2" in="f">' )" = 1 ]; then
    ok "(A7) findMatches/matchChildren: the pattern still matches f's body past 1000 comment children"
else
    no "(A7) findMatches/matchChildren: the pattern lost its match on the flooded body"
fi
"$BIN" "$TMP/slicew/n1000" --no-cache --slice=target >"$TMP/a_slice2.xml" 2>/dev/null
if [ ! -s "$TMP/a_slice.xml" ]; then
    no "(A8) determinism (empty --slice answer)"
elif cmp -s "$TMP/a_slice.xml" "$TMP/a_slice2.xml"; then
    ok "(A8) determinism (two cold --slice runs byte-identical, $( wc -c <"$TMP/a_slice.xml" | tr -d ' ' ) B)"
else
    no "(A8) determinism (two cold --slice runs differ)"
fi

# ── (B) scaling ──────────────────────────────────────────────────────────────────────────────────────
echo
echo "=== (B) scaling: one node's child list 16000 wide, every child trivial ==="

b_slicew_map="$(   usercpu "$TMP/slicew/n16000"  "$BIN" --top-k=100000 )"
b_slicew_walk="$(  usercpu "$TMP/slicew/n16000"  "$BIN" --slice=target )"
arm "(B1) sliceWalk" "$b_slicew_map" "$b_slicew_walk" 8 0.30 "--slice over a 16000-comment root vs the plain map of the same file"

b_span_map="$(     usercpu "$TMP/span/n16000"    "$BIN" --top-k=100000 )"
b_span_walk="$(    usercpu "$TMP/span/n16000"    "$BIN" --grep=needle_marker )"
arm "(B2) collectSpanTiers" "$b_span_map" "$b_span_walk" 8 0.30 "--grep's span-tier pass over a 16000-comment root vs the plain map"

b_health_off="$(   usercpu "$TMP/health_off/n16000" "$BIN" --top-k=100000 )"
b_health_on="$(    usercpu "$TMP/health/n16000"     "$BIN" --top-k=100000 )"
arm "(B3) measureFileHealth" "$b_health_off" "$b_health_on" 8 0.30 "one recovered token over a 16000-comment root vs the identical flood with none"

b_ffi_off="$(      usercpu "$TMP/ffi_off/n16000" "$BIN" --top-k=100000 )"
b_ffi_on="$(       usercpu "$TMP/ffi/n16000"     "$BIN" --top-k=100000 )"
arm "(B4) ffiVisitNode" "$b_ffi_off" "$b_ffi_on" 8 0.30 "an extern \"C\" block 16000 children wide vs the identical flood outside one"

b_loc_off="$(      usercpu "$TMP/locals/n16000"  "$BIN" --lint )"
b_loc_on="$(       usercpu "$TMP/locals/n16000"  "$BIN" --lint --naming-locals )"
arm "(B5) ln_collectLocalDecls" "$b_loc_off" "$b_loc_on" 8 0.30 "--naming-locals' re-parse walk over a 16000-comment body vs --lint alone"

b_pat_map="$(      usercpu "$TMP/pat/n16000"     "$BIN" --top-k=100000 )"
b_pat_walk="$(     usercpu "$TMP/pat/n16000"     "$BIN" --pattern='{ int a; ... }' )"
arm "(B6) findMatches/matchChildren" "$b_pat_map" "$b_pat_walk" 8 0.30 "--pattern over a 16000-comment root and body vs the plain map"

# ── (C) byte-identical against a reference binary ────────────────────────────────────────────────────
echo
echo "=== (C) byte-identical output vs RIPWIRE_REF_BIN ==="
if [ -z "$REF" ]; then
    skip "(C) RIPWIRE_REF_BIN unset — no reference binary to compare against (set it to the pre-change build)"
elif [ ! -x "$REF" ]; then
    no "(C) RIPWIRE_REF_BIN=$REF is not executable"
else
    c_fail=0
    c_seen=0
    cmp_pair(){ # $1 = corpus, rest = flags
        local dir="$1"; shift
        c_seen=$(( c_seen + 1 ))
        "$BIN" "$dir" --no-cache "$@" >"$TMP/c_new" 2>/dev/null
        "$REF" "$dir" --no-cache "$@" >"$TMP/c_ref" 2>/dev/null
        if [ ! -s "$TMP/c_ref" ]; then
            no "(C) reference output of $( basename "$( dirname "$dir" )" )/$( basename "$dir" ) [$*] is empty — the comparison would be vacuous"; c_fail=1
        elif ! cmp -s "$TMP/c_new" "$TMP/c_ref"; then
            no "(C) $( basename "$( dirname "$dir" )" )/$( basename "$dir" ) [$*] differs from the reference binary"; c_fail=1
        fi
    }
    for n in n1000 n16000; do
        for d in slicew slicepp span health health_off ffi ffi_off locals pat; do
            cmp_pair "$TMP/$d/$n" --top-k=100000
        done
        cmp_pair "$TMP/slicew/$n"  --slice=target
        cmp_pair "$TMP/slicepp/$n" --slice=target
        cmp_pair "$TMP/span/$n"    --grep=needle_marker
        cmp_pair "$TMP/health/$n"  --grep=pad
        cmp_pair "$TMP/locals/$n"  --lint --naming-locals
        cmp_pair "$TMP/pat/$n"     --pattern='{ int a; ... }'
    done
    [ "$c_fail" = 0 ] && ok "(C1) $c_seen generated fixture x verb pairs are byte-identical to the reference"
    c_fail=0
    c_seen=0
    for d in "$ROOT/test/cfix" "$ROOT/test/cppqualfix" "$ROOT/test/preproccondfix" "$ROOT/test/ffifix" "$ROOT/test/pyimportprecisefix" "$ROOT/test/sliceflowsensfix" "$ROOT/test/lintfix"; do
        [ -d "$d" ] || continue
        cmp_pair "$d" --top-k=100000
        cmp_pair "$d" --grep=int
        cmp_pair "$d" --lint --naming-locals
    done
    if [ "$c_seen" = 0 ]; then
        no "(C2) no committed fixture tree found — the arm would have been vacuous"
    elif [ "$c_fail" = 0 ]; then
        ok "(C2) $c_seen committed fixture x verb pairs are byte-identical to the reference"
    fi
fi

# ── (D) mutation: every verdict shape above is shown able to fail ────────────────────────────────────
echo
echo "=== (D) MUTATION — the verdict and row readers are shown able to fail ==="
case "$( verdict 0.09 1.22 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change ffiVisitNode pair (0.09s vs 1.22s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the pathology it was written against";;
esac
case "$( verdict 0.02 2.43 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change findMatches pair (0.02s vs 2.43s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the largest pathology it was written against";;
esac
case "$( verdict 0.10 0.70 8 0.30 )" in
    linear\ *) ok "(D) a 7x pair (0.10s vs 0.70s) IS called linear, not quad";;
    *)         no "(D) the isolation verdict calls a linear pair quadratic";;
esac
case "$( verdict 0.01 0.20 8 0.30 )" in
    fast) ok "(D) a sub-0.30s walk arm short-circuits to fast";;
    *)    no "(D) the absolute short-circuit does not fire";;
esac
printf '<lint><f rule="naming-underscore" p="a:1" in="g">a__b</f><f rule="naming-short" p="a:2" in="g">q</f></lint>' >"$TMP/m.xml"
if [ "$( count_rows "$TMP/m.xml" '<f rule="naming-underscore"' )" = 1 ] && [ "$( count_rows "$TMP/m.xml" '<f rule="nope"' )" = 0 ]; then
    ok "(D) the row reader counts rows that are present and invents none that are absent"
else
    no "(D) the row reader miscounts"
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
