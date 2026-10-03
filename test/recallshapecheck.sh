#!/usr/bin/env bash
# recallshapecheck.sh — a function used as a VALUE is never a silent zero.
#
#   test/recallshapecheck.sh                       # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/recallshapecheck.sh
#   test/recallshapecheck.sh build_base/ripwire    # the RED run (a pre-change binary)
#
# THE DEFECT. A function stored in a struct-field initialiser, an object-literal or dict dispatch table, an array of
# function pointers, a variable, or passed as a callback argument, is referenced as a VALUE, not called. The index
# captured only call-shaped references, so the identifier at the binding site was no reference of any kind: --callers,
# --callees, --impact and --uses all answered count="0" with graph_unresolved="0", --safe-delete said
# dead_code_candidate="1" risk="none-found", and --dead-code listed the function. Every one of those zeros read as
# "nothing else uses this" when a dispatch table did. The mechanism that closes it is a port of codebase-memory-mcp's
# reference-as-value usages (MIT; the implementation commit credits it in THIRD_PARTY.md): an identifier in a value
# position emits a usage at its enclosing scope, resolved by name like any other reference.
#
# THE CONTRACT (what every arm below pins).
#   * A value reference is NOT a call. It is its own row, <vr>, and its own count, value_refs=N (the number of <vr>
#     binding sites), emitted only when N > 0 — so an answer with no value reference is byte-identical to before.
#     count=, reaches=, callers= and dead_code_candidate stay CALL facts: value_refs is never added into them.
#   * <vr t= n= p=> names the enclosing symbol (as the <s> rows do), bind= the binding site file:line, and slot= where
#     the value lands: VAR.key / VAR["key"] (a keyed initialiser, object literal, dict, map or struct literal),
#     VAR[i] (the i-th element of a positional initialiser or array), CALLEE#argI / CALLEE#kw (an argument; CALLEE as
#     written), @DECORATOR, or the written left-hand side of an assignment.
#   * called_in= (callers side) lists the functions that call THROUGH that slot: a function whose parameter I is called
#     (slot CALLEE#argI), or a function in the same file that calls VAR[…](…) / VAR.key(…) (a file-scope VAR) — a
#     local VAR only from inside its own function. through= (callees side) is the written callee of such a call
#     (cb, handlers[kind], table.close). Both are may-call clues, never proven calls.
#   * Matching is by bare name, in the same language, and a same-named local or parameter hides the function (no row).
#     A string, a comment, a key or field NAME, a keyword-argument label, a member value (obj.lone) and a type query
#     (typeof lone) are not value references.
#   * Disclosure (CLI == MCP): the legend defines value_refs= and says the row is not a proven call; --json, MCP
#     find_referencing_symbols / find_symbol (valueRefs / valueCallees), MCP impact and uses carry the same rows.
#
# NAMED FLOORS (asserted as floors, never as passes of the contract):
#   F1 a call through a TYPED pointer or receiver field (`p->open(x)`, p a `struct ops *` parameter) names no value:
#      the slot match is by container NAME, and p names no container. --callees=use_ptr stays silent.
#   F2 a member or qualified value (`run(obj.lone)`, `self.f`, `Cls::m`, `this.handler`) is no row.
#
# The fixtures are generated here (nothing is committed under test/). Markers `@NAME` in a comment on a line resolve to
# that line, so no arm hard-codes a line number.
#
# Exits non-zero on any failure; prints PASS/FAIL per arm.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
verdict(){ if [ "$2" = OK ]; then ok "$1"; else no "$1 — $2"; fi; }   # verdict LABEL RESULT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "recallshapecheck: BIN=$BIN"

FX="$TMP/fx"
mkdir -p "$FX/c" "$FX/js" "$FX/ts" "$FX/py" "$FX/go" "$FX/cpp" "$FX/ctl" "$FX/big"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────
cat >"$FX/c/ops.c" <<'EOF'
#include <stdio.h>
struct ops { int (*open)(int); int (*close)(int); };
static int my_open(int x) { return x + 1; }
static int my_close(int x) { return x - 1; }
static int other_open(int x) { return x * 2; }
static int on_event(int x) { return x + 3; }
static int on_tick(int x) { return x + 4; }
static int lone(int x) { return x; }
static int keep(int v) { return v; }
static int truly_dead(int x) { return x; }
static struct ops table = { .open = my_open, .close = my_close };   /* @C_TABLE */
static int (*fns[])(int) = { other_open, &on_tick };                /* @C_FNS */
static struct ops positional = { my_open, my_close };               /* @C_POS */
int use_literal(int x) { struct ops o = { .open = my_open, .close = my_close }; return o.open(x); }  /* @C_LIT */
int use_global(int x) { return table.close(x) + fns[0](x); }
int use_ptr(struct ops *p, int x) { return p->open(x); }
static int run(int (*cb)(int), int x) { return cb(x); }
int use_callback(void) { return run(on_event, 1) + run(&on_tick, 2); }   /* @C_CB */
int use_assign(struct ops *p) { p->open = other_open; return 0; }        /* @C_ASSIGN */
/* @C_N1 a comment that names a function: .open = lone */
int neg_string(void) { const char *s = "lone"; return puts(s); }         /* @C_N2 */
int neg_shadow(void) { int on_event = 5; return keep(on_event); }        /* @C_N3 */
int neg_field_key(void) { struct { int lone; } k = { .lone = 3 }; return k.lone; }   /* @C_N4 */
int neg_call(void) { return lone(1); }                                    /* @C_N5 */
EOF

cat >"$FX/js/table.js" <<'EOF'
function fooGet(req) { return req.a; }
function fooPost(req) { return req.b; }
function fooDel(req) { return req.d; }
function onEvent(x) { return x + 1; }
function onClick(e) { return e; }
function lone(x) { return x; }
const handlers = { get: fooGet, post: fooPost, put(req) { return req.c; } };  // @J_TABLE
const short = { fooDel };                                                      // @J_SHORT
const list = [fooGet, fooDel];                                                 // @J_LIST
function dispatch(kind, req) { return handlers[kind](req); }
function dispatchDot(req) { return handlers.get(req); }
function dispatchPut(req) { return handlers.put(req); }
function run(cb, x) { return cb(x); }
function useCallbacks(xs, bus, el) {
  run(onEvent, 1);                        // @J_RUN
  xs.map(onEvent);                        // @J_MAP
  bus.on("tick", onEvent);                // @J_ON
  el.addEventListener("click", onClick);  // @J_ADD
}
// @J_N1 a comment that names a function: handlers = { get: lone }
function negString() { return { get: "lone" }; }       // @J_N2
function negShadow(fooPost) { return [fooPost]; }      // @J_N3
function negKey() { return { lone: 1 }; }              // @J_N4
function negMember(obj) { return run(obj.lone, 1); }   // @J_N5
function negCall() { return lone(2); }                 // @J_N6
module.exports = { dispatch, dispatchDot, dispatchPut, useCallbacks, short, list, negString, negShadow, negKey, negMember, negCall };  // @J_EXPORTS
EOF

cat >"$FX/ts/table.ts" <<'EOF'
type Handler = (req: { a?: number; b?: number }) => number | undefined;
export function fooGet(req: { a?: number }) { return req.a; }
export function fooPost(req: { b?: number }) { return req.b; }
export function onEvent(x: number) { return x + 1; }
export function onClick(e: Event) { return e; }
export function lone(x: number) { return x; }
export const handlers: Record<string, Handler> = { get: fooGet, post: fooPost };   // @T_TABLE
export function dispatch(kind: string, req: { a?: number }) { return handlers[kind](req); }
export function dispatchDot(req: { a?: number }) { return handlers.get(req); }
export function useCallbacks(xs: number[], el: HTMLElement) {
  el.addEventListener("click", onClick);   // @T_ADD
  return xs.map(onEvent);                  // @T_MAP
}
// @T_N1 a comment that names a function: handlers = { get: lone }
export type LoneType = typeof lone;                                   // @T_N2
export interface HasLone { lone(x: number): number }                  // @T_N3
export function negString() { return { get: "lone" }; }               // @T_N4
export function negShadow(fooPost: number) { return [fooPost]; }      // @T_N5
export function negCall() { return lone(2); }                         // @T_N6
EOF

cat >"$FX/py/dispatch.py" <<'EOF'
import threading

REGISTRY = []


def register(fn):
    REGISTRY.append(fn)
    return fn


def foo_get(req):
    return req["a"]


def foo_post(req):
    return req["b"]


def on_event(x):
    return x + 1


def worker():
    return 0


def handler():
    return 1


def lone(x):
    return x


def keep(v):
    return v


DISPATCH = {"get": foo_get, "post": foo_post}  # @P_DICT
TABLE = [foo_get, on_event]  # @P_LIST


def dispatch(kind, req):
    return DISPATCH[kind](req)


def dispatch_local(req):
    table = {"get": foo_get}  # @P_LOCAL
    return table["get"](req)


def run(cb, x):
    return cb(x)


def use_callbacks(xs):
    run(on_event, 1)  # @P_RUN
    list(map(on_event, xs))  # @P_MAP
    return threading.Thread(target=worker)  # @P_KW


@register  # @P_DECO
def decorated():
    return 2


alias = handler  # @P_ASSIGN


# @P_N1 a comment that names a function: DISPATCH = {"get": lone}
def neg_string():
    return {"get": "lone"}  # @P_N2


def neg_shadow(foo_post):
    return [foo_post]  # @P_N3


def neg_local():
    on_event = 3
    return keep(on_event)  # @P_N4


def neg_kwlabel():
    return dict(lone=1)  # @P_N5


def neg_member(obj):
    return run(obj.lone, 1)  # @P_N6


def neg_call():
    return lone(2)  # @P_N7
EOF

cat >"$FX/go/main.go" <<'EOF'
package main

import "net/http"

type Ops struct {
	Open  func(int) int
	Close func(int) int
}

type K struct{ lone int }

func myOpen(x int) int  { return x + 1 }
func myClose(x int) int { return x - 1 }
func onEvent(x int) int { return x + 2 }
func serve(w http.ResponseWriter, r *http.Request) {}
func lone(x int) int    { return x }
func keep(v int) int    { return v }

var handlers = map[string]func(int) int{"open": myOpen, "close": myClose} // @G_MAP
var ops = Ops{Open: myOpen, Close: myClose}                               // @G_STRUCT
var fns = []func(int) int{onEvent, myClose}                               // @G_SLICE

func run(cb func(int) int, x int) int { return cb(x) }
func useCallbacks() int {
	http.HandleFunc("/", serve) // @G_HANDLE
	return run(onEvent, 1)      // @G_RUN
}
func dispatch(k string, x int) int { return handlers[k](x) }
func useOps(x int) int             { return ops.Open(x) }

// @G_N1 a comment that names a function: handlers = {"open": lone}
func negString() string { return "lone" }                      // @G_N2
func negShadow() int    { onEvent := 3; return keep(onEvent) } // @G_N3
func negKey() K         { return K{lone: 1} }                  // @G_N4
func negCall() int      { return lone(2) }                     // @G_N5

func main() { _ = useCallbacks(); _ = dispatch("open", 1); _ = useOps(1) }
EOF

cat >"$FX/cpp/cb.cpp" <<'EOF'
#include <algorithm>
#include <vector>
struct Ops { int (*open)(int); };
static bool cmpLess(int a, int b) { return a < b; }
static int myOpen(int x) { return x + 1; }
static int lone(int x) { return x; }
void sortAll(std::vector<int>& v) { std::sort(v.begin(), v.end(), cmpLess); }   // @X_SORT
static Ops table = { .open = myOpen };                                            // @X_TABLE
int negString() { const char* s = "lone"; return s[0]; }                         // @X_N1
int negCall() { return lone(1); }                                                 // @X_N2
EOF

# Controls: direct calls only — no answer here may carry a value-reference attribute, row or legend clause.
cat >"$FX/ctl/ctl.c" <<'EOF'
static int helper(int x) { return x + 1; }
static int dead_one(int x) { return x; }
int caller(int x) { return helper(x); }
EOF
cat >"$FX/ctl/ctl.py" <<'EOF'
def py_helper(x):
    return x + 1


def py_caller(x):
    return py_helper(x)
EOF
cat >"$FX/ctl/ctl.js" <<'EOF'
function jsHelper(x) { return x + 1; }
function jsCaller(x) { return jsHelper(x); }
EOF

# Runaway guard: one function stored 300 times. The count stays whole; the rows are capped and the cut disclosed.
python3 - "$FX/big/big.c" <<'EOF'
import sys
lines = [ "static int hot(int x) { return x; }", "static int (*many[])(int) = {" ]
lines += [ "    hot," ] * 300
lines += [ "};", "int use_many(int i) { return many[i](i); }" ]
open( sys.argv[1], "w" ).write( "\n".join( lines ) + "\n" )
EOF

# ── the checker ──────────────────────────────────────────────────────────────────────────────────────────
cat >"$TMP/chk.py" <<'EOF'
# chk.py DIR OUTFILE TOKEN... — asserts on one XML answer. Prints "OK" or one line per failed token, then a
# context line (the root's count/value_refs/graph_unresolved) so a RED run documents the false completeness.
#   attr:NAME=VAL  attr:NAME!=VAL  noattr:NAME
#   vr:k=v;k=v     novr:k=v;...    nvr:N          (the same for u: / d: / s: rows; nu: nd: ns: counts)
#   legend:TEXT    nolegend:TEXT   (the answer's leading comment)
# A row value @MARK resolves to "relpath:line" of the fixture line carrying the marker; "-" means the attribute
# must be ABSENT on that row.
import os, re, sys
import xml.etree.ElementTree as ET
fxdir, outfile, toks = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open( outfile, encoding="utf-8", errors="replace" ).read()
marks = {}
for dp, _, fs in os.walk( fxdir ):
    for f in fs:
        p = os.path.join( dp, f )
        rel = os.path.relpath( p, fxdir )
        try:
            for i, line in enumerate( open( p, encoding="utf-8", errors="replace" ), 1 ):
                for m in re.finditer( r"@([A-Z][A-Z0-9_]*)\b", line ):
                    marks.setdefault( m.group( 1 ), "%s:%d" % ( rel, i ) )
        except OSError:
            pass
def val( v ):
    if re.fullmatch( r"@[A-Z][A-Z0-9_]*", v ):   # a marker; "@register" (a decorator slot) is a literal value
        if v[1:] not in marks:
            raise SystemExit( "chk.py: unknown marker " + v )
        return marks[v[1:]]
    return v
fails = []
m = re.search( r"<!--(.*?)-->", text, re.S )
legend = m.group( 1 ) if m else ""
body = re.sub( r"<!--.*?-->", "", text, flags=re.S ).strip()
try:
    root = ET.fromstring( body )
except ET.ParseError as e:
    print( "FAIL not parseable XML (%s): %s" % ( e, body[:300] ) )
    raise SystemExit( 0 )
def rows( tag ):
    return [ el.attrib for el in root.iter( tag ) ]
def matches( row, spec ):
    for kv in spec.split( ";" ):
        k, _, v = kv.partition( "=" )
        v = val( v )
        if v == "-":
            if k in row:
                return False
        elif row.get( k ) != v:
            return False
    return True
tagOf = { "vr": "vr", "u": "u", "d": "d", "s": "s" }
for t in toks:
    kind, _, spec = t.partition( ":" )
    if kind == "attr":
        if "!=" in spec:
            k, v = spec.split( "!=", 1 )
            if root.get( k ) is None or root.get( k ) == v:
                fails.append( "%s=%r (want present and != %r)" % ( k, root.get( k ), v ) )
        else:
            k, v = spec.split( "=", 1 )
            if root.get( k ) != v:
                fails.append( "%s=%r (want %r)" % ( k, root.get( k ), v ) )
    elif kind == "noattr":
        if spec in root.attrib:
            fails.append( "%s=%r present (want absent)" % ( spec, root.get( spec ) ) )
    elif kind in tagOf:
        if not any( matches( r, spec ) for r in rows( tagOf[kind] ) ):
            fails.append( "no <%s> row matching %s" % ( kind, ";".join( k + "=" + val( v ) for k, _, v in ( kv.partition( "=" ) for kv in spec.split( ";" ) ) ) ) )
    elif kind in ( "novr", "nou", "nod", "nos" ):
        tag = kind[2:]
        hit = [ r for r in rows( tag ) if matches( r, spec ) ]
        if hit:
            fails.append( "unwanted <%s> row %r" % ( tag, hit[0] ) )
    elif kind in ( "nvr", "nu", "nd", "ns" ):
        tag = kind[1:]
        if not spec.isdigit():
            raise SystemExit( "chk.py: non-numeric count token " + t )
        n = len( rows( tag ) )
        if n != int( spec ):
            fails.append( "%d <%s> rows (want %s)" % ( n, tag, spec ) )
    elif kind == "legend":
        if spec not in legend:
            fails.append( "legend lacks %r" % spec )
    elif kind == "nolegend":
        if spec in legend:
            fails.append( "legend has %r (want absent)" % spec )
    else:
        raise SystemExit( "chk.py: unknown token " + t )
if fails:
    ctx = " ".join( "%s=%s" % ( k, root.get( k ) ) for k in ( "count", "reaches", "value_refs", "graph_unresolved", "risk", "dead_code_candidate" ) if root.get( k ) is not None )
    print( "FAIL " + " | ".join( fails ) + "   [answer: <%s %s>]" % ( root.tag, ctx ) )
else:
    print( "OK" )
EOF

# arm LABEL FIXDIR ARGV TOKEN... — run one CLI answer (fresh index) and check it.
n=0
arm() {
    local label="$1" dir="$2" argv="$3"; shift 3
    n=$(( n + 1 ))
    local out="$TMP/out.$n.xml"
    ( cd "$FX/$dir" && "$BIN" . $argv --no-cache --legend=compact >"$out" 2>"$out.err" )
    local rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then no "$label — ripwire exited $rc on: $argv ($(head -c 200 "$out.err"))"; return; fi
    [ -s "$out" ] || { no "$label — empty answer on: $argv"; return; }
    local res; res="$( python3 "$TMP/chk.py" "$FX/$dir" "$out" "$@" 2>&1 )"
    case "$res" in
        OK) ok "$label" ;;
        *)  no "$label — $res" ;;
    esac
}

# ── C: struct-field initialisers, designated and positional, a function-pointer array, callbacks, assignment ──
echo "-- C"
arm "C1 callers my_open: count stays 0 (calls), value_refs=3 at the global table, the positional initialiser and a local literal" \
    c --callers=my_open attr:count=0 attr:graph_unresolved=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@C_TABLE;slot=table.open;called_in=-' 'vr:bind=@C_POS;slot=positional[0];called_in=-' \
    'vr:bind=@C_LIT;slot=o.open;n=use_literal;called_in=use_literal'
arm "C2 callers my_close: table.close is called through in use_global (a file-scope container)" \
    c --callers=my_close attr:count=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@C_TABLE;slot=table.close;called_in=use_global' 'vr:bind=@C_POS;slot=positional[1]' 'vr:bind=@C_LIT;slot=o.close;called_in=-'
arm "C3 callers other_open: fn-pointer array element 0 (called through fns[0]) and a field assignment through a parameter" \
    c --callers=other_open attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:bind=@C_FNS;slot=fns[0];called_in=use_global' 'vr:bind=@C_ASSIGN;slot=p->open;n=use_assign;called_in=-'
arm "C4 callers on_tick: &fn in an array and as an argument; run calls its parameter 0" \
    c --callers=on_tick attr:value_refs=2 nvr:2 'vr:bind=@C_FNS;slot=fns[1]' 'vr:bind=@C_CB;slot=run#arg0;n=use_callback;called_in=run'
arm "C5 callers on_event: the callback argument; NOT the same-named local in neg_shadow" \
    c --callers=on_event attr:value_refs=1 nvr:1 'vr:bind=@C_CB;slot=run#arg0;called_in=run' 'novr:bind=@C_N3'
arm "C6 callees use_literal: the two stored functions; my_open is called through o.open" \
    c --callees=use_literal attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:n=my_open;bind=@C_LIT;slot=o.open;through=o.open' 'vr:n=my_close;bind=@C_LIT;slot=o.close;through=-'
arm "C7 callees use_global: table.close and fns[0] resolve through their file-scope tables" \
    c --callees=use_global attr:count=0 attr:value_refs=2 nvr:2 \
    'vr:n=my_close;bind=@C_TABLE;through=table.close' 'vr:n=other_open;bind=@C_FNS;through=fns[0]'
arm "C8 callees run: a call through parameter cb lists what was passed in as argument 0" \
    c --callees=run attr:count=0 attr:value_refs=2 nvr:2 'vr:n=on_event;bind=@C_CB;through=cb' 'vr:n=on_tick;bind=@C_CB;through=cb'
arm "C9 callees use_callback: the call to run stays a call row; the two passed functions are value rows" \
    c --callees=use_callback attr:count=1 ns:1 's:n=run' attr:value_refs=2 nvr:2 'vr:n=on_event;through=-' 'vr:n=on_tick;through=-'
arm "C10 impact my_open: reaches stays a call radius (0); value_refs=3 is disclosed beside it" \
    c --impact=my_open attr:reaches=0 attr:value_refs=3 nvr:3
arm "C11 safe-delete my_open: a function in a dispatch table is not a dead-code candidate and not risk=none-found" \
    c --safe-delete=my_open attr:callers=0 attr:value_refs=3 attr:dead_code_candidate=0 'attr:risk!=none-found'
arm "C12 dead-code: the five value-referenced statics are excluded and counted; truly_dead is still listed" \
    c --dead-code attr:count=1 nd:1 'd:n=truly_dead' 'nod:n=my_open' 'nod:n=on_event' attr:value_ref_excluded=5
arm "C13 uses my_open: the three binding sites are role=value use-sites" \
    c --uses=my_open attr:count=3 nu:3 'u:role=value;p=@C_TABLE' 'u:role=value;p=@C_POS' 'u:role=value;p=@C_LIT'
arm "C14 path use_callback→on_event: no directed CALL path, and the target's value references are disclosed" \
    c --path=use_callback,on_event attr:reachable=0 attr:to_value_refs=1
arm "C15 negatives: lone (named in a comment, a string and a designated FIELD name) has its one call and no value row" \
    c --callers=lone attr:count=1 'ns:1' 's:n=neg_call' noattr:value_refs nvr:0
arm "F1 floor: a call through a typed parameter's field (p->open) names no container — use_ptr stays silent" \
    c --callees=use_ptr attr:count=0 noattr:value_refs nvr:0

# ── JS: object-literal tables (pair, shorthand, array), computed and dotted dispatch, callbacks, CJS exports ──
echo "-- JavaScript"
arm "J1 callers fooGet: the table pair (called through in dispatch and dispatchDot) and the array element" \
    js --callers=fooGet attr:count=0 attr:graph_unresolved=0 attr:value_refs=2 nvr:2 \
    'vr:bind=@J_TABLE;slot=handlers.get;called_in=dispatch,dispatchDot' 'vr:bind=@J_LIST;slot=list[0];called_in=-'
arm "J2 callers fooPost: handlers.post only — NOT negShadow's same-named parameter" \
    js --callers=fooPost attr:value_refs=1 nvr:1 'vr:bind=@J_TABLE;slot=handlers.post;called_in=dispatch' 'novr:bind=@J_N3'
arm "J3 callers fooDel: shorthand property and array element" \
    js --callers=fooDel attr:value_refs=2 nvr:2 'vr:bind=@J_SHORT;slot=short.fooDel' 'vr:bind=@J_LIST;slot=list[1]'
arm "J4 callers onEvent: three callbacks (run, xs.map, bus.on); only run's is called through" \
    js --callers=onEvent attr:count=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@J_RUN;slot=run#arg0;n=useCallbacks;called_in=run' 'vr:bind=@J_MAP;slot=xs.map#arg0;called_in=-' 'vr:bind=@J_ON;slot=bus.on#arg1;called_in=-'
arm "J5 callers onClick: an addEventListener handler" \
    js --callers=onClick attr:value_refs=1 nvr:1 'vr:bind=@J_ADD;slot=el.addEventListener#arg1'
arm "J6 callers dispatch: the CommonJS export table is a value use" \
    js --callers=dispatch attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@J_EXPORTS;slot=module.exports.dispatch'
arm "J7 callees dispatch: handlers[kind](req) may call every function value in handlers" \
    js --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:n=fooGet;through=handlers[kind]' 'vr:n=fooPost;through=handlers[kind]'
arm "J8 callees dispatchDot: handlers.get(req) reaches the get slot only" \
    js --callees=dispatchDot attr:count=0 attr:value_refs=1 nvr:1 'vr:n=fooGet;bind=@J_TABLE;through=handlers.get'
arm "J9 callees run: a call through parameter cb lists the one function passed in (not obj.lone)" \
    js --callees=run attr:count=0 attr:value_refs=1 nvr:1 'vr:n=onEvent;bind=@J_RUN;through=cb'
arm "J10 callees dispatchPut: the method-shorthand call stays one call row and adds no value row" \
    js --callees=dispatchPut attr:count=1 ns:1 's:n=put' noattr:value_refs nvr:0
arm "J11 negatives: lone (comment, string, object KEY, obj.lone member) has its one call and no value row" \
    js --callers=lone attr:count=1 ns:1 noattr:value_refs nvr:0

# ── TypeScript: a typed Record table, DOM and array callbacks, a type query ──────────────────────────────
echo "-- TypeScript"
arm "T1 callers fooGet: the typed Record table pair, called through in dispatch and dispatchDot" \
    ts --callers=fooGet attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@T_TABLE;slot=handlers.get;called_in=dispatch,dispatchDot'
arm "T2 callers fooPost: NOT negShadow's typed parameter" \
    ts --callers=fooPost attr:value_refs=1 nvr:1 'vr:bind=@T_TABLE;slot=handlers.post' 'novr:bind=@T_N5'
arm "T3 callers onClick / onEvent: addEventListener and map callbacks" \
    ts --callers=onClick attr:value_refs=1 nvr:1 'vr:bind=@T_ADD;slot=el.addEventListener#arg1'
arm "T4 callers onEvent: xs.map callback" \
    ts --callers=onEvent attr:value_refs=1 nvr:1 'vr:bind=@T_MAP;slot=xs.map#arg0'
arm "T5 callees dispatch: handlers[kind] through the Record table" \
    ts --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:n=fooGet;through=handlers[kind]' 'vr:n=fooPost;through=handlers[kind]'
arm "T6 negatives: lone (comment, typeof in a type alias, an interface member, a string) has no value row" \
    ts --callers=lone attr:count=1 noattr:value_refs nvr:0

# ── Python: dict and list dispatch, a local table, callbacks, a keyword argument, a decorator, an alias ──
echo "-- Python"
arm "P1 callers foo_get: dict value, list element and a local table; each called through where it is" \
    py --callers=foo_get attr:count=0 attr:graph_unresolved=0 attr:value_refs=3 nvr:3 \
    'vr:bind=@P_DICT;slot=DISPATCH["get"];called_in=dispatch' 'vr:bind=@P_LIST;slot=TABLE[0];called_in=-' \
    'vr:bind=@P_LOCAL;slot=table["get"];n=dispatch_local;called_in=dispatch_local'
arm "P2 callers foo_post: the dict value only — NOT neg_shadow's same-named parameter" \
    py --callers=foo_post attr:value_refs=1 nvr:1 'vr:bind=@P_DICT;slot=DISPATCH["post"];called_in=dispatch' 'novr:bind=@P_N3'
arm "P3 callers on_event: list element and two callbacks — NOT neg_local's same-named local" \
    py --callers=on_event attr:value_refs=3 nvr:3 'vr:bind=@P_LIST;slot=TABLE[1]' \
    'vr:bind=@P_RUN;slot=run#arg0;called_in=run' 'vr:bind=@P_MAP;slot=map#arg0;called_in=-' 'novr:bind=@P_N4'
arm "P4 callers worker: a keyword-argument value" \
    py --callers=worker attr:value_refs=1 nvr:1 'vr:bind=@P_KW;slot=threading.Thread#target'
arm "P5 callers decorated: a registering decorator receives the function as a value" \
    py --callers=decorated attr:value_refs=1 nvr:1 'vr:bind=@P_DECO;slot=@register'
arm "P6 callers handler: an alias assignment" \
    py --callers=handler attr:value_refs=1 nvr:1 'vr:bind=@P_ASSIGN;slot=alias'
arm "P7 callees dispatch: DISPATCH[kind](req) may call both dict values" \
    py --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:n=foo_get;through=DISPATCH[kind]' 'vr:n=foo_post;through=DISPATCH[kind]'
arm "P8 callees run: a call through parameter cb (not obj.lone)" \
    py --callees=run attr:count=0 attr:value_refs=1 nvr:1 'vr:n=on_event;bind=@P_RUN;through=cb'
arm "P9 uses foo_get: the three sites are role=value (no longer role=read)" \
    py --uses=foo_get attr:count=3 nu:3 'u:role=value;p=@P_DICT' 'u:role=value;p=@P_LIST' 'u:role=value;p=@P_LOCAL' 'nou:role=read'
arm "P10 negatives: lone (comment, string, keyword LABEL, obj.lone member) has its one call and no value row" \
    py --callers=lone attr:count=1 ns:1 noattr:value_refs nvr:0

# ── Go: map and struct literals, a slice of funcs, an http handler, a callback ────────────────────────────
echo "-- Go"
arm "G1 callers myOpen: map value (called through in dispatch) and struct field (called through in useOps)" \
    go --callers=myOpen attr:count=0 attr:graph_unresolved=0 attr:value_refs=2 nvr:2 \
    'vr:bind=@G_MAP;slot=handlers["open"];called_in=dispatch' 'vr:bind=@G_STRUCT;slot=ops.Open;called_in=useOps'
arm "G2 callers myClose: map value, struct field, slice element" \
    go --callers=myClose attr:value_refs=3 nvr:3 'vr:bind=@G_MAP;slot=handlers["close"]' 'vr:bind=@G_STRUCT;slot=ops.Close' 'vr:bind=@G_SLICE;slot=fns[1]'
arm "G3 callers onEvent: slice element and a callback — NOT negShadow's := local" \
    go --callers=onEvent attr:value_refs=2 nvr:2 'vr:bind=@G_SLICE;slot=fns[0]' 'vr:bind=@G_RUN;slot=run#arg0;called_in=run' 'novr:bind=@G_N3'
arm "G4 callers serve: an http.HandleFunc handler" \
    go --callers=serve attr:value_refs=1 nvr:1 'vr:bind=@G_HANDLE;slot=http.HandleFunc#arg1'
arm "G5 callees dispatch: handlers[k](x) may call both map values" \
    go --callees=dispatch attr:count=0 attr:value_refs=2 nvr:2 'vr:n=myOpen;through=handlers[k]' 'vr:n=myClose;through=handlers[k]'
arm "G6 callees useOps: ops.Open(x) reaches the Open field only" \
    go --callees=useOps attr:count=0 attr:value_refs=1 nvr:1 'vr:n=myOpen;bind=@G_STRUCT;through=ops.Open'
arm "G7 negatives: lone (comment, string, struct-literal KEY) has its one call and no value row" \
    go --callers=lone attr:count=1 ns:1 noattr:value_refs nvr:0

# ── C++ (sibling of C): an algorithm comparator, a designated initialiser ────────────────────────────────
echo "-- C++"
arm "X1 callers cmpLess: the std::sort comparator argument" \
    cpp --callers=cmpLess attr:count=0 attr:value_refs=1 nvr:1 'vr:bind=@X_SORT;slot=std::sort#arg2;n=sortAll'
arm "X2 callers myOpen: a designated initialiser" \
    cpp --callers=myOpen attr:value_refs=1 nvr:1 'vr:bind=@X_TABLE;slot=table.open'
arm "X3 negatives: lone (a string) has its one call and no value row" \
    cpp --callers=lone attr:count=1 noattr:value_refs nvr:0

# ── Runaway guard ────────────────────────────────────────────────────────────────────────────────────────
echo "-- runaway guard"
arm "Z1 callers hot: value_refs=300 stays whole; 64 rows shown, the cut disclosed, next= pages the use-sites" \
    big --callers=hot attr:value_refs=300 attr:value_refs_shown=64 nvr:64 'attr:next=--uses=hot'

# ── Controls: no value reference → no new attribute, row or legend clause ────────────────────────────────
echo "-- controls"
for argv in --callers=helper --callees=caller --impact=helper --safe-delete=helper --uses=helper --dead-code \
            --callers=py_helper --callees=py_caller --uses=py_helper --callers=jsHelper --callees=jsCaller \
            --path=caller,helper; do
    arm "K ctl $argv: no value_refs / <vr> / value_ref_excluded / to_value_refs / legend clause" \
        ctl "$argv" noattr:value_refs noattr:value_ref_excluded noattr:to_value_refs nvr:0 nolegend:value_refs
done
arm "K ctl dead-code still lists dead_one (the exclusion is not a blanket change)" ctl --dead-code attr:count=1 'd:n=dead_one'
arm "K ctl safe-delete dead_one keeps its verdict" ctl --safe-delete=dead_one attr:dead_code_candidate=1 attr:risk=none-found

# ── Disclosure: the legend says what a value row is and is not; CLI == JSON == MCP ───────────────────────
echo "-- disclosure"
arm "D1 callers legend (compact) defines value_refs= and says a value row is not a proven call" \
    c --callers=my_open 'legend:value_refs=' 'legend:not a proven call'
for v in --callees=use_literal --impact=my_open --safe-delete=my_open --uses=my_open --dead-code --path=use_callback,on_event; do
    arm "D2 $v legend (compact) carries the value-reference clause" c "$v" 'legend:not a proven call'
done
( cd "$FX/c" && "$BIN" . --callers=my_open --no-cache --legend=full >"$TMP/full.xml" 2>/dev/null )
res="$( python3 "$TMP/chk.py" "$FX/c" "$TMP/full.xml" 'legend:value_refs=' 'legend:not a proven call' 'legend:bind=' 'legend:slot=' 'legend:called_in=' )"
verdict "D3 callers legend (full) defines value_refs=, bind=, slot=, called_in= and 'not a proven call'" "$res"

mcp_call() {   # mcp_call TOOL ARGS_JSON → the tool's text payload on stdout
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":'"$2"'}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'
}
cat >"$TMP/par.py" <<'EOF'
# par.py XMLFILE JSONFILE ARRAYKEY COUNTKEY — the JSON twin carries the same value rows as the CLI XML answer.
import json, re, sys
import xml.etree.ElementTree as ET
x = re.sub( r"<!--.*?-->", "", open( sys.argv[1] ).read(), flags=re.S ).strip()
try:
    root = ET.fromstring( x )
except ET.ParseError as e:
    print( "FAIL cli not XML: %s" % e ); raise SystemExit
raw = open( sys.argv[2] ).read()
if raw.startswith( "__ERROR__" ):
    print( "FAIL json side errored: " + raw[:200] ); raise SystemExit
try:
    j = json.loads( raw )
except ValueError as e:
    print( "FAIL json side not JSON: %s" % e ); raise SystemExit
key = lambda d: ( d.get( "n" ), d.get( "bind" ), d.get( "slot" ), d.get( "called_in" ) or d.get( "through" ) or "" )
cli = sorted( key( el.attrib ) for el in root.iter( "vr" ) )
arr = j.get( sys.argv[3] )
if not isinstance( arr, list ):
    print( "FAIL json has no %s array (keys: %s)" % ( sys.argv[3], ",".join( sorted( j ) ) ) ); raise SystemExit
js = sorted( key( d ) for d in arr )
cnt = j.get( sys.argv[4] )
if not cli:
    print( "FAIL the CLI answer has no <vr> rows to compare (value_refs=%s)" % root.get( "value_refs" ) )
elif cli != js:
    print( "FAIL rows differ: cli=%r json=%r" % ( cli, js ) )
elif str( cnt ) != root.get( "value_refs" ):
    print( "FAIL count differs: cli value_refs=%s json %s=%r" % ( root.get( "value_refs" ), sys.argv[4], cnt ) )
else:
    print( "OK" )
EOF
( cd "$FX/c" && "$BIN" . --callers=my_open --no-cache --legend=compact >"$TMP/cli.callers.xml" 2>/dev/null )
( cd "$FX/c" && "$BIN" . --callees=use_literal --no-cache --legend=compact >"$TMP/cli.callees.xml" 2>/dev/null )
( cd "$FX/c" && "$BIN" . --callers=my_open --no-cache --json >"$TMP/cli.callers.json" 2>/dev/null )
res="$( python3 "$TMP/par.py" "$TMP/cli.callers.xml" "$TMP/cli.callers.json" vr value_refs )"
verdict "D4 CLI --json callers carries the same value rows and value_refs" "$res"
mcp_call find_referencing_symbols '{"path":"'"$FX/c"'","symbol":"my_open"}' >"$TMP/mcp.frs.json"
res="$( python3 "$TMP/par.py" "$TMP/cli.callers.xml" "$TMP/mcp.frs.json" valueRefs value_refs )"
verdict "D5 MCP find_referencing_symbols == CLI --callers (valueRefs, value_refs)" "$res"
mcp_call find_symbol '{"path":"'"$FX/c"'","symbol":"my_open"}' >"$TMP/mcp.fs.json"
res="$( python3 "$TMP/par.py" "$TMP/cli.callers.xml" "$TMP/mcp.fs.json" valueRefs value_refs )"
verdict "D6 MCP find_symbol(my_open).valueRefs == CLI --callers" "$res"
mcp_call find_symbol '{"path":"'"$FX/c"'","symbol":"use_literal"}' >"$TMP/mcp.fs2.json"
res="$( python3 "$TMP/par.py" "$TMP/cli.callees.xml" "$TMP/mcp.fs2.json" valueCallees value_callees )"
verdict "D7 MCP find_symbol(use_literal).valueCallees == CLI --callees" "$res"
mcp_call impact '{"path":"'"$FX/c"'","symbol":"my_open","legend":"compact"}' >"$TMP/mcp.impact.xml"
res="$( python3 "$TMP/chk.py" "$FX/c" "$TMP/mcp.impact.xml" attr:value_refs=3 nvr:3 attr:reaches=0 )"
verdict "D8 MCP impact == CLI --impact (value_refs=3, three rows, reaches=0)" "$res"
mcp_call uses '{"path":"'"$FX/py"'","symbol":"foo_get","legend":"compact"}' >"$TMP/mcp.uses.xml"
res="$( python3 "$TMP/chk.py" "$FX/py" "$TMP/mcp.uses.xml" attr:count=3 'u:role=value;p=@P_DICT' 'nou:role=read' )"
verdict "D9 MCP uses == CLI --uses (role=value rows)" "$res"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/tools.json"
res="$( python3 - "$TMP/tools.json" <<'EOF'
import json, sys
try:
    tools = { t["name"]: t.get( "description", "" ) for t in json.load( open( sys.argv[1] ) )["result"]["tools"] }
except ( ValueError, KeyError ) as e:
    print( "FAIL tools/list unreadable: %s" % e ); raise SystemExit
bad = [ n for n in ( "find_referencing_symbols", "find_symbol" ) if "valueRefs" not in tools.get( n, "" ) ]
print( "FAIL description lacks valueRefs: " + ",".join( bad ) if bad else "OK" )
EOF
)"
verdict "D10 MCP tools/list: find_referencing_symbols and find_symbol describe valueRefs" "$res"

echo
if [ "$fail" -eq 0 ]; then echo "recallshapecheck: ALL PASS ($n CLI arms + disclosure)"; else echo "recallshapecheck: FAIL"; fi
exit "$fail"
