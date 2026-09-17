#!/usr/bin/env bash
# rubyinheritcheck.sh — gate for Ruby INHERITANCE edges: `class Child < Parent` is an IS-A edge, so it
# reaches the lego (interface/implementor) view and the resolver's base walk.
#
# What was missing. ingest_relations.h::captureBases turns a class's base clause into inherit RawRefs
# (role Extends), which buildGraph reads into the CHA-lite name graph chaUp/chaDown — the table Rule 1's
# `super`/implicit-self walk and Rules 2b/2c's methodOnTypeOrBases probe after a type's OWN method set
# misses. Ruby reached none of it. The clause kind `superclass` was already in captureBases' table (Java
# spells its `extends` clause with the same node name), but isBaseTypeNode's list of base-TYPE node kinds
# had no entry Ruby uses: Ruby names a base with (constant) — `class Child < Parent` — or with
# (scope_resolution) — `class Derived < Space::Base`. So Ruby corpora carried no inheritance edges at
# all: `--lego` listed no implementors, and `Child.build` could not reach a `build` defined on Parent.
#
# That second half is what held the gem numbers down in the constant-receiver round
# (test/rubyrecvnarrowcheck.sh, floor (a)): a Rails gem reaches its class methods up an
# ActiveRecord::Base hierarchy, and without chaUp the receiver rule can only see a type's OWN methods.
#
# The rule: a Ruby base is the (constant) or (scope_resolution) child of the class's `superclass` clause,
# named by its FINAL segment (`Space::Base` → `Base`), which is how chaUp and byName key every other
# language's bases. Everything else about captureBases is unchanged.
#
# Stated floors, pinned below so each stays a decision:
#   (a) a COMPUTED superclass (`class Dynamic < Struct.new( :a )`) is a call, not a constant — no edge.
#   (b) a MIXIN (`include Helper` / `extend` / `prepend`) is NOT an inheritance edge in this round. It is
#       a receiver-less call in the class BODY, not a clause — the same shape, and the same decision, as
#       PHP's in-body `use SomeTrait;` (captureBases' own header). Ruby's ancestor chain really does hold
#       included modules, so this is a real residue and a later round's subject, not a claim that it is
#       not inheritance.
#   (c) an OUT-OF-TREE base (`class Rec < ActiveRecord::Base`) mints no edge and no implementor row.
#
# Usage:  test/rubyinheritcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyinheritcheck.sh
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
FIX="$DIR/fix"; mkdir -p "$FIX"

cat > "$FIX/h.rb" <<'RUBY'
class Parent
  def self.build
    1
  end

  def shared_helper( n )
    n
  end

  def bare_helper
    2
  end
end

class Child < Parent
  def use_inherited
    shared_helper( 1 )
  end

  def use_bare
    bare_helper
  end
end

class GrandChild < Child
end

module Space
  class Base
    def self.make
      3
    end
  end
end

class Derived < Space::Base
end

class Rec < ActiveRecord::Base
end

class Dynamic < Struct.new( :a )
end

module Helper
  def helped
    4
  end
end

class Mixed
  include Helper
end

class Unrelated
  def self.build
    9
  end

  def self.make
    9
  end

  def shared_helper( n )
    n
  end

  def bare_helper
    9
  end
end
RUBY

cat > "$FIX/caller.rb" <<'RUBY'
class Caller
  def call_inherited
    Child.build
  end

  def call_two_levels
    GrandChild.build
  end

  def call_scoped_base
    Derived.make
  end

  def call_mixin
    Mixed.new.helped
  end
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

SPLIT="$DIR/split"; sed 's/></>\n</g' "$MAP" >"$SPLIT"
rowOf(){ awk -v pat="$1" '$0 ~ pat{f=1;print;next} /^<s /{f=0} f' "$SPLIT"; }
edgesTo(){ echo "$1" | grep -c "<c n=\"$2\""; }
lego(){ "$BIN" "$FIX" --no-cache --lego="$1" 2>/dev/null | sed 's/></>\n</g'; }

echo "=== the fixture parsed the way this gate assumes ==="
for want in 'n="Parent"' 'n="Child"' 'n="GrandChild"' 'n="Base" sc="Space"' 'n="Derived"' 'n="Unrelated"'; do
    grep -q "$want" "$SPLIT" && ok "indexed: $want" \
        || no "the fixture did not index $want"
done

echo "=== a Ruby subclass is an IMPLEMENTOR in the lego view ==="
LP="$( lego Parent )"
echo "$LP" | grep -q '<impl n="Child"' && ok "--lego=Parent lists Child" \
    || no "--lego=Parent lists no Child: $( echo "$LP" | grep -E '^<(iface|impl)' | tr '\n' ' ' )"
LC="$( lego Child )"
echo "$LC" | grep -q '<impl n="GrandChild"' && ok "--lego=Child lists GrandChild (a second level is its own direct edge)" \
    || no "--lego=Child lists no GrandChild: $( echo "$LC" | grep -E '^<(iface|impl)' | tr '\n' ' ' )"
LB="$( lego Base )"
echo "$LB" | grep -q '<impl n="Derived"' && ok "--lego=Base lists Derived (a scope_resolution base names its FINAL segment)" \
    || no "--lego=Base lists no Derived: $( echo "$LB" | grep -E '^<(iface|impl)' | tr '\n' ' ' )"

echo "=== the base walk reaches a method the receiver's own class does not define ==="
CI="$( rowOf 'n="call_inherited" ' )"
[ "$( edgesTo "$CI" build )" -eq 1 ] && ok "Child.build → exactly one edge named build (Parent::build through the base walk)" \
    || no "Child.build produced $( edgesTo "$CI" build ) build edges: $CI"
CLP="$( "$BIN" "$FIX" --no-cache --callers=Parent::build 2>/dev/null )"
echo "$CLP" | grep -q 'n="call_inherited"' && ok "--callers=Parent::build lists call_inherited" \
    || no "--callers=Parent::build does not list call_inherited"
CLU="$( "$BIN" "$FIX" --no-cache --callers=Unrelated::build 2>/dev/null )"
echo "$CLU" | grep -q 'n="call_inherited"' && no "--callers=Unrelated::build lists call_inherited — the walk took an unrelated same-named def" || ok "--callers=Unrelated::build does not list call_inherited"

CT="$( rowOf 'n="call_two_levels" ' )"
[ "$( edgesTo "$CT" build )" -eq 1 ] && ok "GrandChild.build → exactly one edge (the walk crosses TWO levels)" \
    || no "GrandChild.build produced $( edgesTo "$CT" build ) build edges: $CT"
CS="$( rowOf 'n="call_scoped_base" ' )"
[ "$( edgesTo "$CS" make )" -eq 1 ] && ok "Derived.make → exactly one edge (base written as Space::Base)" \
    || no "Derived.make produced $( edgesTo "$CS" make ) make edges: $CS"
CLM="$( "$BIN" "$FIX" --no-cache --callers=Base::make 2>/dev/null )"
echo "$CLM" | grep -q 'n="call_scoped_base"' && ok "--callers=Base::make lists call_scoped_base" \
    || no "--callers=Base::make does not list call_scoped_base"

echo "=== an implicit-self call inside a subclass reaches the superclass method (Rule 1's bare arm) ==="
UI="$( rowOf 'n="use_inherited" ' )"
[ "$( edgesTo "$UI" shared_helper )" -eq 1 ] && ok "a bare shared_helper inside Child → exactly one edge (Parent#shared_helper)" \
    || no "a bare shared_helper inside Child produced $( edgesTo "$UI" shared_helper ) edges: $UI"
CLS="$( "$BIN" "$FIX" --no-cache --callers=Parent::shared_helper 2>/dev/null )"
echo "$CLS" | grep -q 'n="use_inherited"' && ok "--callers=Parent::shared_helper lists use_inherited" \
    || no "--callers=Parent::shared_helper does not list use_inherited"

UB="$( rowOf 'n="use_bare" ' )"
echo "$UB" | grep -q '<c ' \
    && no "a bare, parenthesis-less bare_helper minted an edge — queries/ruby/tags.scm captures the (call) form only, and a no-arg receiver-less call parses as (identifier): if that changed, say so HERE and in the tags.scm header" \
    || ok "a bare, parenthesis-less call still mints nothing (an extraction floor of tags.scm, not of this round)"

echo "=== floors (a) computed base, (b) mixins, (c) out-of-tree base ==="
lego Struct  | grep -q '<impl n="Dynamic"' && no "class Dynamic < Struct.new( :a ) minted an inheritance edge — a computed superclass is a call, not a constant (floor (a))" \
    || ok "a computed superclass mints no edge (floor (a), stated)"
LH="$( lego Helper )"
echo "$LH" | grep -q '<impl n="Mixed"' && no "include Helper minted an inheritance edge — that is a later round, and it moves the CHA fan-out: say so HERE, in captureBases' header and in CHANGELOG.md (floor (b))" \
    || ok "include Helper is not an inheritance edge (floor (b), stated)"
CM="$( rowOf 'n="call_mixin" ' )"
echo "$CM" | grep -q '<c n="helped"' && ok "…and Mixed.new.helped still edges the one helped def through the name ladder (a floor deletes nothing)" \
    || no "Mixed.new.helped lost its edge: $CM"
LA="$( lego ActiveRecord::Base )"
echo "$LA" | grep -q '<impl n="Rec"' && no "class Rec < ActiveRecord::Base minted an implementor row for a base this tree never defines (floor (c))" \
    || ok "an out-of-tree base mints no implementor row (floor (c), stated)"

echo "=== determinism, warm == cold, and --deps is untouched ==="
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
    || no "the warm cache disagrees with the cold run"

echo "=== mutation: drop the base clause → the inherited pin must vanish ==="
MUT="$DIR/mut"; mkdir -p "$MUT"; cp "$FIX/caller.rb" "$MUT/caller.rb"
sed 's/^class Child < Parent$/class Child/' "$FIX/h.rb" >"$MUT/h.rb"
grep -q '^class Child$' "$MUT/h.rb" || no "mutation did not apply"
MLP="$( "$BIN" "$MUT" --no-cache --lego=Parent 2>/dev/null )"
echo "$MLP" | grep -q '<impl n="Child"' && no "mutation: --lego=Parent still lists Child after the base clause was removed" || ok "mutation: Child is no longer an implementor of Parent"
MQ="$( "$BIN" "$MUT" --no-cache 2>/dev/null | sed 's/></>\n</g' | awk '/n="call_inherited" /{f=1;print;next} /^<s /{f=0} f' )"
[ "$( echo "$MQ" | grep -c '<c n="build"' )" -eq 2 ] \
    && ok "mutation: Child.build is an honest 2-way split again — the pin was the inheritance edge and nothing else" \
    || no "mutation: Child.build produced $( echo "$MQ" | grep -c '<c n="build"' ) build edges with no base clause: $MQ"
MCU="$( "$BIN" "$MUT" --no-cache --callers=Unrelated::build 2>/dev/null )"
echo "$MCU" | grep -q 'n="call_inherited"' && ok "mutation: …and Unrelated::build is back among its callers" \
    || no "mutation: Unrelated::build does not list call_inherited: $( echo "$MCU" | grep -o '<callers[^>]*' )"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
