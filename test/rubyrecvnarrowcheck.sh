#!/usr/bin/env bash
# rubyrecvnarrowcheck.sh — gate for Ruby CONSTANT-RECEIVER call narrowing: `Calc.add(1,2)`,
# `Outer::Engine.run(3)`, `::Top.ping`, `Util.format(5)` resolve to the method defined under THAT
# constant, instead of splitting across every same-named method in the corpus.
#
# What was wrong, and where. resolve.h's Rule 2c (docs/EVALS.md "Phase 4b") already says "the receiver
# token IS the type": a `Cls.m(…)` call whose receiver names a class-like definition resolves against
# that class. It never fired for Ruby, because ingest_binds.h::classifyReceiver accepted a receiver node
# of kind (identifier) only. Ruby's class/module receiver is its OWN node kind — (constant) for `Calc`,
# (scope_resolution) for `Outer::Engine` and `::Top` — so every such call classified RecvKind::None,
# receiverOf then stamped it FieldOfVar with an empty recvVar ("a member access, receiver undecidable"),
# and the resolver fell through to the §2a name spray. Measured before the fix on the four Ruby corpora:
# activerecord 8.1.3 lib = 9,116 edges with ambiguous=1,496 and declined=4,576; a 4,683-file Rails app
# = 23,784 edges with declined=12,485. Constant-receiver call SITES in that same text: 3,176 and 9,499.
#
# The rule, stated so it can be disagreed with:
#   * The receiver's FINAL constant segment is the type name — `Outer::Engine` → `Engine`, `::Top` → `Top`.
#     That is the same final-segment convention Rule 2's type bindings already use (`ns::Foo` → `Foo`),
#     and it meets Symbol::scope, which is the IMMEDIATE enclosing name by design (ingest_sidecap.h).
#   * A (scope_resolution) whose `name:` child is not a (constant) is not a constant receiver at all.
#     `Outer::run(1)` is not that shape — tree-sitter-ruby parses it as an ordinary (call) with receiver
#     (constant) `Outer`, exactly like `Outer.run(1)`, and both narrow through the (constant) arm.
#   * A Ruby MODULE is a receiver of class methods as much as a class is (`Util.format`). `@definition.module`
#     maps to SymKind::Other (ingest_crawl.h::defKind) for every language, and in Ruby that kind is reached
#     by nothing else — queries/ruby/tags.scm emits class, module, method and constant, and the other three
#     have kinds of their own — so buildGraph's Rule 2c class-name set takes Ruby's SymKind::Other symbols.
#   * A MISS never deletes an edge: the receiver naming no in-repo definition (`Time.now`), or naming one
#     that does not define the callee, degrades to the unchanged honest ladder.
#
# Stated floors, pinned below so each stays a decision rather than an accident:
#   (a) LIFTED at parser version 98 by test/rubyinheritcheck.sh (`class Child < Parent` now mints an
#       inherit ref, so chaUp holds Ruby and the base walk runs). The arm below is kept, INVERTED: it
#       now asserts `Child.build` pins to Parent::build, and it is the tripwire that fires if Ruby ever
#       loses its inheritance edges again.
#   (b) Matching is by FINAL SEGMENT, so two classes with the same last name in different namespaces
#       both defining the callee keep BOTH candidates (an honest split), exactly as Rule 2c documents.
#   (c) A variable receiver (`c.scale`) and a chained one (`Calc.new.scale`) are untouched by this round.
#
# Usage:  test/rubyrecvnarrowcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyrecvnarrowcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh. Self-contained via mktemp.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
FIX="$DIR/fix"; mkdir -p "$FIX"   # the corpus — outputs live in $DIR, never here (the crawl census would count them)

cat > "$FIX/r.rb" <<'RUBY'
class Calc
  def self.add( a, b )
    a + b
  end

  def scale( n )
    n * 2
  end
end

class Tally
  def self.add( a, b )
    a - b
  end

  def self.report
    0
  end

  def scale( n )
    n
  end
end

module Outer
  class Engine
    def self.run( x )
      x
    end
  end
end

module Other
  class Motor
    def self.run( x )
      x
    end
  end
end

class Top
  def self.ping
    1
  end
end

class Radar
  def self.ping
    2
  end
end

module Util
  def self.format( x )
    x
  end
end

class Printer
  def self.format( x )
    x
  end
end

module Left
  class Shared
    def self.go
      1
    end
  end
end

module Right
  class Shared
    def self.go
      2
    end
  end
end

class Parent
  def self.build
    1
  end
end

class Child < Parent
end

class Unrelated
  def self.build
    2
  end
end
RUBY

cat > "$FIX/caller.rb" <<'RUBY'
class Caller
  def qualified_call
    Calc.add( 1, 2 )
  end

  def scoped_call
    Outer::Engine.run( 3 )
  end

  def absolute_call
    ::Top.ping
  end

  def module_call
    Util.format( 5 )
  end

  def colon_call
    Util::format( 6 )
  end

  def external_call
    Time.now
  end

  def inherited_call
    Child.build
  end

  def missing_method_call
    Calc.report
  end

  def same_segment_call
    Left::Shared.go
  end

  def instance_call( c )
    c.scale( 7 )
  end

  def chain_call
    Calc.new.scale( 8 )
  end
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

SPLIT="$DIR/split"; sed 's/></>\n</g' "$MAP" >"$SPLIT"
rowOf(){ awk -v pat="$1" '$0 ~ pat{f=1;print;next} /^<s /{f=0} f' "$SPLIT"; }   # an <s> row + its <c> children
edgesTo(){ echo "$1" | grep -c "<c n=\"$2\""; }                                  # how many <c> rows of that name

echo "=== the fixture parsed the way this gate assumes ==="
for want in 'n="add" sc="Calc"' 'n="add" sc="Tally"' 'n="run" sc="Engine"' 'n="run" sc="Motor"' \
            'n="ping" sc="Top"' 'n="ping" sc="Radar"' 'n="format" sc="Util"' 'n="format" sc="Printer"' \
            'n="go" sc="Shared"' 'n="build" sc="Parent"' 'n="build" sc="Unrelated"'; do
    grep -q "$want" "$SPLIT" && ok "indexed: $want" \
        || no "the fixture did not index $want — this gate's arms below are meaningless until it does"
done
grep -q 'n="go" sc="Shared" overloads="2"' "$SPLIT" \
    && ok "Left::Shared::go and Right::Shared::go both carry sc=\"Shared\" and merge into one overloads=\"2\" row (the final-segment collision floor (b) is real)" \
    || no "expected one n=\"go\" sc=\"Shared\" overloads=\"2\" row: $( grep 'n="go"' "$SPLIT" | head -2 | tr '\n' ' ' )"

echo "=== a CONSTANT receiver pins the call to that constant's method ==="
Q="$( rowOf 'n="qualified_call" ' )"
[ "$( edgesTo "$Q" add )" -eq 1 ] && ok "Calc.add( 1, 2 ) → exactly one edge named add" \
    || no "Calc.add( 1, 2 ) produced $( edgesTo "$Q" add ) add edges — the constant receiver did not narrow: $Q"
echo "$Q" | grep -q 'prov="split"' && no "qualified_call still carries prov=\"split\" — the receiver was not read" || ok "…with no prov=\"split\" on it"
echo "$Q" | grep -q 'amb=' && no "qualified_call still carries amb= — the call stayed ambiguous" || ok "…and no amb= on the row"

CL="$( "$BIN" "$FIX" --no-cache --callers=Calc::add 2>/dev/null )"
echo "$CL" | grep -q 'n="qualified_call"' && ok "--callers=Calc::add lists qualified_call" \
    || no "--callers=Calc::add does not list qualified_call: $( echo "$CL" | grep -o '<callers[^>]*' )"
CT="$( "$BIN" "$FIX" --no-cache --callers=Tally::add 2>/dev/null )"
echo "$CT" | grep -q 'n="qualified_call"' && no "--callers=Tally::add STILL lists qualified_call — the wrong half of the split survived" || ok "--callers=Tally::add does not list qualified_call"
echo "$CT" | grep -q 'count="0"' && ok "…and reports count=\"0\" (Tally::add has no caller in this tree)" \
    || no "--callers=Tally::add did not report count=0: $( echo "$CT" | grep -o '<callers[^>]*' )"

echo "=== a SCOPE_RESOLUTION receiver pins by its FINAL segment ==="
S="$( rowOf 'n="scoped_call" ' )"
[ "$( edgesTo "$S" run )" -eq 1 ] && ok "Outer::Engine.run( 3 ) → exactly one edge named run" \
    || no "Outer::Engine.run( 3 ) produced $( edgesTo "$S" run ) run edges: $S"
CE="$( "$BIN" "$FIX" --no-cache --callers=Engine::run 2>/dev/null )"
echo "$CE" | grep -q 'n="scoped_call"' && ok "--callers=Engine::run lists scoped_call" \
    || no "--callers=Engine::run does not list scoped_call"
CM="$( "$BIN" "$FIX" --no-cache --callers=Motor::run 2>/dev/null )"
echo "$CM" | grep -q 'n="scoped_call"' && no "--callers=Motor::run lists scoped_call — Outer::Engine reached Other::Motor" || ok "--callers=Motor::run does not list scoped_call"

A="$( rowOf 'n="absolute_call" ' )"
[ "$( edgesTo "$A" ping )" -eq 1 ] && ok "::Top.ping → exactly one edge named ping (the absolute spelling has no scope: child)" \
    || no "::Top.ping produced $( edgesTo "$A" ping ) ping edges: $A"
CP="$( "$BIN" "$FIX" --no-cache --callers=Top::ping 2>/dev/null )"
echo "$CP" | grep -q 'n="absolute_call"' && ok "--callers=Top::ping lists absolute_call" \
    || no "--callers=Top::ping does not list absolute_call"
CR="$( "$BIN" "$FIX" --no-cache --callers=Radar::ping 2>/dev/null )"
echo "$CR" | grep -q 'n="absolute_call"' && no "--callers=Radar::ping lists absolute_call — ::Top reached Radar" || ok "--callers=Radar::ping does not list absolute_call"

echo "=== a MODULE is a receiver too (Util.format, and the :: spelling of the same call) ==="
M="$( rowOf 'n="module_call" ' )"
[ "$( edgesTo "$M" format )" -eq 1 ] && ok "Util.format( 5 ) → exactly one edge named format" \
    || no "Util.format( 5 ) produced $( edgesTo "$M" format ) format edges — a module receiver did not narrow: $M"
C="$( rowOf 'n="colon_call" ' )"
[ "$( edgesTo "$C" format )" -eq 1 ] && ok "Util::format( 6 ) → exactly one edge named format (parsed as an ordinary (call) with a (constant) receiver)" \
    || no "Util::format( 6 ) produced $( edgesTo "$C" format ) format edges: $C"
CU="$( "$BIN" "$FIX" --no-cache --callers=Util::format 2>/dev/null )"
echo "$CU" | grep -q 'count="2"' && ok "--callers=Util::format reports count=\"2\" (module_call and colon_call)" \
    || no "--callers=Util::format did not report count=2: $( echo "$CU" | grep -o '<callers[^>]*' )"
CPR="$( "$BIN" "$FIX" --no-cache --callers=Printer::format 2>/dev/null )"
echo "$CPR" | grep -q 'count="0"' && ok "--callers=Printer::format reports count=\"0\"" \
    || no "--callers=Printer::format did not report count=0: $( echo "$CPR" | grep -o '<callers[^>]*' )"

echo "=== a MISS never deletes an edge, and never invents one ==="
E="$( rowOf 'n="external_call" ' )"
echo "$E" | grep -q '<c ' && no "Time.now minted an edge — neither Time nor now is defined in this tree: $E" || ok "Time.now → no edge (out-of-tree receiver, unchanged)"
MM="$( rowOf 'n="missing_method_call" ' )"
[ "$( edgesTo "$MM" report )" -eq 1 ] && ok "Calc.report → the one report def still resolves through the honest name ladder (the narrow missed, it did not veto)" \
    || no "Calc.report lost its edge — a narrow MISS must degrade to the ladder, never delete: $MM"

echo "=== the base walk: a method on the SUPERCLASS narrows too (floor (a), lifted at parser version 98) ==="
I="$( rowOf 'n="inherited_call" ' )"
[ "$( edgesTo "$I" build )" -eq 1 ] && ok "Child.build → exactly one edge (Parent::build, through the inheritance edge captureBases now mints for Ruby)" \
    || no "Child.build produced $( edgesTo "$I" build ) build edges — if Ruby LOST its inheritance edges, that is the regression: see ingest_relations.h::isBaseTypeNode's Ruby arm and test/rubyinheritcheck.sh: $I"
CB="$( "$BIN" "$FIX" --no-cache --callers=Parent::build 2>/dev/null )"
echo "$CB" | grep -q 'n="inherited_call"' && ok "--callers=Parent::build lists inherited_call" \
    || no "--callers=Parent::build does not list inherited_call"
CBU="$( "$BIN" "$FIX" --no-cache --callers=Unrelated::build 2>/dev/null )"
echo "$CBU" | grep -q 'n="inherited_call"' && no "--callers=Unrelated::build lists inherited_call — the walk took an unrelated same-named def" || ok "--callers=Unrelated::build does not list inherited_call"

echo "=== floor (b): two same-final-segment classes both defining the callee keep BOTH (honest split) ==="
SS="$( rowOf 'n="same_segment_call" ' )"
[ "$( edgesTo "$SS" go )" -eq 2 ] && ok "Left::Shared.go → both Shared::go defs (final-segment matching; floor, stated)" \
    || no "Left::Shared.go produced $( edgesTo "$SS" go ) go edges — narrowing to ONE of them needs the Ruby constant index, and a claim in this gate: $SS"

echo "=== floor (c): variable and chained receivers are untouched by this round ==="
IC="$( rowOf 'n="instance_call" ' )"
[ "$( edgesTo "$IC" scale )" -eq 2 ] && ok "c.scale( 7 ) → unchanged 2-way split (a variable receiver has no type in Ruby; floor, stated)" \
    || no "c.scale( 7 ) produced $( edgesTo "$IC" scale ) scale edges — this round must not move a variable receiver: $IC"
CC="$( rowOf 'n="chain_call" ' )"
[ "$( edgesTo "$CC" scale )" -eq 2 ] && ok "Calc.new.scale( 8 ) → unchanged 2-way split (the receiver is a CALL, undecidable in one hop; floor, stated)" \
    || no "Calc.new.scale( 8 ) produced $( edgesTo "$CC" scale ) scale edges: $CC"
echo "$CC" | grep -q '<c n="new"' && no "Calc.new minted an edge to a new this tree never defines" || ok "…and Calc.new mints no edge (no def named new exists here)"

echo "=== determinism, and the warm cache agrees with the cold one ==="
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
cmp -s "$MAP" "$DIR/b.xml" && ok "byte-identical across two --no-cache runs" \
    || no "output differs across runs"
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/cold.xml" 2>"$DIR/cold.err"
then
    no "the cold cache run exited non-zero: $( head -3 "$DIR/cold.err" )"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/warm.xml" 2>"$DIR/warm.err"
then
    no "the warm cache run exited non-zero: $( head -3 "$DIR/warm.err" )"
fi
cmp -s "$DIR/cold.xml" "$DIR/warm.xml" && ok "warm run == cold run" \
    || no "the warm cache disagrees with the cold run — the parser version did not move with the extraction change"

echo "=== mutation: the edge follows the RECEIVER, not the caller's file or its order ==="
MUT="$DIR/mut"; mkdir -p "$MUT"; cp "$FIX/r.rb" "$MUT/r.rb"
sed 's/    Calc\.add( 1, 2 )/    Tally.add( 1, 2 )/' "$FIX/caller.rb" >"$MUT/caller.rb"
grep -q 'Tally.add( 1, 2 )' "$MUT/caller.rb" || no "mutation did not apply"
MQ="$( "$BIN" "$MUT" --no-cache 2>/dev/null | sed 's/></>\n</g' | awk '/n="qualified_call" /{f=1;print;next} /^<s /{f=0} f' )"
MCL="$( "$BIN" "$MUT" --no-cache --callers=Tally::add 2>/dev/null )"
echo "$MCL" | grep -q 'n="qualified_call"' && ok "mutation: Tally.add → --callers=Tally::add now lists qualified_call" \
    || no "mutation: the edge did not follow the receiver: $MQ"
MCC="$( "$BIN" "$MUT" --no-cache --callers=Calc::add 2>/dev/null )"
echo "$MCC" | grep -q 'n="qualified_call"' && no "mutation: --callers=Calc::add still lists qualified_call — the pin is not reading the receiver" || ok "mutation: Calc::add no longer lists it"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
