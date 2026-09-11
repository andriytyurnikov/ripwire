#!/usr/bin/env bash
# declinecheck.sh — the TIER-3 DECLINE is disclosed, and every call reference ends in exactly one disposition.
#
#   test/declinecheck.sh                          # uses build/ripwire on test/declinefix
#   RIPWIRE_BIN=asan/ripwire test/declinecheck.sh
#   test/declinecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. buildGraph's name-based ladder ends in tier 3, "a UNIQUE global, else DROP". A call whose candidates
# are two or more same-language definitions, none in the caller's file or directory, and which neither a qualifier
# (`canonical`) nor a receiver/include rule (`narrowed`) pinned, left the resolve loop through `continue`: no edge,
# no amb=, and no header gauge moved. `--callers` on either definition then answered count="0" beside ambiguous=0
# unresolved=0 — a zero that read as "none exists" about a call the resolver had SEEN and declined to guess at. On
# retrofit (the PR #126 review) Response.body's callers fell from 279 to 5 the moment same-named Kotlin body()
# methods appeared, and no document said so. CLAUDE.md non-negotiable #3: a zero means "none found".
#
# THE FIX IS DISCLOSURE, NOT RESOLUTION. The precision rule stands (never guess among cross-directory same-named
# definitions) and the edge set is unchanged — arm (C) pins the pre-change binary's own numbers. What changed is
# that the refusal is COUNTED and VISIBLE:
#   header declined=N (JSON "declined")        calls tier 3 declined; absent when 0
#   --callers declined_calls="K"               declined calls that could have meant SYM — K CALLS, never call x def
#   --callees declined_calls="K"               declined calls SYM itself makes
#   --impact  declined_calls="K"               declined calls that could have reached SYM or a symbol in its radius
#   the MCP twins (find_referencing_symbols, find_symbol, impact) carry the same key
#
# THE CONSERVATION LINE, arm (F). --pin-census ends with `# dispositions calls=N bound=… unaccounted=K`: every call
# reference the resolver considers is counted in exactly one bucket when its resolve-loop iteration ENDS, so a
# `continue` that names no disposition lands in `unaccounted`. The dispositions must sum to calls=, unaccounted must
# be 0, and three buckets are re-derived from other surfaces (the header gauges, the census decision rows). A future
# silent `continue` in any language the fixture reaches turns this gate red.
#
# THE FIXTURE (test/declinefix/). Each language puts one same-named method in a/ (alpha/) and one in b/ (beta/) and
# calls it through an untyped receiver from a third directory — the shape no rule can pin.
#   (A) java, cpp, py, rust   the decline: --callees on the caller and --callers on BOTH definitions read
#                             count="0" declined_calls="1"; the bare name (defs="2") still counts ONE call
#   (B) the other 13 code languages (ts js go swift objc bash ruby csharp c php lua elixir dart): the same decline
#   (C) controls, each one census decision row, exactly as the pre-change binary emitted it:
#       same-directory duplicates -> split (Java, C++, Python); a unique global -> unique (Java, C++, Python);
#       a Rule-1 `narrowed` rescue (Widget::run -> step, flags r); a `canonical` rescue (ns::pick, flags q);
#       an external name -> external (C++ find, Python sum); header edges=13 ambiguous=5 unresolved=1 external=2
#   (D) header declined=17, legend-defined, JSON twin; both ABSENT on a one-directory corpus (test/lpinfix)
#   (E) the three answers in XML / --json / --format=columnar and the MCP twins; each legend defines the key it
#       emits, and an answer with nothing declined carries neither the key nor its clause
#   (F) conservation: the dispositions sum to calls=, unaccounted=0, census declined/external/unresolved == the
#       header's, bound == the non-external decision rows; every exit the fixture is built to reach is reached;
#       a two-root run reaches other_root and conserves too
#   (G) the predicates can fail (a line that does not sum, unaccounted=1, a bare zero, a header without declined=)
#   (H) determinism x2 (map and census), xmllint, no degrade alert on stderr
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/declinefix"
CLEAN="$ROOT/test/lpinfix"                           # one directory: no call can reach tier 3
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "declinecheck: BIN=$BIN  CORPUS=$CORPUS"

cd "$CORPUS" || exit 2                               # every file:name selector below is relative to the root `.`
rw(){ "$BIN" . --no-cache "$@" 2>/dev/null; }

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }                               # first <TAG …> start tag
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
stats(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }                             # the map's STATS comment only
gauge(){ printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }   # "" when absent
disp_in(){ grep -m1 '^# dispositions ' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
# the census decision row for (caller id, callee): "mech<TAB>flags<TAB>targets"
crow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $5 "\t" $8; exit}' "$TMP/c.tsv"; }
# the leading run of comments — the legend the reader meets first (legendcoveragecheck's own reading)
legend_of(){ python3 - "$1" <<'PY'
import re, sys
t = open( sys.argv[1] ).read()
m = re.match( r"(\s*<!--.*?-->)+", t, re.S )
print( m.group( 0 ) if m else "" )
PY
}
# conservation predicate: calls= equals the sum of every other bucket, and unaccounted= is present and 0
conserves(){ python3 - "$1" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[1] ) )
calls = kv.pop( "calls", None )
sys.exit( 0 if calls is not None and "unaccounted" in kv and kv[ "unaccounted" ] == 0 and sum( kv.values() ) == calls else 1 )
PY
}

"$BIN" . --no-cache --pin-census="$TMP/c.tsv" >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
HDR="$( stats "$TMP/map.xml" )"

# ── (A) the decline, disclosed where the zero is read ─────────────────────────────────────────────────────────
echo "=== (A) the decline is disclosed where the zero is read — Java, C++, Python, Rust ==="
# lang | caller id (census) | caller name | callee name | definition 1 | definition 2
while IFS='|' read -r lang cid caller name def1 def2; do
    [ -z "$lang" ] && continue
    rw --callees="$caller" >"$TMP/callees.xml"
    R="$( root_tag "$TMP/callees.xml" callees )"
    [ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
        && ok "(A) $lang: --callees=$caller count=\"0\" declined_calls=\"1\"" \
        || no "(A) $lang: --callees=$caller should read count=\"0\" declined_calls=\"1\": ${R:-no <callees> root}"
    for def in "$def1" "$def2"; do
        rw --callers="$def" >"$TMP/callers.xml"
        R="$( root_tag "$TMP/callers.xml" callers )"
        [ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
            && ok "(A) $lang: --callers=$def count=\"0\" declined_calls=\"1\" — the zero says a call was declined" \
            || no "(A) $lang: --callers=$def is a bare zero: ${R:-no <callers> root}"
    done
    # the bare name unions both definitions; the ONE declined call is one call, not one per definition
    rw --callers="$name" >"$TMP/callers.xml"
    R="$( root_tag "$TMP/callers.xml" callers )"
    [ "$( attr "$R" defs )" = 2 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
        && ok "(A) $lang: --callers=$name (defs=\"2\") counts the declined call once" \
        || no "(A) $lang: --callers=$name should read defs=\"2\" declined_calls=\"1\": ${R:-no <callers> root}"
    [ -z "$( crow "$cid" "$name" )" ] \
        && ok "(A) $lang: still no decision row for $caller -> $name (no edge was added)" \
        || no "(A) $lang: $caller -> $name now has a decision row — the fix changed which edges exist: $( crow "$cid" "$name" )"
done <<'EOF'
java|java/caller/JavaCaller.java::javaDeclined|javaDeclined|jbody|java/alpha/Alpha.java:jbody|java/beta/Beta.java:jbody
cpp|cpp/caller/caller.cpp::cppDeclined|cppDeclined|crender|cpp/alpha/alpha.cpp:crender|cpp/beta/beta.cpp:crender
py|py/caller/caller.py::py_declined|py_declined|pyfetch|py/alpha/alpha.py:pyfetch|py/beta/beta.py:pyfetch
rust|rust/caller/caller.rs::rust_declined|rust_declined|rfetch|rust/alpha/alpha.rs:rfetch|rust/beta/beta.rs:rfetch
EOF

# ── (B) the ladder is language-agnostic ───────────────────────────────────────────────────────────────────────
echo "=== (B) the same decline in every other code language ==="
for pair in ts:tsDeclined js:jsDeclined go:GoDeclined swift:swiftDeclined objc:objcDeclined bash:bash_declined \
            ruby:ruby_declined csharp:CsDeclined c:c_declined php:phpDeclined lua:lua_declined elixir:ex_declined dart:dartDeclined; do
    lang="${pair%%:*}"; caller="${pair#*:}"
    rw --callees="$caller" >"$TMP/sweep.xml"
    R="$( root_tag "$TMP/sweep.xml" callees )"
    [ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
        && ok "(B) $lang: --callees=$caller count=\"0\" declined_calls=\"1\"" \
        || no "(B) $lang: --callees=$caller should read count=\"0\" declined_calls=\"1\": ${R:-no <callees> root}"
done

# ── (C) controls: every shape that is NOT a decline resolves exactly as the pre-change binary resolved it ─────
echo "=== (C) controls — resolution unchanged ==="
# label | caller id | callee | mech | flags | target count
while IFS='|' read -r label cid name mech flags want; do
    [ -z "$label" ] && continue
    ROW="$( crow "$cid" "$name" )"
    GOT_M="$( printf '%s' "$ROW" | cut -f1 )"
    GOT_F="$( printf '%s' "$ROW" | cut -f2 )"
    GOT_N="$( printf '%s' "$ROW" | cut -f3 | awk -F'|' '{ print ( $0 == "" ? 0 : NF ) }' )"
    [ -n "$ROW" ] && [ "$GOT_M" = "$mech" ] && [ "$GOT_F" = "$flags" ] && [ "$GOT_N" = "$want" ] \
        && ok "(C) $label: $name -> $mech flags=$flags targets=$want" \
        || no "(C) $label: $name expected $mech/$flags/$want, census row: '${ROW:-none}'"
done <<'EOF'
same-dir split, Java|java/pair/PairUser.java::javaSplit|jtwin|split|-|2
same-dir split, C++|cpp/pair/user.cpp::cppSplit|ctwin|split|-|2
same-dir split, Python|py/pair/user.py::py_split|pytwin|split|-|2
unique global, Java|java/caller/JavaCaller.java::javaUnique|jonly|unique|-|1
unique global, C++|cpp/caller/caller.cpp::cppUnique|conly|unique|-|1
unique global, Python|py/caller/caller.py::py_unique|pyonly|unique|-|1
narrowed rescue, C++ Rule 1|cpp/widget_run/run.cpp::Widget::run|step|split|r|2
canonical rescue, C++ ns::|cpp/ns_user/use.cpp::cppCanonical|pick|split|q|2
external name, C++|cpp/caller/caller.cpp::cppExternal|find|external|-|0
external name, Python|py/caller/caller.py::py_external|sum|external|-|0
EOF
rw --callees=javaSplit >"$TMP/split.xml"
R="$( root_tag "$TMP/split.xml" callees )"
[ "$( attr "$R" count )" = 2 ] && [ -z "$( attr "$R" declined_calls )" ] \
    && ok "(C) a same-directory split is an edge pair, never a decline: --callees=javaSplit count=\"2\", no declined_calls=" \
    || no "(C) --callees=javaSplit: $R"
for pin in "edges 13" "ambiguous 5" "unresolved 1" "external 2"; do
    set -- $pin
    [ "$( gauge "$HDR" "$1" )" = "$2" ] && ok "(C) header $1=$2, the pre-change binary's own number" \
        || no "(C) header $1=$( gauge "$HDR" "$1" ) — the pre-change binary emits $1=$2 on this fixture"
done

# ── (D) the header gauge ──────────────────────────────────────────────────────────────────────────────────────
echo "=== (D) header declined= counts every declined call, is defined, and is silent at zero ==="
[ "$( gauge "$HDR" declined )" = 17 ] && ok "(D) header declined=17 (4 in arm A + 13 in arm B)" \
    || no "(D) header declined= is not 17: $( printf '%s' "$HDR" | grep -oE ' declined=[0-9]+' || echo absent )"
legend_of "$TMP/map.xml" | grep -q 'hdr:declined=' && ok "(D) the map legend defines hdr:declined=" \
    || no "(D) the map legend does not define hdr:declined="
"$BIN" "$CLEAN" --no-cache >"$TMP/clean.xml" 2>/dev/null
[ -n "$( stats "$TMP/clean.xml" )" ] || no "(D) premise: no stats comment from $CLEAN"
stats "$TMP/clean.xml" | grep -q ' declined=' \
    && no "(D) declined= present on a one-directory corpus, where no call can reach tier 3" \
    || ok "(D) declined= absent where nothing was declined (test/lpinfix)"
rw --json >"$TMP/map.json"
grep -q '"declined":17,' "$TMP/map.json" && ok '(D) --json header carries "declined":17' \
    || no "(D) --json declined gauge missing or wrong: $( grep -oE '"declined":[0-9]+' "$TMP/map.json" || echo absent )"
"$BIN" "$CLEAN" --json --no-cache >"$TMP/clean.json" 2>/dev/null
grep -q '"declined"' "$TMP/clean.json" && no '(D) "declined" present in --json on a decline-free corpus' \
    || ok '(D) "declined" absent from --json on a decline-free corpus'

# ── (E) the answers, every dialect ────────────────────────────────────────────────────────────────────────────
echo "=== (E) callers / callees / impact carry declined_calls= in every dialect, defined where emitted ==="
DEF=java/alpha/Alpha.java:jbody
for spec in "callers $DEF" "callees javaDeclined" "impact $DEF"; do
    set -- $spec
    verb="$1"; sel="$2"
    rw --"$verb"="$sel" >"$TMP/$verb.xml"
    R="$( root_tag "$TMP/$verb.xml" "$verb" )"
    [ "$( attr "$R" declined_calls )" = 1 ] && ok "(E) --$verb=$sel XML root declined_calls=\"1\"" \
        || no "(E) --$verb=$sel XML root: ${R:-no <$verb> root}"
    legend_of "$TMP/$verb.xml" | grep -q 'declined_calls=' && ok "(E) --$verb legend defines declined_calls=" \
        || no "(E) --$verb legend never defines declined_calls="
    rw --"$verb"="$sel" --json >"$TMP/$verb.json"
    grep -q '"declined_calls":1[,}]' "$TMP/$verb.json" && ok "(E) --$verb --json carries \"declined_calls\":1" \
        || no "(E) --$verb --json: $( head -c 240 "$TMP/$verb.json" )"
    rw --"$verb"="$sel" --format=columnar >"$TMP/$verb.col"
    R="$( root_tag "$TMP/$verb.col" "$verb" )"
    [ "$( attr "$R" declined_calls )" = 1 ] && ok "(E) --$verb --format=columnar root declined_calls=\"1\"" \
        || no "(E) --$verb columnar root: ${R:-no <$verb> root}"
done
# omit-at-zero: an answer with nothing declined carries neither the key nor the clause
for spec in "callers java/solo/Solo.java:jonly" "callees javaUnique" "impact java/solo/Solo.java:jonly"; do
    set -- $spec
    verb="$1"; sel="$2"
    rw --"$verb"="$sel" >"$TMP/zero.xml"
    R="$( root_tag "$TMP/zero.xml" "$verb" )"
    [ -n "$R" ] && [ -z "$( attr "$R" declined_calls )" ] && ok "(E) --$verb=$sel: nothing declined, no declined_calls=" \
        || no "(E) --$verb=$sel carries declined_calls= with nothing declined (or no root): ${R:-none}"
    legend_of "$TMP/zero.xml" | grep -q 'declined_calls=' \
        && no "(E) --$verb=$sel legend defines declined_calls= on an answer that does not carry it" \
        || ok "(E) --$verb=$sel legend carries no declined_calls= clause either"
done
# the MCP twins — JSON-RPC over stdio, exactly what a client speaks
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r[ "error" ].get( "message", "" ) if "error" in r else r[ "result" ][ "content" ][ 0 ][ "text" ] )
'
}
call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$CORPUS"'","symbol":"jbody"}' )" )"
printf '%s' "$M" | grep -q '"declined_calls":1[,}]' && ok "(E) MCP find_referencing_symbols carries \"declined_calls\":1" \
    || no "(E) MCP find_referencing_symbols: $( printf '%s' "$M" | head -c 240 )"
M="$( mcp_text "$( call find_symbol '{"path":"'"$CORPUS"'","symbol":"javaDeclined"}' )" )"
printf '%s' "$M" | grep -q '"declined_calls":1[,}]' && ok "(E) MCP find_symbol (the callees direction) carries \"declined_calls\":1" \
    || no "(E) MCP find_symbol: $( printf '%s' "$M" | head -c 240 )"
M="$( mcp_text "$( call impact '{"path":"'"$CORPUS"'","symbol":"jbody","legend":"full"}' )" )"
printf '%s' "$M" | grep -oE '<impact [^>]*>' | grep -q ' declined_calls="1"' && ok "(E) MCP impact root declined_calls=\"1\"" \
    || no "(E) MCP impact: $( printf '%s' "$M" | grep -oE '<impact [^>]*>' | head -1 || echo no root )"

# ── (F) conservation ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (F) conservation — every call reference ends in exactly one disposition ==="
DL="$( grep -m1 '^# dispositions ' "$TMP/c.tsv" )"
if [ -z "$DL" ]; then
    no "(F) the census carries no '# dispositions' line — the resolver's reference total is not exposed"
else
    ok "(F) census: $DL"
    conserves "$DL" && ok "(F) the dispositions sum to calls= and unaccounted=0" || no "(F) conservation broken: $DL"
    for pair in "declined declined" "external external" "unresolved unresolved"; do
        set -- $pair
        [ "$( disp_in "$TMP/c.tsv" "$1" )" = "$( gauge "$HDR" "$2" )" ] \
            && ok "(F) census $1=$( disp_in "$TMP/c.tsv" "$1" ) == header $2=" \
            || no "(F) census $1=$( disp_in "$TMP/c.tsv" "$1" ) but header $2=$( gauge "$HDR" "$2" ) — two derivations disagree"
    done
    NONEXT="$( awk -F'\t' '$1=="C" && $2!="external"' "$TMP/c.tsv" | wc -l | tr -d ' ' )"
    [ "$( disp_in "$TMP/c.tsv" bound )" = "$NONEXT" ] \
        && ok "(F) bound=$NONEXT == the non-external decision rows (recorded at the emission point, not the loop's end)" \
        || no "(F) bound=$( disp_in "$TMP/c.tsv" bound ) but the census has $NONEXT non-external decision rows"
    for d in bound self external unresolved undefined qualified_external declined file_scope; do
        v="$( disp_in "$TMP/c.tsv" "$d" )"
        [ -n "$v" ] && [ "$v" -ge 1 ] && ok "(F) presence: the fixture reaches $d ($v)" \
            || no "(F) presence: $d=${v:-absent} — the fixture no longer exercises that exit, so its arm proves nothing"
    done
fi
# two roots: the caller's only same-named definition lives in the OTHER root, with no include evidence
"$BIN" java/caller java/alpha --no-cache --pin-census="$TMP/mr.tsv" >"$TMP/mr.xml" 2>/dev/null
MR="$( grep -m1 '^# dispositions ' "$TMP/mr.tsv" 2>/dev/null )"
v="$( disp_in "$TMP/mr.tsv" other_root 2>/dev/null )"
[ -n "$MR" ] && conserves "$MR" && [ -n "$v" ] && [ "$v" -ge 1 ] \
    && ok "(F) two-root run reaches other_root ($v) and conserves: $MR" \
    || no "(F) two-root run: ${MR:-no dispositions line}"

# ── (G) the predicates can fail ───────────────────────────────────────────────────────────────────────────────
echo "=== (G) mutation — every predicate above rejects its failure shape ==="
conserves '# dispositions calls=5 bound=2 self=0 external=1 unresolved=0 undefined=0 other_root=0 qualified_external=0 declined=1 file_scope=0 unaccounted=0' \
    && no "(G) the conservation predicate accepts a line that sums to 4 of 5" || ok "(G) a line that does not sum IS rejected"
conserves '# dispositions calls=5 bound=2 self=0 external=1 unresolved=0 undefined=0 other_root=0 qualified_external=0 declined=1 file_scope=0 unaccounted=1' \
    && no "(G) the conservation predicate accepts unaccounted=1" || ok "(G) unaccounted=1 IS rejected"
conserves '# dispositions calls=4 bound=2 external=1 declined=1' \
    && no "(G) the conservation predicate accepts a line with no unaccounted bucket" || ok "(G) a line without unaccounted= IS rejected"
R='<callers of="x" defs="1" count="0" root="." counts_floor="1">'
[ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
    && no "(G) the answer predicate cannot see a bare zero" || ok "(G) a bare count=\"0\" without declined_calls= IS detected"
H='<!-- files=1 symbols=2 edges=0 shown=2 est_tokens=9 ambiguous=0 unresolved=0 order=important-first -->'
[ "$( gauge "$H" declined )" = 17 ] && no "(G) the header predicate cannot see a missing gauge" || ok "(G) a header without declined= IS detected"

# ── (H) determinism, well-formedness, no degrade alert ────────────────────────────────────────────────────────
echo "=== (H) determinism + well-formedness ==="
"$BIN" . --no-cache --pin-census="$TMP/c2.tsv" >"$TMP/map2.xml" 2>/dev/null
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" && ok "(H) map + census byte-identical across two runs" \
    || no "(H) map or census differs between two runs"
if command -v xmllint >/dev/null 2>&1; then
    for f in map.xml callers.xml impact.xml callees.xml; do
        xmllint --noout "$TMP/$f" 2>/dev/null && ok "(H) xmllint clean: $f" || no "(H) xmllint rejected $f"
    done
fi
grep -q 'disposition' "$TMP/err" && no "(H) the map run raised the unaccounted-disposition alert: $( grep 'disposition' "$TMP/err" | head -1 )" \
    || ok "(H) no unaccounted-disposition alert on stderr"

[ "$fail" = 0 ] && echo "declinecheck: PASS" || echo "declinecheck: FAIL"
exit "$fail"
