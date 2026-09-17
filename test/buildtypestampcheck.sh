#!/usr/bin/env bash
# buildtypestampcheck.sh — gate for the build-type token `--version` prints, under EVERY CMake generator.
#
# `ripwire --version` says `(dev, …)` / `(Release, …)`, and several gates decide "can this binary print a
# DEGRADED_PATH_ALERT?" from that token (test/pargates.py build_type_of/NDEBUG_BUILD_TYPES, kotlincheck §12,
# estchargecheck, localscountcheck, qualitystalecheck, churnjoincheck, preproccondcheck, w3fixlegendcheck).
# The token came from CMAKE_BUILD_TYPE alone. A MULTI-CONFIG generator (Ninja Multi-Config, Xcode) leaves that
# empty, so `cmake --build b --config Release` — NDEBUG defined, every alert compiled out — printed `dev`
# (CodeRabbit on PR #261, test/pargates.py:840).
#
# Putting `$<CONFIG>` into the stamp COMMAND is NOT enough, and the reason is why this gate resolves headers
# instead of reading one path: version.h used to be ONE output shared by every configuration. Measured
# 2026-09-16 on a two-file probe (cmake 4.3.4, ninja 1.13.2): with a shared byproduct and a `$<CONFIG>` token,
# a cross-config Ninja Multi-Config build (CMAKE_CROSS_CONFIGS=all) collapses the stamp to ONE command, and the
# Debug, Release and RelWithDebInfo binaries ALL printed `Debug`. Sequential single-config builds happened to
# come out right, recompiling the including TU on every config switch. So the contract asserted here is
# "each configuration's compile sees a header that names THAT configuration, and no other configuration's
# build can rewrite it".
#
# It drives the REAL CMakeLists.txt (configure is ~1 s: every dependency is vendored), builds only the
# ripwire_version_stamp target (a cmake -P script, no compiler), and asks CMake's own File API which include
# directories the `ripwire` target compiles src/main.cpp with, per configuration. The resolver then does what
# the preprocessor does for `#include "version.h"` in src/cli.h: the including file's directory first, then the
# include path in order, first hit wins. No ripwire binary is built or run.
#
# Checks:
#   1) single-config (Unix Makefiles), no CMAKE_BUILD_TYPE (the house dev configure): token `dev`, at <build>/generated/version.h.
#   2) single-config, -DCMAKE_BUILD_TYPE=Release (a scratch tree — never the dev tree): token `Release`, same path.
#   3) multi-config (Ninja Multi-Config if ninja is on PATH, else Xcode, else a named SKIP): Debug then Release,
#      each configuration's compile resolves a header naming itself.
#   4) …the two configurations resolve DIFFERENT header files, and stamping Release left the Debug header's bytes
#      and mtime untouched (so an interleaved build cannot bake the other token in).
#   5) …re-stamping Debug does not rewrite its header (copy_if_different holds per config: no forced recompile).
#   6) Ninja Multi-Config only: one cross-config build of every configuration stamps each with its own token —
#      the exact scenario that produced three `Debug` binaries.
#   7) controls: the token extraction reads a mutated copy's value; the resolver prefers the including file's
#      directory, so it reads what the preprocessor would, not a fixed path.
#
# Observed RED (2026-09-16, on f57a9df3's CMakeLists.txt): arms 3, 4, 5 and 6 under Ninja Multi-Config, and 3, 4 and 5
# under Xcode (ninja off PATH) — every configuration resolved `dev` from the one shared generated/version.h. Against
# the `$<CONFIG>`-token-only fix, arms 3 and 7 pass while 4, 5 and 6 stay RED, #6 reading Release="Debug"
# RelWithDebInfo="Debug" — so the arms tell that fix apart from the per-configuration header.
#
# Usage: test/buildtypestampcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }   # an ABSENT PRECONDITION with a named reason — never a silent pass

command -v cmake >/dev/null 2>&1 || { echo "no cmake on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3 on PATH"; exit 2; }
echo "buildtypestampcheck: ROOT=$ROOT"

# CMake also takes its generator, build type and configuration list from the ENVIRONMENT (CMAKE_GENERATOR; since 3.22
# CMAKE_BUILD_TYPE and CMAKE_CONFIGURATION_TYPES). Observed RED 2026-09-17 with each exported: CMAKE_GENERATOR="Ninja
# Multi-Config" made both single-config trees multi-config, CMAKE_BUILD_TYPE=Release turned `dev` into `Release`, and
# CMAKE_CONFIGURATION_TYPES=RelWithDebInfo removed Debug and Release. So every cmake call scrubs those three, and every
# configure names its generator (CodeRabbit on #264). CMAKE_CONFIG_TYPE, CMAKE_GENERATOR_PLATFORM and
# CMAKE_GENERATOR_TOOLSET were tried too and changed nothing, so they are not scrubbed.
cleanCmake(){
    env -u CMAKE_GENERATOR -u CMAKE_BUILD_TYPE -u CMAKE_CONFIGURATION_TYPES cmake "$@"
}

# Configure the real tree into $1 with the File API codemodel query planted first, so the reply exists.
configure(){
    local dir="$1"
    shift
    mkdir -p "$dir/.cmake/api/v1/query"
    : >"$dir/.cmake/api/v1/query/codemodel-v2"
    cleanCmake -S "$ROOT" -B "$dir" "$@" >"$dir.configure.log" 2>&1
}

# Build ONLY the stamp target; $2 is the configuration (empty for a single-config tree).
stamp(){
    local dir="$1" config="$2"
    if [ -n "$config" ]; then
        cleanCmake --build "$dir" --config "$config" --target ripwire_version_stamp >>"$dir.build.log" 2>&1
    else
        cleanCmake --build "$dir" --target ripwire_version_stamp >>"$dir.build.log" 2>&1
    fi
}

# `token FILE` — the kRipwireBuildType value a header spells, or nothing.
token(){
    sed -nE 's/.*kRipwireBuildType[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$1" | head -1
}

# `resolve BUILD CONFIG INCLUDER_DIR` — prints the header `#include "version.h"` reaches from src/cli.h when the
# `ripwire` target compiles src/main.cpp in CONFIG (empty = a single-config tree's only configuration), per CMake's
# File API reply. Exit 3 = no such header, exit 2 =
# the reply could not be read (named on stderr). INCLUDER_DIR is the quoted-include search's first directory.
resolve(){
    python3 - "$@" <<'PY'
import glob, json, os, sys
build, config, includer = sys.argv[1], sys.argv[2], sys.argv[3]
reply = os.path.join(build, '.cmake', 'api', 'v1', 'reply')
def load(name):
    with open(os.path.join(reply, name), encoding='utf-8') as fh:
        return json.load(fh)
indexes = sorted(glob.glob(os.path.join(reply, 'index-*.json')))
if not indexes:
    print(f'no File API index under {reply}', file=sys.stderr); sys.exit(2)
index = load(os.path.basename(indexes[-1]))
model = next((o for o in index.get('objects', []) if o.get('kind') == 'codemodel'), None)
if model is None:
    print('File API reply has no codemodel object', file=sys.stderr); sys.exit(2)
codemodel = load(model['jsonFile'])
configurations = codemodel.get('configurations', [])
names = [c.get('name') for c in configurations]
if config == '':
    # A single-config tree: its ONE configuration is named after CMAKE_BUILD_TYPE ('' when unset).
    if len(configurations) != 1:
        print(f'expected exactly one configuration in a single-config tree, have {names}', file=sys.stderr); sys.exit(2)
    conf = configurations[0]
else:
    conf = next((c for c in configurations if c.get('name') == config), None)
if conf is None:
    print(f'no configuration {config!r} in the codemodel (have {names})', file=sys.stderr); sys.exit(2)
ref = next((t for t in conf.get('targets', []) if t.get('name') == 'ripwire'), None)
if ref is None:
    print(f'no ripwire target in configuration {config!r}', file=sys.stderr); sys.exit(2)
target = load(ref['jsonFile'])
sources = target.get('sources', [])
group = None
for g in target.get('compileGroups', []):
    if any(sources[i].get('path', '').replace('\\', '/').endswith('src/main.cpp') for i in g.get('sourceIndexes', [])):
        group = g
        break
if group is None:
    print(f'no compile group holds src/main.cpp for {config!r}', file=sys.stderr); sys.exit(2)
dirs = [includer] + [inc['path'] for inc in group.get('includes', [])]
for d in dirs:
    candidate = os.path.join(d, 'version.h')
    if os.path.isfile(candidate):
        print(os.path.realpath(candidate)); sys.exit(0)
print(f'version.h is not reachable from {len(dirs)} include dir(s) for {config!r}', file=sys.stderr)
sys.exit(3)
PY
}

mtimeOf(){ python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }

# ── #1/#2 single-config: the spellings that must not move ────────────────────────────────────────────────────────
singleArm(){
    local label="$1" expect="$2"
    shift 2
    local dir="$TMP/single-$label"
    if ! configure "$dir" "$@"; then
        no "single-config $label: configure failed — tail: $( tail -3 "$dir.configure.log" | tr '\n' ' ' )"
        return
    fi
    if ! stamp "$dir" ""; then
        no "single-config $label: building ripwire_version_stamp failed — tail: $( tail -3 "$dir.build.log" | tr '\n' ' ' )"
        return
    fi
    local header got
    header="$( resolve "$dir" "" "$ROOT/src" )" || { no "single-config $label: no version.h resolved for the ripwire compile"; return; }
    got="$( token "$header" )"
    if [ "$got" = "$expect" ]; then
        ok "single-config $label: the ripwire compile sees kRipwireBuildType=\"$expect\""
    else
        no "single-config $label: the ripwire compile sees kRipwireBuildType=\"$got\", expected \"$expect\" ($header)"
    fi
    if [ "$header" = "$( cd "$dir" && pwd -P )/generated/version.h" ]; then
        ok "single-config $label: the header is still <build>/generated/version.h"
    else
        no "single-config $label: the header moved to $header (single-config layout must not change)"
    fi
}
# The house dev configure's generator on every supported host, named rather than inherited.
singleArm dev dev -G "Unix Makefiles"
singleArm Release Release -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release

# ── #3-#6 multi-config ────────────────────────────────────────────────────────────────────────────────────────────
MULTI_GEN=""
if command -v ninja >/dev/null 2>&1; then
    MULTI_GEN="Ninja Multi-Config"
elif [ "$( uname -s )" = "Darwin" ] && xcodebuild -version >/dev/null 2>&1; then
    MULTI_GEN="Xcode"
fi

if [ -z "$MULTI_GEN" ]; then
    skip "#3-#6 no multi-config generator on this host (no ninja on PATH, no usable Xcode) — the multi-config token is unproven here"
else
    echo "buildtypestampcheck: multi-config generator = $MULTI_GEN"
    MC="$TMP/multi"
    if ! configure "$MC" -G "$MULTI_GEN"; then
        no "multi-config ($MULTI_GEN): configure failed — tail: $( tail -3 "$MC.configure.log" | tr '\n' ' ' )"
    else
        declare -a seen=()
        for config in Debug Release; do
            if ! stamp "$MC" "$config"; then
                no "#3 $MULTI_GEN $config: building ripwire_version_stamp failed — tail: $( tail -3 "$MC.build.log" | tr '\n' ' ' )"
                continue
            fi
            if ! header="$( resolve "$MC" "$config" "$ROOT/src" )"; then
                no "#3 $MULTI_GEN $config: no version.h resolved for the ripwire compile"
                continue
            fi
            got="$( token "$header" )"
            if [ "$got" = "$config" ]; then
                ok "#3 $MULTI_GEN $config: the ripwire compile sees kRipwireBuildType=\"$config\""
            else
                no "#3 $MULTI_GEN $config: the ripwire compile sees kRipwireBuildType=\"$got\", expected \"$config\" ($header)"
            fi
            if [ "$config" = Debug ]; then
                debugHeader="$header"
                cp "$header" "$TMP/debug-before.h"
                debugMtime="$( mtimeOf "$header" )"
            fi
            seen+=( "$header" )
        done

        if [ "${#seen[@]}" -eq 2 ]; then
            if [ "${seen[0]}" != "${seen[1]}" ]; then
                ok "#4 Debug and Release resolve different header files"
            else
                no "#4 Debug and Release share ONE header (${seen[0]}) — the last configuration stamped wins for both"
            fi
            debugNow="$( resolve "$MC" Debug "$ROOT/src" )" || debugNow=""
            if [ "$debugNow" = "$debugHeader" ] && [ "$( token "$debugNow" )" = Debug ] \
                && cmp -s "$debugHeader" "$TMP/debug-before.h" && [ "$( mtimeOf "$debugHeader" )" = "$debugMtime" ]; then
                ok "#4 stamping Release left the Debug header untouched (bytes, mtime, token Debug)"
            else
                no "#4 stamping Release disturbed what the Debug compile sees (now '$debugNow', token '$( [ -n "$debugNow" ] && token "$debugNow" )')"
            fi

            if stamp "$MC" Debug && [ "$( mtimeOf "$debugHeader" )" = "$debugMtime" ] && [ "$( token "$debugHeader" )" = Debug ]; then
                ok "#5 re-stamping Debug kept its header's mtime (no forced recompile of Debug objects)"
            else
                no "#5 re-stamping Debug rewrote its header (mtime $debugMtime -> $( mtimeOf "$debugHeader" ), token '$( token "$debugHeader" )')"
            fi
        else
            no "#4/#5 not reached: only ${#seen[@]} of 2 configurations resolved a header"
        fi
    fi

    if [ "$MULTI_GEN" = "Ninja Multi-Config" ]; then
        XC="$TMP/cross"
        if ! configure "$XC" -G "$MULTI_GEN" -DCMAKE_CROSS_CONFIGS=all -DCMAKE_DEFAULT_CONFIGS=all; then
            no "#6 cross-config configure failed — tail: $( tail -3 "$XC.configure.log" | tr '\n' ' ' )"
        elif ! stamp "$XC" ""; then
            no "#6 cross-config build of ripwire_version_stamp failed — tail: $( tail -3 "$XC.build.log" | tr '\n' ' ' )"
        else
            crossBad=""
            for config in Debug Release RelWithDebInfo; do
                header="$( resolve "$XC" "$config" "$ROOT/src" )" || { crossBad="$crossBad $config=<unresolved>"; continue; }
                got="$( token "$header" )"
                [ "$got" = "$config" ] || crossBad="$crossBad $config=\"$got\""
            done
            if [ -z "$crossBad" ]; then
                ok "#6 one cross-config build stamps Debug, Release and RelWithDebInfo each with its own token"
            else
                no "#6 one cross-config build left configurations with another's token:$crossBad"
            fi
        fi
    else
        skip "#6 the cross-config build is a Ninja Multi-Config feature; $MULTI_GEN builds one configuration per invocation"
    fi
fi

# ── #7 controls ──────────────────────────────────────────────────────────────────────────────────────────────────
# (a) the extraction reads the value that is there: mutate a real stamped header, re-run the identical extraction.
realHeader="$TMP/single-dev/generated/version.h"
if [ -f "$realHeader" ]; then
    sed 's/kRipwireBuildType   = "[^"]*"/kRipwireBuildType   = "MUTATED"/' "$realHeader" >"$TMP/mutated.h"
    if cmp -s "$realHeader" "$TMP/mutated.h"; then
        no "#7a mutation control did not take — the stamped header's token line could not be rewritten"
    elif [ "$( token "$TMP/mutated.h" )" = MUTATED ] && [ "$( token "$realHeader" )" = dev ]; then
        ok "#7a token extraction reads a mutated copy's value (MUTATED) and the original's (dev)"
    else
        no "#7a token extraction is inert: mutated copy reads '$( token "$TMP/mutated.h" )', original '$( token "$realHeader" )'"
    fi
else
    no "#7a no stamped header from arm #1 to mutate ($realHeader)"
fi
# (b) the resolver honours quoted-include precedence: a version.h in the including file's directory must win.
if [ -f "$realHeader" ]; then
    mkdir -p "$TMP/planted"
    cp "$TMP/mutated.h" "$TMP/planted/version.h"
    planted="$( resolve "$TMP/single-dev" "" "$TMP/planted" )" || planted=""
    unplanted="$( resolve "$TMP/single-dev" "" "$ROOT/src" )" || unplanted=""
    if [ "$planted" = "$( cd "$TMP/planted" && pwd -P )/version.h" ] && [ "$( token "$planted" )" = MUTATED ] \
        && [ "$unplanted" != "$planted" ]; then
        ok "#7b resolver prefers the including file's directory (planted header wins; without it, the build's header)"
    else
        no "#7b resolver ignores include precedence: planted='$planted' unplanted='$unplanted'"
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
