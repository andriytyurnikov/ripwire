#!/usr/bin/env bash
# decltodefcheck.sh — the gate for: #63's decl→def widening must never ANSWER FOR A DEFINITION IT CANNOT
# TIE TO THE DECLARATION. A count carrying counts_floor="1" is a floor; a floor that OVER-counts is not a
# floor at all, it is a wrong answer wearing an honesty marker.
#
# THE DEFECT (H1, shipped in 0.6.0). graph.h::declToDefFollowThrough widens a header-qualified selector
# (`Store.h:putObject` → declarations only, which carry no call-graph edges) to the definitions those
# declarations stand for. Its target test was
#     s.name == name && s.scope == d.scope && hasBody( s.id )
# and `Symbol::scope` is the IMMEDIATELY ENCLOSING class/namespace name only — namespaces are dropped
# (model.h; graph.h ~1082 already says so for another table). So the test is name+bare-class, which:
#   * matches `b::Store::putObject` for a selector naming `a/Store.h` (both scopes are the bare "Store"),
#     and
#   * degenerates to NAME ALONE for free functions, whose scope is "" — the exact over-count the function's
#     own contract note forbids in writing ("Name alone would turn `Foo.h:size` into every free `size` in
#     the repository — an over-count inside an honesty fix, which is strictly worse than the silence it
#     replaces").
#
# THE FIX IT GATES — positive proof, then disclose the residue. A candidate definition survives only with
# EVIDENCE that it belongs to the declaration's file: it is IN that file, or its file #includes that file,
# resolved PATH-precisely (resolve.h::resolvePreciseInclude — never by basename). Unprovable candidates are
# DROPPED, which leaves the count under rather than over (the floor's safe direction), and the number
# dropped is reported so the answer is not a bare zero.
#
# WHAT IT ASSERTS
#   (A) TWO NAMESPACES, ONE CLASS NAME — `a/Store.h:putObject` has ZERO callers; b/Store.cpp's caller must
#       not be served. Its CONTROL is the same corpus's `b/Store.h:putObject`, which must still find that
#       caller: without the control this arm passes just as well on a build where the widening died
#       entirely, which would be #63 reopened. This is also the path-vs-basename decoy — the two headers
#       share a basename and only the include target's PATH tells them apart.
#   (B) FREE FUNCTIONS — `api.h:helper` has ZERO callers; two unrelated `helper`s in anonymous namespaces
#       in TUs that do not include api.h must not be served. CONTROL: the BARE-name selector still unions
#       both, so the fix narrowed the file: tier and nothing else.
#   (C) #63'S OWN CASE — a header, its definition in a .cpp that #includes it, and a caller. The widening
#       MUST still fire: the header-qualified count equals the .cpp-qualified count and both are non-zero.
#       Trading the over-count for #63's silent zero is not a fix. Two shapes: same directory, and the
#       include/ + src/ split whose target is a RELATIVE path (`../include/api.h`).
#   (D) DECL AND DEF IN ONE FILE — a header that both declares and defines still answers. (The selection
#       already holds a bodied def there, so the widening short-circuits; the arm exists because that
#       short-circuit is what makes the proof's same-file clause a guard rather than the live path.)
#   (E) THE RESIDUE IS COUNTED — when candidates were found and dropped, the count of dropped candidates is
#       reported; when nothing was dropped it is 0. Asserted through a standalone unit driver, at the
#       resolver seam where the number is produced.
#   (E2) THE RESIDUE IS DISCLOSED — the same number reaches the READER, as `unproven_defs="N"` on the
#       --callers/--callees root, on all three dialects (XML, --json, --format=columnar), with the clause
#       that defines it in the legend beside it; and BOTH are absent when nothing was dropped. The arm is
#       there because a dropped candidate that the answer does not mention is a plain zero — which is the
#       silence #63 exists to kill, so shipping (E) without (E2) would trade one honesty defect for another.
#   (F) MUTATION — every assertion SHAPE above is shown able to fail, against hand-built inputs.
#
# WHAT (E) AND (E2) EACH COVER, since between them they close what was once a stated gap. (E) reads the
# number at the seam in graph.h that produces it; (E2) reads the RENDERED answer, which is composed in
# src/verbs_navigate.h and was, until the disclosure landed, incapable of carrying it — graph.h has zero
# emit sites, so for one commit the count existed and no reader could see it. Neither arm subsumes the
# other: (E) would stay green if every emitter dropped the attribute, and (E2) would stay green on a
# rendered constant. Keep both (CONTRIBUTING §2, shape 7).
#
# Usage:
#   bash test/decltodefcheck.sh                     # build/ripwire
#   bash test/decltodefcheck.sh build/ripwire_base  # the RED run (a base binary lacks the fix)
#   RIPWIRE_BIN=asan/ripwire bash test/decltodefcheck.sh
#
# Exits non-zero on any failure. Writes only under its own mktemp dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "decltodefcheck: python3 required"; exit 2; }
echo "decltodefcheck: BIN=$BIN"

# ── readers (one each, so no arm hand-rolls a second regex for the same job) ──────────────────────────
# The document is minified onto ONE line and the legend is a comment on that same line, so nothing here is
# ever filtered line-wise: the root element is extracted BY NAME with a non-greedy match instead.
rootEl(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"<"+sys.argv[2]+r"\b[^>]*>",d)
sys.stdout.write(m.group(0) if m else "")' "$1" "$2"; }

# LEFT-ANCHORED on purpose: `defs` is a proper suffix of `unproven_defs` and of `bodyless_defs`, so an
# unanchored search would read one attribute's value out of another's name — and arm (E2) below asserts the
# ABSENCE of one of them, which is exactly the assertion a suffix match makes vacuous.
attr(){ python3 -c '
import re,sys
m=re.search(r"(?<![A-Za-z0-9_])"+sys.argv[2]+r"=\"([^\"]*)\"",sys.argv[1])
sys.stdout.write(m.group(1) if m else "")' "$1" "$2"; }

# The LEADING comment block — the legend a reader meets before the first element, read as a span because G4
# minifies the whole document onto one line (the same extraction test/graphlegendbudgetcheck.sh uses).
legendOf(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.match(r"\A(?:\s*<!--.*?-->)+",d,re.S)
sys.stdout.write(m.group(0) if m else "")' "$1"; }

# One JSON key off the top-level object, as text; empty when the key is absent.
jsonKey(){ python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
sys.stdout.write("" if sys.argv[2] not in d else str(d[sys.argv[2]]))' "$1" "$2"; }

# Every `n="…"` row name in a document, one per line — the arms below assert on the NAME SET, never on a
# substring of the whole document (of="…" echoes the selector, so a bare grep matches itself).
rowNames(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
sys.stdout.write("\n".join(re.findall(r"<s\b[^>]*\bn=\"([^\"]*)\"",d)))' "$1"; }

# Assert a capture is non-empty BEFORE anything is concluded from it.
nonempty(){ [ -n "$2" ] && return 0; no "$1 (empty capture — the arm reading it would have been vacuous)"; return 1; }

run(){ # run <corpus> <selector-flag>  → stdout to $2out
    "$BIN" "$1" --no-cache "$2" 2>/dev/null; }

run2(){ # run <corpus> <selector-flag> <dialect-flag> — the --json / --format=columnar spellings of the same answer
    "$BIN" "$1" --no-cache "$2" "$3" 2>/dev/null; }

# ── corpora, built here rather than committed: each is a minimal repro and a committed .h/.cpp fixture
#    would also join every OTHER gate's view of test/. ────────────────────────────────────────────────
mkdir -p "$TMP/ns/a" "$TMP/ns/b" "$TMP/free" "$TMP/hdr" "$TMP/split/include" "$TMP/split/src" "$TMP/same"

# (A) two namespaces, one class name, one shared basename.
cat > "$TMP/ns/a/Store.h" <<'EOF'
#pragma once
namespace a {
class Store {
public:
    int putObject(int x);
};
}
EOF
cat > "$TMP/ns/b/Store.h" <<'EOF'
#pragma once
namespace b {
class Store {
public:
    int putObject(int x);
};
}
EOF
cat > "$TMP/ns/b/Store.cpp" <<'EOF'
#include "Store.h"
namespace b {
int Store::putObject(int x)
{
    return x + 1;
}
}
int callB(int x)
{
    b::Store s;
    return s.putObject(x);
}
EOF

# (B) free functions: a declaring header nobody includes, two unrelated same-named definitions with
#     internal linkage, each called by its own TU.
cat > "$TMP/free/api.h" <<'EOF'
#pragma once
int helper(int a);
EOF
cat > "$TMP/free/other.cpp" <<'EOF'
namespace {
int helper(int a)
{
    return a * 2;
}
}
int unrelatedCaller(int a)
{
    return helper(a);
}
EOF
cat > "$TMP/free/third.cpp" <<'EOF'
namespace {
int helper(int a)
{
    return a + 7;
}
}
int anotherUnrelated(int a)
{
    return helper(a);
}
EOF

# (C1) #63's own shape: header, defining .cpp beside it, caller.
cat > "$TMP/hdr/Store.h" <<'EOF'
#pragma once
class Store
{
public:
    int putObject(const char* key);
};
EOF
cat > "$TMP/hdr/Store.cpp" <<'EOF'
#include "Store.h"
int Store::putObject(const char* key)
{
    return key ? 1 : 0;
}
EOF
cat > "$TMP/hdr/Caller.cpp" <<'EOF'
#include "Store.h"
int driveTheStore(Store& s)
{
    return s.putObject("k");
}
EOF

# (C2) the same shape across directories, so the include target is a RELATIVE path rather than a bare name.
cat > "$TMP/split/include/api.h" <<'EOF'
#pragma once
class Engine
{
public:
    int spin(int turns);
};
EOF
cat > "$TMP/split/src/engine.cpp" <<'EOF'
#include "../include/api.h"
int Engine::spin(int turns)
{
    return turns * 3;
}
EOF
cat > "$TMP/split/src/driver.cpp" <<'EOF'
#include "../include/api.h"
int driveEngine(Engine& e)
{
    return e.spin(4);
}
EOF

# (D) declaration AND definition in one header, plus a caller elsewhere.
cat > "$TMP/same/Widget.h" <<'EOF'
#pragma once
class Widget
{
public:
    int go(int x);
};
inline int Widget::go(int x)
{
    return x + 1;
}
EOF
cat > "$TMP/same/use.cpp" <<'EOF'
#include "Widget.h"
int driveWidget(Widget& w)
{
    return w.go(2);
}
EOF

echo
echo "=== (A) two namespaces, one class name — the header that declares NOTHING's caller answers zero ==="
run "$TMP/ns" --callers=a/Store.h:putObject >"$TMP/a_far.xml"
run "$TMP/ns" --callers=b/Store.h:putObject >"$TMP/a_own.xml"
RA_F="$( rootEl "$TMP/a_far.xml" callers )"; RA_O="$( rootEl "$TMP/a_own.xml" callers )"
if nonempty "(A) no <callers> root for a/Store.h:putObject" "$RA_F" \
   && nonempty "(A) no <callers> root for b/Store.h:putObject" "$RA_O"; then
    N_F="$( attr "$RA_F" count )"; N_O="$( attr "$RA_O" count )"
    # CONTROL FIRST: b/Store.h really does reach callB through its own .cpp's #include. If this is 0 the
    # widening is dead and the a/ assertion below would be green for the wrong reason.
    if [ "$N_O" != "1" ] || ! rowNames "$TMP/a_own.xml" | grep -qx 'callB'; then
        no "(A) control broken — b/Store.h:putObject should still reach callB (count=\"$N_O\"); the a/ arm would be vacuous"
    elif rowNames "$TMP/a_far.xml" | grep -qx 'callB'; then
        no "(A) a/Store.h:putObject serves callB — a definition in ANOTHER namespace, proven by nothing (H1)"
    elif [ "$N_F" != "0" ]; then
        no "(A) a/Store.h:putObject count=\"$N_F\", expected 0 — nothing calls a::Store::putObject"
    else
        ok "(A) a/Store.h:putObject count=\"0\"; control b/Store.h:putObject count=\"1\" names callB"
    fi
fi

echo
echo "=== (B) free functions — scope=\"\" must not let the widening degenerate to name alone ==="
run "$TMP/free" --callers=api.h:helper >"$TMP/b_file.xml"
run "$TMP/free" --callers=helper       >"$TMP/b_bare.xml"
RB_F="$( rootEl "$TMP/b_file.xml" callers )"; RB_B="$( rootEl "$TMP/b_bare.xml" callers )"
if nonempty "(B) no <callers> root for api.h:helper" "$RB_F" \
   && nonempty "(B) no <callers> root for the bare helper" "$RB_B"; then
    N_BF="$( attr "$RB_F" count )"; N_BB="$( attr "$RB_B" count )"
    SERVED="$( rowNames "$TMP/b_file.xml" | grep -xE 'unrelatedCaller|anotherUnrelated' | tr '\n' ' ' )"
    # CONTROL FIRST: the BARE-name tier is untouched by this fix and still unions both definitions.
    if [ "$N_BB" != "2" ]; then
        no "(B) control broken — the bare-name selector should still find both callers (count=\"$N_BB\", expected 2)"
    elif [ -n "$SERVED" ]; then
        no "(B) api.h:helper serves $SERVED — anonymous-namespace helpers in TUs that never include api.h (H1)"
    elif [ "$N_BF" != "0" ]; then
        no "(B) api.h:helper count=\"$N_BF\", expected 0 — nothing calls the declared helper"
    else
        ok "(B) api.h:helper count=\"0\"; control: bare helper still count=\"2\""
    fi
fi

echo
echo "=== (C) #63 — the declaring header still answers what the defining .cpp answers ==="
for shape in "hdr:Store.h:Store.cpp:putObject:driveTheStore" "split:include/api.h:src/engine.cpp:spin:driveEngine"; do
    dir="${shape%%:*}";  rest="${shape#*:}"
    hdr="${rest%%:*}";   rest="${rest#*:}"
    cpp="${rest%%:*}";   rest="${rest#*:}"
    sym="${rest%%:*}";   who="${rest#*:}"
    run "$TMP/$dir" "--callers=$cpp:$sym" >"$TMP/c_${dir}_cpp.xml"
    run "$TMP/$dir" "--callers=$hdr:$sym" >"$TMP/c_${dir}_hdr.xml"
    RC_C="$( rootEl "$TMP/c_${dir}_cpp.xml" callers )"; RC_H="$( rootEl "$TMP/c_${dir}_hdr.xml" callers )"
    nonempty "(C/$dir) no <callers> root for the .cpp-qualified selector" "$RC_C" || continue
    nonempty "(C/$dir) no <callers> root for the header-qualified selector" "$RC_H" || continue
    N_C="$( attr "$RC_C" count )"; N_H="$( attr "$RC_H" count )"
    if [ -z "$N_C" ] || [ "$N_C" = "0" ]; then
        no "(C/$dir) control broken — .cpp-qualified count=\"$N_C\"; the equality arm would be vacuous at 0==0"
    elif [ "$N_H" != "$N_C" ]; then
        no "(C/$dir) header-qualified count=\"$N_H\" != .cpp-qualified count=\"$N_C\" — #63's silent zero is back"
    elif ! rowNames "$TMP/c_${dir}_hdr.xml" | grep -qx "$who"; then
        no "(C/$dir) header-qualified answer does not name $who — equal counts over the wrong rows"
    else
        ok "(C/$dir) $hdr:$sym count=\"$N_H\" == $cpp:$sym count=\"$N_C\", both name $who"
    fi
done

echo
echo "=== (D) declaration and definition in ONE file — the selection already holds the body ==="
run "$TMP/same" --callers=Widget.h:go >"$TMP/d.xml"
RD="$( rootEl "$TMP/d.xml" callers )"
if nonempty "(D) no <callers> root for Widget.h:go" "$RD"; then
    N_D="$( attr "$RD" count )"
    if [ "$N_D" = "1" ] && rowNames "$TMP/d.xml" | grep -qx 'driveWidget'; then
        ok "(D) Widget.h:go count=\"1\" names driveWidget (decl+def in one file)"
    else
        no "(D) Widget.h:go count=\"$N_D\" — a file holding BOTH the declaration and the body must answer"
    fi
fi

echo
echo "=== (E) the residue is COUNTED — candidates found and dropped are reported, not silently gone ==="
# graph.h has no emit site, so the number is asserted at the resolver seam through a standalone driver
# compiled against the already-built ripwire objects (the test/includeprecisecheck.sh recipe). See THE
# DISCLOSURE GAP in this file's header for what this arm does NOT cover.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    echo "cannot find CMake flags/link under $BUILD_DIR — build with CMake first"; exit 2
fi
CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"
LINK_BODY="$( sed -E 's#^[^ ]+ ##' "$LINK_TXT" )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#-o +ripwire##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#[^ "]*ripwire.dir/src/main.cpp.o##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | tr -d '"' )"

cat > "$TMP/decltodef_unit.cpp" <<EOF
// generated by test/decltodefcheck.sh — the residue count at the seam that produces it.
#include "$ROOT/src/model.h"
#include "$ROOT/src/ingest.h"
#include "$ROOT/src/graph.h"
#include <cstdio>
#include <string>
#include <vector>
using namespace rw;
static int g_fail = 0;
static void check( bool cond, const char* what )
{
    std::printf( cond ? "  PASS  %s\n" : "  FAIL  %s\n", what );
    if( !cond ) { g_fail = 1; }
}
// how many symbols in \`sel\` own a body — the widening's own predicate, so the driver never re-rolls it.
static std::size_t bodiedIn( const IngestResult& ing, const std::vector<NodeId>& sel )
{
    std::size_t n = 0;
    for( NodeId id : sel ) { if( isDefinitionNotDeclaration( ing.symbols[ id ] ) ) { ++n; } }
    return n;
}
int main( int argc, char** argv )
{
    if( argc < 3 ) { std::printf( "UNIT FAIL: usage: %s <nsCorpus> <hdrCorpus>\n", argv[0] ); return 2; }
    const IngestResult nsIng  = ingest( argv[1] );
    const IngestResult hdrIng = ingest( argv[2] );

    // DROPPED: b::Store::putObject is a bodied same-named, same-bare-scope candidate whose file includes
    // b/Store.h, never a/Store.h — one candidate found, one dropped, nothing widened.
    std::size_t dropped = 12345;
    const std::vector<NodeId> far = resolveAllByNameQualified( nsIng, "a/Store.h:putObject", &dropped );
    check( !far.empty(), "(E) premise: a/Store.h:putObject resolves to the declaration" );
    check( bodiedIn( nsIng, far ) == 0, "(E) a/Store.h:putObject widened to NO definition" );
    check( dropped == 1, "(E) unproven candidate count is 1 for a/Store.h:putObject" );

    // NOT DROPPED: Store.cpp includes Store.h, so its definition is proven and the selection widens.
    std::size_t none = 12345;
    const std::vector<NodeId> own = resolveAllByNameQualified( hdrIng, "Store.h:putObject", &none );
    check( bodiedIn( hdrIng, own ) == 1, "(E) Store.h:putObject widened to its proven definition" );
    check( none == 0, "(E) unproven candidate count is 0 when every candidate was proven" );

    // A selector that never reaches the widening at all reports 0, not a stale value.
    std::size_t bare = 12345;
    (void) resolveAllByNameQualified( hdrIng, "putObject", &bare );
    check( bare == 0, "(E) a bare-name selector reports 0 unproven (the widening never runs)" );

    if( g_fail ) { std::printf( "UNIT FAIL\n" ); return 1; }
    std::printf( "UNIT ALL PASS\n" );
    return 0;
}
EOF

UNIT_OK=1
# compiled+linked FROM the build dir: link.txt's object and library paths are relative to it.
if ( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -c "$TMP/decltodef_unit.cpp" -o "$TMP/unit.o" ) 2>"$TMP/cc.err"; then
    ok "(E) residue driver compiles against the ripwire flags"
else
    no "(E) residue driver failed to compile — the residue count is not reported at the resolver seam"
    sed -n '1,25p' "$TMP/cc.err"
    UNIT_OK=0
fi
# shellcheck disable=SC2086
if [ "$UNIT_OK" = 1 ]; then
    if ( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "$TMP/unit.o" $LINK_BODY -o "$TMP/unit" ) 2>"$TMP/ld.err"; then
        ok "(E) residue driver links against the ripwire objects"
    else
        no "(E) residue driver failed to link"; sed -n '1,25p' "$TMP/ld.err"; UNIT_OK=0
    fi
fi
if [ "$UNIT_OK" = 1 ]; then
    "$TMP/unit" "$TMP/ns" "$TMP/hdr" >"$TMP/unit.out" 2>&1
    urc=$?
    grep -E '^  (PASS|FAIL) ' "$TMP/unit.out" || true
    if [ "$urc" -eq 0 ] && grep -q '^UNIT ALL PASS$' "$TMP/unit.out"; then
        ok "(E) residue driver: UNIT ALL PASS"
    else
        no "(E) residue driver reported failures (rc=$urc)"; sed -n '1,40p' "$TMP/unit.out"
    fi
fi

echo
echo "=== (E2) the residue is DISCLOSED — unproven_defs= on the rendered answer, absent when nothing dropped ==="
# The numbers pinned here are the ones arm (E)'s driver reads at the seam (1 for a/Store.h:putObject, 2 for
# api.h:helper): the point of this arm is that the SAME number survives to the reader, so a disagreement
# between the two arms is the defect, not a tolerance.
run  "$TMP/ns"   --callers=a/Store.h:putObject                   >"$TMP/e2_x_callers.xml"
run  "$TMP/ns"   --callees=a/Store.h:putObject                   >"$TMP/e2_x_callees.xml"
run  "$TMP/free" --callers=api.h:helper                          >"$TMP/e2_free.xml"
run  "$TMP/free" --callers=helper                                >"$TMP/e2_bare.xml"
run  "$TMP/hdr"  --callers=Store.h:putObject                     >"$TMP/e2_clean.xml"
run2 "$TMP/ns"   --callers=a/Store.h:putObject --json            >"$TMP/e2_json.json"
run2 "$TMP/ns"   --callers=a/Store.h:putObject --format=columnar >"$TMP/e2_col.xml"

# (E2a) PRESENT, with the seam's own number, on both directions of the 1-hop question. The callees half is
# the one that would have been lost to a copy of bodyless_defs=: that attribute is gated behind !wantCallers
# because a declaration has no callees, and the residue has no such asymmetry — a selector that could not
# tie its definitions to the file it named is equally unanswered whichever edge direction was asked.
for pair in "e2_x_callers.xml:callers:1" "e2_x_callees.xml:callees:1" "e2_free.xml:callers:2"; do
    f="${pair%%:*}"; rest="${pair#*:}"; el="${rest%%:*}"; want="${rest#*:}"
    R="$( rootEl "$TMP/$f" "$el" )"
    nonempty "(E2a) no <$el> root in $f" "$R" || continue
    GOT="$( attr "$R" unproven_defs )"
    CNT="$( attr "$R" count )"
    if [ "$GOT" = "$want" ]; then
        ok "(E2a) $f <$el> carries unproven_defs=\"$GOT\" beside count=\"$CNT\""
    else
        no "(E2a) $f <$el> unproven_defs=\"${GOT:-<absent>}\", expected \"$want\" — the dropped candidates reach the reader as a bare count=\"$CNT\""
    fi
done

# (E2b) ABSENT when nothing was dropped — the other half of "absent at zero", and the arm that stops the
# attribute from becoming noise on every answer. CONTROL FIRST in both cases: a document with no answer in
# it has no attribute either, and would pass this vacuously.
R_CLEAN="$( rootEl "$TMP/e2_clean.xml" callers )"
R_BARE="$( rootEl "$TMP/e2_bare.xml" callers )"
if nonempty "(E2b) no <callers> root for Store.h:putObject" "$R_CLEAN" \
   && nonempty "(E2b) no <callers> root for the bare helper" "$R_BARE"; then
    C_CLEAN="$( attr "$R_CLEAN" count )"; C_BARE="$( attr "$R_BARE" count )"
    if [ "$C_CLEAN" != "1" ] || [ "$C_BARE" != "2" ]; then
        no "(E2b) control broken — every candidate proven: count=\"$C_CLEAN\" (expected 1); bare name: count=\"$C_BARE\" (expected 2). Both absence arms would be vacuous"
    elif [ -n "$( attr "$R_CLEAN" unproven_defs )" ]; then
        no "(E2b) Store.h:putObject carries unproven_defs=\"$( attr "$R_CLEAN" unproven_defs )\" — every candidate was PROVEN, so there is no residue to disclose"
    elif [ -n "$( attr "$R_BARE" unproven_defs )" ]; then
        no "(E2b) the bare-name selector carries unproven_defs= — the widening never runs on that tier, so the attribute is a claim about nothing"
    else
        ok "(E2b) absent at zero: neither the fully-proven file:name answer nor the bare-name answer carries unproven_defs="
    fi
fi

# (E2c) THE OTHER TWO DIALECTS. --help promises the same content in each; an honesty attribute that only the
# default XML carries is a disclosure a --json caller never receives.
J="$( jsonKey "$TMP/e2_json.json" unproven_defs )"
if [ "$J" = "1" ]; then ok "(E2c) --json carries \"unproven_defs\":1"; else no "(E2c) --json unproven_defs is \"${J:-<absent>}\", expected 1"; fi
R_COL="$( rootEl "$TMP/e2_col.xml" callers )"
if nonempty "(E2c) no <callers> root in the columnar answer" "$R_COL"; then
    G_COL="$( attr "$R_COL" unproven_defs )"
    if [ "$G_COL" = "1" ]; then ok "(E2c) --format=columnar carries unproven_defs=\"1\""; else no "(E2c) columnar unproven_defs=\"${G_COL:-<absent>}\", expected 1"; fi
fi

# (E2d) THE LEGEND, emitted exactly when the attribute is — graphlegend.h's own rule (rootRelPathsLegend: a
# legend that defines an attribute the document did not emit is the mirror-image false claim), which is also
# what keeps this clause off every bare-name answer and out of the shared essay's byte budget.
L_HAS="$( legendOf "$TMP/e2_x_callers.xml" )"
L_NOT="$( legendOf "$TMP/e2_clean.xml" )"
if nonempty "(E2d) the disclosing answer has no leading legend comment" "$L_HAS" \
   && nonempty "(E2d) the clean answer has no leading legend comment" "$L_NOT"; then
    case "$L_HAS" in
        *'unproven_defs='*) HAS_DEF=1 ;;
        *)                  HAS_DEF=0 ;;
    esac
    case "$L_NOT" in
        *'unproven_defs='*) NOT_DEF=1 ;;
        *)                  NOT_DEF=0 ;;
    esac
    if [ "$HAS_DEF" != 1 ]; then
        no "(E2d) the answer carrying unproven_defs= does not DEFINE it in the legend the reader meets first"
    elif [ "$NOT_DEF" != 0 ]; then
        no "(E2d) an answer with no residue still defines unproven_defs= — a legend defining an attribute the document did not emit"
    else
        ok "(E2d) the unproven_defs= clause is present exactly when the attribute is"
    fi
fi

echo
echo "=== (F) MUTATION — every assertion shape above is shown able to fail ==="
# (A)/(B) shape: the row-name reader must SEE a wrong caller when one is present…
printf '<callers of="a/Store.h:putObject" defs="2" count="1"><s t="fn" n="callB" p="b/Store.cpp:8"/></callers>' >"$TMP/m_a.xml"
rowNames "$TMP/m_a.xml" | grep -qx 'callB' \
    && ok "(F) A/B-shape: a wrongly-served row IS detected" \
    || no "(F) the row-name reader cannot see a served row that is present"
# …and must NOT be fooled by of=", which echoes the selector into the same document.
printf '<callers of="b/Store.cpp:callB" defs="1" count="0"></callers>' >"$TMP/m_a2.xml"
[ -z "$( rowNames "$TMP/m_a2.xml" )" ] \
    && ok "(F) A/B-shape: of=\"…callB\" with no rows is NOT read as a served row" \
    || no "(F) the row-name reader matched the of= echo — every 'must not serve' arm would be inert"
# (A)/(B) controls: a zero control count must be rejected rather than passing as agreement.
printf '<callers of="x" count="0"></callers>' >"$TMP/m_c0.xml"
[ "$( attr "$( rootEl "$TMP/m_c0.xml" callers )" count )" = "0" ] \
    && ok "(F) control guard: a zero control count IS detected (0==0 vacuity would be caught)" \
    || no "(F) the control guard cannot see a zero count"
# (C) shape: unequal counts must be seen.
printf '<callers of="Store.h:putObject" count="0"></callers>' >"$TMP/m_c.xml"
[ "$( attr "$( rootEl "$TMP/m_c.xml" callers )" count )" != "1" ] \
    && ok "(F) C-shape: a header count that DISAGREES with the .cpp count is detected" \
    || no "(F) the (C) equality comparison cannot tell 0 from 1"
# (E2) shape: the attribute reader must SEE the attribute when it is there…
printf '<callers of="a/Store.h:putObject" defs="1" count="0" unproven_defs="7"></callers>' >"$TMP/m_e2.xml"
[ "$( attr "$( rootEl "$TMP/m_e2.xml" callers )" unproven_defs )" = "7" ] \
    && ok "(F) E2-shape: unproven_defs=\"7\" IS read off a root that carries it" \
    || no "(F) the unproven_defs reader cannot see the attribute — every (E2a) arm would be inert"
# …must report ABSENCE as empty, so (E2b) is an assertion and not a tautology…
printf '<callers of="Store.h:putObject" defs="2" count="1"></callers>' >"$TMP/m_e2b.xml"
[ -z "$( attr "$( rootEl "$TMP/m_e2b.xml" callers )" unproven_defs )" ] \
    && ok "(F) E2-shape: a root WITHOUT the attribute reads as empty" \
    || no "(F) the reader invents a value for an absent attribute — (E2b) would pass on anything"
# …and must not confuse the two attributes whose names end in the same six bytes (`defs`). Both directions:
# the suffix must not be read as the whole name, and the whole name must not be read as the suffix.
printf '<callers of="x" bodyless_defs="3" unproven_defs="5" defs="9" count="0"></callers>' >"$TMP/m_e2c.xml"
RM="$( rootEl "$TMP/m_e2c.xml" callers )"
[ "$( attr "$RM" defs )" = "9" ] && [ "$( attr "$RM" unproven_defs )" = "5" ] && [ "$( attr "$RM" bodyless_defs )" = "3" ] \
    && ok "(F) E2-shape: defs=/bodyless_defs=/unproven_defs= are read as three distinct attributes" \
    || no "(F) the attribute reader matches a NAME SUFFIX — defs=$( attr "$RM" defs ) unproven=$( attr "$RM" unproven_defs ) bodyless=$( attr "$RM" bodyless_defs )"
# (E2c) shape: the JSON reader must tell a present key from an absent one.
printf '{"of":"x","defs":1,"count":0,"unproven_defs":4}' >"$TMP/m_e2j.json"
printf '{"of":"x","defs":1,"count":0}'                   >"$TMP/m_e2j0.json"
[ "$( jsonKey "$TMP/m_e2j.json" unproven_defs )" = "4" ] && [ -z "$( jsonKey "$TMP/m_e2j0.json" unproven_defs )" ] \
    && ok "(F) E2-shape: the JSON key reader distinguishes present from absent" \
    || no "(F) the JSON key reader cannot tell a present key from an absent one"
# (E2d) shape: the legend reader must return nothing for a document with no leading comment, or its
# present/absent comparison is two empty strings agreeing with each other (CONTRIBUTING §2, shape 3).
[ -z "$( legendOf "$TMP/m_e2.xml" )" ] \
    && ok "(F) E2-shape: legendOf returns empty for a document with no leading comment" \
    || no "(F) legendOf invents a legend — the (E2d) comparison could be empty==empty"
# (E) shape: the driver's own reporter must be able to say FAIL — a run that prints no verdict is not a pass.
printf 'UNIT FAIL\n' >"$TMP/m_e.out"
grep -q '^UNIT ALL PASS$' "$TMP/m_e.out" \
    && no "(F) the (E) verdict reader accepts a driver run that failed" \
    || ok "(F) E-shape: a driver run without UNIT ALL PASS is NOT read as a pass"
# VACUITY guard itself. Run in a subshell so it cannot set fail.
if ( nonempty "probe" "" >/dev/null 2>&1 ); then
    no "(F) nonempty() accepts an empty capture — every arm's vacuity guard is inert"
else
    ok "(F) vacuity guard: nonempty() rejects an empty capture"
fi
[ -z "$( rootEl "$TMP/m_e.out" callers )" ] \
    && ok "(F) rootEl: returns empty for an element the document does not contain" \
    || no "(F) rootEl matched a <callers> element in a document that has none"

echo
echo "=== determinism + well-formedness on the answers this gate reads ==="
run "$TMP/ns" --callers=a/Store.h:putObject >"$TMP/det1.xml"
run "$TMP/ns" --callers=a/Store.h:putObject >"$TMP/det2.xml"
if cmp -s "$TMP/det1.xml" "$TMP/det2.xml"; then ok "determinism: a/Store.h:putObject byte-identical run-to-run"; else no "non-deterministic --callers output"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/a_far.xml" 2>/dev/null && xmllint --noout "$TMP/c_hdr_hdr.xml" 2>/dev/null; then
        ok "xml well-formed"
    else
        no "xml malformed"
    fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

echo
[ "$fail" -eq 0 ] && { echo "decltodefcheck: ALL PASS"; exit 0; }
echo "decltodefcheck: FAILURES"; exit 1
