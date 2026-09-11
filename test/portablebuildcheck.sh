#!/usr/bin/env bash
# portablebuildcheck.sh — gate for L1 ( independence MUST-FIX #5): "Non-NATIVE build hardcodes
# -mcpu=apple-m1 -ffast-math — Linux/x86 fails out of the box".
#
# Exercises the REAL arch-flag-selection logic in cmake/PortableFlags.cmake — not a reimplementation —
# by include()-ing it into a tiny standalone CMakeLists.txt in a scratch dir. This is deliberately NOT a
# full `cmake -S . -B ...` configure of the real project: that would pay for all 15 FetchContent grammar
# clones just to inspect three compiler flags. PortableFlags.cmake only touches APPLE/CMAKE_SYSTEM_PROCESSOR
# and the two options, so a `project(x LANGUAGES NONE)` host is enough to drive it for real.
#
# Checks:
#   1) default (no flags) configure on THIS machine: if this machine really is Apple Silicon, the auto
#      -mcpu=apple-m1 branch must fire (proves auto-detect still gives Apple-Silicon devs today's behavior).
#   2) default configure + RIPWIRE_PRETEND_LINUX=ON (the test-only hook): must emit -O2 -ffast-math
#      -fno-finite-math-only and NOTHING Apple/host-specific (-mcpu=apple-m1 absent, -march=native absent).
#      This is the provable half of "Linux/x86-64/aarch64 must configure cleanly with no Apple flags" —
#      see the NOTE at the bottom for what this machine cannot prove.
#   3) RIPWIRE_NATIVE=ON: must emit -march=native (opt-in, unaffected by RIPWIRE_PRETEND_LINUX).
#   4) the real top-level CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally (it must be
#      confined to the RIPWIRE_IS_APPLE_SILICON branch inside cmake/PortableFlags.cmake).
#   5) the real top-level CMakeLists.txt still routes through cmake/PortableFlags.cmake (didn't drift back
#      to an inline literal).
#
# Usage: test/portablebuildcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
MODULE="$ROOT/cmake/PortableFlags.cmake"
CMAKE_TOP="$ROOT/CMakeLists.txt"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v cmake >/dev/null 2>&1 || { echo "no cmake on PATH"; exit 2; }
[ -f "$MODULE" ] || { echo "missing $MODULE"; exit 2; }

# Build a tiny standalone project dir that only includes PortableFlags.cmake and prints its result.
# $2, when given, overrides CMAKE_SYSTEM_PROCESSOR before the include — the only way this
# Apple-Silicon machine can drive the x86-64 branch of the real module (LANGUAGES NONE means no
# toolchain probe runs afterwards to overwrite it).
mk_probe(){
    local dir="$1"
    local proc="${2:-}"
    mkdir -p "$dir/src"
    {
        printf 'cmake_minimum_required(VERSION 3.24)\n'
        printf 'project(portableprobe LANGUAGES NONE)\n'
        [ -n "$proc" ] && printf 'set(CMAKE_SYSTEM_PROCESSOR %s)\n' "$proc"
        printf 'include("%s")\n' "$MODULE"
    } >"$dir/CMakeLists.txt"
}

# Configure the probe with the given extra -D args; echoes the RIPWIRE_ARCH_FLAGS line (without the
# 'RIPWIRE_ARCH_FLAGS:' prefix), or nothing if the configure failed outright.
run_probe(){
    local dir="$1"; shift
    local proc="${PROBE_PROC:-}"
    mk_probe "$dir" "$proc"
    local log="$dir/configure.log"
    if ! cmake -S "$dir" -B "$dir/build" "$@" >"$log" 2>&1; then
        printf 'CONFIGURE_FAILED\n'
        return
    fi
    grep -o 'RIPWIRE_ARCH_FLAGS:.*' "$log" | tail -1 | sed 's/^RIPWIRE_ARCH_FLAGS://'
}

echo "portablebuildcheck: BIN=n/a (CMake-configure-level gate, no ripwire binary needed)"

# ── #1: default configure on THIS machine — Apple Silicon devs keep today's behavior ───────────────────
hostFlags="$( run_probe "$TMP/host" )"
hostArch="$( uname -s ):$( uname -m )"
if [ "$( uname -s )" = "Darwin" ] && { [ "$( uname -m )" = "arm64" ] || [ "$( uname -m )" = "aarch64" ]; }; then
    if printf '%s' "$hostFlags" | grep -q -- '-mcpu=apple-m1'; then
        ok "default configure on real Apple Silicon ($hostArch) auto-applies -mcpu=apple-m1: '$hostFlags'"
    else
        no "default configure on real Apple Silicon ($hostArch) did NOT apply -mcpu=apple-m1: '$hostFlags'"
    fi
else
    skip_note="host is $hostArch, not Apple Silicon — auto-detect branch not exercised by #1 on this machine"
    printf '  SKIP  %s\n' "$skip_note"
fi

# ── #2: RIPWIRE_PRETEND_LINUX=ON — the provable portable-path check ────────────────────────────────────
linuxFlags="$( run_probe "$TMP/linux" -DRIPWIRE_PRETEND_LINUX=ON )"
if [ "$linuxFlags" = "CONFIGURE_FAILED" ]; then
    no "RIPWIRE_PRETEND_LINUX=ON configure failed outright: $(tail -5 "$TMP/linux/configure.log" 2>/dev/null)"
elif printf '%s' "$linuxFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "RIPWIRE_PRETEND_LINUX=ON still emits -mcpu=apple-m1: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-march=native'; then
    no "RIPWIRE_PRETEND_LINUX=ON still emits -march=native: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-O2' && printf '%s' "$linuxFlags" | grep -q -- '-ffast-math' \
     && printf '%s' "$linuxFlags" | grep -q -- '-fno-finite-math-only'; then
    ok "RIPWIRE_PRETEND_LINUX=ON configures clean with NO Apple/host-specific flag: '$linuxFlags'"
else
    no "RIPWIRE_PRETEND_LINUX=ON flags missing expected portable baseline: '$linuxFlags'"
fi

# ── #2b: the x86-64 FLOOR — an x86-64 target MUST carry -march=x86-64-v3 ──────────────────────────────
# Not cosmetic: src/infra/strkern.h compiles its AVX2 mirror behind __AVX2__, which only this flag defines
# on a portable build. Drop the flag and every x86-64 binary silently falls back to the scalar twins —
# correct output, several times the CPU on every text-scanning verb, and nothing else in the tree notices.
# The owner's floor is v3 (AVX2 + BMI1/2 + FMA + LZCNT + MOVBE, the RHEL 10 level), never v4/AVX-512.
x86Flags="$( PROBE_PROC=x86_64 run_probe "$TMP/x86" -DRIPWIRE_PRETEND_LINUX=ON )"
if [ "$x86Flags" = "CONFIGURE_FAILED" ]; then
    no "#2b x86-64 probe configure failed outright: $(tail -5 "$TMP/x86/configure.log" 2>/dev/null)"
elif ! printf '%s' "$x86Flags" | grep -q -- '-march=x86-64-v3'; then
    no "#2b an x86-64 target did NOT get the -march=x86-64-v3 floor (strkern.h's AVX2 path would not compile): '$x86Flags'"
elif printf '%s' "$x86Flags" | grep -qE -- '-march=x86-64-v4|-mavx512'; then
    no "#2b x86-64 floor was raised to v4/AVX-512, which the owner decision excludes: '$x86Flags'"
elif printf '%s' "$x86Flags" | grep -q -- '-mcpu=apple-m1'; then
    no "#2b x86-64 target also emits -mcpu=apple-m1: '$x86Flags'"
else
    ok "#2b x86-64 target carries the v3 floor and nothing Apple-specific: '$x86Flags'"
fi

# ── #2c: the floor is x86-ONLY — an aarch64 Linux target must not be handed an x86 -march ─────────────
armFlags="$( PROBE_PROC=aarch64 run_probe "$TMP/arm" -DRIPWIRE_PRETEND_LINUX=ON )"
# The sentinel FIRST (CodeRabbit #127 / 3985249736): CONFIGURE_FAILED contains no '-march=x86' either, so
# without this arm a broken aarch64-specific CMake path reported PASS on this portability gate — the exact
# shape #2b above already guards against, missing on the one arm whose expectation is an ABSENCE.
if [ "$armFlags" = "CONFIGURE_FAILED" ]; then
    no "#2c aarch64 probe configure failed outright: $(tail -5 "$TMP/arm/configure.log" 2>/dev/null)"
elif printf '%s' "$armFlags" | grep -q -- '-march=x86'; then
    no "#2c an aarch64 target was handed an x86 architecture flag: '$armFlags'"
else
    ok "#2c aarch64 target stays generic (NEON is baseline there, no flag needed): '$armFlags'"
fi

# ── #2d-#2g: the TARGET architecture decides the floor, never the HOST ─────────────────────────────────
# release.yml builds the macOS x86_64 binary ON an arm64 runner: `-DCMAKE_OSX_ARCHITECTURES=x86_64`. CMake
# derives CMAKE_SYSTEM_PROCESSOR from the RUNNING machine there (arm64 — CMakeDetermineSystem honours only
# CMAKE_APPLE_SILICON_PROCESSOR, never CMAKE_OSX_ARCHITECTURES), so a floor keyed on it handed every x86_64
# compile `-mcpu=apple-m1` and no -march at all. Clang >= 17 (AppleClang 16 — the Xcode 16.2 release.yml
# pins since c7982037) rejects that outright: "unsupported option '-mcpu=' for target". Clang 16 (AppleClang
# 15, every release through v0.5.0) let it through, so the Intel-Mac binary could only ever have been the
# x86-64 BASELINE — strkern.h's scalar twins, below the owner's v3 floor, and nothing else in the tree notices.
# #2b cannot see this: it SETS CMAKE_SYSTEM_PROCESSOR=x86_64, which a real cross configure never does.
# Darwin-only: CMAKE_OSX_ARCHITECTURES is a no-op everywhere else, and the Linux legs build natively (#2b/#2c).
cat >"$TMP/ccverdict.py" <<'PY'
# Reads a real configure's compile_commands.json; prints PASS/FAIL lines, then DONE (absent DONE = no verdict).
import json, shlex, subprocess, sys
ccPath, srcPrefix = sys.argv[ 1 ], sys.argv[ 2 ]
def argv( e ):
    return list( e[ 'arguments' ] ) if 'arguments' in e else shlex.split( e[ 'command' ] )
def targetsX86( a ):
    return any( a[ i ] == '-arch' and i + 1 < len( a ) and a[ i + 1 ] == 'x86_64' for i in range( len( a ) ) )
try:
    entries = [ e for e in json.load( open( ccPath ) ) if e.get( 'file', '' ).startswith( srcPrefix ) ]
except Exception as exc:
    entries = None
    print( 'FAIL compile_commands.json unreadable: %s' % exc )
if entries is not None and not entries:
    print( 'FAIL compile_commands.json lists no src/ translation unit — nothing was checked' )
elif entries:
    n   = len( entries )
    rel = lambda e: 'src/' + e[ 'file' ][ len( srcPrefix ): ]
    x86 = [ e for e in entries if targetsX86( argv( e ) ) ]
    v3  = [ e for e in entries if '-march=x86-64-v3' in argv( e ) ]
    m1  = [ e for e in entries if '-mcpu=apple-m1' in argv( e ) ]
    print( '%s %d of %d src/ compile lines target -arch x86_64 (the cross configure reached the compiler)' % ( 'PASS' if len( x86 ) == n else 'FAIL', len( x86 ), n ) )
    missing = [ rel( e ) for e in entries if '-march=x86-64-v3' not in argv( e ) ]
    print( '%s %d of %d src/ compile lines carry -march=x86-64-v3%s' % ( 'PASS' if not missing else 'FAIL', len( v3 ), n, ' (first without: %s)' % missing[ 0 ] if missing else '' ) )
    print( '%s %d of %d src/ compile lines carry -mcpu=apple-m1%s' % ( 'FAIL' if m1 else 'PASS', len( m1 ), n, ' (first: %s)' % rel( m1[ 0 ] ) if m1 else '' ) )
    # The macros the compiler DEFINES on one shipped TU's exact line (ingest.cpp includes strkern.h): the
    # flag list proves intent, only the preprocessor proves strkern.h's `#elif defined( __AVX2__ )` is taken.
    probe = next( ( e for e in entries if e[ 'file' ].endswith( '/src/ingest.cpp' ) ), entries[ 0 ] )
    line, skipNext = [], False
    for tok in argv( probe ):
        if skipNext:
            skipNext = False
        elif tok in ( '-o', '-MT', '-MF' ):
            skipNext = True
        elif tok not in ( '-c', '-MD', probe[ 'file' ] ):
            line.append( tok )
    r = subprocess.run( line + [ '-dM', '-E', '-x', 'c++', '/dev/null' ], cwd=probe.get( 'directory' ), capture_output=True, text=True )
    defs = { l.split()[ 1 ] for l in r.stdout.splitlines() if l.startswith( '#define ' ) and len( l.split() ) > 1 }
    if r.returncode != 0:
        print( 'FAIL the compiler REJECTED %s\'s exact x86_64 command line (rc=%d): %s' % ( rel( probe ), r.returncode, ( r.stderr.strip().splitlines() or [ '(no stderr)' ] )[ 0 ] ) )
    elif '__x86_64__' in defs and '__AVX2__' in defs:
        print( 'PASS %s\'s exact command line defines __x86_64__ and __AVX2__ — strkern.h compiles its AVX2 path' % rel( probe ) )
    else:
        print( 'FAIL %s\'s exact command line: __x86_64__=%s __AVX2__=%s — the shipped x86_64 binary would carry the SCALAR twins' % ( rel( probe ), '__x86_64__' in defs, '__AVX2__' in defs ) )
print( 'DONE' )
PY
if [ "$( uname -s )" = "Darwin" ]; then
    hostCpu="$( uname -m )"
    # #2d: module level, the host's own CMAKE_SYSTEM_PROCESSOR left alone — only the TARGET is named
    osxX86Flags="$( run_probe "$TMP/osx-x86" -DCMAKE_OSX_ARCHITECTURES=x86_64 )"
    if [ "$osxX86Flags" = "CONFIGURE_FAILED" ]; then
        no "#2d CMAKE_OSX_ARCHITECTURES=x86_64 probe configure failed outright: $(tail -5 "$TMP/osx-x86/configure.log" 2>/dev/null)"
    elif printf '%s' "$osxX86Flags" | grep -q -- '-mcpu=apple-m1'; then
        no "#2d an x86_64 target on a $hostCpu host was handed -mcpu=apple-m1 — the HOST chose the flags, not the target: '$osxX86Flags'"
    elif ! printf '%s' "$osxX86Flags" | grep -q -- '-march=x86-64-v3'; then
        no "#2d an x86_64 target on a $hostCpu host did NOT get the -march=x86-64-v3 floor: '$osxX86Flags'"
    else
        ok "#2d CMAKE_OSX_ARCHITECTURES=x86_64 on a $hostCpu host carries the v3 floor and nothing Apple-specific: '$osxX86Flags'"
    fi
    # #2e: the other direction — an arm64 target keeps its Apple Silicon tuning whatever the host is
    osxArmFlags="$( run_probe "$TMP/osx-arm" -DCMAKE_OSX_ARCHITECTURES=arm64 )"
    if [ "$osxArmFlags" = "CONFIGURE_FAILED" ]; then
        no "#2e CMAKE_OSX_ARCHITECTURES=arm64 probe configure failed outright: $(tail -5 "$TMP/osx-arm/configure.log" 2>/dev/null)"
    elif printf '%s' "$osxArmFlags" | grep -q -- '-march=x86'; then
        no "#2e an arm64 target on a $hostCpu host was handed an x86 architecture flag: '$osxArmFlags'"
    elif ! printf '%s' "$osxArmFlags" | grep -q -- '-mcpu=apple-m1'; then
        no "#2e an arm64 target on a $hostCpu host lost its Apple Silicon tuning: '$osxArmFlags'"
    else
        ok "#2e CMAKE_OSX_ARCHITECTURES=arm64 on a $hostCpu host keeps -mcpu=apple-m1: '$osxArmFlags'"
    fi
    # #2f: a universal tree cannot give one slice -march=x86-64-v3 and the other -mcpu=apple-m1 through one
    # add_compile_options(), and release.yml never builds one — the module must REFUSE it by name rather than
    # hand both slices one arch's flags (this same defect, on half the binary)
    fatFlags="$( run_probe "$TMP/osx-fat" '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64' )"
    if [ "$fatFlags" = "CONFIGURE_FAILED" ] && grep -q 'one architecture per build tree' "$TMP/osx-fat/configure.log"; then
        ok "#2f a universal CMAKE_OSX_ARCHITECTURES=x86_64;arm64 configure is refused by name, not given one slice's flags"
    elif [ "$fatFlags" = "CONFIGURE_FAILED" ]; then
        no "#2f the universal configure failed, but not with the refusal: $(tail -5 "$TMP/osx-fat/configure.log" 2>/dev/null)"
    else
        no "#2f a universal CMAKE_OSX_ARCHITECTURES=x86_64;arm64 configure was ACCEPTED with one flag set for both slices: '$fatFlags'"
    fi
    # #2g: the REAL project, exactly as release.yml configures its macos-x64 leg — every src/ compile line, and
    # the macros the compiler defines on one of them
    if ! cmake -S "$ROOT" -B "$TMP/real-x86" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
               -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >"$TMP/real-x86.log" 2>&1; then
        no "#2g the real project's x86_64-target configure failed: $(tail -5 "$TMP/real-x86.log" 2>/dev/null)"
    else
        realVerdict="$( python3 "$TMP/ccverdict.py" "$TMP/real-x86/compile_commands.json" "$ROOT/src/" 2>&1 )"
        # a here-string, not a pipe: rows read in a pipeline subshell would print FAIL and leave fail=0
        while IFS= read -r row; do
            case "$row" in
                PASS\ *) ok "#2g ${row#PASS }" ;;
                FAIL\ *) no "#2g ${row#FAIL }" ;;
            esac
        done <<<"$realVerdict"
        printf '%s\n' "$realVerdict" | grep -q '^DONE$' \
            || no "#2g the compile_commands verdict never finished — no evidence either way: $( printf '%s' "$realVerdict" | tail -3 )"
    fi
else
    printf '  SKIP  #2d-#2g host is %s: CMAKE_OSX_ARCHITECTURES is Darwin-only (a no-op here); native Linux targets are #2b/#2c and the ubuntu CI legs\n' "$( uname -s )"
fi

# ── #2h: the release leg that CROSS-BUILDS x86_64 runs on the exact tuple it was verified on ──────────────────────
# #2d-#2g make the macos-x64 binary an x86-64-v3 binary, and release.yml then EXECUTES it on its arm64 runner
# under Rosetta 2: scripts/pgobuild.sh's nine instrumented training runs, the determinism diff, --version and
# the smoke test. So the runner's Rosetta must execute the v3 extensions the binary carries (AVX2, BMI1/2, FMA,
# LZCNT, MOVBE). Sonoma's cannot — macos-14 runners SIGILL a -march=x86-64-v3 slice at its first vector
# instruction (test/strkerncheck.sh, PR #127 run 4, rc 132); macOS 15's gained AVX2, but its LZCNT/MOVBE coverage
# was never verified; macos-26 with Xcode 26.6 ran the leg green. And a newer runner raises the binary's minimum
# macOS with it: with no deployment target clang takes the lower of the runner's macOS and the SDK default (14.x
# on macos-14, 26.0 on macos-26), so the target is PINNED at 14.0, a decision rather than a side effect of the
# runner. A bound is not enough — "macos-N with N >= 15" plus "any numeric target" passed a macos-15 leg pinned
# at 26.0 — so the verdict holds the exact tuple. Text-level; any host.
cat >"$TMP/relverdict.py" <<'PY'
import re, sys
text = open( sys.argv[ 1 ] ).read()
matrix = text.split( 'include:', 1 )[ 1 ].split( '\n    runs-on:', 1 )[ 0 ] if 'include:' in text else ''
cross = [ leg for leg in re.split( r'\n\s*- name: ', matrix ) if 'CMAKE_OSX_ARCHITECTURES=x86_64' in leg ]
# The tuple the leg was VERIFIED on, held exactly. Changing the runner or the Xcode is a deliberate edit to release.yml AND
# to this tuple, made together with fresh evidence: the runner's Rosetta 2 decides which x86-64-v3 instructions the PGO
# training, determinism and smoke runs can execute, and the Xcode is the compiler that ran them green. The minimum macOS
# stays "14.0" (the std::print floor src/infra/emit.h names), or macOS 14/15 Intel users are dropped without a word —
# quoted, because a bare 14.0 is a YAML number, not the string the release's otool minos check matches.
RUNNER, XCODE, MINOS = 'macos-26', '/Applications/Xcode_26.6.app/Contents/Developer', '14.0'
EXPECT = ( ( 'os',                RUNNER, False, 'the runner whose Rosetta 2 ran this leg\'s x86-64-v3 PGO training and smoke green' ),
           ( 'developer_dir',     XCODE,  False, 'the Xcode the leg was verified with' ),
           ( 'deployment_target', MINOS,  True,  'the minimum macOS the release keeps' ) )
def scalar( leg, key ):
    m = re.search( r"""^[ \t]*%s:[ \t]*("[^"\n]*"|'[^'\n]*'|[^\s#]+)""" % key, leg, re.M )
    if not m:
        return None, False
    raw    = m.group( 1 )
    quoted = len( raw ) >= 2 and raw[ 0 ] == raw[ -1 ] and raw[ 0 ] in '"\''
    return ( raw[ 1:-1 ] if quoted else raw ), quoted
def shown( value, quoted ):
    return '(absent)' if value is None else ( '"%s"' % value if quoted else value )
if len( cross ) != 1:
    print( 'FAIL expected exactly one release leg with CMAKE_OSX_ARCHITECTURES=x86_64, found %d — nothing was checked' % len( cross ) )
else:
    leg  = cross[ 0 ]
    name = leg.split( '\n', 1 )[ 0 ].strip()
    for key, want, mustQuote, why in EXPECT:
        got, quoted = scalar( leg, key )
        if got == want and ( quoted or not mustQuote ):
            print( 'PASS leg %s %s: %s, %s' % ( name, key, shown( want, mustQuote ), why ) )
        else:
            print( 'FAIL leg %s %s: %s%s, but the verified tuple is %s — %s; moving it edits release.yml and #2h\'s tuple together, deliberately'
                   % ( name, key, shown( got, quoted ), ' (a bare YAML number)' if got == want else '', shown( want, mustQuote ), why ) )
    # Each pin must also REACH the build. The deployment target through the step's export, with no -D on the leg that
    # disagrees (CMake reads MACOSX_DEPLOYMENT_TARGET only when CMAKE_OSX_DEPLOYMENT_TARGET is not given); the Xcode
    # through the job env's DEVELOPER_DIR, without which the image's default Xcode builds the release.
    exported = 'MACOSX_DEPLOYMENT_TARGET=${{ matrix.deployment_target }}' in text
    override = [ v for v in re.findall( r'CMAKE_OSX_DEPLOYMENT_TARGET=(\S+)', leg ) if v != MINOS ]
    if not exported:
        print( 'FAIL leg %s: no step exports matrix.deployment_target as MACOSX_DEPLOYMENT_TARGET — the key pins nothing; the runner\'s macOS sets the minimum' % name )
    elif override:
        print( 'FAIL leg %s: -DCMAKE_OSX_DEPLOYMENT_TARGET=%s on the leg overrides the exported %s — the pinned minimum is not what ships' % ( name, override[ 0 ], MINOS ) )
    else:
        print( 'PASS leg %s: a step exports deployment_target as MACOSX_DEPLOYMENT_TARGET and no -D on the leg overrides it' % name )
    wired = re.search( r'^[ \t]*DEVELOPER_DIR:[ \t]*\$\{\{[ \t]*matrix\.developer_dir\b', text, re.M )
    print( 'PASS leg %s: the job env hands developer_dir to the toolchain as DEVELOPER_DIR' % name if wired else
           'FAIL leg %s: nothing exports matrix.developer_dir as DEVELOPER_DIR — the image\'s default Xcode, not the pinned one, builds the release' % name )
print( 'DONE' )
PY
relVerdict="$( python3 "$TMP/relverdict.py" "$ROOT/.github/workflows/release.yml" 2>&1 )"
while IFS= read -r row; do
    case "$row" in
        PASS\ *) ok "#2h ${row#PASS }" ;;
        FAIL\ *) no "#2h ${row#FAIL }" ;;
    esac
done <<<"$relVerdict"
printf '%s\n' "$relVerdict" | grep -q '^DONE$' \
    || no "#2h the release.yml verdict never finished — no evidence either way: $( printf '%s' "$relVerdict" | tail -3 )"

# ── #3: RIPWIRE_NATIVE=ON stays opt-in and unaffected by the pretend-Linux hook ─────────────────────────
nativeFlags="$( run_probe "$TMP/native" -DRIPWIRE_NATIVE=ON -DRIPWIRE_PRETEND_LINUX=ON )"
if printf '%s' "$nativeFlags" | grep -q -- '-march=native'; then
    ok "RIPWIRE_NATIVE=ON emits -march=native regardless of RIPWIRE_PRETEND_LINUX: '$nativeFlags'"
else
    no "RIPWIRE_NATIVE=ON did not emit -march=native: '$nativeFlags'"
fi
if printf '%s' "$nativeFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "RIPWIRE_NATIVE=ON unexpectedly also emits -mcpu=apple-m1: '$nativeFlags'"
else
    ok "RIPWIRE_NATIVE=ON does not also emit -mcpu=apple-m1"
fi

# ── #4/#5: the REAL top-level CMakeLists.txt routes through the module, no reintroduced literal ─────────
if grep -Eq '^\s*add_compile_options\(-O2 -mcpu=apple-m1' "$CMAKE_TOP"; then
    no "CMakeLists.txt still hardcodes -mcpu=apple-m1 unconditionally"
else
    ok "CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally"
fi
if grep -q 'include(cmake/PortableFlags.cmake)' "$CMAKE_TOP" && grep -q 'add_compile_options(\${RIPWIRE_ARCH_FLAGS})' "$CMAKE_TOP"; then
    ok "CMakeLists.txt routes the optimization profile through cmake/PortableFlags.cmake"
else
    no "CMakeLists.txt does not route through cmake/PortableFlags.cmake"
fi

# ── #6: no ORDERED STL algorithm over std::string_view with the DEFAULT comparator, anywhere in src/ ──
# WHY THIS IS A PORTABILITY RULE AND NOT A STYLE ONE. libstdc++'s string_view three-way compare computes
# `n1 - n2` on size_type and lets it wrap (bits/string_view.h, _S_compare). That wrap is well-defined C++,
# but the G1 sanitizer stack runs -fsanitize=integer, which reports it, and -fno-sanitize-recover=all turns
# the report into an abort. libc++ (every macOS leg, including the macOS ASan leg) computes the same answer
# without the subtraction and never reports. So `std::binary_search( first, last, sv )` is green on this
# machine, green on the macOS sanitizer leg, and aborts EVERY ranked run on the Linux sanitizer leg.
# That is exactly what happened at 69a17f9: the external-name veto's two table lookups took main red with
# `unsigned integer overflow: 3 - 17` inside std::binary_search, on a repository whose own macOS battery
# and macOS ASan leg were both clean. The rule is therefore mechanical: pass an explicit byte-comparator.
SVBAD="$( grep -rnE '(binary_search|lower_bound|upper_bound|equal_range)\(' "$ROOT/src" 2>/dev/null \
          | grep -vE '^\s*[0-9]+:\s*//' \
          | grep -E 'kPythonBuiltinNames|kCFamilyStdNames|string_view' \
          | grep -vE 'nameLess|svLess|, *\[' || true )"
if [ -z "$SVBAD" ]; then
    ok "#6 no ordered STL search over string_view relies on libstdc++'s wrapping three-way compare"
else
    no "#6 ordered STL search over string_view with the DEFAULT comparator — aborts the Linux G1 leg (pass an explicit byte-comparator):"
    printf '%s\n' "$SVBAD" | sed 's/^/        /'
fi

# NOTE (what this gate can prove vs what only Linux CI can prove): this machine is Apple-Silicon macOS, so
# it can prove the FLAG-SELECTION LOGIC never emits an Apple-specific flag once RIPWIRE_IS_APPLE_SILICON is
# false (checks #2/#3 above, via the RIPWIRE_PRETEND_LINUX hook), and that the real CMakeLists.txt wires
# that logic in (checks #4/#5). It CANNOT prove that clang/gcc on actual Linux/x86-64 hardware accepts the
# resulting flags and links a working binary, nor exercise CMAKE_SYSTEM_PROCESSOR values this host never
# reports (e.g. "x86_64"). That end-to-end proof is exactly what .github/workflows/ci.yml's ubuntu-24.04
# matrix leg provides; this gate is the local, sub-second proxy that catches a regression before it ever
# reaches CI.

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
