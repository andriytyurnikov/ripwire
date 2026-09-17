#!/usr/bin/env bash
# fieldusescheck.sh — the MEMBER-VARIABLE (t="field") gate: field symbols + `--uses=Owner.field` per-site
# resolution (ARISE bibliography RANK-A card A3 / CodexGraph's FIELD schema element).
#
#   test/fieldusescheck.sh                        # uses build/ripwire on test/fieldusesfix
#   RIPWIRE_BIN=asan/ripwire test/fieldusescheck.sh
#
# WHY A HAND-DERIVED GOLDEN. A per-site owner resolution looks plausible whether or not it is right — a
# name-matched union of every `count` in the tree and a resolved answer both print rows with roles and
# lines. Every expected set below is derived BY HAND from the fixture (test/fieldusesfix; line numbers are
# load-bearing there), so a wrong pin, a leaked sibling-owner site, or a claimed write that is really an
# alias miss all go RED here.
#
# THE DERIVATION (shapes.cpp; Counter and Gauge BOTH declare `count` and `label`).
#   Counter.count : 11 w (bare `count += step`, inside the owner)  · 12 w (this->count++)
#                   17 w (this->count = count — the bare rhs is the PARAMETER, shadowed, never the field)
#                   22 r (bare, inside the owner)  · 33 w (inner.count — `inner` is a Gauge FIELD of type Counter)
#                   38 w (c.count, c: Counter&)   · 41 r (&c.count — address-of is a READ, the write is NOT claimed)
#                   48 r (a.count, a: const Counter&)  · 54 r amb=2 (x.count, T& x — type unknown, both owners)
#                   NOT 28 (Gauge's own bare count) · NOT 39 (g->count) · NOT 42 (the alias write — THE KNOWN MISS)
#                   NOT 59 (the file-scope global `count` in a free function)
#                   ⇒ count=9, pinned=8, amb_sites=1, owners_of_name=2
#   Gauge.count   : 28 w (bare, inside Gauge) · 39 w (g->count, g: Gauge*) · 48 r (b.count) · 54 r amb=2  ⇒ count=4
#   Gauge.level   : 27 w + 27 r (level = level + amount) · 43 r (g->level)                                ⇒ count=3
#   Counter.step  : 11 r                       Counter.label : 40 w
#   tally.py      : Tally.total 13 w (augmented) · 17 r · 25 r amb=2 — NOT 9 (the defining assignment is the DEF, not a use)
#                   Meter.total 25 w · 25 r amb=2 (other.total — an untyped receiver is a candidate site of BOTH owners)
#                   Tally.hits 14 r (receiver of a method call) · Tally.limit: the annotated attribute is a t="var"
#                   SYMBOL (pre-round contract), so its selector takes the name-matched form, not the member form
#   shapes.go     : Box.width is NOT served (Go) — the selector must REFUSE naming the language
#
# Arms:
#   (A) side table  — THE RULE (docs/EVALS.md): a field is NEVER in the symbol universe. The flagless map carries
#                     no t="field" row and the 8e186bb symbol count; every instance field answers --uses=Owner.field
#                     with member= echoing it; a class-static constant and a Python annotated class attribute stay
#                     t="var"; a static data member and a Go struct field are not fields
#   (B) golden      — the exact (role, file:line[, amb]) set for Counter.count / Gauge.count / Gauge.level /
#                     Counter.step / Counter.label, plus the root pinned=/amb_sites=/owners_of_name= arithmetic
#   (C) known miss  — the alias write (line 42) is ABSENT from BOTH owners' answers (disclosed, never widened)
#   (D) refusal     — a bare field name shared by two owners refuses (exit 1) listing the Owner.field spellings;
#                     a bare name with ONE owner still answers; an unserved language refuses naming the language;
#                     an unknown owner refuses
#   (E) spellings   — Owner::field and the canonical id give the same rows as Owner.field
#   (F) python      — the self.x / annotated-attribute contract above
#   (G) nonlocal    — --nonlocal-state charges the GLOBAL `count` only to the free function that touches it,
#                     never to a method touching the same-named FIELD (precision)
#   (H) additive    — the flagless map carries the field rows with NO <c> edges; determinism, xmllint, and warm==cold on a
#                     cache the second run provably READ (its RIPWIRE_CACHE_STATS line: the cold run wrote the file, and the
#                     warm one reparsed nothing and reused every file — without it a failed write reparses and "matches")
#   (I) legend      — the member-form legend defines every attribute it emits and states the alias limit
#   (J) std receiver — a receiver whose declared type is written in namespace `std` names NO in-repo class, even when
#                     one shares the type's final segment (resolve.h namesStdType, the guard Rule 2 already applies).
#                     Its own fixture, built below with load-bearing line numbers (in-repo `pair` and `Twin` both
#                     declare `first`; `store::Text` and `Blob` both declare `len`; an in-repo `string` has a Twin `rep`):
#                       use.cpp:1 local std::pair · :2 std::pair parameter · :7 `::std::pair` (a global `::` is no qualifier)
#                       :8 `std::string s; s.rep.first` (the base type of a two-hop receiver)  ⇒ split, owner_candidates=2
#                       :6 the SAME function declares `std::pair v` and `pair v` — the std record TOMBSTONES the name
#                          (a skip would hand both sites to the in-repo pair)                   ⇒ both sites split
#                       :9 / :10 / :12 a std local, a std parameter and a `std::make_pair` local SHADOW Node's member `p` —
#                          a tombstoned local never falls back to the member's type             ⇒ split
#                       :13 the same rule for a NON-std tombstone: `Twin p` and `pair p` in one method of Pod, whose member
#                          `p` is a pair — the flat table cannot tell which declaration a site sees, and the member
#                          answered neither                                                     ⇒ both sites split
#                       CONTROLS that must keep pinning: :3 `pair r` · :11 Node's own member `p` · :4 `store::Text t` and
#                          :5 a `const store::Text&` parameter (a non-std qualifier still narrows, against a second `len` owner)
#                     ⇒ pair.first count=13 pinned=2 amb_sites=11 · Twin.first count=11 pinned=0 · Text.len pinned=2 · Blob.len count=0
#
# Exits non-zero on any failure. Does NOT edit test/regression.sh (listed there by hand, same commit).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fieldusesfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/fieldusesfix dir — fixture missing"; exit 2; }
echo "fieldusescheck: BIN=$BIN  FIX=$FIX"

# one "role basename:line[ owner_candidates=K]" line per <u> row (M15: the per-site owner-candidate count is owner_candidates=, never amb=), sorted — paths reduced to basenames so the
# assertions hold wherever the checkout lives.
rows(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>/dev/null | grep -o '<u [^>]*/>' \
        | sed -E 's/.*role="([a-z]*)" p="([^"]*\/)?([^"/]*)"( in_id="[^"]*")?( owner_candidates="([0-9]+)")?.*/\1 \3 \6/; s/ +$//; s/ ([0-9]+)$/ owner_candidates=\1/' | sort; }
attr(){ printf '%s' "$2" | grep -o "<uses [^>]*>" | grep -o " $1=\"[^\"]*\"" | head -1 | sed -E 's/.*="([^"]*)"/\1/'; }
# $1 a RIPWIRE_CACHE_STATS line (artifactcheck's observable): true only when that run parsed nothing and reused every file it
# indexed — a cache it READ, not a cold parse whose output merely equals the cold run's
cache_was_read(){
    reparsed="$( printf '%s' "$1" | sed -nE 's/.* reparsed=([0-9]+) .*/\1/p' )"; reused="$( printf '%s' "$1" | sed -nE 's/.* reused=([0-9]+) .*/\1/p' )"
    files="$( printf '%s' "$1" | sed -nE 's/.* files=([0-9]+) .*/\1/p' )"
    [ "$reparsed" = "0" ] && [ -n "$files" ] && [ "$files" -gt 0 ] && [ "$reused" = "$files" ]
}
expect_rows(){  # $1 selector, $2 label, $3.. expected lines
    sel="$1"; label="$2"; shift 2
    want="$( printf '%s\n' "$@" | sort )"; got="$( rows "$sel" )"
    if [ "$got" = "$want" ]; then ok "$label: --uses=$sel rows exact"; else no "$label: --uses=$sel row set mismatch"; printf '    want:\n%s\n    got:\n%s\n' "$want" "$got"; fi
}

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"

# ── (A) the side table ───────────────────────────────────────────────────────────────────────────────────
printf '%s' "$MAP" | grep -q 't="field"' && no '(A) the flagless map carries a t="field" row — fields must never enter the symbol universe' \
                                          || ok '(A) the flagless map carries no field row (side table only)'
for fld in Counter.count Counter.step Counter.label Gauge.count Gauge.level Gauge.label Gauge.inner \
           Tally.total Tally.hits Meter.total; do
    OUT="$( "$BIN" "$FIX" --uses=$fld --no-cache 2>/dev/null )"
    [ "$( attr member "$OUT" )" = "$fld" ] && [ "$( attr defs "$OUT" )" = "1" ] \
        && ok "(A) field $fld answers the member form (member=\"$fld\" defs=\"1\")" || no "(A) field $fld: member=$( attr member "$OUT" ) defs=$( attr defs "$OUT" )"
done
for name in count step label level inner hits; do   # (`total` is ALSO a free function in shapes.cpp; `limit` stays a t="var" symbol — both legitimate map rows)
if printf '%s' "$MAP" | grep -q '<s t="var"[^>]* n="limit"'; then ok '(A) annotated class attribute limit stays a t="var" map symbol (pre-round contract)'; else no '(A) annotated attribute limit is no longer a t="var" symbol'; fi
printf '%s' "$MAP" | grep -q '<s t="var"[^>]* n="limit"' || true
    printf '%s' "$MAP" | grep -q "<s t=\"[a-z]*\"[^>]* n=\"$name\"" && no "(A) field name '$name' is a map symbol" || ok "(A) '$name' is not a map symbol"
done
if printf '%s' "$MAP" | grep -q '<s t="var"[^>]* n="kMax"'; then ok '(A) class-static constant kMax stays t="var"'; else no '(A) kMax is no longer t="var"'; fi
"$BIN" "$FIX" --uses=Counter.live --no-cache >/dev/null 2>&1 && no '(A) static data member live answers as a field' || ok '(A) static data member live is not a field (refuses, disclosed)'
printf '%s' "$MAP" | grep -q '<s t="[a-z]*"[^>]* n="width"' && no '(A) Go struct field `width` became a symbol (Go is not served)' || ok '(A) Go struct field `width` is not a symbol (unserved language)'
# one field per Python (class, name) even though Tally.total/Meter.total are assigned in several methods: the
# scope-qualified spellings resolve exactly ONE field each (arm F pins their rows), and a bare `label` — two C++
# owners, no same-named function — refuses with exactly two spellings
"$BIN" "$FIX" --uses=label --no-cache >/dev/null 2>"$TMP/label.err"
if grep -q 'declared by 2 owners' "$TMP/label.err"; then ok "(A) bare label: exactly one field per owner (2 owners)"; else { no "(A) bare label owners != 2"; cat "$TMP/label.err"; }; fi

# ── (B) golden ───────────────────────────────────────────────────────────────────────────────────────────
expect_rows Counter.count "(B) Counter.count" \
    "write shapes.cpp:11" "write shapes.cpp:12" "write shapes.cpp:17" "read shapes.cpp:22" "write shapes.cpp:33" \
    "write shapes.cpp:38" "read shapes.cpp:41" "read shapes.cpp:48" "read shapes.cpp:54 owner_candidates=2"
expect_rows Gauge.count   "(B) Gauge.count"   "write shapes.cpp:28" "write shapes.cpp:39" "read shapes.cpp:48" "read shapes.cpp:54 owner_candidates=2"
expect_rows Gauge.level   "(B) Gauge.level"   "write shapes.cpp:27" "read shapes.cpp:27" "read shapes.cpp:43"
expect_rows Counter.step  "(B) Counter.step"  "read shapes.cpp:11"
expect_rows Counter.label "(B) Counter.label" "write shapes.cpp:40"
CC="$( "$BIN" "$FIX" --uses=Counter.count --no-cache 2>/dev/null )"
if [ "$( attr count "$CC" )" = "9" ]; then ok '(B) Counter.count count="9"'; else no "(B) Counter.count count=$( attr count "$CC" ) (want 9)"; fi
if [ "$( attr pinned "$CC" )" = "8" ]; then ok '(B) Counter.count pinned="8"'; else no "(B) Counter.count pinned=$( attr pinned "$CC" ) (want 8)"; fi
if [ "$( attr amb_sites "$CC" )" = "1" ]; then ok '(B) Counter.count amb_sites="1"'; else no "(B) Counter.count amb_sites=$( attr amb_sites "$CC" ) (want 1)"; fi
if [ "$( attr owners_of_name "$CC" )" = "2" ]; then ok '(B) Counter.count owners_of_name="2"'; else no "(B) Counter.count owners_of_name=$( attr owners_of_name "$CC" ) (want 2)"; fi
if [ "$( attr defs "$CC" )" = "1" ]; then ok '(B) Counter.count defs="1"'; else no "(B) Counter.count defs=$( attr defs "$CC" ) (want 1)"; fi
if printf '%s' "$CC" | grep -q 'counts_floor="1"'; then ok '(B) counts_floor="1" on the member form'; else no '(B) member form lacks counts_floor="1"'; fi

# ── (C) the known miss ───────────────────────────────────────────────────────────────────────────────────
rows Counter.count | grep -q 'shapes.cpp:42' && no "(C) alias write (line 42) CLAIMED for Counter.count — no alias analysis exists, this is a false row" \
                                            || ok "(C) alias write (line 42) is a disclosed miss on Counter.count"
rows Gauge.count   | grep -q 'shapes.cpp:42' && no "(C) alias write (line 42) CLAIMED for Gauge.count" || ok "(C) alias write (line 42) absent from Gauge.count too"
rows Counter.count | grep -q 'shapes.cpp:59' && no "(C) the free-function global write (line 59) leaked into Counter.count" || ok "(C) global count write (line 59) is not a field use-site"

# ── (D) refusals ─────────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --uses=count --no-cache >"$TMP/bare.out" 2>"$TMP/bare.err"; rc=$?
if [ "$rc" = "1" ]; then ok "(D) bare --uses=count (two owners) refuses, exit 1"; else no "(D) bare --uses=count exit $rc (want 1)"; fi
if [ ! -s "$TMP/bare.out" ]; then ok "(D) the refusal writes nothing to stdout"; else no "(D) refusal wrote stdout bytes"; fi
grep -q 'Counter.count' "$TMP/bare.err" && grep -q 'Gauge.count' "$TMP/bare.err" \
    && ok "(D) refusal lists the Owner.field spellings (Counter.count, Gauge.count)" || { no "(D) refusal does not list both spellings"; cat "$TMP/bare.err"; }
LV="$( "$BIN" "$FIX" --uses=level --no-cache 2>/dev/null )"; rc=$?
[ "$rc" = "0" ] && [ "$( attr count "$LV" )" = "3" ] && ok "(D) bare --uses=level (ONE owner) answers with the member form (count=3)" \
    || no "(D) bare --uses=level rc=$rc count=$( attr count "$LV" ) (want 0 / 3)"
"$BIN" "$FIX" --uses=Box.width --no-cache >"$TMP/go.out" 2>"$TMP/go.err"; rc=$?
[ "$rc" = "1" ] && grep -q 'lang=go' "$TMP/go.err" && ok "(D) --uses=Box.width refuses naming the language (lang=go)" \
    || { no "(D) --uses=Box.width rc=$rc, stderr does not name lang=go"; cat "$TMP/go.err"; }
"$BIN" "$FIX" --uses=Nope.count --no-cache >/dev/null 2>"$TMP/nope.err"; rc=$?
if [ "$rc" = "1" ]; then ok "(D) --uses=Nope.count (unknown owner) refuses, exit 1"; else no "(D) --uses=Nope.count exit $rc (want 1)"; fi

# ── (E) spellings agree ──────────────────────────────────────────────────────────────────────────────────
if [ "$( rows Counter::count )" = "$( rows Counter.count )" ]; then ok "(E) Counter::count rows == Counter.count rows"; else no "(E) Counter::count and Counter.count disagree"; fi
CANON="shapes.h::Counter::count"   # the path::Owner::field spelling (a path TAIL resolves, as everywhere)
if [ "$( rows "$CANON" )" = "$( rows Counter.count )" ]; then ok "(E) canonical id rows == Counter.count rows"; else no "(E) canonical id '$CANON' disagrees with Counter.count"; fi

# ── (F) python ───────────────────────────────────────────────────────────────────────────────────────────
expect_rows Tally.total "(F) Tally.total" "write tally.py:13" "read tally.py:17" "read tally.py:25 owner_candidates=2"
expect_rows Meter.total "(F) Meter.total" "write tally.py:25" "read tally.py:25 owner_candidates=2"
expect_rows Tally.hits  "(F) Tally.hits"  "read tally.py:14"
rows Tally.total | grep -q 'tally.py:9' && no "(F) the defining assignment (line 9) counted as a use of Tally.total" || ok "(F) defining assignment (line 9) is a def, not a use"
LIM="$( "$BIN" "$FIX" --uses=Tally::limit --no-cache 2>/dev/null )"; rc=$?   # the SYMBOL spelling — Owner.attr is the member form's, and this is not a member
[ "$rc" = "0" ] && [ "$( attr defs "$LIM" )" = "1" ] && [ -z "$( attr member "$LIM" )" ] \
    && ok "(F) Tally::limit: the annotated attribute answers as the t=\"var\" symbol (scope tier, name-matched form, no member=)" \
    || no "(F) Tally::limit rc=$rc defs=$( attr defs "$LIM" ) member=$( attr member "$LIM" )"

# ── (G) nonlocal-state precision ─────────────────────────────────────────────────────────────────────────
NLS="$( "$BIN" "$FIX" --nonlocal-state --no-cache 2>/dev/null )"
NROWS="$( printf '%s' "$NLS" | grep -o '<fn [^>]*n="[A-Za-z_]*"' | wc -l | tr -d ' ' )"
if printf '%s' "$NLS" | grep -q '<fn [^>]*n="reset_global"'; then ok "(G) the free function writing the GLOBAL count is a nonlocal-state row"; else no "(G) reset_global row missing"; fi
for fn in bump set peek fill reset total relay; do
    printf '%s' "$NLS" | grep -q "<fn [^>]*n=\"$fn\"" && no "(G) $fn touches only the FIELD count/level, yet is charged to the global cell" || ok "(G) $fn (field-only) is not charged to the global"
done
if [ "$NROWS" = "1" ]; then ok "(G) exactly one nonlocal-state row (the global's one writer)"; else no "(G) nonlocal-state rows = $NROWS (want 1)"; fi
if printf '%s' "$NLS" | grep -q 'field'; then ok "(G) the nonlocal-state legend discloses the instance-field exclusion"; else no "(G) nonlocal-state legend does not mention fields"; fi

# ── (H) additive / determinism / well-formedness ─────────────────────────────────────────────────────────
if printf '%s' "$MAP" | grep -q 'symbols=27 '; then ok "(H) flagless map symbols=27 — the 8e186bb binary's count on this fixture (fields add nothing)"; else no "(H) flagless map symbols= moved: $( printf '%s' "$MAP" | grep -o 'symbols=[0-9]*' | head -1 )"; fi
"$BIN" "$FIX" --uses=Counter.count --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIX" --uses=Counter.count --no-cache >"$TMP/b" 2>/dev/null
if cmp -s "$TMP/a" "$TMP/b"; then ok "(H) determinism: two --no-cache runs byte-identical"; else no "(H) --uses=Counter.count is not deterministic"; fi
"$BIN" "$FIX" --uses=Counter.count --cache="$TMP/c.bin" >/dev/null 2>&1
RIPWIRE_CACHE_STATS=1 "$BIN" "$FIX" --uses=Counter.count --cache="$TMP/c.bin" >"$TMP/w" 2>"$TMP/w.err"
HSTATS="$( grep 'cache-stats' "$TMP/w.err" )"
if [ -s "$TMP/c.bin" ] && cache_was_read "$HSTATS"; then ok "(H) the warm run READ the cache the cold run wrote (${HSTATS#ripwire: })"; else no "(H) the warm run did not read a written cache: ${HSTATS:-<no cache-stats line>}"; fi
if cmp -s "$TMP/a" "$TMP/w"; then ok "(H) warm cache == cold (field refs round-trip the cache)"; else no "(H) warm --uses=Counter.count differs from cold"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/a" 2>/dev/null; then ok "(H) --uses=Counter.count is well-formed XML"; else no "(H) --uses=Counter.count is not well-formed XML"; fi
    if printf '%s' "$MAP" | xmllint --noout - 2>/dev/null; then ok "(H) the map with field rows is well-formed XML"; else no "(H) the map is not well-formed XML"; fi
fi

# ── (I) legend ───────────────────────────────────────────────────────────────────────────────────────────
LEG="$( printf '%s' "$CC" | sed 's/-->.*//' )"
for a in owner_candidates pinned amb_sites owners_of_name; do
    if printf '%s' "$LEG" | grep -q "$a="; then ok "(I) legend defines $a="; else no "(I) legend does not define $a="; fi
done
if printf '%s' "$LEG" | grep -qi 'alias'; then ok "(I) legend states the no-alias-analysis limit"; else no "(I) legend does not state the alias limit"; fi
if printf '%s' "$LEG" | grep -qi 'macro'; then ok "(I) legend states the macro limit"; else no "(I) legend does not state the macro limit"; fi

# ── (J) a receiver typed in namespace std ────────────────────────────────────────────────────────────────
STD="$TMP/stdrecv"
mkdir -p "$STD/lib" "$STD/app"
cat > "$STD/lib/pair.h" <<'EOF'
struct pair { int first; int second; };
struct Twin { int first; };
namespace store { struct Text { int len; }; }
struct Blob { int len; };
struct string { Twin rep; };
EOF
cat > "$STD/app/use.cpp" <<'EOF'
int local() { std::pair<int, int> p; return p.first; }
int param( const std::pair<int, int>& q ) { return q.first; }
int mine() { pair r; return r.first; }
int text() { store::Text t; return t.len; }
int qparam( const store::Text& u ) { return u.len; }
int both() { { std::pair<int, int> v; if( v.first ) { return 1; } } pair v; return v.first; }
int global() { ::std::pair<int, int> g; return g.first; }
int chain() { std::string s; return s.rep.first; }
struct Node { pair p; int get() { std::pair<int, int> p; return p.first; }
    int peek( const std::pair<int, int>& p ) { return p.first; }
    int own() { return p.first; }
    int made() { auto p = std::make_pair( 1, 2 ); return p.first; } };
struct Pod { pair p; int two() { { Twin p; if( p.first ) { return 1; } } pair p; return p.first; } };
EOF
# presence guard: the fixture spells every shape the rows below derive from (a vanished line would make a split vacuous)
if [ "$( grep -c 'std::pair<int, int>' "$STD/app/use.cpp" )" = "6" ] && grep -q 'store::Text t;' "$STD/app/use.cpp" && grep -q 'std::string s;' "$STD/app/use.cpp" \
   && grep -q '{ Twin p;' "$STD/app/use.cpp"; then
    ok "(J) fixture spells the six std::pair declarations, the store::Text control, the std::string two-hop receiver and Pod's two p declarations"
else
    no "(J) fixture lost a shape — the rows below would not measure the std guard"
fi
srows(){ "$BIN" "$STD" --uses="$1" --no-cache 2>/dev/null | grep -o '<u [^>]*/>' \
         | sed -E 's/.*role="([a-z]*)" p="([^"]*\/)?([^"/]*)"( in_id="[^"]*")?( owner_candidates="([0-9]+)")?.*/\1 \3 \6/; s/ +$//; s/ ([0-9]+)$/ owner_candidates=\1/' | sort; }
expect_srows(){
    sel="$1"; label="$2"; shift 2
    want="$( printf '%s\n' "$@" | sort )"; got="$( srows "$sel" )"
    if [ "$got" = "$want" ]; then ok "$label: --uses=$sel rows exact"; else no "$label: --uses=$sel row set mismatch"; printf '    want:\n%s\n    got:\n%s\n' "$want" "$got"; fi
}
expect_srows pair.first "(J) pair.first" \
    "read use.cpp:1 owner_candidates=2" "read use.cpp:2 owner_candidates=2" "read use.cpp:3" \
    "read use.cpp:6 owner_candidates=2" "read use.cpp:6 owner_candidates=2" "read use.cpp:7 owner_candidates=2" "read use.cpp:8 owner_candidates=2" \
    "read use.cpp:9 owner_candidates=2" "read use.cpp:10 owner_candidates=2" "read use.cpp:11" "read use.cpp:12 owner_candidates=2" \
    "read use.cpp:13 owner_candidates=2" "read use.cpp:13 owner_candidates=2"
expect_srows Twin.first "(J) Twin.first" \
    "read use.cpp:1 owner_candidates=2" "read use.cpp:2 owner_candidates=2" \
    "read use.cpp:6 owner_candidates=2" "read use.cpp:6 owner_candidates=2" "read use.cpp:7 owner_candidates=2" "read use.cpp:8 owner_candidates=2" \
    "read use.cpp:9 owner_candidates=2" "read use.cpp:10 owner_candidates=2" "read use.cpp:12 owner_candidates=2" \
    "read use.cpp:13 owner_candidates=2" "read use.cpp:13 owner_candidates=2"
expect_srows Text.len "(J) Text.len (a non-std qualifier keeps pinning)" "read use.cpp:4" "read use.cpp:5"
expect_srows Blob.len "(J) Blob.len (the second len owner the control pins against)"
PF="$( "$BIN" "$STD" --uses=pair.first --no-cache 2>/dev/null )"
TL="$( "$BIN" "$STD" --uses=Text.len --no-cache 2>/dev/null )"
[ "$( attr count "$PF" )" = "13" ] && [ "$( attr pinned "$PF" )" = "2" ] && [ "$( attr amb_sites "$PF" )" = "11" ] && [ "$( attr owners_of_name "$PF" )" = "2" ] \
    && ok '(J) pair.first count="13" pinned="2" amb_sites="11" owners_of_name="2"' \
    || no "(J) pair.first count=$( attr count "$PF" ) pinned=$( attr pinned "$PF" ) amb_sites=$( attr amb_sites "$PF" ) owners_of_name=$( attr owners_of_name "$PF" ) (want 13/2/11/2)"
[ "$( attr pinned "$TL" )" = "2" ] && [ "$( attr owners_of_name "$TL" )" = "2" ] \
    && ok '(J) Text.len pinned="2" against owners_of_name="2" (the control has a contrast)' \
    || no "(J) Text.len pinned=$( attr pinned "$TL" ) owners_of_name=$( attr owners_of_name "$TL" ) (want 2/2)"
"$BIN" "$STD" --uses=pair.first --cache="$TMP/std.bin" >/dev/null 2>&1
RIPWIRE_CACHE_STATS=1 "$BIN" "$STD" --uses=pair.first --cache="$TMP/std.bin" >"$TMP/stdwarm" 2>"$TMP/stdwarm.err"
JSTATS="$( grep 'cache-stats' "$TMP/stdwarm.err" )"
if [ -s "$TMP/std.bin" ] && cache_was_read "$JSTATS"; then ok "(J) the warm run READ the cache the cold run wrote (${JSTATS#ripwire: })"; else no "(J) the warm run did not read a written cache: ${JSTATS:-<no cache-stats line>}"; fi
if [ -n "$PF" ] && [ "$( cat "$TMP/stdwarm" )" = "$PF" ]; then ok "(J) warm cache == cold (the qualified type text round-trips the cache)"; else no "(J) warm --uses=pair.first differs from cold"; fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
