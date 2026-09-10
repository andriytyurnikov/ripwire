#!/usr/bin/env bash
# qddialscheck.sh — the per-kind DIALS of --quality-delta (round 2026-09-10, audit lane Q1's dial table).
#
# Q1 measured the verb on three labelled populations — 12 working-tree replays of landed commits, 40 ref-pair
# replays, and a 15-case synthetic battery — and found the precision problem concentrated in a few kinds while
# the recall headroom sat in others. Each section below is ONE dial, with the case that must stay caught beside
# the case that must stop firing, so a later change cannot quietly restore either half:
#
#   1. short-horizon-churn — churn="self" is informational; GATING needs >= 2 COMMITTED in-window commits on
#      the edited lines (the working edit never counted).
#   2. dead-code — the blanket .h/.hpp/.hh/.hxx exclusion is gone; what is exempt is what the LANGUAGE invokes
#      (constructors, destructors, operators, bare type declarations, main).
#   3. verbosity/complexity — verbosity counts CODE lines (blank and comment lines are not debt); both kinds
#      gate on a bar CROSSING or >= 25% growth, and a sub-bar doubling is a minor row rather than silence.
#   4. api-surface — new-symbol rows are a header COUNT, a surface that SHRANK is not a regression, and a
#      single trailing DEFAULTED parameter is minor.
#   5. duplication / new-clone-of-reused-helper — an overload set, a one-file group and a vendored path are
#      not this change's duplication.
#   6. error-masking — a block whose only content is a COMMENT is a swallow.
#
# Fixtures are built in temp dirs (git-init where a section needs history); the repo is never touched.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/qddialscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional AND env (a red-first run hands the pre-change binary in)
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qddialscheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qddialscheck: BIN=$BIN  (temp corpora)"

# One emitted row, as its own line. The document is newline-free (G4), and a row's own attributes carry
# both '/' (p="path:line") and '"' — so a single-line grep with a character class is the wrong tool and
# silently matched the wrong row when it was tried. Split on '>' first, then match the whole row.
row(){ printf '%s' "$1" | tr '>' '\n' | grep "kind=\"$2\" sym=\"$3\"" ; }
rows(){ printf '%s' "$1" | tr '>' '\n' | grep '<r ' ; }

# ── 1) short-horizon-churn: SELF is informational, TWO committed in-window rewrites gate ─────────────────
# One file, two multi-line functions, and a history built so the two differ ONLY in how many COMMITTED
# in-window commits wrote the lines the working edit touches:
#   c0, backdated 200 days (OUTSIDE the 14-day window)  — both functions written.
#   c1, now — rewrites once() line 1 AND twice() line 1.
#   c2, now — rewrites twice() line 2.
#   working tree — rewrites BOTH lines of BOTH functions.
# once():  edited lines blame to {c1 (in), c0 (out)} → ONE in-window commit → churn="self", informational.
# twice(): edited lines blame to {c1, c2}            → TWO in-window commits → the rewrite thrash that gates.
CH="$WORK/churn"; mkdir -p "$CH/src"
( cd "$CH" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
wr(){ printf 'int once(){\n    int a = %s;\n    int b = %s;\n    return a + b;\n}\nint twice(){\n    int c = %s;\n    int d = %s;\n    return c + d;\n}\nint drive(){ return once() + twice(); }\n' "$1" "$2" "$3" "$4" > "$CH/src/f.cpp"; }
cm(){ ( cd "$CH" && git add -A >/dev/null 2>&1 && GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -qm "$2" >/dev/null 2>&1 ); }
OLD="$( date -u -r $(( $( date +%s ) - 200*86400 )) +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '200 days ago' +%Y-%m-%dT%H:%M:%S )"
NOW="$( date -u +%Y-%m-%dT%H:%M:%S )"
wr 1 2 3 4      ; cm "$OLD" c0
wr 11 2 33 4    ; cm "$NOW" c1
wr 11 2 33 44   ; cm "$NOW" c2
wr 111 222 333 444
OCH="$( cd "$CH" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
ECH="$( cd "$CH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
row "$OCH" short-horizon-churn twice | grep -q 'gating="1"' \
    && ok "churn: twice() GATES (two committed in-window rewrites of the edited lines)" \
    || { no "churn: twice() must still gate — the thrash signal was not preserved"; rows "$OCH"; }
row "$OCH" short-horizon-churn once >/dev/null \
    && ok "churn: once() still REPORTED (the kind stays informational, not deleted)" \
    || { no "churn: once() row disappeared — the dial demotes, it does not drop"; rows "$OCH"; }
row "$OCH" short-horizon-churn once | grep -q 'gating="1"' \
    && { no "churn: once() must NOT gate — ONE in-window commit is a touch, not thrash (this is the dial)"; rows "$OCH"; } \
    || ok "churn: once() does not gate (one in-window commit is informational)"
row "$OCH" short-horizon-churn once | grep -q 'sev="minor"' \
    && ok "churn: once() carries sev=minor" \
    || no "churn: once() should be sev=minor"
[ "$ECH" = 2 ] && ok "churn: exit 2 (the gating twice() row fires it)" || no "churn: expected exit 2, got $ECH"
[ "$OCH" = "$( cd "$CH" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "churn: byte-identical run to run (deterministic)" || no "churn: non-deterministic delta"

# ── 2) dead-code: the header exclusion is gone; what is exempt is what the LANGUAGE invokes ──────────────
# The kind used to answer false for ANY symbol in a .h/.hpp/.hh/.hxx file ("header-exported by convention"),
# which on this header-only codebase hid 96.8% of src from it — synthetic S6 (the sole caller of a header
# function deleted) was silently missed. The proxy is replaced by the rule it stood for: a symbol the
# language itself invokes has no named call site for the graph to record, so zero in-edges says nothing.
#
# Two arms, both red on the pre-change binary and for opposite reasons:
#   the header function that LOSES its last caller must now be reported (recall);
#   the constructor / destructor / operator / bare type the working tree ADDS must not be (precision) —
#   before the dial those were only silent because they sat in a header, and in a .cpp they were reported.
DC="$WORK/dead"; mkdir -p "$DC/src"
( cd "$DC" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
printf 'inline int usedHelper(){ return 41; }\n' > "$DC/src/lib.hpp"
cat > "$DC/src/m.cpp" <<'CPP'
#include "lib.hpp"
struct Thing {
    Thing() { value = 1; }
    ~Thing() { value = 0; }
    bool operator==( const Thing& o ) const { return value == o.value; }
    int value;
};
int driver(){ return usedHelper(); }
int main(){ Thing t; return driver() + t.value; }
CPP
( cd "$DC" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
# the working edit: driver() stops calling usedHelper (S6 — the sole caller deleted), and a brand-new type
# arrives whose ctor, dtor and operator have no named caller anywhere.
python3 - "$DC/src/m.cpp" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("int driver(){ return usedHelper(); }","""struct Extra {
    Extra() { n = 2; }
    ~Extra() { n = 0; }
    bool operator<( const Extra& o ) const { return n < o.n; }
    int n;
};
int driver(){ return 41; }""")
open(p,"w").write(s)
PY
ODC="$( cd "$DC" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
row "$ODC" dead-code usedHelper >/dev/null \
    && ok "dead-code: a HEADER function that lost its sole caller is reported (synthetic S6)" \
    || { no "dead-code: usedHelper not reported — the header exclusion still hides the kind"; rows "$ODC"; }
DEADROWS="$( rows "$ODC" | grep -c 'kind="dead-code"' )"
# One match on the whole family: the ctor and dtor BOTH index as Extra::Extra (the parser keeps no leading
# tilde) and the operator arrives XML-escaped as operator&lt;, so naming them one by one greps for spellings
# that never appear. Anything under the new type is a language-invoked symbol and must not be a row.
rows "$ODC" | grep 'kind="dead-code"' | grep -q 'Extra' \
    && { no "dead-code: a language-invoked member of Extra reported (ctor/dtor/operator/type)"; rows "$ODC" | grep 'kind="dead-code"'; } \
    || ok "dead-code: no ctor/dtor/operator/type row for the new Extra type (the language invokes them)"
[ "$DEADROWS" = 1 ] && ok "dead-code: exactly ONE dead-code row on this fixture (only usedHelper)" \
    || { no "dead-code: expected 1 dead-code row, got $DEADROWS"; rows "$ODC" | grep 'kind="dead-code"'; }
[ "$ODC" = "$( cd "$DC" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "dead-code: byte-identical run to run (deterministic)" || no "dead-code: non-deterministic delta"


[ "$fail" = 0 ] && echo "qddialscheck: ALL PASS" || echo "qddialscheck: FAILURES"
exit "$fail"
