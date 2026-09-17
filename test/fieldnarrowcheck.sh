#!/usr/bin/env bash
# fieldnarrowcheck.sh — gate for P2-D Rule 2b: FIELD-typed member narrowing (W1-P1-12).
#
# The gap this closes: a member call whose receiver is a bare FIELD of the enclosing class
# (`m_pool.acquire()` / `m_p->tune()` inside a method of Owner) used to resolve `acquire` by BARE NAME
# against every same-named definition in the corpus — inflating per-symbol `amb=` and the header
# `ambiguous=` gauge. Rule 2b: when the receiver names a field whose DECLARED TYPE is a type the index
# knows (the S5-E HAS-A field capture), narrow the candidate set to that type's members, walking direct
# bases (chaUp) when the type itself does not define the method. RESOLVE-stage only — no kParserVer bump
# (arm q, 2026-09-16, is the exception: the field capture records the namespace a type was written in, kParserVer 99).
#
# Zero false edges is the bar — narrowing that guesses wrong is worse than ambiguity disclosed:
#   * a LOCAL (param / declared var) that shadows the field name vetoes the narrow (real C++ lookup);
#   * two same-NAMED classes (scope strings drop namespaces, so `n1::Dup` and `n2::Dup` collide) with a
#     same-named field of DIFFERENT types TOMBSTONE the field entry — neither narrows;
#   * an unknown/unindexed field type, a chained `this->f.m()` receiver, a receiver in a scope-less free
#     function, and multiple bases both defining the method all DEGRADE to the unchanged honest split;
#   * Python `self.member.m()` and TS `this.member.m()` receivers are NOT captured as named receivers
#     (chained member access; receiver capture is C++/ObjC+Python identifiers only) → UNCHANGED, and the
#     (e-py)/(e-ts) arms pin that honesty. Widening receiver capture is an EXTRACTION change (kParserVer)
#     and deliberately out of this round.
#
# The fixture is GENERATED here (self-contained; nothing committed under test/). Line numbers in the
# fixture are load-bearing: `--callees` rows carry p="file:LINE", which is how a Pool::acquire edge is
# told apart from the same-named Decoy::acquire decoy.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/fieldnarrowcheck.sh   (or asan/ripwire)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fieldfix"; FIX2="$TMP/dupfix"
mkdir -p "$FIX" "$FIX2"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"

# LINE NUMBERS ARE ASSERTED BELOW — edit with care.
cat >"$FIX/a.cpp" <<'EOF'
struct Pool { void acquire() { } void tune() { } };
struct Decoy { void acquire() { } void tune() { } };

struct Owner {
    Pool m_pool;
    Pool* m_p;
    void run() { m_pool.acquire(); }
    void ptr() { m_p->tune(); }
    void expl() { this->m_pool.acquire(); }
};

struct Base { void helper() { } };
struct Derived : Base { };
struct DecoyH { void helper() { } };
struct Owner4 { Derived m_d; void inh_go() { m_d.helper(); } };

struct Owner5 { Pool m_x; void shadowParam( Decoy& m_x ) { m_x.acquire(); } };
struct Owner6 { Pool m_y; void shadowLocal() { Decoy m_y; m_y.acquire(); } };

struct Owner3 { UnknownT m_u; void unk() { m_u.acquire(); } };

struct B1 { void dual() { } };
struct B2 { void dual() { } };
struct D2 : B1, B2 { };
struct Owner7 { D2 m_dd; void multi() { m_dd.dual(); } };

Unknown gg;
void freeuse() { gg.acquire(); }
EOF

cat >"$FIX/p.py" <<'EOF'
class PHelper:
    def compute(self):
        return 1

class PDecoy:
    def compute(self):
        return 2

class POwner:
    member: PHelper
    def po_go(self):
        return self.member.compute()
EOF

cat >"$FIX/t.ts" <<'EOF'
class THelper { compute(): number { return 1; } }
class TDecoy { compute(): number { return 2; } }
class TOwner {
  member: THelper;
  to_go(): number { return this.member.compute(); }
}
EOF

# FIX2 — the same-named-class collision corpus, ISOLATED so its header ambiguous= gauge is exact.
# Symbol scopes drop the namespace (both classes read scope "Dup"), so the two same-named `m_f` fields
# with DIFFERENT types must tombstone the field-type entry: NEITHER go() may narrow.
cat >"$FIX2/ns.cpp" <<'EOF'
namespace n1 { struct Pool2 { void grab() { } };
               struct Dup { Pool2 m_f; void go() { m_f.grab(); } }; }
namespace n2 { struct Decoy2 { void grab() { } };
               struct Dup { Decoy2 m_f; void go() { m_f.grab(); } }; }
EOF

echo "fieldnarrowcheck: BIN=$BIN  CORPUS=$FIX + $FIX2 (generated)"

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null | tr '>' '\n' )"
callees(){ "$BIN" "$FIX" "--callees=$1" --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n'; }

# ── presence guards (a gate that cannot observe what it asserts is green-while-inert) ──
# TS symbols carry no scope string (no sc= attribute), so to_go is matched by its n= name. Row 6: a scoped row
# prints n= then sc= (the short id; the canonical id composes as p::sc::n with the enclosing <f p=>).
for want in 'n="acquire" sc="Pool"' 'n="acquire" sc="Decoy"' 'n="run" sc="Owner"' 'n="helper" sc="Base"' 'n="helper" sc="DecoyH"' 'n="inh_go" sc="Owner4"' 'n="po_go" sc="POwner"' 'n="to_go"'; do
    printf '%s\n' "$MAP" | grep -qF "$want" || no "presence guard: fixture symbol $want not indexed"
done
[ "$fail" = 0 ] && ok "presence: all fixture symbols indexed"

# ── (a) value field, type known: `m_pool.acquire()` → Pool::acquire (a.cpp:1) ONLY, decoy (a.cpp:2) unlinked ──
RUN="$( callees run )"
printf '%s\n' "$RUN" | grep -q 'a.cpp:1"' \
    && ok "(a) run() → Pool::acquire (field m_pool's declared type)" \
    || no "(a) run() has NO edge to Pool::acquire — field-typed narrow missing or dropped the correct edge"
printf '%s\n' "$RUN" | grep -q 'a.cpp:2"' \
    && no "(a/d) run() still linked to Decoy::acquire — the same-named decoy on an unrelated class must not be linked" \
    || ok "(d) run() decoy Decoy::acquire NOT linked"

# ── (a2) the narrow is visible in amb=: Owner::run's map row carries no ambiguous-call count ──
printf '%s\n' "$MAP" | grep 'id="[^"]*::Owner::run"' | grep -q 'amb=' \
    && no "(a2) Owner::run row still carries amb= — the field-typed call still counts ambiguous" \
    || ok "(a2) Owner::run row has no amb= (call resolved, honestly unambiguous)"

# ── (f) pointer field: `m_p->tune()` narrows exactly like a value field ──
PTR="$( callees ptr )"
printf '%s\n' "$PTR" | grep -q 'a.cpp:1"' \
    && ok "(f) ptr() → Pool::tune (pointer field m_p)" \
    || no "(f) ptr() has NO edge to Pool::tune — pointer-field narrow missing"
printf '%s\n' "$PTR" | grep -q 'a.cpp:2"' \
    && no "(f) ptr() still linked to Decoy::tune" \
    || ok "(f) ptr() decoy Decoy::tune NOT linked"

# ── (c) inheritance: field type Derived defines no helper — the DIRECT-base walk finds Base::helper (a.cpp:12);
#        the same-named DecoyH::helper (a.cpp:14) stays unlinked ──
INH="$( callees inh_go )"
printf '%s\n' "$INH" | grep -q 'a.cpp:12"' \
    && ok "(c) inh_go() → Base::helper (member found on the field type's base)" \
    || no "(c) inh_go() has NO edge to Base::helper — base walk missing"
printf '%s\n' "$INH" | grep -q 'a.cpp:14"' \
    && no "(c) inh_go() still linked to DecoyH::helper — decoy reached through the base walk" \
    || ok "(c) inh_go() decoy DecoyH::helper NOT linked"

# ── (b) unchanged-degrade arms: every uncertain shape keeps the honest 2-way split ──
EXPL="$( callees expl )"
( printf '%s\n' "$EXPL" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$EXPL" | grep -q 'a.cpp:2"' ) \
    && ok "(b) expl() this->m_pool.acquire() chained receiver stays honestly split (receiver capture limit, disclosed)" \
    || no "(b) expl() lost its honest split — a chained this->field receiver must not narrow (capture is None)"
UNK="$( callees unk )"
( printf '%s\n' "$UNK" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$UNK" | grep -q 'a.cpp:2"' ) \
    && ok "(b) unk() unknown field type UnknownT stays honestly split" \
    || no "(b) unk() lost its honest split — an unindexed field type must degrade, not narrow"
FREE="$( callees freeuse )"
( printf '%s\n' "$FREE" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$FREE" | grep -q 'a.cpp:2"' ) \
    && ok "(b) freeuse() scope-less receiver stays honestly split" \
    || no "(b) freeuse() lost its honest split — a free function has no enclosing class to look fields up in"
MULTI="$( callees multi )"
( printf '%s\n' "$MULTI" | grep -q 'a.cpp:22"' ) && ( printf '%s\n' "$MULTI" | grep -q 'a.cpp:23"' ) \
    && ok "(b) multi() two bases both define dual() → ambiguous base walk refuses, split kept" \
    || no "(b) multi() lost its honest split — a 2-way base hit must refuse to narrow"

# ── (s) shadowing: a LOCAL that shadows the field name vetoes the narrow (real C++ lookup order) ──
SHP="$( callees shadowParam )"
printf '%s\n' "$SHP" | grep -q 'a.cpp:2"' \
    && ok "(s1) shadowParam( Decoy& m_x ) keeps its Decoy::acquire edge — the param shadows field m_x" \
    || no "(s1) shadowParam lost Decoy::acquire — the field type was wrongly narrowed over the shadowing param"
# since 2026-09-16 Rule 2 reads the parameter's written type (narrowcheck arms 7-18), so the parameter's Decoy is
# the WHOLE answer — main's binary still linked the field's Pool::acquire here as half of a split
printf '%s\n' "$SHP" | grep -q 'a.cpp:1"' \
    && no "(s1) shadowParam linked to Pool::acquire — the FIELD type beat the shadowing Decoy& parameter" \
    || ok "(s1) shadowParam field type Pool NOT linked (the typed parameter shadows the field)"
SHL="$( callees shadowLocal )"
printf '%s\n' "$SHL" | grep -q 'a.cpp:2"' \
    && ok "(s2) shadowLocal's local Decoy m_y still wins (Rule 2 narrow preserved)" \
    || no "(s2) shadowLocal lost its Rule-2 edge to Decoy::acquire"
printf '%s\n' "$SHL" | grep -q 'a.cpp:1"' \
    && no "(s2) shadowLocal linked to Pool::acquire — the FIELD type beat the shadowing local" \
    || ok "(s2) shadowLocal field type Pool NOT linked (local shadows field)"

# ── (e) cross-language honesty: Python/TS field receivers are chained accesses — NOT narrowed, stays split ──
PY="$( callees po_go )"
( printf '%s\n' "$PY" | grep -q 'p.py:2"' ) && ( printf '%s\n' "$PY" | grep -q 'p.py:6"' ) \
    && ok "(e-py) po_go() self.member.compute() stays honestly split (annotated attr NOT narrowed — disclosed limit)" \
    || no "(e-py) po_go() lost its honest split — Python receiver behavior must be unchanged this round"
TS="$( callees to_go )"
( printf '%s\n' "$TS" | grep -q 't.ts:1"' ) && ( printf '%s\n' "$TS" | grep -q 't.ts:2"' ) \
    && ok "(e-ts) to_go() this.member.compute() stays honestly split (TS receivers uncaptured — disclosed limit)" \
    || no "(e-ts) to_go() lost its honest split — TS receiver behavior must be unchanged this round"

# ── (h) the header gauge agrees with the arms above: exactly the 6 honest splits remain ambiguous
#        (expl, unk, freeuse, multi, po_go, to_go — run/ptr/inh_go narrowed, shadowLocal and shadowParam are
#        Rule 2; shadowParam was a split until Rule 2 read parameter types, 2026-09-16, which moved this from 7).
#        Counted from the fixture, not guessed: flip arms above before touching this number. ──
AMB="$( printf '%s\n' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB" = "ambiguous=6" ] \
    && ok "(h) header gauge ambiguous=6 — only the honest splits remain" \
    || no "(h) header gauge is '$AMB', expected ambiguous=6 (3 field-typed calls narrowed, 6 honest splits kept)"

# ── (n) same-NAMED class collision (FIX2): conflicting same-named fields tombstone — NEITHER Dup::go narrows ──
MAP2="$( "$BIN" "$FIX2" --no-cache 2>/dev/null | tr '>' '\n' )"
printf '%s\n' "$MAP2" | grep -qF 'n="go" sc="Dup"' || no "(n) presence guard: Dup::go not indexed in FIX2"
AMB2="$( printf '%s\n' "$MAP2" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB2" = "ambiguous=2" ] \
    && ok "(n) both n1::Dup::go and n2::Dup::go stay ambiguous (conflicting field types tombstoned)" \
    || no "(n) FIX2 header gauge is '$AMB2', expected ambiguous=2 — a name-collided field type must never narrow"
GO2="$( "$BIN" "$FIX2" --callees=go --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n' )"
( printf '%s\n' "$GO2" | grep -q 'ns.cpp:1"' ) && ( printf '%s\n' "$GO2" | grep -q 'ns.cpp:3"' ) \
    && ok "(n) both grab() defs stay linked across the collision" \
    || no "(n) a grab() edge vanished — the tombstone dropped a correct edge"

# ── (q) a field type written in namespace `std` (2026-09-16) — an EXTRACTION change, unlike the rest of this gate. The
#        field capture keeps a qualified type's final segment, so `std::string name_;` recorded `string`, and three
#        readers of that record took it for an in-repo class of that name: Rule 2b pinned `name_.size()` to it
#        (census mech=receiver-rule), the HAS-A block drew Record → string, and the member index pinned `name_.len`
#        to string.len. `std` is reserved to the implementation, so no in-repo class IS a std:: type — the sibling
#        rule for locals and parameters (resolve.h namesStdType, test/narrowcheck.sh arms 17-24). Every other
#        qualifier keeps narrowing on its final segment: store::Text is the control (q2/q4/q6).
#        (q7) is the trap the obvious fix walks into. Skipping the std field at capture UN-TOMBSTONES a same-named
#        class's differently-typed field — measured on rocksdb: test_util/testutil.h's `std::string contents_` and
#        db/log_test.cc's `Slice& contents_` share the key StringSource#contents_, and the skip pinned four
#        testutil.h `contents_.size()` calls to Slice::size. So the std field must still tombstone the entry; the
#        fixture holds the collision in BOTH record orders (StringSink's std side sorts first, StringSource's last).
#        LINE NUMBERS in app/rec.cpp are asserted below. ──
FIX3="$TMP/stdfix"; FIX4="$TMP/tombfix"
mkdir -p "$FIX3/lib" "$FIX3/lib2" "$FIX3/store" "$FIX3/app" "$FIX4/0" "$FIX4/a" "$FIX4/b" "$FIX4/c"
cat >"$FIX3/lib/str.h" <<'EOF'
struct string { int size() { return 0; } int len; };
EOF
cat >"$FIX3/lib2/blob.h" <<'EOF'
struct Blob { int size() { return 1; } };
EOF
cat >"$FIX3/store/text.h" <<'EOF'
namespace store { struct Text { int size() { return 4; } int len; }; }
EOF
cat >"$FIX3/app/rec.cpp" <<'EOF'
struct Record {
    std::string name_;
    store::Text body_;
    int nameLength() { return name_.size(); }
    int bodyLength() { return body_.size(); }
    int nameLen() { return name_.len; }
    int bodyLen() { return body_.len; }
    int thisNameLen() { return this->name_.len; }
};
EOF
cat >"$FIX4/0/pipe.h" <<'EOF'
struct StringSink { std::string contents_; int drained() { return contents_.size(); } };
EOF
cat >"$FIX4/a/slice.h" <<'EOF'
struct Slice { int size() const { return 2; } };
struct Other { int size() const { return 3; } };
EOF
cat >"$FIX4/a/log_test.cc" <<'EOF'
struct StringSource { Slice& contents_; int left() { return contents_.size(); } };
EOF
cat >"$FIX4/b/testutil.h" <<'EOF'
struct StringSource { std::string contents_; int used() { return contents_.size(); } };
EOF
cat >"$FIX4/c/sink.cc" <<'EOF'
struct StringSink { Slice& contents_; int filled() { return contents_.size(); } };
EOF
"$BIN" "$FIX3" --no-cache --pin-census="$TMP/q3.tsv" >/dev/null 2>&1
"$BIN" "$FIX4" --no-cache --pin-census="$TMP/q4.tsv" >/dev/null 2>&1
qMechs(){  # qMechs TSV CALLER — the distinct deciding mechanisms of CALLER's size() census rows ("" = no row: declined)
    awk -F '\t' -v c="$2" '$1 == "C" && index( $6, c ) && $7 == "size" { print $2 }' "$1" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'
}
qHas(){ grep -qF "$2" "$1" 2>/dev/null; }
qMissing=""
for want in '::Record::nameLength#' '::Record::bodyLength#' '::Record::nameLen#' '::Record::bodyLen#' 'dispositions calls=2 '; do
    qHas "$TMP/q3.tsv" "$want" || qMissing="$qMissing [stdfix $want]"
done
for want in '0/pipe.h::StringSink::drained#' 'a/log_test.cc::StringSource::left#' 'b/testutil.h::StringSource::used#' 'c/sink.cc::StringSink::filled#' 'dispositions calls=4 '; do
    qHas "$TMP/q4.tsv" "$want" || qMissing="$qMissing [tombfix $want]"
done
[ -z "$qMissing" ] && ok "(q0) presence: both census files name every fixture caller and count every size() call" \
    || no "(q0) presence guard:$qMissing — every (q) arm below would be vacuous"

# (q1) the defect; (q2) the in-repo qualified control
Q1="$( qMechs "$TMP/q3.tsv" '::Record::nameLength#' )"
Q1PIN="$( awk -F '\t' '$1 == "C" && index( $6, "::Record::nameLength#" ) && $7 == "size" && $8 ~ /^lib\/str\.h::string::size#[0-9]+$/' "$TMP/q3.tsv" 2>/dev/null )"
if [ "$Q1" != "receiver-rule" ] && [ -z "$Q1PIN" ]; then
    ok "(q1) std::string name_; name_.size() is NOT pinned to the in-repo string::size (mech=[${Q1:-declined}])"
else
    no "(q1) std::string name_; name_.size() pinned to the in-repo lib/str.h string::size (mech=[${Q1:-none}]) — a std:: field type named an in-repo class"
fi
Q2="$( awk -F '\t' '$1 == "C" && index( $6, "::Record::bodyLength#" ) && $7 == "size" { print $2 "|" $8 }' "$TMP/q3.tsv" 2>/dev/null )"
case "$Q2" in
    "receiver-rule|store/text.h::Text::size#"*) ok "(q2) control: store::Text body_; body_.size() still narrows to store/text.h Text::size (receiver-rule)" ;;
    *) no "(q2) control: store::Text body_; body_.size() lost its narrow to Text::size — an in-repo qualifier was refused: [${Q2:-no row}]" ;;
esac

# (q3) no HAS-A edge to the in-repo namesake; (q4) the in-repo qualified member keeps its edge
COMPOSE="$( "$BIN" "$FIX3" --around=Record --no-cache 2>/dev/null | grep -o '<compose>.*</compose>' )"
printf '%s' "$COMPOSE" | grep -qF 'name="name_"' \
    && no "(q3) HAS-A still draws Record → string for std::string name_: $COMPOSE" \
    || ok "(q3) no HAS-A edge from Record's std::string name_ to the in-repo string"
printf '%s' "$COMPOSE" | grep -qF '<field name="body_" type="Text" owner="Record" rel="creates"/>' \
    && ok "(q4) control: HAS-A keeps Record → Text for store::Text body_" \
    || no "(q4) control: HAS-A lost Record → Text for store::Text body_: [${COMPOSE:-no <compose> block}]"

# (q5) the member index reads the same field-type record: `name_.len` must not pin to string.len; (q6) body_.len still pins
STRLEN="$( "$BIN" "$FIX3" --uses=string.len --no-cache 2>/dev/null )"
for line in 6 8; do   # 6: `name_.len` (a bare receiver), 8: `this->name_.len` (through this) — both read the class#field entry
    USES5="$( printf '%s' "$STRLEN" | grep -oE "<u [^>]*p=\"app/rec.cpp:$line\"[^>]*/>" )"
    if [ -z "$USES5" ] || printf '%s' "$USES5" | grep -q 'owner_candidates='; then
        ok "(q5) --uses=string.len does not pin std::string name_'s .len read (app/rec.cpp:$line) to the in-repo string: [${USES5:-no row}]"
    else
        no "(q5) --uses=string.len PINS app/rec.cpp:$line (std::string name_.len) to the in-repo string: $USES5"
    fi
done
USES6="$( "$BIN" "$FIX3" --uses=Text.len --no-cache 2>/dev/null | grep -oE '<u [^>]*p="app/rec.cpp:7"[^>]*/>' )"
if [ -n "$USES6" ] && ! printf '%s' "$USES6" | grep -q 'owner_candidates='; then
    ok "(q6) control: --uses=Text.len still pins store::Text body_'s .len read (app/rec.cpp:7)"
else
    no "(q6) control: --uses=Text.len lost its pin on app/rec.cpp:7: [${USES6:-no row}]"
fi

# (q7) the tombstone survives in both record orders: no StringSource/StringSink contents_.size() narrows to Slice::size
for caller in '0/pipe.h::StringSink::drained#' 'a/log_test.cc::StringSource::left#' 'b/testutil.h::StringSource::used#' 'c/sink.cc::StringSink::filled#'; do
    M7="$( qMechs "$TMP/q4.tsv" "$caller" )"
    [ "$M7" != "receiver-rule" ] \
        && ok "(q7) tombstone: $caller contents_.size() is not narrowed (mech=[${M7:-declined}]) — same-named classes, contents_ typed std::string vs Slice&" \
        || no "(q7) tombstone lost: $caller contents_.size() narrowed by receiver-rule — the std field no longer tombstones StringSource/StringSink#contents_"
done

# (q8) determinism + cache transparency on the std fixture: the written scope rides the cached compose record
"$BIN" "$FIX3" --no-cache --pin-census="$TMP/q3b.tsv" >/dev/null 2>&1
rm -f "$TMP/qc"
"$BIN" "$FIX3" --cache="$TMP/qc" >/dev/null 2>&1
"$BIN" "$FIX3" --cache="$TMP/qc" --pin-census="$TMP/q3w.tsv" >/dev/null 2>&1
if [ -s "$TMP/q3.tsv" ] && cmp -s "$TMP/q3.tsv" "$TMP/q3b.tsv" && cmp -s "$TMP/q3.tsv" "$TMP/q3w.tsv"; then
    ok "(q8) stdfix census byte-identical: cold, cold again, and warm"
else
    no "(q8) stdfix census differs across runs or warm vs cold"; diff "$TMP/q3.tsv" "$TMP/q3w.tsv" | head -6
fi

# ── KNOWN GAP (help wanted: prompts/help-wanted/ts-literal-receivers.md) — issue #59, on receivers whose type is CERTAIN ──
# A built-in method called on a LITERAL binds an unrelated, same-named, never-imported user function — with the
# graph's ambiguity gauge at zero, so the answer reads as confident. `"a-b".replace(…)` can only be
# String.prototype.replace; today it binds src/unrelated.ts's `export function replace`. The arms below assert
# TODAY's behaviour, so they PASS now. Flipping them is the acceptance test for the prompt: no edge into
# unrelated.ts, and the call still COUNTED (a named, disclosed disposition — never a silent drop). A FAIL on a
# KNOWN GAP arm means the gap moved: rewrite that arm to assert the fixed behaviour, never delete it.
# The two CONTROLS are not gaps. They are TRUE edges any fix must keep: a typed user-object receiver, and a
# literal receiver whose method the repo itself defines on String.prototype (a literal CAN reach user code).
# Separate corpora on purpose: (h)'s ambiguous=6 is counted over $FIX and must not move.
LIT="$TMP/tslitfix"; OBJ="$TMP/tsobjfix"
mkdir -p "$LIT/src" "$OBJ/src"
cat >"$LIT/src/literals.ts" <<'EOF'
export function viaString(): string { return "a-b".replace(/-/g, " "); }
export function viaChain(): string[] { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n: number): string { return `n=${n}`.padStart(8); }
export function viaArray(): number[] { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s: string): boolean { return /x/.test(s); }
EOF
cat >"$LIT/src/unrelated.ts" <<'EOF'
export function replace(value: number): number { return value; }
export function split(value: number): number { return value; }
export function padStart(value: number): number { return value; }
export function map(value: number): number { return value; }
export function test(value: number): number { return value; }
EOF
cat >"$OBJ/src/rewriter.ts" <<'EOF'
export class Rewriter {
  replace(a: string, b: string): string { return a + b; }
}
EOF
cat >"$OBJ/src/user.ts" <<'EOF'
import { Rewriter } from "./rewriter";
export function viaObjectReceiver(r: Rewriter): string { return r.replace("a", "b"); }
EOF
cat >"$OBJ/src/proto.js" <<'EOF'
String.prototype.shout = function () { return "!"; };
function viaPrototypeExtension() { return "x".shout(); }
module.exports = { viaPrototypeExtension };
EOF
LITMAP="$( "$BIN" "$LIT" --no-cache 2>/dev/null )"
litMissing=""
for want in viaString viaChain viaTemplate viaArray viaRegex replace split padStart map test; do
    printf '%s' "$LITMAP" | grep -q "n=\"$want\"" || litMissing="$litMissing $want"
done
[ -z "$litMissing" ] && ok "(kg-ts) presence: every literal-receiver fixture symbol is indexed" \
    || no "(kg-ts) presence guard: fixture symbols not indexed:$litMissing — every arm below would be vacuous"
litGap(){  # litGap CALLER "LINE:NAME ..." — CALLER's literal-receiver calls each bind unrelated.ts:LINE, gauge at zero
    local out root want line name missed=""
    out="$( "$BIN" "$LIT" "--callees=src/literals.ts:$1" --no-cache 2>/dev/null )"
    root="$( printf '%s' "$out" | grep -oE '<callees [^>]*>' | head -1 )"
    if [ -z "$root" ]; then
        no "(kg-ts) $1: no <callees> root — the arm cannot observe the gap"; return
    fi
    for want in $2; do
        line="${want%%:*}"; name="${want#*:}"
        printf '%s' "$out" | grep -q "n=\"$name\" p=\"src/unrelated.ts:$line\"" || missed="$missed .$name()"
    done
    if [ -z "$missed" ] && printf '%s' "$root" | grep -q 'graph_ambiguous="0"'; then
        ok "KNOWN GAP (help wanted: prompts/help-wanted/ts-literal-receivers.md): $1's literal-receiver call(s) bind unrelated.ts ($2) with graph_ambiguous=\"0\" — flipping this is the acceptance test"
    else
        no "KNOWN GAP (help wanted: prompts/help-wanted/ts-literal-receivers.md) MOVED for $1:${missed:- the gauge} no longer binds unrelated.ts confidently — if the fix landed, rewrite this arm to assert no edge AND a counted disposition: $root"
    fi
}
litGap viaString   "1:replace"
litGap viaChain    "1:replace 2:split"
litGap viaTemplate "3:padStart"
litGap viaArray    "4:map"
litGap viaRegex    "5:test"
OBJOUT="$( "$BIN" "$OBJ" --callees=src/user.ts:viaObjectReceiver --no-cache 2>/dev/null )"
printf '%s' "$OBJOUT" | grep -q 'n="replace" p="src/rewriter.ts:2"' \
    && ok "(kg-ts control) a typed user-object receiver r.replace() keeps its edge to Rewriter.replace (rewriter.ts:2)" \
    || no "(kg-ts control) viaObjectReceiver lost its edge to Rewriter.replace — a literal-receiver rule over-reached: $( printf '%s' "$OBJOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
PROTOOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaPrototypeExtension --no-cache 2>/dev/null )"
printf '%s' "$PROTOOUT" | grep -q 'n="shout" p="src/proto.js:1"' \
    && ok "(kg-ts control) \"x\".shout() keeps its edge to the repo's own String.prototype.shout (proto.js:1) — a literal receiver can reach user code" \
    || no "(kg-ts control) \"x\".shout() lost its edge to String.prototype.shout — a literal-receiver veto must let prototype extensions through: $( printf '%s' "$PROTOOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"

# ── (i) determinism — narrowed candidate order must be byte-stable run-to-run ──
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "(i) deterministic (fieldfix map byte-identical across two runs)" \
    || { no "(i) non-deterministic fieldfix map"; diff "$TMP/m1" "$TMP/m2" | head -6; }

# ── (j) cache transparency — field-type facts round-trip the incremental cache: warm == cold ──
rm -f "$TMP/cc"
"$BIN" "$FIX" --cache="$TMP/cc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/cc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null && ok "(j) cache-transparent (warm == cold)" \
    || { no "(j) cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
