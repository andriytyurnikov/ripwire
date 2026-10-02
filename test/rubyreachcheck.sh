#!/usr/bin/env bash
# rubyreachcheck.sh — gate for what a Ruby BARE call can reach. A receiver-less `m` / `m( x )` inside a class or module
# is a send to self, and Ruby's method lookup decides which `def` answers it: the class, its included, extended and
# prepended modules, its superclass and theirs — and, because self may be any instance below the defining class, what
# a subclass or an includer adds (the template-method and concern idioms). A method of any OTHER class can never answer
# it; neither can an enclosing class's method (lexical nesting is constant lookup, not method lookup — `outer_helper`
# from inside `Outer::Inner` is a NoMethodError). Before this round three things broke that:
#   * mixins were no ancestor: `include Hub::SignalMixin` put nothing in the caller's base walk, so `signal`
#     split between the mixin's def and an unrelated `Hub#signal` in the same file, and a concern's call to its
#     includer's method (`audit_target`) declined;
#   * a class-BODY call ran against the enclosing namespace: `define_section :first` inside `Ns::Catalog` read Rule 1's
#     self as `Ns` and bound to `Ns.define_section`, not `Catalog.define_section`;
#   * a candidate no lookup can reach still bound by name: `render` in a controller to a component's `def render`,
#     `request` to the `Rating#request` of a class the controller merely names, `errors` in an ActiveModel form to a
#     stub's `def errors` — the method Ruby runs is the framework's, outside the tree.
# THE RULE (resolve.h Narrower::rubyReachable; graph.h): mixins are Ruby bases, scoped by Ruby's constant lookup like a
# superclass; a class-body call's self is the class; and a bare call inside a class or module keeps only the candidates
# whose owner lies in that reach — the caller's ancestors, and the ancestors of every class below it — plus top-level
# defs (private methods of Object, reachable from anywhere). When none is left it declines (declined=): the method is
# outside the indexed tree, and the tool says so rather than naming a namesake.
#
# Stated floors, each pinned below where a fixture can show it:
#   (a) a class whose lookup can leave the class — a `SimpleDelegator`/`Delegator`/`DelegateClass` or Draper decorator
#       below it in reach, or a `method_missing` in reach — refuses nothing: its bare calls bind as before.
#   (b) `delegate :x, to: :y` and Forwardable's `def_delegators` define methods the tree does not index yet; a bare call
#       to one inside the delegating class declines when the target's class is out of reach.
#   (c) instance and class methods share one name space here, as everywhere in the graph: `extend M` and `include M`
#       both put M in reach, so an instance method's call to an extended module's method is admitted.
#   (d) inside `instance_eval`/`class_eval`/`instance_exec` blocks self changes; the rule reads the lexical self, as
#       Rule 1 always has, so a DSL block run against another in-tree object declines its calls there.
#   (e) reach is read by class NAME, as the inheritance graph is keyed: two classes sharing a name share their reach,
#       which refuses less, never more.
#   (f) a call outside any class — a script's top level, an RSpec example group's blocks — is untouched by the rule.
#   (g) `prepend M` is read as `include M`: a prepended override is not preferred over the class's own method.
#
# Usage:  test/rubyreachcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyreachcheck.sh
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
for d in lib/coord lib/app lib/ns lib/dsl lib/other lib/services lib/tmpl lib/impls lib/concerns lib/orders lib/util lib/deco \
         lib/models lib/ghost lib/forms lib/stubs app/models spec
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
RUBY
cat > "$FIX/app/models/post.rb" <<'RUBY'
class Post < ApplicationRecord
  scope :published, -> { where(published: true) }
end
RUBY
cat > "$FIX/lib/app/ctl.rb" <<'RUBY'
class Ctl
  include Hub::SignalMixin

  def act
    signal(:acted)
  end
end
RUBY
cat > "$FIX/lib/app/outer.rb" <<'RUBY'
class Outer
  def outer_helper
    6
  end

  class Inner
    def m
      outer_helper
    end
  end
end
RUBY
cat > "$FIX/lib/app/pages_controller.rb" <<'RUBY'
class PagesController < ActionController::Base
  def show
    render
    request
    Rating.check
  end
end
RUBY
cat > "$FIX/lib/app/registry.rb" <<'RUBY'
class Registry
  extend RegistryDsl

  register :a
end
RUBY
cat > "$FIX/lib/app/uses_top.rb" <<'RUBY'
class UsesTop
  def m
    top_helper
  end
end
RUBY
cat > "$FIX/lib/concerns/auditable.rb" <<'RUBY'
module Auditable
  def audit
    audit_target
  end
end
RUBY
cat > "$FIX/lib/coord/hub.rb" <<'RUBY'
class Hub
  def signal(name)
    name
  end

  module SignalMixin
    def signal(name)
      name
    end
  end
end
RUBY
cat > "$FIX/lib/deco/user_deco.rb" <<'RUBY'
class UserDeco < SimpleDelegator
  def label
    display_name
  end
end
RUBY
cat > "$FIX/lib/dsl/registry_dsl.rb" <<'RUBY'
module RegistryDsl
  def register(name)
    name
  end
end
RUBY
cat > "$FIX/lib/forms/signup_form.rb" <<'RUBY'
class SignupForm
  include ActiveModel::Model

  def check
    errors
  end
end
RUBY
cat > "$FIX/lib/ghost/ghost.rb" <<'RUBY'
class Ghost
  def method_missing(name, *args)
    name
  end

  def respond_to_missing?(name, include_private = false)
    true
  end

  def m
    phantom
  end
end
RUBY
cat > "$FIX/lib/impls/impl.rb" <<'RUBY'
class Impl < BaseTemplate
  def hook
    1
  end
end
RUBY
cat > "$FIX/lib/models/user_model.rb" <<'RUBY'
class UserModel
  def display_name
    "u"
  end

  def phantom
    "p"
  end
end
RUBY
cat > "$FIX/lib/ns/catalog.rb" <<'RUBY'
module Ns
  def self.define_section(name)
    name
  end

  class Catalog
    def self.define_section(name)
      name
    end

    define_section :first
  end
end
RUBY
cat > "$FIX/lib/orders/order.rb" <<'RUBY'
class Order
  include Auditable

  def audit_target
    4
  end
end
RUBY
cat > "$FIX/lib/other/component.rb" <<'RUBY'
class Component
  def render
    "component"
  end
end
RUBY
cat > "$FIX/lib/other/robot.rb" <<'RUBY'
class Robot
  def register(name)
    name
  end
end
RUBY
cat > "$FIX/lib/other/spec_support.rb" <<'RUBY'
def spec_only_helper
  7
end
RUBY
cat > "$FIX/lib/other/unrelated.rb" <<'RUBY'
class Unrelated
  def hook
    2
  end

  def audit_target
    3
  end
end
RUBY
cat > "$FIX/lib/services/rating.rb" <<'RUBY'
class Rating
  def self.check
    true
  end

  def request
    nil
  end
end
RUBY
cat > "$FIX/lib/stubs/link_stub.rb" <<'RUBY'
class LinkStub
  def errors
  end

  def where(conditions)
    conditions
  end
end
RUBY
cat > "$FIX/lib/tmpl/base_template.rb" <<'RUBY'
class BaseTemplate
  def template
    hook
  end
end
RUBY
cat > "$FIX/lib/util/helpers.rb" <<'RUBY'
def top_helper
  5
end
RUBY
cat > "$FIX/spec/page_spec.rb" <<'RUBY'
describe "pages" do
  it "works" do
    spec_only_helper
  end
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
if [ -s "$DIR/map.err" ]; then no "unexpected stderr: $( head -3 "$DIR/map.err" )"; else ok "clean stderr"; fi
if command -v xmllint >/dev/null 2>&1
then
    if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi
fi

# callers ROOT SYM — the --callers=SYM caller rows, one per line, in $DIR/c.rows; returns 2 when the run failed, so an
# absence arm can never read a crashed run as "no caller".
callers(){
    if ! "$BIN" "$1" --no-cache --callers="$2" >"$DIR/c.out" 2>"$DIR/c.err"
    then
        no "--callers=$2 exited non-zero: $( head -3 "$DIR/c.err" )"
        return 2
    fi
    sed 's/></>\n</g' "$DIR/c.out" | grep '^<s t="' >"$DIR/c.rows"
    return 0
}
# reaches SYM CALLER WHY — CALLER (a symbol name) is a caller of SYM
reaches(){
    callers "$FIX" "$1" || return
    grep -q " n=\"$2\"" "$DIR/c.rows" && ok "$2 → $1 ($3)" \
        || no "$2 does not reach $1 ($3); callers: $( tr '\n' ' ' <"$DIR/c.rows" )"
}
# misses SYM CALLER WHY — CALLER is NOT a caller of SYM
misses(){
    callers "$FIX" "$1" || return
    grep -q " n=\"$2\"" "$DIR/c.rows" && no "$2 reaches $1 — $3" || ok "$2 does not reach $1 ($3)"
}

echo "=== a mixin is an ancestor: the base walk reaches it, ahead of a same-file namesake ==="
reaches SignalMixin::signal act "include Hub::SignalMixin — the mixin's def answers"
misses  Hub::signal act "Hub is not an ancestor of Ctl, only the mixin's namespace"
reaches RegistryDsl::register Registry "extend RegistryDsl — the class-body DSL call reaches the extended module"
misses  Robot::register       Registry "Robot is no ancestor of Registry"

echo "=== a class-body call runs with the class as self ==="
reaches Catalog::define_section Catalog "define_section :first inside Ns::Catalog names Catalog.define_section"
misses  Ns::define_section      Catalog "the enclosing namespace's method is not self's"

echo "=== below the caller: a subclass's or an includer's method answers a self call ==="
reaches Impl::hook           template "BaseTemplate#template's hook dispatches to Impl < BaseTemplate"
misses  Unrelated::hook      template "Unrelated is neither above nor below BaseTemplate"
reaches Order::audit_target  audit    "Auditable#audit's audit_target dispatches to its includer Order"
misses  Unrelated::audit_target audit "Unrelated does not include Auditable"

echo "=== out of reach: the method Ruby runs is not in the tree, so the call declines ==="
misses Component::render     show    "a controller's render is ActionController's, not a component's"
misses Rating::request   show    "naming Rating does not make its methods self's"
misses LinkStub::errors      check   "an ActiveModel form's errors is ActiveModel's"
misses LinkStub::where       Post    "a scope lambda's where runs on the model's relation"
misses Outer::outer_helper   m       "Outer::Inner does not inherit from Outer: lexical nesting is not lookup"

echo "=== what the rule leaves alone ==="
reaches top_helper              m      "a top-level def is a private method of Object, reachable from any self"
reaches UserModel::display_name label  "floor (a): a SimpleDelegator subclass forwards what it lacks"
reaches UserModel::phantom      m      "floor (a): a class with method_missing answers any name"
reaches spec_only_helper "&lt;file-scope&gt;" "floor (f): an example group's block is in no class"

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

echo "=== mutation: drop the include → the concern no longer reaches Order ==="
MUT="$DIR/mut"; cp -R "$FIX" "$MUT"
grep -v '^  include Auditable$' "$FIX/lib/orders/order.rb" >"$MUT/lib/orders/order.rb"
grep -q 'include Auditable' "$MUT/lib/orders/order.rb" && no "mutation did not apply"
if callers "$MUT" "Order::audit_target"
then
    grep -q ' n="audit"' "$DIR/c.rows" && no "mutation: without the include, audit still reaches Order::audit_target" \
        || ok "mutation: without the include, audit no longer reaches Order::audit_target"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
