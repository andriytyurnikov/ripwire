#!/usr/bin/env bash
# rubydescribedclasscheck.sh — gate for RSpec's `described_class` as a CONSTANT receiver: inside
# `RSpec.describe Calc do … end`, `described_class.m1( 1 )` is `Calc.m1( 1 )`, so it pins to Calc::m1 through the
# same Rule 2c arm a written `Calc.m1( 1 )` takes (#267), instead of declining.
#
# Why it matters: a spec's calls are the test→code edges tested=, --seams and --test-gate read. `described_class`
# is how RSpec spells the class under test (902 uses in one measured Rails app's spec/, 4216 in another), and it is
# a bare (identifier) receiver no binding names, so every such call declined and the spec reached nothing.
#
# The rule is RSpec's own (rspec-core 3.13, Metadata::ExampleGroupHash#described_class): a group's described class
# is its FIRST description argument unless that is nil or a String; otherwise it is the parent group's. So the
# INNERMOST enclosing example group whose first argument is a constant wins, and a string-described group passes
# its parent's through. An example group is a call of describe/context (and their x/f and feature spellings)
# with no receiver or the receiver `RSpec`, that carries a block.
#
# Stated floors, pinned below so each stays a decision:
#   (a) a CHAINED receiver (`described_class.new.m_chain`) is untouched — the same one-hop bound as #267's
#       `Calc.new.scale`: the receiver is a call, not a constant.
#   (b) a group with no constant (`RSpec.describe "no class"`, `RSpec.describe :sym`) names no class, so
#       `described_class` there is left exactly as it was.
#   (c) a `describe` call on any other receiver (`Docs.describe Calc do`) is not an RSpec example group.
#   (d) `subject` — the implicit `described_class.new` — is NOT modeled in this round: an explicit `subject { … }`
#       can be anything, and telling the two apart is its own round.
#
# Usage:  test/rubydescribedclasscheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubydescribedclasscheck.sh
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
FIX="$DIR/fix"; mkdir -p "$FIX/lib" "$FIX/spec"

# Every method name is defined on TWO classes, so an unpinned call is a split or a decline and a pinned one names
# exactly one class. Each case below uses its own name: a spec's calls all land in one <file-scope> owner.
cat > "$FIX/lib/calc.rb" <<'RUBY'
class Calc
  def self.m_top( a )
    a
  end

  def self.m_str( a )
    a
  end

  def self.m_ctx( a )
    a
  end

  def self.m_inner( a )
    a
  end

  def self.m_none( a )
    a
  end

  def self.m_sym( a )
    a
  end

  def self.m_docs( a )
    a
  end

  def m_chain
    1
  end
end

class Tally
  def self.m_top( a )
    a
  end

  def self.m_str( a )
    a
  end

  def self.m_ctx( a )
    a
  end

  def self.m_inner( a )
    a
  end

  def self.m_none( a )
    a
  end

  def self.m_sym( a )
    a
  end

  def self.m_docs( a )
    a
  end

  def m_chain
    2
  end
end

module Outer
  class Engine
    def self.e_run
      1
    end
  end
end

class Other
  def self.e_run
    2
  end
end

module Docs
  def self.describe( what )
    yield
  end
end
RUBY

cat > "$FIX/spec/calc_spec.rb" <<'RUBY'
RSpec.describe Calc do
  it "pins the top-level group's class" do
    described_class.m_top( 1 )
  end

  describe "a string group" do
    it "passes its parent's class through" do
      described_class.m_str( 1 )
    end
  end

  context "a context" do
    it "passes its parent's class through too" do
      described_class.m_ctx( 1 )
    end
  end

  describe Tally do
    it "takes the innermost constant" do
      described_class.m_inner( 1 )
    end
  end

  it "leaves a chained receiver alone" do
    described_class.new.m_chain
  end
end
RUBY

cat > "$FIX/spec/engine_spec.rb" <<'RUBY'
describe Outer::Engine do
  it { described_class.e_run }
end
RUBY

cat > "$FIX/spec/noclass_spec.rb" <<'RUBY'
RSpec.describe "no class" do
  it { described_class.m_none( 1 ) }
end

RSpec.describe :sym do
  it { described_class.m_sym( 1 ) }
end
RUBY

cat > "$FIX/spec/docs_spec.rb" <<'RUBY'
Docs.describe Calc do
  described_class.m_docs( 1 )
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

# calls ROOT SYM SPEC — 0 when --callers=SYM lists SPEC's <file-scope> as a caller, 1 when it does not, and a FAIL (2)
# when the run itself failed: an absence arm must never read a crashed run as "not a caller".
calls(){
    if ! "$BIN" "$1" --no-cache --callers="$2" >"$DIR/c.out" 2>"$DIR/c.err"
    then
        no "--callers=$2 exited non-zero: $( head -3 "$DIR/c.err" )"
        return 2
    fi
    sed 's/></>\n</g' "$DIR/c.out" | grep -q "p=\"spec/$3:"
}
# pins SPEC METHOD CLASS OTHER WHY — SPEC's call reaches CLASS::METHOD and not OTHER::METHOD
pins(){
    local hit=1 miss=1
    calls "$FIX" "$3::$2" "$1"; hit=$?
    calls "$FIX" "$4::$2" "$1"; miss=$?
    if [ "$hit" -eq 2 ] || [ "$miss" -eq 2 ]
    then
        return
    fi
    if [ "$hit" -eq 0 ] && [ "$miss" -eq 1 ]
    then
        ok "$1: described_class.$2 → $3::$2 alone ($5)"
    else
        no "$1: described_class.$2 — $3::$2 caller=$( [ "$hit" -eq 0 ] && echo yes || echo no ), $4::$2 caller=$( [ "$miss" -eq 0 ] && echo yes || echo no ) — want $3 alone ($5)"
    fi
}
# untouched SPEC METHOD WHY — SPEC's call is NOT pinned to Calc alone: Calc and Tally answer the same
untouched(){
    local a=1 b=1
    calls "$FIX" "Calc::$2" "$1"; a=$?
    calls "$FIX" "Tally::$2" "$1"; b=$?
    if [ "$a" -eq 2 ] || [ "$b" -eq 2 ]
    then
        return
    fi
    [ "$a" -eq "$b" ] && ok "$1: described_class.$2 is not pinned to one class ($3)" \
        || no "$1: described_class.$2 reaches Calc=$( [ "$a" -eq 0 ] && echo yes || echo no ) Tally=$( [ "$b" -eq 0 ] && echo yes || echo no ) — $3"
}

echo "=== described_class is the innermost constant-described group's class ==="
pins calc_spec.rb   m_top   Calc   Tally "RSpec.describe Calc do"
pins calc_spec.rb   m_str   Calc   Tally "a string-described group passes its parent's class through"
pins calc_spec.rb   m_ctx   Calc   Tally "so does a string-described context"
pins calc_spec.rb   m_inner Tally  Calc  "a nested describe Tally is the innermost constant — RSpec's own rule"
pins engine_spec.rb e_run   Engine Other "a bare describe, and a scope_resolution constant named by its final segment"

echo "=== floors (a) chained, (b) no constant, (c) not RSpec — each left exactly as it was ==="
untouched calc_spec.rb    m_chain "described_class.new.m_chain — the receiver is a call, the #267 one-hop bound (floor (a), stated)"
untouched noclass_spec.rb m_none  "RSpec.describe \"no class\" names no class (floor (b), stated)"
untouched noclass_spec.rb m_sym   "RSpec.describe :sym names no class (floor (b), stated)"
untouched docs_spec.rb    m_docs  "Docs.describe Calc is not an RSpec example group (floor (c), stated)"

echo "=== determinism and warm == cold ==="
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

echo "=== mutation: describe Tally instead of Calc → the pin must follow the group's constant ==="
MUT="$DIR/mut"; mkdir -p "$MUT/lib" "$MUT/spec"; cp "$FIX/lib/calc.rb" "$MUT/lib/calc.rb"
sed 's/^RSpec.describe Calc do$/RSpec.describe Tally do/' "$FIX/spec/calc_spec.rb" >"$MUT/spec/calc_spec.rb"
grep -q '^RSpec.describe Tally do$' "$MUT/spec/calc_spec.rb" || no "mutation did not apply"
calls "$MUT" "Tally::m_top" calc_spec.rb; mt=$?
calls "$MUT" "Calc::m_top" calc_spec.rb; mc=$?
if [ "$mt" -ne 2 ] && [ "$mc" -ne 2 ]
then
    [ "$mt" -eq 0 ] && [ "$mc" -eq 1 ] && ok "mutation: described_class.m_top follows the group to Tally::m_top" \
        || no "mutation: with RSpec.describe Tally, Tally caller=$( [ "$mt" -eq 0 ] && echo yes || echo no ), Calc caller=$( [ "$mc" -eq 0 ] && echo yes || echo no )"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
