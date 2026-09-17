#!/usr/bin/env bash
# qbaselineproducercheck.sh — a .ripwire_quality_baseline sidecar is a floor only for the build that pinned it.
#
# THE BUG THIS PINS. `--quality-baseline` writes a sidecar holding `dead <key>` records, and a dead set is a
# function of CALL RESOLUTION (quality.h isDeadCandidate reads g.inEdges). The sidecar stamped only `head <sha>`,
# and --quality-delta's one staleness test (selectBaseline) compared only that. So at the SAME HEAD a floor pinned
# by one build was compared against another build's working-tree dead set — the qsnap cache defect
# (test/qsnapproducercheck.sh) in the file a user writes on purpose. The window is ordinary: pin with the PATH
# binary, then run the delta with ./build/ripwire, or after an upgrade, before the next commit.
#
# MEASURED before the fix, two real builds of d8c225a2 — as built, and with graph.h's keepStdQualifiedCandidates
# forced to `return true` (the std::-qualified call guard off) — over this gate's fixture, where
# `std::launder( &v )` binds the in-repo Pool::launder only without the guard:
#   PHANTOM, working tree untouched but for a comment:
#     pin guarded,   delta guarded     baseline="sidecar" gating="0", exit 0
#     pin unguarded, delta guarded     baseline="sidecar" gating="1", exit 2 — a dead-code row on Pool::launder
#   HIDDEN, working tree drops the std::launder call (Pool::launder really loses its only caller):
#     pin unguarded, delta unguarded   baseline="sidecar" gating="1", exit 2 — the real regression
#     pin guarded,   delta unguarded   baseline="sidecar" gating="0", exit 0 — the regression is hidden
#
# THE FIX. The sidecar format is v6: it carries `producer <64 hex>`, the build's producer identity
# (cmake/source_identity.cmake — SHA-256 over src/ and queries/). A sidecar pinned at the current HEAD whose
# producer is absent or differs is FOREIGN: never honored, never deleted (the build that pinned it may run
# again), and the delta falls back to the git-HEAD tree THIS build computes, disclosed as
# baseline="git-HEAD (foreign sidecar ignored)". A root with no git HEAD has nothing to fall back to and exits
# 1 naming the foreign pin. A v5 sidecar can only come from a build without the stamp, so the version rule
# refuses it — and that refusal now lands on the marker that says a sidecar is there.
#
# Checks (a forged pair differs in exactly ONE thing, and the mutation is asserted to have taken):
#   (A) FORMAT — the binary's own pin is v6 and carries exactly one producer record, equal to this tree's
#       identity: $BIN was built from these sources and says so.
#   (B) HONORED — this build's own pin is the floor (baseline="sidecar", exit 0) and is left byte-identical.
#   (C) PHANTOM — the pin with its dead records dropped (a resolver that saw a caller for Pool::launder):
#         C1 producer kept    -> served: a gating dead-code row the no-sidecar run lacks (the control)
#         C2 producer flipped -> ignored: rows and exit equal the no-sidecar run, the marker says why, the
#                                file stays on disk byte-identical, stderr names the foreign pin
#   (D) HIDDEN — the working tree deletes useIt's only call; the pin gains useIt's dead key, read from a real
#       pin at a scratch commit where useIt is dead (a resolver that never saw the call):
#         D1 producer kept    -> served: the real regression disappears (the control)
#         D2 producer flipped -> ignored: the regression is reported, exit equal to the no-sidecar run
#   (E) UNSTAMPED — a v6 pin with its producer record deleted is not honored: nothing says which build wrote it.
#   (F) PRE-STAMP — the v5 shape (older header, no producer) is refused by the version rule and reported as
#       baseline="git-HEAD (sidecar unreadable)", never as "no sidecar": the file is right there.
#   (G) STALE WINS — a pin that is BOTH at another sha and from another build keeps the stale self-heal.
#   (H) NO GIT — this build's pin is honored in a non-git root; a foreign one exits 1 naming it, never "no <file>",
#       and is left on disk; a v5 one exits 1 naming the refusal, never "no <file>".
#   (I) MCP — the read-only quality_delta verb answers the D pair the same way (served / ignored, file kept).
#   (J) DISCLOSURE — the full legend defines the foreign marker; --help names it.
#
# Uses its own temp repos and a private XDG_CACHE_HOME (TMPDIR unset). Needs git, cmake and python3.
# Usage:  test/qbaselineproducercheck.sh   |   RIPWIRE_BIN=build/ripwire test/qbaselineproducercheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
IDSCRIPT="$ROOT/cmake/source_identity.cmake"
CMAKE="${CMAKE:-cmake}"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -f "$IDSCRIPT" ] || { echo "no $IDSCRIPT — run from the repo"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v "$CMAKE" >/dev/null 2>&1 || { echo "cmake required (set CMAKE=)"; exit 2; }

echo "qbaselineproducercheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
XDG="$TMP/xdg"; mkdir -p "$XDG"
REPO="$TMP/repo"; SIDE="$REPO/.ripwire_quality_baseline"

rw(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$@"; }
pin(){ rw "$1" --quality-baseline >/dev/null 2>&1; }
# delta NAME ROOT [flags]: stdout -> $TMP/NAME.out, stderr -> $TMP/NAME.err, exit code -> $TMP/NAME.rc
delta(){ local n="$1" r="$2"; shift 2; rw "$r" --quality-delta --legend=compact "$@" >"$TMP/$n.out" 2>"$TMP/$n.err"; echo $? >"$TMP/$n.rc"; }
rc_of(){ cat "$TMP/$1.rc"; }
marker_of(){ sed -n 's/.*<quality-delta [^>]*baseline="\([^"]*\)".*/\1/p' "$TMP/$1.out" | head -1; }
rows_of(){ tr '<' '\n' <"$TMP/$1.out" | grep '^r kind=' ; }
# same findings AND same exit as a reference run
same_answer(){ [ "$( rows_of "$1" )" = "$( rows_of "$2" )" ] && [ "$( rc_of "$1" )" = "$( rc_of "$2" )" ]; }
# flip the producer record's last hex digit — the one-thing-different mutation
flip_producer(){ python3 - "$1" "$2" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().split("\n")
for i, l in enumerate(lines):
    m = re.fullmatch(r"producer ([0-9a-f]{64})", l)
    if m:
        h = m.group(1)
        lines[i] = "producer " + h[:-1] + ("1" if h[-1] == "0" else "0")
        break
open(dst, "w").write("\n".join(lines))
PYEOF
}

# ── fixture: `std::launder` binds the in-repo Pool::launder only for a resolver without the std:: guard ────
mkdir -p "$REPO/src"
cat > "$REPO/src/pool.cpp" <<'EOF'
struct Pool
{
    int launder( int x ) { int s = x; for( int i = 0; i < x; ++i ) { s += i; } return s; }
};
EOF
cat > "$REPO/src/use.cpp" <<'EOF'
#include <new>
int useIt( int v ) { return *std::launder( &v ) + 1; }
int main() { return useIt( 1 ); }
EOF
printf '.ripwire_quality_baseline\n' > "$REPO/.gitignore"
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init

# ── (A) FORMAT ──────────────────────────────────────────────────────────────────────────────────────────────
pin "$REPO"
if [ ! -f "$SIDE" ]; then
    no "(A) --quality-baseline wrote no sidecar on a clean committed tree — every later arm would be vacuous"
    echo "qbaselineproducercheck: SOME CHECKS FAILED"; exit 1
fi
cp "$SIDE" "$TMP/pin0"
head -1 "$TMP/pin0" | grep -q '^# ripwire quality baseline v6 ' \
    && ok "(A) the sidecar header names format v6" \
    || no "(A) the sidecar header is '$( head -1 "$TMP/pin0" )', not v6 — an older binary would read a producer-stamped pin as its own"
ID="$( "$CMAKE" -DRIPWIRE_SOURCE_DIR="$ROOT" -P "$IDSCRIPT" 2>/dev/null | sed -n 's/^-- source_identity=\([0-9a-f]\{64\}\)$/\1/p' )"
PRODUCERS="$( grep -c '^producer ' "$TMP/pin0" )"
PRODUCER="$( sed -n 's/^producer \([0-9a-f]\{64\}\)$/\1/p' "$TMP/pin0" | head -1 )"
if [ "$PRODUCERS" -ne 1 ] || [ -z "$PRODUCER" ]; then
    no "(A) the sidecar carries $PRODUCERS producer record(s) and no 64-hex value — nothing says which build computed its dead set"
elif [ -z "$ID" ]; then
    no "(A) cmake/source_identity.cmake printed no identity for this tree — cannot compare the stamp"
else
    [ "$PRODUCER" = "$ID" ] \
        && ok "(A) exactly one producer record, equal to this tree's source identity (${ID:0:16}…)" \
        || no "(A) producer ${PRODUCER:0:16}… != this tree's identity ${ID:0:16}… — was $BIN built from THIS tree? rebuild and re-run"
fi
DEADN="$( grep -c '^dead ' "$TMP/pin0" )"
[ "$DEADN" -ge 1 ] \
    && ok "(A) the pin's dead set is non-empty ($DEADN) — Pool::launder has no caller for this build" \
    || no "(A) the pin's dead set is empty — the phantom forgery below would drop nothing (fixture drifted)"

# the no-sidecar reference for the untouched tree
echo "// touch" >> "$REPO/src/use.cpp"
mv "$SIDE" "$TMP/pin0.parked"
delta c_ref "$REPO"
mv "$TMP/pin0.parked" "$SIDE"
[ "$( marker_of c_ref )" = "git-HEAD" ] || no "(C) setup: the no-sidecar run reports baseline=\"$( marker_of c_ref )\", not git-HEAD"

# ── (B) HONORED ─────────────────────────────────────────────────────────────────────────────────────────────
delta b "$REPO"
{ [ "$( marker_of b )" = "sidecar" ] && [ "$( rc_of b )" -eq 0 ] && cmp -s "$SIDE" "$TMP/pin0"; } \
    && ok "(B) this build's own pin is the floor: baseline=\"sidecar\", exit 0, file untouched" \
    || no "(B) this build's own pin was not honored (baseline=\"$( marker_of b )\", exit $( rc_of b )) — the producer check rejects what it wrote"

# ── (C) PHANTOM ─────────────────────────────────────────────────────────────────────────────────────────────
grep -v '^dead ' "$TMP/pin0" > "$TMP/c1"
flip_producer "$TMP/c1" "$TMP/c2"
cmp -s "$TMP/pin0" "$TMP/c1" && no "(C) dropping the dead records did not change the pin — C1 would serve the original"

cp "$TMP/c1" "$SIDE"; delta c1 "$REPO"
{ [ "$( marker_of c1 )" = "sidecar" ] && ! rows_of c_ref | grep -q 'kind="dead-code"' && rows_of c1 | grep -q 'kind="dead-code".*gating="1"'; } \
    && ok "(C1) control: the forged dead set, producer kept, IS served — a gating dead-code row the no-sidecar run lacks (exit $( rc_of c_ref ) -> $( rc_of c1 ))" \
    || no "(C1) control did not fire (baseline=\"$( marker_of c1 )\", exit $( rc_of c1 )) — the forgery cannot show a foreign dead set is harmful"

if cmp -s "$TMP/c1" "$TMP/c2"; then
    no "(C2) the pin has no producer record to flip — a sidecar another build pinned is indistinguishable from this build's, and is served"
else
    cp "$TMP/c2" "$SIDE"; delta c2 "$REPO"
    [ "$( marker_of c2 )" = "git-HEAD (foreign sidecar ignored)" ] \
        && ok "(C2) the same forgery from ANOTHER build is not the floor: baseline=\"git-HEAD (foreign sidecar ignored)\"" \
        || no "(C2) a sidecar from another build reports baseline=\"$( marker_of c2 )\""
    same_answer c2 c_ref \
        && ok "(C2) its findings and exit equal the no-sidecar git-HEAD run (exit $( rc_of c2 ))" \
        || { no "(C2) a sidecar from another build changed the answer (exit ref=$( rc_of c_ref ) foreign=$( rc_of c2 ))"; diff <( rows_of c_ref ) <( rows_of c2 ) | head -4; }
    cmp -s "$SIDE" "$TMP/c2" \
        && ok "(C2) the foreign pin is left on disk byte-identical — the build that pinned it may run again" \
        || no "(C2) the foreign pin was removed or rewritten by a delta run"
    grep -q 'pinned by another ripwire build' "$TMP/c2.err" && ! grep -q "^ripwire: no " "$TMP/c2.err" \
        && ok "(C2) stderr names the foreign pin, and never says there is no sidecar" \
        || { no "(C2) stderr does not name the foreign pin truthfully"; head -3 "$TMP/c2.err"; }
fi

# ── (D) HIDDEN ──────────────────────────────────────────────────────────────────────────────────────────────
git -C "$REPO" checkout -q -- src/use.cpp
rm -f "$SIDE"
cat > "$REPO/src/use.cpp" <<'EOF'
#include <new>
int useIt( int v ) { return *std::launder( &v ) + 1; }
int main() { return 1; }
EOF
git -C "$REPO" commit -qam "drop the call"
pin "$REPO"; cp "$SIDE" "$TMP/pin_scratch" 2>/dev/null || : >"$TMP/pin_scratch"
git -C "$REPO" reset -q --soft HEAD~1                          # HEAD back to init; the working tree keeps the deletion
NEWKEYS="$( comm -13 <( sed -n 's/^dead //p' "$TMP/pin0" | sort ) <( sed -n 's/^dead //p' "$TMP/pin_scratch" | sort ) )"
rm -f "$SIDE"; delta d_ref "$REPO"
if [ -z "$NEWKEYS" ]; then
    no "(D) no key is dead at the scratch commit and alive at HEAD — the hidden-direction forgery would be vacuous"
elif ! rows_of d_ref | grep -q 'kind="dead-code".*gating="1"'; then
    no "(D) the no-sidecar run reports no gating dead-code row for the deleted call — the hidden arms would be vacuous"
else
    ok "(D) the deleted call is a real gating dead-code regression with no sidecar (exit $( rc_of d_ref ))"
    { cat "$TMP/pin0"; printf 'dead %s\n' $NEWKEYS; } > "$TMP/d1"
    flip_producer "$TMP/d1" "$TMP/d2"
    cp "$TMP/d1" "$SIDE"; delta d1 "$REPO"
    { [ "$( marker_of d1 )" = "sidecar" ] && ! rows_of d1 | grep -q 'kind="dead-code"' && [ "$( rc_of d1 )" -ne "$( rc_of d_ref )" ]; } \
        && ok "(D1) control: the forged dead set, producer kept, IS served — the real regression disappears (exit $( rc_of d_ref ) -> $( rc_of d1 ))" \
        || no "(D1) control did not fire (baseline=\"$( marker_of d1 )\", exit $( rc_of d1 ))"
    if cmp -s "$TMP/d1" "$TMP/d2"; then
        no "(D2) the pin has no producer record to flip — another build's dead set hides a real regression, unseen"
    else
        cp "$TMP/d2" "$SIDE"; delta d2 "$REPO"
        { [ "$( marker_of d2 )" = "git-HEAD (foreign sidecar ignored)" ] && same_answer d2 d_ref; } \
            && ok "(D2) the same forgery from ANOTHER build is ignored — the regression is reported, exit $( rc_of d2 ) as with no sidecar" \
            || { no "(D2) a sidecar from another build hid a real regression (baseline=\"$( marker_of d2 )\", exit ref=$( rc_of d_ref ) foreign=$( rc_of d2 ))"; diff <( rows_of d_ref ) <( rows_of d2 ) | head -4; }
    fi
fi

# ── (E) UNSTAMPED v6 ────────────────────────────────────────────────────────────────────────────────────────
grep -v '^producer ' "$TMP/pin0" > "$TMP/e"
if cmp -s "$TMP/pin0" "$TMP/e"; then
    no "(E) the pin has no producer record to delete — an unstamped pin cannot be told from a stamped one"
else
    cp "$TMP/e" "$SIDE"; delta e "$REPO"
    { [ "$( marker_of e )" = "git-HEAD (foreign sidecar ignored)" ] && same_answer e d_ref; } \
        && ok "(E) a v6 pin with no producer record is not honored — nothing says which build computed it" \
        || no "(E) an unstamped v6 pin reports baseline=\"$( marker_of e )\", exit $( rc_of e ) (no-sidecar exit $( rc_of d_ref ))"
fi

# ── (F) PRE-STAMP v5 ────────────────────────────────────────────────────────────────────────────────────────
grep -v '^producer ' "$TMP/pin0" | sed '1s/^# ripwire quality baseline v[0-9]* /# ripwire quality baseline v5 /' > "$TMP/f"
head -1 "$TMP/f" | grep -q ' v5 ' || no "(F) the v5 header rewrite did not take"
cp "$TMP/f" "$SIDE"; delta f "$REPO"
[ "$( marker_of f )" = "git-HEAD (sidecar unreadable)" ] \
    && ok "(F) a v5 sidecar is refused and reported as a sidecar that is there: baseline=\"git-HEAD (sidecar unreadable)\"" \
    || no "(F) a v5 sidecar reports baseline=\"$( marker_of f )\" — 'sidecar' serves an unstamped dead set, bare 'git-HEAD' says no sidecar existed"
{ grep -q "predates this binary's baseline format" "$TMP/f.err" && ! grep -q "^ripwire: no " "$TMP/f.err"; } \
    && ok "(F) stderr names the format refusal and never says there is no sidecar" \
    || { no "(F) stderr about the refused v5 sidecar is missing or contradicts itself"; head -3 "$TMP/f.err"; }
same_answer f d_ref \
    && ok "(F) its findings and exit equal the no-sidecar run" \
    || no "(F) a refused v5 sidecar changed the answer (exit ref=$( rc_of d_ref ) v5=$( rc_of f ))"

# ── (G) STALE WINS ──────────────────────────────────────────────────────────────────────────────────────────
flip_producer "$TMP/pin0" "$TMP/g0"
sed 's/^head [0-9a-f]*$/head 0123456789abcdef0123456789abcdef01234567/' "$TMP/g0" > "$TMP/g"
cmp -s "$TMP/g0" "$TMP/g" && no "(G) the head-stamp rewrite did not take"
cp "$TMP/g" "$SIDE"; delta g "$REPO"
{ [ "$( marker_of g )" = "git-HEAD (stale sidecar removed)" ] && [ ! -e "$SIDE" ]; } \
    && ok "(G) a pin at another sha AND from another build is STALE: removed, as the staleness rule always did" \
    || no "(G) a stale foreign pin reports baseline=\"$( marker_of g )\" (file still there: $( [ -e "$SIDE" ] && echo yes || echo no ))"

# ── (H) NO GIT ──────────────────────────────────────────────────────────────────────────────────────────────
NG="$TMP/nogit"; mkdir -p "$NG/src"
cp "$REPO/src/pool.cpp" "$NG/src/"
printf 'int useIt( int v ) { return v + 1; }\nint main() { return useIt( 1 ); }\n' > "$NG/src/use.cpp"
pin "$NG"
if [ ! -f "$NG/.ripwire_quality_baseline" ]; then
    no "(H) --quality-baseline wrote no sidecar in a non-git root — the arm would be vacuous"
else
    delta h1 "$NG"
    { [ "$( marker_of h1 )" = "sidecar" ] && [ "$( rc_of h1 )" -eq 0 ]; } \
        && ok "(H) control: this build's pin is honored in a non-git root (baseline=\"sidecar\", exit 0)" \
        || no "(H) this build's own pin was not honored in a non-git root (baseline=\"$( marker_of h1 )\", exit $( rc_of h1 ))"
    flip_producer "$NG/.ripwire_quality_baseline" "$TMP/h2"
    if cmp -s "$NG/.ripwire_quality_baseline" "$TMP/h2"; then
        no "(H) the non-git pin has no producer record to flip — another build's pin is honored where there is no HEAD to check it against"
    else
        cp "$TMP/h2" "$NG/.ripwire_quality_baseline"; delta h2 "$NG"
        { [ "$( rc_of h2 )" -eq 1 ] && grep -q 'pinned by another ripwire build' "$TMP/h2.err" && ! grep -q "^ripwire: no " "$TMP/h2.err"; } \
            && ok "(H) a foreign pin in a non-git root exits 1 naming it — there is no HEAD tree to fall back to" \
            || { no "(H) a foreign pin in a non-git root: exit $( rc_of h2 ), stderr does not name it truthfully"; head -2 "$TMP/h2.err"; }
        cmp -s "$NG/.ripwire_quality_baseline" "$TMP/h2" \
            && ok "(H) the foreign pin is left on disk" \
            || no "(H) the foreign pin was removed or rewritten in a non-git root"
    fi
    grep -v '^producer ' "$TMP/h2" | sed '1s/^# ripwire quality baseline v[0-9]* /# ripwire quality baseline v5 /' > "$NG/.ripwire_quality_baseline"
    delta h3 "$NG"
    { [ "$( rc_of h3 )" -eq 1 ] && grep -q "predates this binary's baseline format" "$TMP/h3.err" && ! grep -q "^ripwire: no " "$TMP/h3.err"; } \
        && ok "(H) a v5 sidecar in a non-git root exits 1 and never says there is no sidecar" \
        || { no "(H) a v5 sidecar in a non-git root: exit $( rc_of h3 ), stderr contradicts the file on disk"; head -2 "$TMP/h3.err"; }
fi

# ── (I) MCP ─────────────────────────────────────────────────────────────────────────────────────────────────
mcp_baseline(){ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$REPO"'"}}}' \
    | env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" --mcp 2>/dev/null | tail -1 \
    | python3 -c 'import sys, json
r = json.load(sys.stdin)
if "error" in r or r.get("result", {}).get("isError"):
    print("__ERROR__")
else:
    d = json.loads(r["result"]["content"][0]["text"])
    print("%s|%d" % (d["baseline"], d["gating"]))' 2>/dev/null; }
if [ -f "$TMP/d2" ] && ! cmp -s "$TMP/d1" "$TMP/d2"; then
    cp "$TMP/d1" "$SIDE"; M1="$( mcp_baseline )"
    [ "$M1" = "sidecar|0" ] \
        && ok "(I) MCP control: this build's stamp, forged dead set served (sidecar, gating 0)" \
        || no "(I) MCP control did not fire: '$M1'"
    cp "$TMP/d2" "$SIDE"; M2="$( mcp_baseline )"
    case "$M2" in
        "git-HEAD (foreign sidecar ignored)|0"|"__ERROR__"|"") no "(I) MCP quality_delta on another build's pin: '$M2'" ;;
        "git-HEAD (foreign sidecar ignored)|"*) ok "(I) MCP quality_delta ignores another build's pin and reports the regression ($M2)" ;;
        *) no "(I) MCP quality_delta on another build's pin: '$M2'" ;;
    esac
    if cmp -s "$SIDE" "$TMP/d2"; then
        ok "(I) the read-only verb leaves the foreign pin on disk"
    else
        no "(I) the MCP verb changed the foreign pin on disk"
    fi
else
    no "(I) no D pair to drive the MCP arm with (see (D))"
fi

# ── (J) DISCLOSURE ──────────────────────────────────────────────────────────────────────────────────────────
cp "$TMP/d2" "$SIDE" 2>/dev/null
rw "$REPO" --quality-delta >"$TMP/j.out" 2>/dev/null
grep -q 'baseline="git-HEAD (foreign sidecar ignored)" means' "$TMP/j.out" \
    && ok "(J) the full legend defines the foreign marker it emits" \
    || no "(J) the full legend does not define baseline=\"git-HEAD (foreign sidecar ignored)\""
"$BIN" --help=all >"$TMP/help" 2>/dev/null
[ -s "$TMP/help" ] || no "(J) --help=all printed nothing — the help arm below would be vacuous"
tr -s ' \n' ' ' <"$TMP/help" | grep -q 'git-HEAD (foreign sidecar ignored)' \
    && ok "(J) --help names the foreign-sidecar marker before anyone runs the verb" \
    || no "(J) --help does not name baseline=\"git-HEAD (foreign sidecar ignored)\""

[ "$fail" -eq 0 ] && echo "qbaselineproducercheck: ALL PASS" || { echo "qbaselineproducercheck: SOME CHECKS FAILED"; exit 1; }
