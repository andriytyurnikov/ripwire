#!/usr/bin/env bash
# clsrecvcheck.sh — Rule 2c, the CLASS-NAME receiver route (docs/EVALS.md "Phase 4b").
#
#   test/clsrecvcheck.sh                    # uses build/ripwire on test/clsrecvfix
#   RIPWIRE_BIN=asan/ripwire test/clsrecvcheck.sh
#
# WHY THIS GATE EXISTS. `Cls.m(...)` — a static/classmethod call THROUGH THE CLASS NAME — reaches the
# resolver as a named-receiver call whose receiver variable has no local binding, so Rule 2 (typed local)
# cannot fire and the S6-C locality tie-break hands the win to the CALLER's own class by the scope segment.
# On astropy that was 5 of the 13 sibling-class disconfirmations left after Phase 4 (`_Interval.validate(…)`
# pinned to `ModelBoundingBox::validate`; `IERS_B.open()` pinned to `IERS_Auto::open`). Rule 2c reads the
# receiver token as the type it names and resolves the callee against that class — walking its direct bases
# level by level when the class itself defines no such method — under Rule 2b's shadow veto.
#
# THE FIXTURE (test/clsrecvfix/boxes.py): one class-name call, four controls (untyped local, a shadowing
# parameter, an inherited method through the base walk, a class that defines no such method).
#
# The three controls where the route does NOT fire used to assert the S6-C locality pin STANDS (mech=locality,
# lpin="1") — that is, that the caller's own Box::validate kept winning by the scope segment. Since 2026-09-16 an
# explicit receiver whose type no receiver rule established earns no scope-segment credit (test/localitycheck.sh
# arms 5-9: that pin was the wrong answer on 14 of 14 sampled rocksdb sites), so a non-firing route leaves the
# honest two-way split instead. The contrast the controls exist for is unchanged: the route fires ⇒ receiver-rule,
# Interval::validate ALONE; it does not ⇒ both candidates survive.
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/clsrecvfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "clsrecvcheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
MAP="$( cat "$TMP/map.xml" )"
# row 6 (2026-09-12): a scoped row prints n= then sc= (the short id); the canonical id composes as <f p=>::sc::n
row(){ _n="${1##*::}"; _r="${1#*::}"; _s="${_r%::*}"; printf '%s' "$MAP" | tr '<' '\n' | grep "n=\"$_n\" sc=\"$_s\"" | head -1; }
# the census C row for a (caller, callee): "<mech> <targets>"
crow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $8; exit}' "$TMP/c.tsv"; }

# ── (A) THE ROUTE — `Interval.validate(v)` resolves to the class the receiver NAMES ───────────────
R="$( crow 'boxes.py::Box::__setitem__' validate )"
printf '%s' "$R" | grep -q '^receiver-rule	' && ok "(A) Box::__setitem__ -> validate is receiver-rule: $R" \
    || no "(A) Box::__setitem__ -> validate is not receiver-rule: '${R:-no row}'"
printf '%s' "$R" | grep -q 'boxes.py::Interval::validate' && ! printf '%s' "$R" | grep -q 'boxes.py::Box::validate' \
    && ok "(A) the target is Interval::validate alone (not the caller's own Box::validate)" \
    || no "(A) targets are not exactly Interval::validate: '$R'"
printf '%s' "$( row 'boxes.py::Box::__setitem__' )" | grep -q 'lpin=' && no "(A) Box::__setitem__ still carries lpin= — the route did not fire" \
    || ok "(A) no lpin= on Box::__setitem__ — the pin is evidence-backed now"

# a control's census row is the honest two-way split: mech split, BOTH validate definitions, nothing else
isBothSplit(){ printf '%s' "$1" | grep -q '^split	' && printf '%s' "$1" | grep -q 'boxes.py::Interval::validate#' && printf '%s' "$1" | grep -q 'boxes.py::Box::validate#' \
    && [ "$( printf '%s' "$1" | cut -f2 | tr '|' '\n' | grep -c . )" = 2 ]; }

# ── (B) control: an UNTYPED local receiver is not a class name — the route does not fire, the split stands ────
R="$( crow 'boxes.py::Box::other' validate )"
isBothSplit "$R" && ok "(B) Box::other -> item.validate is the honest split, not a route: $R" \
    || no "(B) Box::other -> validate is not the two-way split: '${R:-no row}' (the route must key on the CLASS NAME only)"
printf '%s' "$( row 'boxes.py::Box::other' )" | grep -q 'amb="1"' && ! printf '%s' "$( row 'boxes.py::Box::other' )" | grep -q 'lpin=' \
    && ok "(B) Box::other discloses amb=\"1\" and carries no lpin=" \
    || no "(B) Box::other row does not disclose the split: $( row 'boxes.py::Box::other' )"

# ── (C) control: a PARAMETER named like the class SHADOWS it — vetoed ────────────────────────────
R="$( crow 'boxes.py::Box::shadowed' validate )"
isBothSplit "$R" && ok "(C) Box::shadowed -> Interval.validate is VETOED by the parameter Interval (split): $R" \
    || no "(C) Box::shadowed -> validate is not the two-way split: '${R:-no row}' (a local named Interval must veto the route)"

# ── (D) the DIRECT-base walk: Leaf(Interval) defines no validate — Interval::validate through the base ─
R="$( crow 'boxes.py::Box::inherited' validate )"
printf '%s' "$R" | grep -q '^receiver-rule	' && printf '%s' "$R" | grep -q 'boxes.py::Interval::validate' \
    && ok "(D) Box::inherited -> Leaf.validate lands Interval::validate through the base walk: $R" \
    || no "(D) Box::inherited -> validate: '${R:-no row}' (want receiver-rule -> Interval::validate)"

# ── (E) control: a class that defines no such method and has no bases — nothing fires ───────────
R="$( crow 'boxes.py::Box::miss' validate )"
isBothSplit "$R" && ok "(E) Box::miss -> Point.validate: nothing fires, the ladder's split stands: $R" \
    || no "(E) Box::miss -> validate is not the two-way split: '${R:-no row}' (Point defines no validate — nothing may fire)"

# ── (F) the header agrees: the three controls are the three ambiguous calls, and no locality pin is left ────────
HDR="$( printf '%s' "$MAP" | grep -o '<!-- files=[^>]*-->' | head -1 )"
printf '%s' "$HDR" | grep -q ' ambiguous=3 ' && ! printf '%s' "$HDR" | grep -q 'locality_pinned=[1-9]' \
    && ok "(F) header ambiguous=3 (other, shadowed, miss) and no locality_pinned" \
    || no "(F) header is not ambiguous=3 without a locality pin: $HDR"

# ── (G) determinism + well-formedness ─────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --no-cache >"$TMP/map2.xml" 2>/dev/null
if cmp -s "$TMP/map.xml" "$TMP/map2.xml"; then ok "(G) two runs byte-identical"; else no "(G) the map is not deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map.xml" 2>/dev/null; then ok "(G) well-formed XML"; else no "(G) xmllint rejects the map"; fi
fi

[ "$fail" = 0 ] && { echo "clsrecvcheck: OK"; exit 0; }
echo "clsrecvcheck: FAILURES ABOVE"; exit 1
