#!/usr/bin/env bash
# stdqualcheck.sh — gate for the std::-QUALIFIED C++ call scope guard (graph.h keepStdQualifiedCandidates).
#
# WHAT WAS BROKEN. A C++ call written `std::X( … )` looks up the canonical key `std::X` first. When no in-repo
# def is keyed that way — the normal case, because the def lives in the standard library — the site fell to the
# bare-name spray, and a LONE in-repo definition named X took it: any class's `move()`, `swap()`, `fill()`, at
# full confidence, with no amb= and no prov="split". Nothing splits a lone candidate, so nothing disclosed it.
# Found by a read-only probe of a large C++20 database engine: one header-only string wrapper declares a
# `move()` member, and ~2,100 caller functions' std::move sites bound to it, making that one-line accessor the
# top-ranked symbol of the whole tree. A 6-line reproduction gave --callers count=3.
#
# THE RULE. A call whose written qualifier is `std` — `std::X`, `::std::X`, or a standard library's inline ABI
# namespace spelling such as `std::__1::X` — may bind only a definition that is itself inside namespace std: a
# def scoped `std`, a member of a class written `std::…`, or a def in one of those inline namespaces. When none
# survives the site is refused and counted in the header's `external=`. It is std-ONLY, on purpose: any other
# qualifier can legitimately miss its def's scope (a namespace alias, a using-declaration, a derived-class
# qualifier), and §8's alias arm is the true edge a general rule would delete.
#
# THE CORPUS is test/stdqualfix/; each file's header maps its call spellings to the arm below. EVERY expected
# number is a LITERAL read off those files by hand, never derived the way the resolver derives it.
#
# RED-FIRST (recorded 2026-09-11, plain build of origin/main 3511c93b, before graph.h changed): 19 of the 35
# checks FAIL. The pre-fix readings, each the literal the matching arm now refuses:
#   header           edges=15 ambiguous=1 unresolved=0 external=2           (now edges=6 ambiguous=0 external=12)
#   --callers        Buf::move 4, Slot::swap 3, Cursor::unreachable 2      (now 1 / 1 / 1)
#   --callees        takeTwice takeRooted takeInline flipTwice flipRooted stopHere rotate clearHost = 1 each
#                    (now 0 each); launderIt 2, amb="1", one arm on arena.h's decoy (now 1, polyfill.h, no amb=)
#   census           takeTwice 2x 'unique' -> Buf::move, rotate 'receiver-rule' -> Token::exchange (now 'external');
#                    C external rows 2 (bareMove, bridgeMove)               (now 12)
# The 16 that pass on BOTH binaries are, by construction, the controls: the true member calls (useBuf, useSlot,
# clearGrid), the alias call, the unqualified veto, the ObjC++ floor, the specialization zero and its vacuity
# guard, the Rule-3 eligibility guard, the name-based --uses counts and the hygiene arms. They are what proves the
# guard took ONLY what it should.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/stdqualcheck.sh   |   bash test/stdqualcheck.sh asan/ripwire
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"      # BOTH seams: positional arg and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
# RELATIVE corpus path (we cd to $ROOT below): every p= is relative to the crawl root, so rows read
# `p="buffers.h:21"` and the literals below stay writable.
FIX="test/stdqualfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$ROOT/$FIX" ] || { echo "no test/stdqualfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "stdqualcheck: BIN=$BIN  CORPUS=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | head -1 | tr -dc 0-9; }
el(){ printf '%s' "$1" | grep -oE '<(callers|callees) .*' | head -1; }   # the answer element, without the legend comment

expect(){   # $1 verb  $2 sym  $3 want  $4 prose
    local out; out="$( run "$FIX" "--$1=$2" --no-cache )"
    local got; got="$( cnt "$out" )"
    [ "${got:-REFUSED}" = "$3" ] && ok "--$1=$2 count=$3 — $4" \
        || no "--$1=$2 expected count=$3, got '${got:-REFUSED}' — $4"
}

# the census C rows for one caller: "<mech>\t<targets>" per site, in site order
crows(){ awk -F'\t' -v c="$1" '$1=="C" && index($6, c"#") > 0 {print $2 "\t" $8}' "$TMP/c.tsv"; }

run "$FIX" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml"
MAP="$( cat "$TMP/map.xml" )"
[ -s "$TMP/c.tsv" ] || no "the census run wrote nothing — every census arm below would be vacuous"

# ── §1 THE FALSE EDGES ARE GONE — every std:: spelling, against a LONE same-named member ──────────────────────
BUFC="$( run "$FIX" --callers=Buf::move --no-cache )"
[ "$( cnt "$BUFC" )" = 1 ] \
    && ok "--callers=Buf::move count=1 — only the true member call remains (was 4: three std::move callers)" \
    || no "--callers=Buf::move expected 1, got '$( cnt "$BUFC" )': $( el "$BUFC" )"
printf '%s' "$BUFC" | grep -qE 'n="(takeTwice|takeRooted|takeInline)"' \
    && no "a std::move caller still binds Buf::move: $( el "$BUFC" )" \
    || ok "no std::move / ::std::move / std::__1::move caller is listed under Buf::move"
expect callers Slot::swap          1 "only useSlot's a.swap( b ) remains (was 3)"
expect callees takeTwice           0 "std::move x2 binds nothing in-repo (was Buf::move)"
expect callees takeRooted          0 "::std::move — the leading-:: spelling arrives as qualifier std"
expect callees takeInline          0 "std::__1::move — the libc++ inline-namespace spelling arrives as __1"
expect callees flipTwice           0 "std::swap x2 binds nothing in-repo (was Slot::swap)"
expect callees flipRooted          0 "::std::swap binds nothing in-repo"
expect callees stopHere            0 "std::unreachable() in a .cpp binds nothing in-repo (was Cursor::unreachable)"
# NON-VACUITY: the sites still EXTRACT. --uses is name-based by contract (it answers "where is this name written",
# the call graph answers "what resolves to this def"), so the refused sites stay listed — a count of 0 above is the
# resolver refusing, not the reference disappearing. 7 = takeTwice 2 + takeRooted + takeInline + useBuf + bareMove
# + bridgeMove; 4 = flipTwice 2 + flipRooted + useSlot.
expect uses    move                7 "every move site is still a use-site (unchanged by the guard)"
expect uses    swap                4 "every swap site is still a use-site (unchanged by the guard)"
[ "$( crows takeTwice | grep -c '^external' )" = 2 ] \
    && ok "census: takeTwice has 2 'external' rows — one per std::move SITE, refused rather than dropped silently" \
    || no "census: takeTwice expected 2 external rows, got: $( crows takeTwice | tr '\n' ' ' )"

# ── §2 THE TRUE MEMBER CALLS ARE KEPT ────────────────────────────────────────────────────────────────────────
USEBUF="$( run "$FIX" --callees=useBuf --no-cache )"
{ [ "$( cnt "$USEBUF" )" = 1 ] && printf '%s' "$USEBUF" | grep -q 'n="move" p="buffers.h:21"'; } \
    && ok "--callees=useBuf count=1 -> Buf::move (buffers.h:21) — buf.move() still binds" \
    || no "useBuf lost its true edge to Buf::move: $( el "$USEBUF" )"
USESLOT="$( run "$FIX" --callees=useSlot --no-cache )"
{ [ "$( cnt "$USESLOT" )" = 1 ] && printf '%s' "$USESLOT" | grep -q 'n="swap" p="buffers.h:29"'; } \
    && ok "--callees=useSlot count=1 -> Slot::swap (buffers.h:29) — a.swap( b ) still binds" \
    || no "useSlot lost its true edge to Slot::swap: $( el "$USESLOT" )"

# ── §3 A DEF INSIDE namespace std STILL BINDS — the survivor path, and the specialization reading ──────────────
# polyfill.h puts `launder` in `namespace std { inline namespace __1 { … } }`, so its scope is "__1" and the
# canonical key std::launder misses; arena.h holds a same-directory decoy. The guard must keep the def inside std.
LAUNDER="$( run "$FIX" --callees=launderIt --no-cache )"
{ [ "$( cnt "$LAUNDER" )" = 1 ] && printf '%s' "$LAUNDER" | grep -q 'n="launder" p="polyfill.h:15"'; } \
    && ok "--callees=launderIt count=1 -> the std::__1::launder def (polyfill.h:15) — the def inside std survives" \
    || no "launderIt did not bind exactly the inline-namespace def (was 2, split onto arena.h): $( el "$LAUNDER" )"
printf '%s' "$LAUNDER" | grep -q 'p="arena.h' \
    && no "launderIt still reaches the Arena::launder decoy: $( el "$LAUNDER" )" \
    || ok "no edge from std::launder to the Arena::launder decoy"
printf '%s' "$MAP" | grep -qE 'n="launderIt"[^>]*amb=' \
    && no "launderIt carries amb= — the guard left a split where one def is inside std" \
    || ok "PRECISE: launderIt carries no amb= (was amb=\"1\")"
# stdspec.cpp: `namespace std { template<> struct hash<Mine> { operator() } }` used as `std::hash<Mine>{}( m )`.
# Measured on the pre-fix binary: zero callees — the brace-initialised temporary names no call reference that
# reaches operator(). Pinned at that literal so the guard is seen to invent nothing; the vacuity guard asserts
# the specialization's operator() really is indexed (so the zero is about resolution, not a missing file).
printf '%s' "$MAP" | grep -qE '<s t="method" n="operator\(\)" id="stdspec\.cpp::hash&lt;Mine&gt;::operator\(\)"' \
    && ok "the std::hash<Mine> specialization's operator() IS indexed (scope hash<Mine>)" \
    || no "the specialization's operator() is missing from the map — the arm below is vacuous"
expect callees hashMine            0 "std::hash<Mine>{}( m ) — no edge today, none after: pinned, not invented"

# ── §4 A RULE-3-NARROWED SITE IS STILL GUARDED ──────────────────────────────────────────────────────────────
# `exchange` has two defs (token.h, sub/ledger.h) and exchange_user.cpp includes only token.h, so Rule 3 pins
# `std::exchange` to Token::exchange — census mech "receiver-rule", no amb=. An #include is evidence about FILES,
# never about namespace std, so only the canonical tier may exempt a site from the guard.
[ "$( run "$FIX" --uses=exchange --no-cache | grep -oE '<uses [^>]*>' | grep -oE 'defs="[0-9]+"' )" = 'defs="2"' ] \
    && ok "exchange has 2 defs, so Rule 3 is eligible (the arm below tests a narrowed site, not a lone one)" \
    || no "exchange no longer has exactly 2 defs — the Rule-3 arm is vacuous"
expect callees rotate              0 "std::exchange narrowed by Rule 3 to Token::exchange is refused (was 1)"
[ "$( crows rotate )" = "$( printf 'external\t' )" ] \
    && ok "census: rotate's one site is 'external' (was 'receiver-rule' -> token.h::Token::exchange)" \
    || no "census: rotate expected one external row, got: $( crows rotate | tr '\n' ' ' )"

# ── §5 THE CUDA GRAMMAR PATH ─────────────────────────────────────────────────────────────────────────────────
expect callees clearHost           0 "kernels.cu std::fill binds nothing in-repo (was Grid::fill)"
CGRID="$( run "$FIX" --callees=clearGrid --no-cache )"
{ [ "$( cnt "$CGRID" )" = 1 ] && printf '%s' "$CGRID" | grep -q 'n="fill" p="kernels.cu:7"'; } \
    && ok "--callees=clearGrid count=1 -> Grid::fill (kernels.cu:7) — the CUDA member call still binds" \
    || no "clearGrid lost its true edge to Grid::fill: $( el "$CGRID" )"

# ── §6 THE UNQUALIFIED CONTROL IS UNCHANGED ─────────────────────────────────────────────────────────────────
# `move( x )` under `using namespace std;` has no qualifier; the Phase-5 veto refuses it (table name, no free move),
# before the fix and after. Asserted from the census so the zero cannot be a missing site.
expect callees bareMove            0 "unqualified move( x ) binds nothing — the Phase-5 veto, as before"
[ "$( crows bareMove )" = "$( printf 'external\t' )" ] \
    && ok "census: bareMove's site is refused by the Phase-5 veto ('external', no target) — unchanged" \
    || no "census: bareMove expected one external row, got: $( crows bareMove | tr '\n' ' ' )"

# ── §7 ObjC++ — the qualifier is lost at EXTRACTION, so the guard cannot see it (a STATED FLOOR) ────────────────
# tree-sitter-objc parses `std::move( x )` as an ERROR node `std::` beside a bare call. bridgeMove is refused by
# the Phase-5 veto on both binaries; bridgeStop's std::unreachable is not a table name and still binds the lone
# Cursor::unreachable. Pinned so that closing the floor (a parser change) is a visible decision, not drift.
expect callees bridgeMove          0 "bridge.mm std::move — refused by the Phase-5 veto, not by this guard"
BSTOP="$( run "$FIX" --callees=bridgeStop --no-cache )"
{ [ "$( cnt "$BSTOP" )" = 1 ] && printf '%s' "$BSTOP" | grep -q 'n="unreachable" p="buffers.h:38"'; } \
    && ok "FLOOR: bridge.mm std::unreachable() still binds Cursor::unreachable — ObjC++ carries no qualifier" \
    || no "the ObjC++ floor moved (bridgeStop no longer binds Cursor::unreachable) — update this arm and the fixture: $( el "$BSTOP" )"
expect callers Cursor::unreachable 1 "only the ObjC++ floor remains under Cursor::unreachable (was 2: stopHere too)"

# ── §8 A NON-std QUALIFIER IS UNCHANGED — the alias control ──────────────────────────────────────────────────
PROBE="$( run "$FIX" --callees=probePath --no-cache )"
{ [ "$( cnt "$PROBE" )" = 1 ] && printf '%s' "$PROBE" | grep -q 'n="exists" p="alias.cpp:10"'; } \
    && ok "--callees=probePath count=1 -> vendor::fsimpl::exists via the fs:: alias — a non-std qualifier keeps its edge" \
    || no "the fs:: alias call lost its true edge (the guard generalised past std): $( el "$PROBE" )"

# ── §9 THE HEADER DISCLOSURE MOVES THE RIGHT WAY ─────────────────────────────────────────────────────────────
# edges 15 -> 6: the eight std-qualified false edges go, and launderIt's split collapses to one arm.
# ambiguous 1 -> 0: that split was the corpus's only guess. external 2 -> 12: the ten refused std-qualified SITES
# (takeTwice 2, takeRooted, takeInline, flipTwice 2, flipRooted, stopHere, rotate, clearHost) join the two
# Phase-5 refusals (bareMove, bridgeMove). unresolved stays 0: that gauge means "defined in-repo but lang-filtered".
printf '%s' "$MAP" | grep -qE 'files=13 symbols=35 edges=6 shown=35 est_tokens=[0-9]+ ambiguous=0 unresolved=0 external=12 ' \
    && ok "fixture header: edges=6 ambiguous=0 unresolved=0 external=12 (was edges=15 ambiguous=1 external=2)" \
    || no "fixture header wrong: $( printf '%s' "$MAP" | grep -oE 'files=13 [^-]*' | head -1 )"
[ "$( grep -c $'^C\texternal\t' "$TMP/c.tsv" )" = 12 ] \
    && ok "census: exactly 12 'C external' rows — one per refusal, agreeing with the header's external=12" \
    || no "census: expected 12 external rows, got $( grep -c $'^C\texternal\t' "$TMP/c.tsv" )"

# ── §10 hygiene: determinism, warm == cold, well-formed XML ──────────────────────────────────────────────────
run "$FIX" --pin-census="$TMP/c2.tsv" --no-cache >"$TMP/map2.xml"
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" \
    && ok "deterministic: map + census byte-identical across two --no-cache runs" \
    || no "non-deterministic: map or census differs between two runs"
run "$FIX" --cache="$TMP/c.bin" >"$TMP/cold.xml"; run "$FIX" --cache="$TMP/c.bin" >"$TMP/warm.xml"
cmp -s "$TMP/cold.xml" "$TMP/warm.xml" \
    && ok "warm == cold (the guard reads only facts that survive the cache round-trip)" \
    || no "warm != cold"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map.xml" 2>/dev/null && printf '%s' "$BUFC" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (fixture map + --callers)" || no "xml malformed"
else
    no "cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
