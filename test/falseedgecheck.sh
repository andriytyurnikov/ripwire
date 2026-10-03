#!/usr/bin/env bash
# falseedgecheck.sh — a call never binds by name alone to an in-repo definition the language says it cannot reach.
#
#   test/falseedgecheck.sh                          # uses build/ripwire on test/falseedgefix
#   RIPWIRE_BIN=asan/ripwire test/falseedgecheck.sh
#   test/falseedgecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. The name ladder in buildGraph binds a call to the lone in-repo definition of its spelling. Three call
# shapes have no in-repo target by the language's own rules, and still got one:
#   (1) a call with NO receiver bound to something such a call cannot reach: a Go/Python/JS method (none of the three
#       has an implicit `this`), a JS accessor (`new URL( u )` → a `get URL ()` getter), a C struct or enum (C has no
#       constructor call). Go `append( xs, x )` became a caller of `func ( h *History ) append`, and a C call of the
#       function opts_parse() was drawn to `struct opts_parse` instead of the function.
#   (2) a call to a language builtin or a global object: Go `append max copy delete len close`, JS/TS `JSON.*`,
#       `Buffer.*`, `Math.*`, `Object.*`, `Array.*`, `Promise.*`, `console.*`, `crypto.*`, the global `fetch`, bound
#       to a same-named in-repo function, method or object property that the calling file never imports.
#   (3) a call through a binding to a package OUTSIDE the tree: a CommonJS `require( 'pkg' )` (default, destructured,
#       or used as a receiver), an ES namespace import of a bare specifier, a Go import of a path outside the module.
# Each was a confident false row in a graded answer; this fixture holds a paraphrased minimal repro of each.
#
# THE CONTRACT. Such a call loses its in-repo edge and is counted EXTERNAL (one `C external` census row, the header's
# external=), never declined and never silently dropped. When the language makes exactly one in-repo FUNCTION
# reachable, that one is the edge (Python's imported `match`, C's function opts_parse). A name the calling scope
# defines, imports from inside the tree, or shadows keeps its edge: the near-miss arms below are true edges that must
# survive (a same-package Go `min` that shadows the builtin, a JS `const JSON = require( './query' )`, an imported
# in-repo `fetch`/`append`, a Go package-level function variable, an in-module Go import, a C++ constructor call).
#
# ARMS (one fixture root per language under test/falseedgefix/; each root is indexed on its own).
#   (A) Go:  builtin append/max/copy/delete/len/close never reach a method, a function-local var or another
#            package's function; qualified calls into an outside package (plain and aliased import) and the standard
#            library never reach a same-named in-repo function. Near misses keep: same-package `min` (shadows the
#            builtin), same-package `copy`, a receiver call `h.append()`, a package-level func VARIABLE called bare,
#            an in-module qualified call `own.Pick()`.
#   (B) JS:  JSON.stringify, `new URL()`, Buffer.from, console/Math/Object/Array/Promise members, require('destroy'),
#            require('supertest'), a receiver from require('qs') and a name destructured from require('cookie') never
#            reach an in-repo function, getter, method or object property. Near misses keep: a destructured relative
#            require, a relative-module receiver, a file-local `const JSON` shadow, a same-file `function fetch`, a
#            const arrow function, `ContentType.from` on the in-repo class, `this.set`/`this.get`.
#   (C) TS:  the global fetch never reaches a class FIELD named fetch, JSON.parse never reaches an exported `parse`,
#            crypto.subtle.verify never reaches an exported `verify`, `import * as qs from 'qs'` never reaches an
#            in-repo `stringify`; a file that imports nothing does not reach another file's exported `fetch` (root
#            tsimport/). Near misses keep: named imports of in-repo `parse` and `fetch`, `new App()` + `app.dispatch()`;
#            default and named imports of outside packages stay unbound (a pin: already true before this gate).
#   (D) Python (src/ layout): an imported module function `match` is the edge — not the two same-named methods; a
#            bare `process()` that only a METHOD defines has no edge. Near misses keep: imported in-repo `append`,
#            a same-module helper, a class-body call to a function of the class body. Pins: bare builtins `open` and
#            `format` reach neither the method nor the unimported module function.
#   (E) C:   `opts_parse( … )` reaches the FUNCTION, not `struct opts_parse`; `find_type( … )` never reaches
#            `enum find_type`; window_count() keeps its edge. C++ (root cpp/): `Point( v )` is a constructor call and
#            keeps both rows it had (the struct rule is C's alone).
#   (R) Rust (no implicit receiver either): a bare call imported from an outside crate never reaches a same-named
#            METHOD; a same-module free function and a receiver call keep their edges.
#   (F) propagation: --callers and --impact of the in-repo decoys no longer list the false callers.
#   (G) disclosure: every call the arms above unbind is a `C external` census row (empty targets), and every root's
#            census dispositions still sum to calls= with unaccounted=0.
#   (H) MCP twins: find_referencing_symbols and find_symbol carry exactly the CLI's rows (fresh TMPDIR cache).
#   (K) the predicates can fail: a document carrying the false row is caught; an empty document is not a pass.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that indexes a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/falseedgefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "falseedgecheck: BIN=$BIN  CORPUS=$CORPUS"

# rw ROOT ARGS… — run against one fixture root (every selector below is relative to that root's `.`)
rw(){ local r="$1"; shift; ( cd "$CORPUS/$r" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

# rows DOC — the answer's <s> rows as sorted "t n file" lines (p= without its line number), or the single line
# NOROOT when the document carries no callees/callers/impact root element, or one whose defs= is absent or 0 (the
# selector matched nothing) — so an empty answer, or one about no symbol, is never a pass
rows(){ python3 - "$1" <<'PY'
import re, sys
doc = open( sys.argv[ 1 ], encoding="utf-8", errors="replace" ).read()
root = re.search( r"<(callees|callers|impact) [^>]*>", doc )
defs = re.search( r' defs="([0-9]+)"', root.group( 0 ) ) if root else None
if not defs or int( defs.group( 1 ) ) < 1:
    print( "NOROOT" ); sys.exit( 0 )
out = set()
for s in re.findall( r"<s [^>]*/>", doc ):
    t = re.search( r' t="([^"]*)"', s ); n = re.search( r' n="([^"]*)"', s ); p = re.search( r' p="([^"]*)"', s )
    if t and n and p:
        out.add( "%s %s %s" % ( t.group( 1 ), n.group( 1 ), p.group( 1 ).rsplit( ":", 1 )[ 0 ] ) )
for line in sorted( out ):
    print( line )
PY
}
# answer ROOT VERB SEL — write the verb's answer to a per-call file and echo its path
answer(){ local f; f="$TMP/$1.$2.$( printf '%s' "$3" | tr '/:.' '___' ).xml"; rw "$1" "--$2=$3" >"$f"; printf '%s' "$f"; }
# lacks ROOT VERB SEL "N FILE" … — no row names N at FILE (any kind); the root element must be present
lacks(){
    local r="$1" v="$2" s="$3"; shift 3
    local f got; f="$( answer "$r" "$v" "$s" )"; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --$v=$s produced no <$v> answer about a symbol"; return; fi
    local nf
    for nf in "$@"; do
        if printf '%s\n' "$got" | grep -qE "^[^ ]+ ${nf% *} ${nf#* }\$"; then
            no "($r) --$v=$s still lists ${nf% *} at ${nf#* } — a false edge: $( printf '%s' "$got" | tr '\n' ';' )"
        else
            ok "($r) --$v=$s does not list ${nf% *} at ${nf#* }"
        fi
    done
}
# has ROOT VERB SEL "t n file" … — each named row is present (the near-miss form where other rows are not pinned)
has(){
    local r="$1" v="$2" s="$3"; shift 3
    local f got; f="$( answer "$r" "$v" "$s" )"; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --$v=$s produced no <$v> answer about a symbol"; return; fi
    local row
    for row in "$@"; do
        if printf '%s\n' "$got" | grep -qxF "$row"; then ok "($r) --$v=$s keeps the true edge [$row]"
        else no "($r) --$v=$s lost the true edge [$row]: $( printf '%s' "$got" | tr '\n' ';' )"; fi
    done
}
# exactly ROOT VERB SEL "t n file;t n file" — the exact row set (";"-separated, sorted); "" = no rows at all
exactly(){
    local r="$1" v="$2" s="$3" want="$4"
    local f got; f="$( answer "$r" "$v" "$s" )"; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --$v=$s produced no <$v> answer about a symbol"; return; fi
    got="$( printf '%s' "$got" | tr '\n' ';' | sed 's/;$//' )"
    if [ "$got" = "$want" ]; then ok "($r) --$v=$s rows are exactly [${want:-none}]"
    else no "($r) --$v=$s rows are [${got:-none}], want [${want:-none}]"; fi
}

# ── census: one per root, written FIRST so no arm reads a missing file ─────────────────────────────────────────
for r in go js ts tsimport py c cpp rs; do
    if ! rw "$r" --pin-census="$TMP/$r.tsv" >/dev/null; then no "($r) the census run exited non-zero"; fi
    if [ ! -s "$TMP/$r.tsv" ]; then no "($r) the census run wrote no census — every census arm for this root would be vacuous"; fi
done
# ext_row ROOT FILE CALLER CALLEE — the census holds a `C external` row for that caller and callee with no target
ext_row(){
    python3 - "$TMP/$1.tsv" "$2" "$3" "$4" <<'PY'
import sys
census, path, caller, callee = sys.argv[ 1: ]
for line in open( census, encoding="utf-8", errors="replace" ):
    f = line.rstrip( "\n" ).split( "\t" )
    if len( f ) < 9 or f[ 0 ] != "C" or f[ 1 ] != "external":
        continue
    cid = f[ 5 ]
    head, _, tail = cid.partition( "::" )
    if head == path and tail.rsplit( "#", 1 )[ 0 ].split( "::" )[ -1 ] == caller and f[ 6 ] == callee and f[ 7 ] == "":
        sys.exit( 0 )
sys.exit( 1 )
PY
}
externals(){
    local r="$1" file="$2" caller="$3"; shift 3
    local c
    for c in "$@"; do
        if ext_row "$r" "$file" "$caller" "$c"; then ok "(G) ($r) census: $caller → $c is a C external row"
        else no "(G) ($r) census: no C external row for $file $caller → $c (bound, declined or dropped instead)"; fi
    done
}

echo "=== (A) Go: builtins, outside packages, and receiverless calls to methods ==="
lacks go callees algo/algo.go:Collect "append hist/history.go" "max term/terminal.go" "copy util/copy.go" "len hist/cache.go"
lacks go callees algo/drain.go:Drain "delete hist/cache.go" "len hist/cache.go" "close hist/cache.go"
lacks go callees tui/screen.go:Open "NewScreen tui/screen.go" "Split tui/screen.go" "len hist/cache.go"
lacks go callees tui/paint.go:Paint "NewScreen tui/screen.go"
echo "--- (A) near misses: true edges kept"
exactly go callees own/own.go:Pick "fn min own/own.go;fn score own/own.go"
has go callees util/copy.go:Dup "fn copy util/copy.go"
lacks go callees util/copy.go:Dup "len hist/cache.go"
exactly go callees hist/history.go:Remember "method append hist/history.go"
exactly go callees own/hook.go:Fire "var hook own/hook.go"
exactly go callees algo/route.go:Route "fn Pick own/own.go"

echo "=== (B) JS: globals, required packages, accessors ==="
lacks js callees lib/response.js:length "stringify lib/query.js"
lacks js callees lib/response.js:redirect "URL lib/request.js"
lacks js callees lib/request.js:host "URL lib/request.js"
lacks js callees lib/response.js:finish "destroy helpers/stream.js"
lacks js callees lib/response.js:encode "from lib/content-type.js"
lacks js callees tests/response.test.js:checkStatus "request helpers/context.js"
exactly js callees lib/globals.js:summarize ""
lacks js callees lib/encode.js:toQuery "stringify lib/query.js"
lacks js callees lib/encode.js:readCookies "parse lib/query.js"
echo "--- (B) near misses: true edges kept"
exactly js callees tests/context.test.js:makeCtx "fn request helpers/context.js"
exactly js callees tests/context.test.js:encodeQuery "fn stringify lib/query.js"
exactly js callees lib/shadow.js:emit "fn stringify lib/query.js"
exactly js callees lib/shadow.js:load "fn fetch lib/shadow.js"
exactly js callees lib/arrow.js:clean "fn normalize lib/arrow.js"
exactly js callees lib/response.js:parseType "method from lib/content-type.js"
has js callees lib/response.js:redirect "method set lib/response.js"
has js callees lib/request.js:host "method get lib/request.js"

echo "=== (C) TS: globals and outside packages ==="
lacks ts callees src/utils/token.ts:fetchKeys "fetch src/base.ts"
lacks ts callees src/utils/token.ts:decodePart "parse src/utils/cookie.ts"
lacks ts callees src/utils/sig.ts:checkSig "verify src/utils/token.ts"
lacks ts callees src/client.ts:encode "stringify src/helpers.ts"
lacks tsimport callees src/remote.ts:pull "fetch src/client.ts"
echo "--- (C) near misses: true edges kept, and the outside-package pins"
exactly ts callees src/app.ts:readCookie "fn parse src/utils/cookie.ts"
exactly ts callees src/app.ts:serve "cls App src/base.ts;method dispatch src/base.ts"
exactly ts callees src/client.ts:probe ""
exactly ts callees src/client.ts:check ""
exactly tsimport callees src/use.ts:load "fn fetch src/client.ts"

echo "=== (D) Python: an imported function beats same-named methods; a bare call never reaches a method ==="
exactly py callees src/ui/widget.py:prune_children "fn match src/ui/css/match.py"
lacks py callees src/ui/widget.py:run_all "process src/ui/worker.py"
echo "--- (D) near misses: true edges kept, and the builtin pins"
exactly py callees src/ui/use_lists.py:grow "fn append src/ui/lists.py"
exactly py callees src/ui/use_lists.py:twice "fn helper src/ui/use_lists.py"
exactly py callees src/ui/worker.py:Worker "fn _default src/ui/worker.py"
lacks py callees src/ui/widget.py:read_config "open src/ui/worker.py"
lacks py callees src/ui/report.py:render "format src/ui/text.py"

echo "=== (E) C: a call never reaches a struct or an enum; C++ construction is untouched ==="
f="$( answer c callees copy.c:copy_command )"; got="$( rows "$f" )"
if [ "$got" = "NOROOT" ]; then no "(c) --callees=copy.c:copy_command produced no <callees> answer"
else
    if printf '%s\n' "$got" | grep -qE '^fn opts_parse (arguments\.c|mux\.h)$'; then
        ok "(c) copy_command → the FUNCTION opts_parse"
    else
        no "(c) copy_command does not reach the function opts_parse: $( printf '%s' "$got" | tr '\n' ';' )"
    fi
    if printf '%s\n' "$got" | grep -qE '^(cls|struct|enum|type|typedef) opts_parse '; then
        no "(c) copy_command still lists struct opts_parse: $( printf '%s' "$got" | tr '\n' ';' )"
    else
        ok "(c) copy_command does not list struct opts_parse"
    fi
fi
exactly c callees copy.c:classify "fn window_count window.c"
exactly cpp callees use.cpp:origin "cls Point point.hpp;fn Point point.hpp"

echo "=== (R) Rust: no implicit receiver either — a bare call never reaches a method ==="
lacks rs callees src/lib.rs:draw "render src/history.rs"
exactly rs callees src/lib.rs:paint "fn helper src/lib.rs;method render src/history.rs"

echo "=== (F) propagation: the decoys' callers and impact ==="
exactly go callers hist/history.go:append "fn Remember hist/history.go"
lacks go impact hist/history.go:append "Collect algo/algo.go"
lacks go impact hist/cache.go:len "Collect algo/algo.go" "Drain algo/drain.go" "Open tui/screen.go" "Dup util/copy.go"
exactly go callers util/copy.go:copy "fn Dup util/copy.go"
exactly js callers lib/query.js:stringify "fn emit lib/shadow.js;fn encodeQuery tests/context.test.js"
exactly js callers helpers/stream.js:destroy ""
exactly ts callers src/base.ts:fetch ""
exactly py callers src/ui/fuzzy.py:match ""

echo "=== (G) disclosure: each unbound call is a C external census row; conservation per root ==="
externals go algo/algo.go Collect append max copy len
externals go util/copy.go Dup len
externals go algo/drain.go Drain delete len close
externals go tui/screen.go Open NewScreen Split len
externals go tui/paint.go Paint NewScreen
externals js lib/response.js length stringify
externals js lib/response.js redirect URL
externals js lib/request.js host URL
externals js lib/response.js finish destroy
externals js lib/response.js encode from
externals js tests/response.test.js checkStatus request
externals js lib/globals.js summarize log keys max from resolve
externals js lib/encode.js toQuery stringify
externals js lib/encode.js readCookies parse
externals ts src/utils/token.ts fetchKeys fetch
externals ts src/utils/token.ts decodePart parse
externals ts src/utils/sig.ts checkSig verify
externals ts src/client.ts encode stringify
externals tsimport src/remote.ts pull fetch
externals py src/ui/widget.py run_all process
externals c copy.c classify find_type
externals rs src/lib.rs draw render
for r in go js ts tsimport py c cpp rs; do
    DL="$( grep -m1 '^# dispositions ' "$TMP/$r.tsv" 2>/dev/null )"
    if [ -z "$DL" ]; then no "(G) ($r) the census carries no '# dispositions' line"; continue; fi
    if python3 - "$DL" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[ 1 ] ) )
if "calls" not in kv or "unaccounted" not in kv:
    sys.exit( 1 )
total = kv.pop( "calls" )
sys.exit( 0 if kv[ "unaccounted" ] == 0 and sum( kv.values() ) == total else 1 )
PY
    then
        ok "(G) ($r) dispositions sum to calls= with unaccounted=0"
    else
        no "(G) ($r) conservation broken: $DL"
    fi
done

echo "=== (H) MCP twins (fresh TMPDIR: the MCP cache lives there) ==="
mcp_json(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp 2>/dev/null | tail -1
}
mkdir -p "$TMP/mcp"
# mcp_names TOOL ARGS FIELD — the "name@file" entries of one array of the answer, sorted, ";"-joined; NOJSON if none
mcp_names(){
    mcp_json "$1" "$2" | python3 -c '
import json, sys
try:
    r = json.load( sys.stdin ); d = json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] )
except Exception:
    print( "NOJSON" ); sys.exit( 0 )
arr = d.get( sys.argv[ 1 ] )
if arr is None:
    print( "NOJSON" ); sys.exit( 0 )
print( ";".join( sorted( "%s@%s" % ( e.get( "name" ), e.get( "file" ) ) for e in arr ) ) )' "$3"
}
# margs ROOT SELECTOR — the tool arguments (built by printf: no brace expansion can split them)
margs(){ printf '{"path":"%s","symbol":"%s"}' "$CORPUS/$1" "$2"; }
mcp_is(){
    local what="$1" got="$2" want="$3"
    if [ "$got" = "NOJSON" ]; then no "(H) $what: no JSON answer with that array"
    elif [ "$got" = "$want" ]; then ok "(H) $what = [${want:-none}]"
    else no "(H) $what = [${got:-none}], want [${want:-none}]"; fi
}
mcp_is "find_referencing_symbols hist/history.go:append calledBy" \
    "$( mcp_names find_referencing_symbols "$( margs go hist/history.go:append )" calledBy )" \
    "Remember@hist/history.go"
mcp_is "find_symbol Collect calls" \
    "$( mcp_names find_symbol "$( margs go algo/algo.go:Collect )" calls )" ""
mcp_is "find_symbol Pick calls (near miss)" \
    "$( mcp_names find_symbol "$( margs go own/own.go:Pick )" calls )" "min@own/own.go;score@own/own.go"
mcp_is "find_symbol prune_children calls" \
    "$( mcp_names find_symbol "$( margs py src/ui/widget.py:prune_children )" calls )" "match@src/ui/css/match.py"
mcp_is "find_symbol fetchKeys calls" \
    "$( mcp_names find_symbol "$( margs ts src/utils/token.ts:fetchKeys )" calls )" ""

echo "=== (K) the predicates can fail ==="
printf '<callees of="x" defs="1"><s t="method" n="append" p="hist/history.go:6"/></callees>' >"$TMP/k1.xml"
got="$( rows "$TMP/k1.xml" )"
if [ "$got" = "method append hist/history.go" ]; then ok "(K) rows() reads a false row back"
else no "(K) rows() missed a planted row: [$got]"; fi
printf 'nothing here' >"$TMP/k2.xml"
if [ "$( rows "$TMP/k2.xml" )" = "NOROOT" ]; then ok "(K) an answer with no root element is NOROOT, never an empty pass"
else no "(K) rows() treated a rootless document as an answer"; fi
printf '<callers of="x" found="0"/>' >"$TMP/k3.xml"
if [ "$( rows "$TMP/k3.xml" )" = "NOROOT" ]; then ok "(K) an answer about no symbol (no defs=) is NOROOT, never an empty pass"
else no "(K) rows() treated a not-found answer as an empty answer"; fi
printf 'C\tunique\t1\t1\t-\talgo/algo.go::Collect#1\tappend\thist/history.go::append#3\t10\n' >"$TMP/k.tsv"
if ext_row k algo/algo.go Collect append; then no "(K) ext_row accepted a BOUND census row as external"
else ok "(K) ext_row rejects a bound census row"; fi
printf 'C\texternal\t1\t0\t-\talgo/algo.go::Collect#1\tappend\t\t10\n' >"$TMP/k.tsv"
if ext_row k algo/algo.go Collect append; then ok "(K) ext_row reads a planted external row back"
else no "(K) ext_row missed a planted external row"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; exit 1; fi
