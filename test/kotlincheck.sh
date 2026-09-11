#!/usr/bin/env bash
# kotlincheck.sh — the Kotlin ingest coverage gate (grammar + tags.scm + the Kotlin<->Java JVM bridge).
#
# Modeled on luacheck.sh/elixircheck.sh: a small fixture, assertions pinned to what the binary
# ACTUALLY does (every number below was read off a real run before it was written down), plus
# mutation arms so the edge assertions are non-tautological.
#
# ── WHY THIS GATE IS NOT VACUOUS ──────────────────────────────────────────────────────────────────
# Against a pre-Kotlin binary, every .kt file in this fixture leaves the index as
# `why="unsupported-ext"` — the map reports files=1 (the lone .java) and every Kotlin-side arm fails.
# That trivial red is not what this gate is for. The two things worth pinning by exact number are the
# things a naive port gets wrong silently, not loudly: (a) whether a class/object/companion-object
# member gets its ENCLOSING SCOPE in its canonical id= (kotlinEnclosingScopeOf, ingest_names.h) — a
# scope-less id is exactly what makes a same-name collision across classes invisible — and (b) the
# JVM bridge itself (graph.h langCompatible), in BOTH directions, plus the collision it cannot narrow:
# a same-name Kotlin/Java pair with no other evidence must surface as ambiguous= with BOTH candidates
# getting the edge (§5) — never silently resolve to one side, which is exactly what a definition read
# as bodyless does (graph.h's decl/def collapse deletes it as a forward declaration), so §5 is really
# guarding ingest_sidecap.h's positional body fallback.
#
# ── FIXTURE (test/kotlinfix/) ─────────────────────────────────────────────────────────────────────
#   Util.kt        fun square(n: Int): Int                  -- top-level function, cross-file callee
#                   class Formatter { fun format(n: Int) }    -- a plain member function
#                   object Extra { fun helper(n: Int) }       -- one half of the collision pair
#                   enum class Mode { ON, OFF }               -- the enum_class_body collision pair (§8)
#                   interface Labeled { fun label(): String } -- captureBases DIRECT shape (§9, bare, no call)
#                   open class Shape { open fun area(): Int }
#                   class Square(...) : Shape(), Labeled       -- captureBases WRAPPED shape (§9, Shape()) + DIRECT (Labeled)
#                   fun describe(name, age = 0, vararg tags)   -- countParams fixture (§10): 3 real params, not 5
#   Greeter.kt      class Greeter(name: String) {
#                     companion object { fun of(name): Greeter } -- companion-object factory function
#                     fun greet(): String -> square(2)          -- member function, CROSS-FILE call
#                   }
#                   fun Int.doubled(): Int                    -- extension function
#                   fun useJavaHelper(): Int -> JavaBridge.helper(5)  -- Kotlin -> Java, qualified
#                   fun ambiguousCall(): Int -> helper(5)      -- Kotlin -> ???, BARE (the collision probe)
#                   fun runAll(): Int -> of, greet, doubled, useJavaHelper, ambiguousCall
#   JavaBridge.java class JavaBridge {
#                     static int helper(int n)                 -- the OTHER half of the collision pair
#                     int callGreeter() -> Greeter.of(...), .greet()  -- Java -> Kotlin, BOTH bridge uses
#                   }
#                   class Mode { void run() }                 -- the OTHER half of the §8 collision pair
#
# ── FINDINGS from running `ripwire test/kotlinfix` and reading the raw output ───────────────────────
#   - files=3 symbols=29 edges=14 ambiguous=2 unresolved=0, clean stderr (no ABI/degrade line).
#   - id="Greeter.kt::Greeter::of" / id="Greeter.kt::Greeter::greet" / id="Util.kt::Formatter::format"
#     / id="Util.kt::Extra::helper" — every class/object/companion-object member carries its enclosing
#     scope; a top-level function (square, doubled, useJavaHelper, runAll, ambiguousCall) carries none
#     (scope-less, by contract — id= is absent, not empty, at file scope).
#   - JVM BRIDGE, Java -> Kotlin (the clean direction): --callers=Greeter.kt:of and
#     --callers=Greeter.kt:greet BOTH report count=2 — runAll (same-language) AND
#     JavaBridge.java's callGreeter (cross-language), unambiguous, graph_ambiguous=0 on THIS pair
#     (helper's collision is what carries the file's ambiguous=2 total).
#   - JVM BRIDGE, Kotlin -> Java, qualified (useJavaHelper -> JavaBridge.helper(5)): resolves cleanly
#     to JavaBridge's helper specifically... but see the collision arm below — the qualification is
#     NOT what disambiguates it (Kotlin navigation-expression receivers do not narrow candidates yet,
#     a separate, still-open gap); it resolves correctly here only because the SAME collision the bare
#     call hits also admits both candidates, and both genuinely get the edge (§5).
#   - THE COLLISION, FIXED (was silently wrong; now honestly ambiguous — see graph.h's langCompatible
#     comment for the full history): ambiguousCall's BARE `helper(5)` — no receiver, no import
#     evidence — has TWO real candidates (Util.kt's Extra.helper and JavaBridge.java's helper). Both
#     useJavaHelper's qualified call AND ambiguousCall's bare call now correctly show BOTH candidates
#     as callers (count=2 each) and graph_ambiguous="2" — the tool used to silently pick JavaBridge's
#     helper for both with zero signal in the header; the root cause was defBodyNodeOf reading every
#     Kotlin definition as bodyless (positional function_body/class_body, not a body: field) and
#     graph.h's decl/def collapse deleting the "bodyless" Kotlin candidate whenever a same-named Java
#     definition existed. Fixed by extending ingest_sidecap.h's positional body fallback (previously
#     ObjC-only) to Kotlin (kParserVer 84).
#   - --deps: one Include record (`com.example.util.square`, Greeter.kt's import) — Kotlin's
#     IncludeLang is Other/deferred (resolve.h, same posture as Java), so it is captured for
#     disclosure but never file-resolved; dep_langs= names "kt" in the capable set regardless
#     (dependencyCapable() is about the language, not about how far the resolver currently reaches).
#   - --skipped: <lang n="kt" files="2" symbols="22"/> and <lang n="java" files="1" symbols="7"/>.
#   - CAPTUREBASES DELEGATION_SPECIFIER (§9, a review-round coverage gap, not part of the original
#     port): no prior fixture had a Kotlin class with a base clause at all, so captureBases's Kotlin
#     arm (src/ingest_relations.h) — both the WRAPPED shape (`Shape()`, delegation_specifier ->
#     constructor_invocation -> user_type) and the DIRECT shape (`Labeled`, bare interface, no call,
#     user_type right under delegation_specifier) — ran with zero test coverage. `class Square(...) :
#     Shape(), Labeled` exercises both in one header: --uses=Shape shows role="call" (the constructor
#     delegation is ALSO a real call, via tags.scm's constructor_invocation capture) AND role="extends"
#     at the same site; --uses=Labeled shows role="extends" only (no call — Labeled is never invoked).
#   - COUNTPARAMS (§10, a review-round coverage gap): no prior Kotlin fixture had a function with more
#     than one parameter, so the fix for function_value_parameters counting `parameter` children ONLY
#     (a parameter's own `vararg` modifier and default-value expression are SIBLINGS in this grammar,
#     not nested — the generic "every named child" rule misreads 3 real params as 5) had nothing
#     pinning it. `describe(name: String, age: Int = 0, vararg tags: String)` --metrics reports
#     params="3", not 5.
#   - ENUM CLASS BODY (§8, a second-opinion review finding, not part of the original port): Util.kt's
#     `enum class Mode` and JavaBridge.java's package-private `class Mode` are unrelated same-name
#     types. `class_declaration`'s enum-class form nests its members under `enum_class_body`, a
#     DIFFERENT positional child than a plain class's `class_body` — the ObjC/Kotlin body-fallback
#     (ingest_sidecap.h) originally recognized only `class_body`, so the Kotlin enum read as bodyless
#     and graph.h's decl/def collapse deleted it whenever the Java Mode existed, the same silent-drop
#     §5 exists to catch for `helper`. Fixed by adding `enum_class_body` to that fallback (kParserVer 85).
#
# Usage:
#   bash test/kotlincheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/kotlincheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/kotlincheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/kotlinfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "kotlincheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 0. PRESENCE: the fixture really spells every shape the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
presence(){ grep -qF -- "$2" "$FIX/$1" && ok "fixture $1 spells: $3" || no "fixture $1 no longer spells: $3"; }
presence Util.kt        'fun square(n: Int)'          'a top-level function, cross-file callee'
presence Util.kt        'class Formatter'             'a plain class with a member function'
presence Util.kt        'object Extra'                'the Kotlin half of the collision pair'
presence Greeter.kt     'companion object'             'a companion-object factory function'
presence Greeter.kt     'fun Int.doubled()'            'an extension function'
presence Greeter.kt     'JavaBridge.helper(5)'         'a qualified Kotlin -> Java call'
presence Greeter.kt     '= helper(5)'                  'the BARE Kotlin -> ??? call (the collision probe; `= ` keeps this from matching the qualified call above)'
presence JavaBridge.java 'static int helper(int n)'    'the Java half of the collision pair'
presence JavaBridge.java 'Greeter.of('                 'a Java -> Kotlin companion-object call'
presence JavaBridge.java 'g.greet()'                   'a Java -> Kotlin member call'

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on the Kotlin fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. STRUCTURE: 3 files / 29 symbols / 14 edges, the collision correctly ambiguous ==="
# ═══════════════════════════════════════════════════════════════════════════
# edges=14/ambiguous=2, not 11/0: the two collision call sites (useJavaHelper, ambiguousCall) each
# admit BOTH same-name candidates as real edges (RefRole::Call is deliberately un-narrowed — graph.h's
# own doctrine), which is what "correctly ambiguous" costs in edge count. See §5. symbols=29, not 15:
# §8's enum_class_body collision pair (Mode/Mode) adds 3 definitions but no call edges (neither is
# ever constructed); §9's Labeled/Shape/Square/describe fixture adds 8 more definitions and Square's
# `Shape()` delegation adds the one extra edge (edges=14, not 13) — a constructor-delegation call is
# also a real call (tags.scm's constructor_invocation capture); §11's TRULY-bodyless Taggable/Taggable
# collision pair adds the final 3 definitions (Kotlin's bodyless interface, Java's class, its one
# method) and, like §8/§9's Labeled, no call edges (neither is ever constructed or invoked).
grep -q 'files=3 symbols=29' "$MAP_OUT" && ok "header: files=3 symbols=29" || no "header: expected files=3 symbols=29: $( grep -o 'files=[0-9]* symbols=[0-9]*' "$MAP_OUT" )"
grep -q 'edges=14' "$MAP_OUT" && ok "header: edges=14" || no "header: expected edges=14: $( grep -o 'edges=[0-9]*' "$MAP_OUT" )"
grep -q 'ambiguous=2' "$MAP_OUT" && ok "header: ambiguous=2" || no "header: expected ambiguous=2: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" )"
grep -q 'unresolved=0' "$MAP_OUT" && ok "header: unresolved=0" || no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" )"

grep -q 'id="Greeter.kt::Greeter::of"' "$MAP_OUT" && ok 'scope: companion-object factory carries id=Greeter.kt::Greeter::of' \
    || no "scope: Greeter::of id missing — kotlinEnclosingScopeOf regressed: $( grep -o 'n="of"[^>]*' "$MAP_OUT" )"
grep -q 'id="Greeter.kt::Greeter::greet"' "$MAP_OUT" && ok 'scope: member function carries id=Greeter.kt::Greeter::greet' \
    || no "scope: Greeter::greet id missing: $( grep -o 'n="greet"[^>]*' "$MAP_OUT" )"
grep -q 'id="Util.kt::Formatter::format"' "$MAP_OUT" && ok 'scope: plain class member carries id=Util.kt::Formatter::format' \
    || no "scope: Formatter::format id missing: $( grep -o 'n="format"[^>]*' "$MAP_OUT" )"
grep -q 'id="Util.kt::Extra::helper"' "$MAP_OUT" && ok 'scope: object member carries id=Util.kt::Extra::helper' \
    || no "scope: Extra::helper id missing: $( grep -o 'n="helper"[^>]*' "$MAP_OUT" )"
# Negative: a TOP-LEVEL function must NOT pick up a spurious scope (kotlinEnclosingScopeOf's own
# self-exclusion / walk-through-anonymous-companion logic must not over-fire).
echo "$( grep -o '<s t="fn" n="doubled"[^>]*>' "$MAP_OUT" )" | grep -q 'id=' \
    && no "scope: top-level extension function doubled() got a spurious id= (should be scope-less)" \
    || ok "scope: top-level extension function doubled() is correctly scope-less"

CR="$( "$BIN" "$FIX" --callers=square --no-cache 2>/dev/null )"
echo "$CR" | grep -q 'n="greet"' && ok "--callers=square lists greet (Greeter.kt -> Util.kt, cross-file)" \
    || no "--callers=square did not list greet: $CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. JVM BRIDGE, Java -> Kotlin (graph.h langCompatible) ==="
# ═══════════════════════════════════════════════════════════════════════════
# callGreeter() is the ONLY cross-language caller each has; runAll() is the same-language caller.
# count=2 (not 1) on each is the proof both edges are live, not just one.
OF_CALLERS="$( "$BIN" "$FIX" --callers="Greeter.kt:of" --no-cache 2>/dev/null )"
echo "$OF_CALLERS" | grep -q 'count="2"' && ok "--callers=Greeter.kt:of -> count=2 (runAll + Java's callGreeter)" \
    || no "--callers=Greeter.kt:of: expected count=2: $( echo "$OF_CALLERS" | grep -o '<callers [^>]*>' )"
# defs="1", not graph_ambiguous= (that attribute is the WHOLE GRAPH's gauge, not this symbol's own —
# it will read "2" here too once §5's collision exists elsewhere in the same file, correctly). `of`
# has exactly one definition — no same-name collision on THIS symbol, unlike helper's.
echo "$OF_CALLERS" | grep -q 'defs="1"' && ok "--callers=Greeter.kt:of -> defs=1 (no same-name collision on this symbol)" \
    || no "--callers=Greeter.kt:of: expected defs=1: $( echo "$OF_CALLERS" | grep -o '<callers [^>]*>' )"

GREET_CALLERS="$( "$BIN" "$FIX" --callers="Greeter.kt:greet" --no-cache 2>/dev/null )"
echo "$GREET_CALLERS" | grep -q 'count="2"' && ok "--callers=Greeter.kt:greet -> count=2 (runAll + Java's callGreeter)" \
    || no "--callers=Greeter.kt:greet: expected count=2: $( echo "$GREET_CALLERS" | grep -o '<callers [^>]*>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. JVM BRIDGE, Kotlin -> Java, QUALIFIED (useJavaHelper -> JavaBridge.helper) ==="
# ═══════════════════════════════════════════════════════════════════════════
HELPER_CALLERS="$( "$BIN" "$FIX" --callers="JavaBridge.java:helper" --no-cache 2>/dev/null )"
echo "$HELPER_CALLERS" | grep -q 'n="useJavaHelper"' && ok "--callers=JavaBridge.java:helper lists useJavaHelper (Kotlin -> Java, qualified)" \
    || no "--callers=JavaBridge.java:helper did not list useJavaHelper: $HELPER_CALLERS"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. IMPORTS + CENSUS ==="
# ═══════════════════════════════════════════════════════════════════════════
DEPS="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
echo "$DEPS" | grep -q '<inc t="com.example.util.square"/>' && ok '--deps: Greeter.kt import captured as t="com.example.util.square" (whole dotted specifier)' \
    || no "--deps: import specifier not captured cleanly: $( echo "$DEPS" | grep -oE '<inc t="[^"]*"' )"
echo "$DEPS" | grep -qE 'dep_langs="[^"]*,kt[,"]' && ok '--deps health: dep_langs= names kt in the disclosed capable set' \
    || no "--deps health: dep_langs= does not list kt: $( echo "$DEPS" | grep -o 'dep_langs="[^"]*"' )"
# NOT ',kt"' alone — that only matches when kt is the LAST token, which is only true because Kotlin is
# currently the last-appended Lang (model.h). This diff's own eliximportcheck.sh fix (`,ex[,"]`) exists
# for the exact same reason: the next language appended after Kotlin would otherwise make THIS assertion
# fail for a reason unrelated to what it tests.

SK="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
echo "$SK" | grep -q 'unsupported_ext="0"' && ok '--skipped: unsupported_ext=0 (no .kt/.java falls out of the index)' \
    || no "--skipped: expected unsupported_ext=0: $( echo "$SK" | grep -o 'unsupported_ext="[0-9]*"' )"
echo "$SK" | grep -q '<lang n="kt" files="2" symbols="22"/>' && ok '--skipped: <lang n="kt" files="2" symbols="22"/> census row' \
    || no "--skipped: kotlin census row missing/wrong: $( echo "$SK" | grep -o '<lang n="kt"[^/]*/>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. THE COLLISION: a bare same-name Kotlin/Java call is now HONESTLY ambiguous ==="
# ═══════════════════════════════════════════════════════════════════════════
# Both the bare call (ambiguousCall) and the qualified one (useJavaHelper) must show BOTH same-name
# candidates as real edges. A definition read as bodyless is deleted from the candidate pool as a
# forward declaration before ambiguous= is consulted (graph.h's decl/def collapse), so a regression in
# ingest_sidecap.h's positional body fallback shows up here as one side silently winning.
USES_HELPER="$( "$BIN" "$FIX" --uses=helper --no-cache 2>/dev/null )"
echo "$USES_HELPER" | grep -q 'defs="2"' && ok '--uses=helper: defs="2" — BOTH candidates are visible (Extra.helper, JavaBridge.helper)' \
    || no "--uses=helper: expected defs=2: $( echo "$USES_HELPER" | grep -o '<uses [^>]*>' )"
echo "$USES_HELPER" | grep -q 'graph_ambiguous="2"' \
    && ok '--uses=helper: graph_ambiguous="2" — the collision correctly surfaces (both call sites, both candidates)' \
    || no "--uses=helper: graph_ambiguous is no longer 2 — a regression to the old silent-pick, or a narrowing change: $( echo "$USES_HELPER" | grep -o '<uses [^>]*>' )"
# Both candidates must get the edge from BOTH call sites — a regression to the old body-detection bug
# would drop Extra.helper from one or both.
# $HELPER_CALLERS is §3's run of the same query — reused, not re-run.
UTIL_HELPER_CALLERS="$( "$BIN" "$FIX" --callers="Util.kt:helper" --no-cache 2>/dev/null )"
echo "$HELPER_CALLERS" | grep -q 'count="2"' && echo "$UTIL_HELPER_CALLERS" | grep -q 'count="2"' \
    && ok 'both helper() definitions get BOTH call sites as callers (count=2 each) — the collision is real, not one-sided' \
    || no "collision asymmetric — JavaBridge=$( echo "$HELPER_CALLERS" | grep -o 'count="[0-9]*"' ) Util=$( echo "$UTIL_HELPER_CALLERS" | grep -o 'count="[0-9]*"' ) (the positional body fallback may have regressed)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 8. ENUM CLASS BODY: enum_class_body is a DIFFERENT positional child than class_body ==="
# ═══════════════════════════════════════════════════════════════════════════
# Util.kt's `enum class Mode` and JavaBridge.java's package-private `class Mode` are the same shape
# of collision §5 pins for `helper` — a same-name pair with no other evidence, both must stay real
# candidates. The difference is WHERE the bug lived: class_declaration's enum-class form nests its
# members under enum_class_body, not class_body, so the ObjC/Kotlin positional body-fallback missed
# it until a second-opinion review caught the gap (kParserVer 85). Verified via a raw parse of
# `enum class Status { READY, DONE }`: (class_declaration (type_identifier) (enum_class_body ...)).
USES_MODE="$( "$BIN" "$FIX" --uses=Mode --no-cache 2>/dev/null )"
echo "$USES_MODE" | grep -q 'defs="2"' && ok '--uses=Mode: defs="2" — BOTH candidates are visible (Kotlin enum class, Java class)' \
    || no "--uses=Mode: expected defs=2: $( echo "$USES_MODE" | grep -o '<uses [^>]*>' )"
echo "$USES_MODE" | grep -q 'graph_ambiguous="2"' \
    && ok '--uses=Mode: graph_ambiguous="2" — the enum class was not silently dropped as bodyless' \
    || no "--uses=Mode: graph_ambiguous is no longer 2: $( echo "$USES_MODE" | grep -o '<uses [^>]*>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 9. CAPTUREBASES: Kotlin delegation_specifier, both shapes (WRAPPED call + DIRECT bare) ==="
# ═══════════════════════════════════════════════════════════════════════════
# No prior fixture had a Kotlin class with a base clause at all, so captureBases's Kotlin arm
# (src/ingest_relations.h) ran with zero test coverage — a copy-paste slip in its isClause/
# isBaseTypeNode tables, or a grammar-shape change on a future tree-sitter-kotlin bump, could have
# silently zeroed out every Kotlin inherit edge with nothing here to notice. `class Square(...) :
# Shape(), Labeled` exercises both shapes in one header: `Shape()` is WRAPPED (delegation_specifier ->
# constructor_invocation -> user_type — and a real CALL too, via tags.scm's own constructor_invocation
# capture, so it carries BOTH role="call" and role="extends" at the same site); `Labeled` is DIRECT
# (bare interface, no call — user_type sits right under delegation_specifier, so it is role="extends"
# only).
#     Assertions grep only the <u .../> rows (not the whole output) — the verb's own legend prose
#     ITSELF contains the literal substrings 'role="call"'/'role="extends"' as worked examples, so a
#     naive whole-output grep would pass vacuously (matching the legend, not the data).
USES_SHAPE="$( "$BIN" "$FIX" --uses=Shape --no-cache 2>/dev/null | grep -o '<u role="[a-z]*"[^/]*/>' )"
echo "$USES_SHAPE" | grep -q 'role="call"' && echo "$USES_SHAPE" | grep -q 'role="extends"' && echo "$USES_SHAPE" | grep -q 'in_id="Square"' \
    && ok '--uses=Shape: Square gets BOTH role="call" and role="extends" at the Shape() delegation site' \
    || no "--uses=Shape: expected both call and extends roles for Square: $USES_SHAPE"

USES_LABELED="$( "$BIN" "$FIX" --uses=Labeled --no-cache 2>/dev/null | grep -o '<u role="[a-z]*"[^/]*/>' )"
echo "$USES_LABELED" | grep -q 'role="extends"' && echo "$USES_LABELED" | grep -q 'in_id="Square"' \
    && ok '--uses=Labeled: Square gets role="extends" (DIRECT — bare interface, no call)' \
    || no "--uses=Labeled: expected role=extends for Square: $USES_LABELED"
echo "$USES_LABELED" | grep -q 'role="call"' \
    && no "--uses=Labeled: got a spurious role=\"call\" — Labeled is never invoked, only implemented" \
    || ok "--uses=Labeled: correctly carries no role=\"call\" (a bare interface is never a call site)"

LEGO_LABELED="$( "$BIN" "$FIX" --lego=Labeled --no-cache 2>/dev/null )"
echo "$LEGO_LABELED" | grep -q 'implementors="1"' && echo "$LEGO_LABELED" | grep -q '<impl n="Square"' \
    && ok '--lego=Labeled: Square is the one implementor' \
    || no "--lego=Labeled: expected Square as the sole implementor: $LEGO_LABELED"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 10. COUNTPARAMS: Kotlin function_value_parameters counts \`parameter\` children only ==="
# ═══════════════════════════════════════════════════════════════════════════
# No prior Kotlin fixture had a function with more than one parameter, so the fix for
# function_value_parameters (src/ingest_metrics.h) — count `parameter` children ONLY, since a
# parameter's own `vararg` modifier and default-value expression are SIBLINGS in this grammar, not
# nested — had nothing pinning it. The generic "every named child" rule would misread these 3 real
# params (name, age, tags) as 5 (the extra siblings: age's `= 0` default-value expression, tags'
# `vararg` modifier).
DESCRIBE_METRICS="$( "$BIN" "$FIX" --metrics --no-cache 2>/dev/null )"
echo "$DESCRIBE_METRICS" | grep -o '<s t="fn" n="describe"[^>]*>' | grep -q 'params="3"' \
    && ok 'describe(name, age = 0, vararg tags): params="3" (not 5 — the sibling modifiers/defaults are correctly excluded)' \
    || no "describe(): expected params=3: $( echo "$DESCRIBE_METRICS" | grep -o '<s t=\"fn\" n=\"describe\"[^>]*>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 11. TRULY BODYLESS: a Kotlin interface with NO braces at all is still a definition ==="
# ═══════════════════════════════════════════════════════════════════════════
# §8's enum-class Mode and §9's Labeled interface both HAVE a body (enum_class_body / class_body) and
# so already exercise ingest_sidecap.h's positional-body fallback. `interface Taggable` (no braces —
# not even an empty `{}`) has NO such child for that fallback to find AT ALL, because Kotlin has no
# forward-declaration syntax for types: this bodyless spelling is the type's sole, complete
# definition, same as `Labeled`/`Mode` are once bodied. Before graph.h's decl/def collapse gained the
# Kotlin-class exception (its `hasBody` lambda: `... || (lang==Kotlin && kind==Class)`), a bodyless
# type read exactly like a forward declaration and was silently deleted whenever a same-name Java
# class existed (JavaBridge.java's Taggable, below) — the same silent-drop shape §5/§8 exist to catch,
# but for a definition that was never going to grow a body-fallback child to find. Found in review,
# not in the original port (a post-PR-review coderabbit finding).
USES_TAGGABLE="$( "$BIN" "$FIX" --uses=Taggable --no-cache 2>/dev/null )"
echo "$USES_TAGGABLE" | grep -q 'defs="2"' \
    && ok '--uses=Taggable: defs="2" — the bodyless Kotlin interface survives alongside the Java class' \
    || no "--uses=Taggable: expected defs=2: $USES_TAGGABLE"
echo "$USES_TAGGABLE" | grep -q 'graph_ambiguous="2"' \
    && ok '--uses=Taggable: graph_ambiguous="2" — the collision correctly surfaces' \
    || no "--uses=Taggable: expected graph_ambiguous=2: $USES_TAGGABLE"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 6. DETERMINISM: default map thrice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
# $MAP_OUT (line ~119) is already one run of this exact invocation — reused here as the first of the
# three rather than re-running it, so this gate costs two subprocess runs, not three.
"$BIN" "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_c.xml" 2>/dev/null
diff -q "$MAP_OUT" "$TMP/det_b.xml" >/dev/null && diff -q "$TMP/det_b.xml" "$TMP/det_c.xml" >/dev/null \
    && ok "determinism: default map byte-identical across three runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 7. MUTATION: the cross-file and bridge edges move independently ==="
# ═══════════════════════════════════════════════════════════════════════════
mutate(){ rm -rf "$TMP/mut"; cp -R "$FIX" "$TMP/mut"; }
pyedit(){ python3 -c '
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    sys.exit("mutation target not present: " + old)
open(p, "w").write(s.replace(old, new, 1))
' "$@"; }

# 7a. rename the cross-file call target (greet -> square) — the edge must vanish, proving §1's
#     --callers=square assertion is not a tautology.
mutate
pyedit "$TMP/mut/Greeter.kt" 'val doubled = square(2)' 'val doubled = squareX(2)' \
    && { "$BIN" "$TMP/mut" --no-cache >"$TMP/mut.xml" 2>/dev/null; MUT_RC=$?
         if [ "$MUT_RC" -ne 0 ]; then
             no "mutation 7a: binary exited $MUT_RC on the mutated fixture — absent output means a crash, not proof the edge vanished"
         elif grep -q '<c n="square"/>' "$TMP/mut.xml"; then
             no "mutation: greet -> square edge survived a renamed call site (tautology)"
         else
             ok "mutation: renamed square() call site -> greet -> square edge vanished"
         fi; } \
    || no "mutation 7a: the call-site rename did not apply — the arm would have been inert"

# 7b. rename the Java -> Kotlin bridge call (callGreeter's Greeter.of -> a nonexistent name) — the
#     bridge edge must vanish, proving §2's count="2" assertion is not a tautology.
mutate
pyedit "$TMP/mut/JavaBridge.java" 'Greeter g = Greeter.of("java");' 'Greeter g = Greeter.ofX("java");' \
    && { OF_CALLERS_MUT="$( "$BIN" "$TMP/mut" --callers="Greeter.kt:of" --no-cache 2>/dev/null )"
         echo "$OF_CALLERS_MUT" | grep -q 'count="1"' \
             && ok "mutation: renamed Java -> Kotlin bridge call -> Greeter.kt:of callers drops 2 -> 1" \
             || no "mutation: expected count=1 after renaming the bridge call, got: $( echo "$OF_CALLERS_MUT" | grep -o '<callers [^>]*>' )"; } \
    || no "mutation 7b: the bridge call-site rename did not apply — the arm would have been inert"

# 7c. rename the Kotlin -> Java qualified bridge call (JavaBridge.helper -> a nonexistent name) — the
#     bridge edge must vanish, proving §3's assertion is not a tautology.
mutate
pyedit "$TMP/mut/Greeter.kt" 'fun useJavaHelper(): Int = JavaBridge.helper(5)' 'fun useJavaHelper(): Int = JavaBridge.helperX(5)' \
    && { HELPER_CALLERS_MUT="$( "$BIN" "$TMP/mut" --callers="JavaBridge.java:helper" --no-cache 2>/dev/null )"; MUT_RC=$?
         if [ "$MUT_RC" -ne 0 ]; then
             no "mutation 7c: binary exited $MUT_RC on the mutated fixture — absent output means a crash, not proof useJavaHelper dropped out"
         elif echo "$HELPER_CALLERS_MUT" | grep -q 'n="useJavaHelper"'; then
             no "mutation: useJavaHelper survived as a caller of helper() after its call site was renamed (tautology)"
         else
             ok "mutation: renamed Kotlin -> Java qualified call -> useJavaHelper no longer a caller of helper()"
         fi; } \
    || no "mutation 7c: the qualified bridge call-site rename did not apply — the arm would have been inert"

# 7d. rename the Kotlin enum class out of collision (Mode -> ModeKt) — §8's defs="2" must drop to
#     defs="1" (only Java's Mode left), proving that assertion is not a tautology either.
mutate
pyedit "$TMP/mut/Util.kt" 'enum class Mode { ON, OFF }' 'enum class ModeKt { ON, OFF }' \
    && { USES_MODE_MUT="$( "$BIN" "$TMP/mut" --uses=Mode --no-cache 2>/dev/null )"
         echo "$USES_MODE_MUT" | grep -q 'defs="1"' \
             && ok "mutation: renamed Kotlin enum out of collision -> --uses=Mode defs 2 -> 1" \
             || no "mutation 7d: expected defs=1 after removing the Kotlin side of the collision, got: $( echo "$USES_MODE_MUT" | grep -o '<uses [^>]*>' )"; } \
    || no "mutation 7d: the enum class rename did not apply — the arm would have been inert"

# 7e. drop Labeled from Square's base list (`: Shape(), Labeled` -> `: Shape()`) — --uses=Labeled must
#     drop to count="0", proving §9's DIRECT-shape assertion is not a tautology.
mutate
pyedit "$TMP/mut/Util.kt" 'class Square(private val side: Int) : Shape(), Labeled {' 'class Square(private val side: Int) : Shape() {' \
    && { USES_LABELED_MUT="$( "$BIN" "$TMP/mut" --uses=Labeled --no-cache 2>/dev/null )"
         echo "$USES_LABELED_MUT" | grep -q 'count="0"' \
             && ok "mutation: dropped Labeled from Square's base list -> --uses=Labeled count 1 -> 0" \
             || no "mutation 7e: expected count=0 after dropping the DIRECT base, got: $( echo "$USES_LABELED_MUT" | grep -o '<uses [^>]*>' )"; } \
    || no "mutation 7e: the base-list edit did not apply — the arm would have been inert"

# 7f. drop describe()'s vararg parameter — params must fall 3 -> 2, proving §10's countParams
#     assertion tracks real source changes rather than reporting a hardcoded value.
mutate
pyedit "$TMP/mut/Util.kt" 'fun describe(name: String, age: Int = 0, vararg tags: String): String = "$name/$age/${tags.size}"' 'fun describe(name: String, age: Int = 0): String = "$name/$age"' \
    && { DESCRIBE_MUT="$( "$BIN" "$TMP/mut" --metrics --no-cache 2>/dev/null | grep -o '<s t="fn" n="describe"[^>]*>' )"
         echo "$DESCRIBE_MUT" | grep -q 'params="2"' \
             && ok "mutation: dropped describe()'s vararg parameter -> params 3 -> 2" \
             || no "mutation 7f: expected params=2 after dropping the vararg parameter, got: $DESCRIBE_MUT"; } \
    || no "mutation 7f: the parameter-list edit did not apply — the arm would have been inert"

# 7g. rename the bodyless Kotlin interface out of collision (Taggable -> TaggableKt) — §11's defs="2"
#     must drop to defs="1" (only Java's Taggable left), proving that assertion is not a tautology.
mutate
pyedit "$TMP/mut/Util.kt" 'interface Taggable' 'interface TaggableKt' \
    && { USES_TAGGABLE_MUT="$( "$BIN" "$TMP/mut" --uses=Taggable --no-cache 2>/dev/null )"
         echo "$USES_TAGGABLE_MUT" | grep -q 'defs="1"' \
             && ok "mutation: renamed bodyless Kotlin interface out of collision -> --uses=Taggable defs 2 -> 1" \
             || no "mutation 7g: expected defs=1 after removing the Kotlin side of the collision, got: $( echo "$USES_TAGGABLE_MUT" | grep -o '<uses [^>]*>' )"; } \
    || no "mutation 7g: the interface rename did not apply — the arm would have been inert"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 12. HOSTILE NESTING: 600 nested string templates are refused before the parse, never a process abort ==="
# ═══════════════════════════════════════════════════════════════════════════
# tree-sitter-kotlin's external scanner keeps one stack entry per OPEN string, and upstream abort()ed when the next push
# would overrun the 1024-byte serialization buffer: on the first Kotlin binary ONE such file ended the run for its whole
# tree at rc=134 with no output — the map, --skipped, --grep, --match, every verb. Two independent layers now, and this
# section is the runtime arm for the FIRST: ingest's kotlinStringsNestTooDeep prescan (ingest.h
# kMaxKotlinStringNestDepth = 128) refuses the FILE before any parse, names it on stderr (plus DEGRADED_PATH_ALERT on a
# non-NDEBUG build) and rows it in --skipped as why="nest-refused". The SECOND layer, the vendored scanner refusing the
# push instead of aborting, is vendorpatchcheck arm J. The ceiling is pinned from BOTH sides (128 indexed, 129 refused)
# and the siblings must stay indexed, so a guard that refuses the whole tree and a guard that refuses nothing are both red.
NEST="$TMP/nest"; mkdir -p "$NEST"
python3 - "$NEST" <<'PYEOF'
import os, sys
root = sys.argv[1]
def nested(depth):   # `depth` simultaneously-open strings: "a${"a${ … "leaf" … }"}"
    return '"a${' * (depth - 1) + '"leaf"' + '}"' * (depth - 1)
def write(name, fn, depth):
    with open(os.path.join(root, name), "w") as f:
        f.write("package nest\n\nfun %s(): Int = 1\n\nval v_%s = %s\n" % (fn, fn, nested(depth)))
write("Deep.kt", "deepFn", 600)
write("OverCeiling.kt", "overCeilingFn", 129)
write("AtCeiling.kt", "atCeilingFn", 128)
with open(os.path.join(root, "Sibling.kt"), "w") as f:
    f.write('package nest\n\nfun siblingFn(name: String): String = "hi ${name.uppercase()} ${"x${name}"}"\n\nfun callsSibling(): String = siblingFn("k")\n')
PYEOF
nestOpeners(){ grep -o '"a\${' "$1" | wc -l | tr -d ' '; }   # open strings = openers + 1 (the "leaf")
[ "$( nestOpeners "$NEST/Deep.kt" )" = 599 ] && [ "$( nestOpeners "$NEST/OverCeiling.kt" )" = 128 ] && [ "$( nestOpeners "$NEST/AtCeiling.kt" )" = 127 ] \
    && ok "presence: Deep.kt nests 600 open strings, OverCeiling.kt 129, AtCeiling.kt 128" \
    || no "presence: fixture depths are not 600/129/128 — every arm below would assert on the wrong input"

"$BIN" "$NEST" --no-cache >"$TMP/nest.xml" 2>"$TMP/nest.err"; NEST_RC=$?
[ "$NEST_RC" -eq 0 ] && ok "hostile nesting: the map exits 0 (the first Kotlin binary died here at rc=134, the scanner's abort)" \
    || no "hostile nesting: the map exited $NEST_RC — 134 is the scanner's abort(): $( head -3 "$TMP/nest.err" )"
# Every arm below reads the map, so it is evaluated ONLY on a clean exit: a crashed run prints nothing, and "no deepFn in
# an empty file" would otherwise pass for the very defect this section exists to catch.
if [ "$NEST_RC" -eq 0 ]; then
    command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$TMP/nest.xml" 2>/dev/null && ok "hostile nesting: the map is well-formed" || no "hostile nesting: the map fails xmllint"; }
    grep -q 'n="siblingFn"' "$TMP/nest.xml" && grep -q 'n="callsSibling"' "$TMP/nest.xml" \
        && ok "hostile nesting: Sibling.kt stays indexed (siblingFn, callsSibling) — the refusal is per file, not per tree" \
        || no "hostile nesting: Sibling.kt's symbols are missing — the guard took the tree down with the file"
    grep -q 'n="atCeilingFn"' "$TMP/nest.xml" \
        && ok "hostile nesting: AtCeiling.kt (128 open strings) is indexed — the ceiling is inclusive" \
        || no "hostile nesting: AtCeiling.kt (128 deep) was refused — the prescan over-counts at the ceiling"
    grep -q 'n="deepFn"' "$TMP/nest.xml" || grep -q 'n="overCeilingFn"' "$TMP/nest.xml" \
        && no "hostile nesting: Deep.kt or OverCeiling.kt contributed symbols — the prescan did not refuse them before the parse" \
        || ok "hostile nesting: Deep.kt (600) and OverCeiling.kt (129) contribute no symbols — refused before the parse"
    grep -q 'Deep.kt: kotlin string-template nesting > 128 levels' "$TMP/nest.err" && grep -q 'OverCeiling.kt: kotlin string-template nesting > 128 levels' "$TMP/nest.err" \
        && ok "hostile nesting: both refusals are named on stderr (the json/yaml house skip style)" \
        || no "hostile nesting: stderr does not name both refusals: $( head -5 "$TMP/nest.err" )"
    # DEGRADED_PATH_ALERT prints only where NDEBUG is undefined (the plain dev build, the asan build); Release compiles it
    # out. The flavour is read from --version's build-type token, the reading estchargecheck and versioncheck share, so
    # this arm neither goes red on a Release leg nor passes blind on the plain build.
    NEST_FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
    case "$NEST_FLAVOUR" in
        Release|RelWithDebInfo|MinSizeRel)
            ok "hostile nesting: $NEST_FLAVOUR build defines NDEBUG — DEGRADED_PATH_ALERT is compiled out, nothing to assert" ;;
        *)
            grep -q 'math degraded.*kMaxKotlinStringNestDepth' "$TMP/nest.err" \
                && ok "hostile nesting: DEGRADED_PATH_ALERT names the refusal on this '${NEST_FLAVOUR:-unknown}' (non-NDEBUG) build" \
                || no "hostile nesting: '${NEST_FLAVOUR:-unknown}' is a non-NDEBUG build, yet the Kotlin refusal raised no DEGRADED_PATH_ALERT" ;;
    esac
else
    no "hostile nesting: the symbol, stderr and degrade-alert arms were NOT evaluated — the map did not exit 0"
fi

SKN="$( "$BIN" "$NEST" --skipped --no-cache 2>/dev/null )"; SKN_RC=$?
deepBytes="$( wc -c < "$NEST/Deep.kt" | tr -d ' ' )"; overBytes="$( wc -c < "$NEST/OverCeiling.kt" | tr -d ' ' )"
if [ "$SKN_RC" -eq 0 ] && echo "$SKN" | grep -q '<skipped '; then
    ok "--skipped exits 0 over the hostile tree with a <skipped> report"
    echo "$SKN" | grep -q "<f p=\"Deep.kt\" why=\"nest-refused\" bytes=\"$deepBytes\" ext=\".kt\"/>" \
        && ok "--skipped itemizes Deep.kt: why=\"nest-refused\" bytes=\"$deepBytes\" ext=\".kt\"" \
        || no "--skipped has no exact nest-refused row for Deep.kt: $( echo "$SKN" | grep -o '<f p="[^"]*" why="[^"]*"[^/]*/>' | head -5 )"
    echo "$SKN" | grep -q "<f p=\"OverCeiling.kt\" why=\"nest-refused\" bytes=\"$overBytes\" ext=\".kt\"/>" \
        && ok "--skipped itemizes OverCeiling.kt" || no "--skipped has no exact nest-refused row for OverCeiling.kt"
    # why="nest-refused" specifically: AtCeiling.kt is one long whitespace-poor line, so it legitimately earns a
    # minified-suspect <h> health row — an indexed file flagged, which is exactly what it is.
    echo "$SKN" | grep -q 'p="AtCeiling.kt" why="nest-refused"' && no "--skipped rows AtCeiling.kt as nest-refused, but it was indexed" \
        || ok "--skipped does not row AtCeiling.kt as nest-refused (indexed, not refused)"
    echo "$SKN" | grep -q 'nest_refused="2"' && ok '--skipped header: nest_refused="2"' \
        || no "--skipped header: expected nest_refused=\"2\": $( echo "$SKN" | grep -o '<skipped [^>]*>' )"
    echo "$SKN" | grep -q '<!-- nest_refused= counts' && ok "--skipped defines nest_refused= in the legend of the document that carries the rows" \
        || no "--skipped: nest-refused rows with no legend clause defining them"
    "$BIN" "$NEST" --skipped --no-cache 2>/dev/null | cmp -s - <( echo "$SKN" ) && ok "--skipped over the hostile tree: two runs byte-identical" \
        || no "--skipped over the hostile tree differs between two runs"
else
    no "--skipped over the hostile tree exited $SKN_RC or printed no <skipped> report — its row, header and legend arms were NOT evaluated"
fi
SK_CLEAN="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
if echo "$SK_CLEAN" | grep -q '<skipped '; then
    echo "$SK_CLEAN" | grep -q 'nest_refused\|nest-refused' \
        && no "--skipped on the clean kotlinfix mentions nest_refused — absent-means-nothing-happened is broken" \
        || ok "--skipped on the clean kotlinfix: no nest_refused attribute, row or legend clause"
else
    no "--skipped on the clean kotlinfix printed no <skipped> report — the absent-when-zero arm would pass on nothing"
fi

# warm: a refused file yields no facts, so it is never cached — a cached re-run must re-read and re-refuse it, not lose it.
"$BIN" "$NEST" --cache="$TMP/nest.cache" >/dev/null 2>&1
if ls "$TMP"/nest.cache* >/dev/null 2>&1; then
    SKW="$( "$BIN" "$NEST" --skipped --cache="$TMP/nest.cache" 2>/dev/null )"
    echo "$SKW" | grep -q 'nest_refused="2"' && echo "$SKW" | grep -q '<f p="Deep.kt" why="nest-refused"' \
        && ok "warm: the cached re-run still refuses and rows both files" \
        || no "warm: the cached re-run lost the refusal: $( echo "$SKW" | grep -o '<skipped [^>]*>' )"
else
    no "warm: presence — the first run wrote no cache under $TMP/nest.cache* (the warm arm would have run cold)"
fi

# multi-root: the row relabels like every other skipped row, and the count sums across roots.
mkdir -p "$TMP/other"; printf 'package other\n\nfun otherFn(): Int = 2\n' > "$TMP/other/Other.kt"
SKM="$( cd "$TMP" && "$BIN" nest other --skipped --no-cache 2>/dev/null )"
echo "$SKM" | grep -q '<f p="nest/Deep.kt" why="nest-refused"' && echo "$SKM" | grep -q 'nest_refused="2"' \
    && ok "multi-root: the refusal row keeps its <label>/<rel> spelling (nest/Deep.kt) and nest_refused merges to 2" \
    || no "multi-root: expected <f p=\"nest/Deep.kt\" why=\"nest-refused\" and nest_refused=\"2\": $( echo "$SKM" | grep -o '<f p="[^"]*" why="nest-refused"[^/]*/>' )"

# Mutation: take ONE level off OverCeiling.kt (129 -> 128). The identical extraction must now index it and the count must
# drop to 1 — so the ceiling arms above track DEPTH, not a file name or a size.
rm -rf "$TMP/nestmut"; cp -R "$NEST" "$TMP/nestmut"
python3 - "$TMP/nestmut/OverCeiling.kt" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
t = s.replace('"a${', '', 1).replace('}"', '', 1)
if t == s:
    sys.exit("mutation target not present")
open(p, "w").write(t)
PYEOF
if [ "$( nestOpeners "$TMP/nestmut/OverCeiling.kt" )" = 127 ]; then
    "$BIN" "$TMP/nestmut" --no-cache >"$TMP/nestmut.xml" 2>/dev/null
    SKMUT="$( "$BIN" "$TMP/nestmut" --skipped --no-cache 2>/dev/null )"
    grep -q 'n="overCeilingFn"' "$TMP/nestmut.xml" && echo "$SKMUT" | grep -q 'nest_refused="1"' \
        && ok "mutation: one level off OverCeiling.kt (129 -> 128) -> indexed, nest_refused 2 -> 1" \
        || no "mutation: 128-deep OverCeiling.kt is still refused, or the count did not move: $( echo "$SKMUT" | grep -o '<skipped [^>]*>' )"
else
    no "mutation 12: OverCeiling.kt did not lose exactly one level — the arm would have been inert"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
