#!/usr/bin/env bash
# rubyclassrecvcheck.sh — gate for a Ruby call on a CLASS: `Report.generate`, `User.where( … )`, `Report.new( 1 )`,
# `JSON.parse( s )`. The receiver is a constant, so the call is sent to the class object, and Ruby's lookup on it answers.
# Before this round such a call bound to whichever in-tree method had the name once the class itself missed it: Rails
# apps' `Hash.new`, `Date.new` and `Service.new` all bound to one controller's `new` action, a model's `where` to a mailer
# preview's mock.
# THE RULE (graph.h RubyTypedReceivers::closedLookup; ingest_binds.h classifyRubyReceiver; parser version 137):
#   * the class the tree opens at the constant answers: its methods, the modules it extends or includes (a concern's
#     `class_methods do`, a nested `module ClassMethods`), its superclasses', then a reopened Module, Class, Object,
#     Kernel or BasicObject. The shallowest that defines the name decides;
#   * `C.new` is Class#new, which runs initialize: it reaches the first `initialize` that lookup finds;
#   * when nothing there defines the name, Ruby's answer is outside the tree — ActiveRecord::Base's `where`,
#     StandardError's initialize — and the call is refused as external, never bound to an unrelated namesake;
#   * a constant the tree never opens (JSON, Time, RSpec, `Point = Struct.new( … )`) answers only from a reopened root;
#     a QUALIFIED constant names an in-tree class only when the tree opens that path (`Stripe::Customer` is not the
#     app's Customer);
#   * a class whose lookup holds a method_missing answers any name, and is left as before.
#
# Stated floors, each pinned below:
#   (a) a constant the tree assigns (`DEFAULT_LIMITS = Limits.new`) is a value of a class the tree does not type: a
#       call on it binds by name as before.
#   (b) the tree does not tell `def self.m` from `def m`: a class's own instance method answers a call on the class.
#   (c) `C.new` reaches initialize even when the class defines `def self.new`: the override is not read.
#   (d) a qualified constant is read by the paths the tree opens: one Ruby finds through a class's ancestors
#       (`Sub::Failure` for a Failure its superclass nests) is refused.
#
# Usage:  test/rubyclassrecvcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyclassrecvcheck.sh
# Exits non-zero on any failure. Self-contained via mktemp.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
FIX="$DIR/fix"
for d in app/models app/services lib/billing spec
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/lib/report.rb" <<'RUBY'
class Report
  extend Finders
  include Searchable
  include Taggable
  include Archivable

  def self.generate( n )
    n
  end

  def initialize( n )
    @n = n
  end

  def render
    "r"
  end
end
RUBY

cat > "$FIX/lib/child_report.rb" <<'RUBY'
class ChildReport < Report
end
RUBY

cat > "$FIX/lib/finders.rb" <<'RUBY'
module Finders
  def lookup( id )
    id
  end
end
RUBY

cat > "$FIX/lib/searchable.rb" <<'RUBY'
module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def search( q )
      q
    end
  end
end
RUBY

cat > "$FIX/lib/taggable.rb" <<'RUBY'
module Taggable
  def self.included( base )
    base.extend ClassMethods
  end

  module ClassMethods
    def tagged_with( t )
      t
    end
  end
end
RUBY

# ActiveSupport::Concern extends a concern's nested ClassMethods onto every includer without a written `extend`
cat > "$FIX/lib/archivable.rb" <<'RUBY'
module Archivable
  extend ActiveSupport::Concern

  module ClassMethods
    def archived
      []
    end
  end
end
RUBY

# another concern's ClassMethods of the same name, which Report never includes
cat > "$FIX/lib/purgeable.rb" <<'RUBY'
module Purgeable
  extend ActiveSupport::Concern

  module ClassMethods
    def archived
      []
    end
  end
end
RUBY

cat > "$FIX/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
RUBY

cat > "$FIX/app/models/user.rb" <<'RUBY'
class User < ApplicationRecord
  def self.admins
    where( admin: true )
  end
end
RUBY

cat > "$FIX/app/models/customer.rb" <<'RUBY'
class Customer < ApplicationRecord
  def self.create_from( params )
    params
  end
end
RUBY

cat > "$FIX/lib/billing/invoice.rb" <<'RUBY'
module Billing
  class Invoice
    def self.issue( n )
      n
    end
  end
end
RUBY

cat > "$FIX/lib/errors.rb" <<'RUBY'
class ValidationFailed < StandardError
end

class Base
  class Failure < StandardError
    def initialize( m )
      super
    end
  end
end

class Sub < Base
end
RUBY

cat > "$FIX/lib/core_ext.rb" <<'RUBY'
class Module
  def cached_name
    name
  end
end

class Time
  def self.zone_now
    now
  end
end
RUBY

cat > "$FIX/lib/limits.rb" <<'RUBY'
class Limits
  def fetch_limit( k )
    k
  end
end

DEFAULT_LIMITS = Limits.new
RUBY

cat > "$FIX/lib/dynamic.rb" <<'RUBY'
class Dynamic
  def self.method_missing( name, *args )
    name
  end
end
RUBY

cat > "$FIX/lib/builder.rb" <<'RUBY'
class Builder
  def self.new( *args )
    super
  end

  def initialize( x )
    @x = x
  end
end
RUBY

cat > "$FIX/lib/helpers.rb" <<'RUBY'
def format_amount( n )
  n.to_s
end
RUBY

# Every name the fixture's calls might bind to by name alone: a Decoy target is a wrong edge.
cat > "$FIX/lib/decoy.rb" <<'RUBY'
class Decoy
  def where( *a ); end
  def find_by( *a ); end
  def parse( s ); end
  def now; end
  def new( *a ); end
  def create_from( p ); end
  def lookup( id ); end
  def search( q ); end
  def tagged_with( t ); end
  def describe( *a ); end
  def anything; end
  def format_amount( n ); end
  def cached_name; end
  def zone_now; end
  def archived; end
end
RUBY

CALLER=app/services/caller.rb
cat > "$FIX/$CALLER" <<'RUBY'
class Caller
  def run( s )
    Report.generate( 1 ) # @own
    ChildReport.generate( 2 ) # @inherited
    Report.lookup( 3 ) # @extended
    Report.search( "q" ) # @concern
    Report.tagged_with( "t" ) # @class_methods
    Report.archived # @concern_class_methods
    Billing::Invoice.issue( 4 ) # @qualified_opened
    Customer.create_from( {} ) # @customer
    Report.new( 5 ) # @new
    ChildReport.new( 6 ) # @new_inherited
    ValidationFailed.new( "x" ) # @new_out_of_tree
    Point.new( 1, 2 ) # @struct
    User.where( admin: true ) # @ar_where
    User.find_by( id: 1 ) # @ar_find_by
    Stripe::Customer.create_from( {} ) # @qualified_not_opened
    JSON.parse( s ) # @json
    Time.now # @time
    Time.zone_now # @time_reopened
    Report.cached_name # @root_module
    JSON.cached_name # @root_external
    Report.format_amount( 7 ) # @private_top
    Dynamic.anything # @missing
    DEFAULT_LIMITS.fetch_limit( :a ) # @value_floor
    Report.render # @instance_floor
    Builder.new( 8 ) # @self_new_floor
    Sub::Failure.new( "m" ) # @ancestor_const_floor
  end
end

Point = Struct.new( :x, :y )
RUBY

SPEC=spec/report_spec.rb
cat > "$FIX/$SPEC" <<'RUBY'
RSpec.describe Report do # @rspec_describe
  it "generates" do
    described_class.generate( 1 ) # @described
  end
end
RUBY

echo "=== the map is well-formed ==="
MAP="$DIR/a.xml"
if ! "$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/a.err"
then
    no "the default map exited non-zero: $( head -3 "$DIR/a.err" )"
fi
if command -v xmllint >/dev/null 2>&1
then
    if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi
fi

# The census (src/pincensus.h): one `C` row per call site the resolver decided or refused, so each arm reads ONE line.
census(){
    if ! "$BIN" "$1" --no-cache --pin-census="$DIR/census.tsv" >/dev/null 2>"$DIR/census.err"
    then
        no "--pin-census on $1 exited non-zero: $( head -3 "$DIR/census.err" )"
        return 2
    fi
    return 0
}
# line FILE MARK — the line number carrying `# @MARK` (empty when the marker is missing)
line(){
    grep -n "# @$2\$" "$FIX/$1" | head -1 | cut -d: -f1
}
# rows FILE LINE CALLEE — "mechanism<TAB>targets" of each CALLEE call the census records on FILE:LINE
rows(){
    awk -F'\t' -v f="$1" -v l="$2" -v c="$3" '$1 == "C" && $9 == l && $7 == c && index( $6, f "::" ) == 1 { print $2 "\t" $8 }' "$DIR/census.tsv"
}
# reaches CALLEE SYM FILE MARK WHY — the CALLEE call on the marked line resolves to SYM, and to no Decoy
reaches(){
    local n r; n="$( line "$3" "$4" )"
    [ -n "$n" ] || { no "fixture marker @$4 missing in $3"; return; }
    r="$( rows "$3" "$n" "$1" )"
    if printf '%s\n' "$r" | grep -qF "::$2#" && ! printf '%s\n' "$r" | grep -qF "::Decoy::"
    then
        ok "@$4 :$1 → $2 ($5)"
    else
        no "@$4 ($3:$n) :$1 does not reach $2 alone ($5); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# only CALLEE SYM FILE MARK WHY — the CALLEE call on the marked line has one target, SYM (a trailing id path, or a whole
# `file::id` one)
only(){
    local n r t; n="$( line "$3" "$4" )"
    [ -n "$n" ] || { no "fixture marker @$4 missing in $3"; return; }
    r="$( rows "$3" "$n" "$1" )"
    t="$( printf '%s\n' "$r" | cut -f2 | tr '|' '\n' | grep . | sed 's/#[0-9]*$//' )"
    if [ "$( printf '%s\n' "$t" | grep -c . )" -eq 1 ] && { [ "$t" = "$2" ] || [ "${t%::$2}" != "$t" ]; }
    then
        ok "@$4 :$1 → $2 alone ($5)"
    else
        no "@$4 ($3:$n) :$1 does not reach $2 alone ($5); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# refused CALLEE FILE MARK WHY — the CALLEE call on the marked line is recorded and refused as external
refused(){
    local n r; n="$( line "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    r="$( rows "$2" "$n" "$1" )"
    if [ -n "$r" ] && ! printf '%s\n' "$r" | grep -qv "^external	\$"
    then
        ok "@$3 :$1 refused as external ($4)"
    else
        no "@$3 ($2:$n) :$1 is not refused ($4); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}

census "$FIX" || exit 1

echo "=== the class the tree opens answers: its methods, its mixins', its superclasses' ==="
only    generate      Report::generate        $CALLER own              "the class's own def self.generate"
only    generate      Report::generate        $CALLER inherited        "a superclass's class method"
only    lookup        Finders::lookup         $CALLER extended         "a module the class extends"
only    search        Searchable::search      $CALLER concern          "a concern's class_methods block"
only    tagged_with   ClassMethods::tagged_with $CALLER class_methods  "a nested module ClassMethods the concern extends onto its includer"
only    archived      lib/archivable.rb::ClassMethods::archived $CALLER concern_class_methods "the ClassMethods of the concern Report includes, not another concern's"
only    issue         Invoice::issue          $CALLER qualified_opened "a qualified constant whose path the tree opens"
only    create_from   Customer::create_from   $CALLER customer         "the app's own Customer"
only    generate      Report::generate        $SPEC   described        "described_class is the group's class"

echo "=== C.new runs initialize ==="
only    new           Report::initialize      $CALLER new              "Report.new reaches Report#initialize, never a method named new"
only    new           Report::initialize      $CALLER new_inherited    "a subclass with no initialize reaches its superclass's"
refused new           $CALLER new_out_of_tree "StandardError's initialize is outside the tree"
refused new           $CALLER struct          "Point = Struct.new: the tree never opens Point"

echo "=== a lookup that leaves the tree is refused, never handed to a namesake ==="
refused where         $CALLER ar_where        "User.where is ActiveRecord::Base's"
refused find_by       $CALLER ar_find_by      "User.find_by is ActiveRecord::Base's"
refused create_from   $CALLER qualified_not_opened "Stripe::Customer is not the app's Customer: the tree never opens that path"
refused parse         $CALLER json            "JSON is never opened"
refused now           $CALLER time            "Time is opened, and its opening defines no now"
only    zone_now      Time::zone_now          $CALLER time_reopened    "a class the tree reopens answers from the reopening"
refused describe      $SPEC   rspec_describe  "RSpec is never opened"
refused format_amount $CALLER private_top     "a top-level def is a private method of Object: no receiver may call it"

echo "=== a reopened root answers every class object ==="
only    cached_name   Module::cached_name     $CALLER root_module      "a class is a Module"
only    cached_name   Module::cached_name     $CALLER root_external    "so is a class the tree never opens"

echo "=== method_missing answers any name: left as before ==="
MISSING="$( rows $CALLER "$( line $CALLER missing )" anything )"
if printf '%s\n' "$MISSING" | grep -qF "::Decoy::anything#"
then
    ok "@missing :anything binds by name as before (Dynamic answers any name)"
else
    no "@missing :anything no longer binds by name; census: $( printf '%s' "$MISSING" | tr '\t\n' ' ;' )"
fi

echo "=== stated floors ==="
only    fetch_limit   Limits::fetch_limit     $CALLER value_floor      "floor (a): a constant the tree assigns binds by name"
only    render        Report::render          $CALLER instance_floor   "floor (b): an instance method answers a call on the class"
only    new           Builder::initialize     $CALLER self_new_floor   "floor (c): def self.new is not read"
refused new           $CALLER ancestor_const_floor "floor (d): Sub::Failure is Base::Failure through Sub's ancestors, a path the tree never opens"

echo "=== determinism and warm == cold ==="
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
if cmp -s "$MAP" "$DIR/b.xml"
then
    ok "byte-identical across two --no-cache runs"
else
    no "output differs across runs"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/cold.xml" 2>"$DIR/cold.err"
then
    no "the cold cache run exited non-zero: $( head -3 "$DIR/cold.err" )"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/warm.xml" 2>"$DIR/warm.err"
then
    no "the warm cache run exited non-zero: $( head -3 "$DIR/warm.err" )"
fi
if cmp -s "$DIR/cold.xml" "$DIR/warm.xml"
then
    ok "warm run == cold run"
else
    no "the warm cache disagrees with the cold run"
fi

echo "=== --callers: Report.new is a caller of Report#initialize ==="
"$BIN" "$FIX" --no-cache --callers=Report::initialize >"$DIR/callers.xml" 2>/dev/null
if grep -q 'caller.rb' "$DIR/callers.xml"
then
    ok "--callers=Report::initialize names app/services/caller.rb"
else
    no "--callers=Report::initialize does not name the caller: $( head -c 400 "$DIR/callers.xml" )"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
