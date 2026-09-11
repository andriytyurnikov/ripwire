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
#   6) no ordered STL algorithm over std::string_view takes the default comparator in src/ — a line-local grep
#      (#6) plus a pass that resolves each container through its declaration (#6b), with planted controls.
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

# ── #6b: the same rule, resolved through each container's DECLARATION — the half the grep above cannot see ──
# #6 is line-local and type-blind: it fires only when `string_view` is spelled on the call line, and it never
# looked at std::sort at all. PR #135's extent detector sorted a std::vector<std::string_view> MEMBER declared
# 67 lines up and binary-searched a std::span<const std::string_view> PARAMETER (src/extentsuspect.h); neither
# call line names the type. #6 stayed green, both macOS legs stayed green, and on the Linux G1 leg every ingest
# of a C++ tree with two same-file class names that prefix one another aborted INSIDE ingest — before any verb
# ran, so even --pack-task's refusal arms died rc=134 with empty stderr (CI run 34583440115; the report,
# `unsigned integer overflow: 8 - 13` at libstdc++ string_view:576, came from resetExtentScratch's std::sort).
# The pass: every ordered algorithm called at its DEFAULT arity (no comparator argument) → the container its first
# argument ranges over (`x.begin()`, `std::begin( x )`, a ranges:: argument) → the NEAREST PRECEDING declaration
# of that name in the same file (a member access skips parameter-shaped ones). string_view anywhere in that
# declaration's template arguments (vector, span, array, a pair element) or a C array of string_view is a finding.
# static_assert calls are exempt: constant evaluation runs no sanitizer. Stated blind spots — zero findings means
# "none found", not "none exists": a container declared in ANOTHER file, an `auto`-typed container, and a
# comparator lambda that itself applies `<` to string_views. The two control scans run on planted input every
# time, so a scanner that goes quiet fails this arm instead of passing it.
SVSCAN="$TMP/svorder.py"
cat > "$SVSCAN" <<'PY'
import bisect
import os
import re
import sys

# ordered algorithm -> its classic (iterator-pair) arity WITHOUT a comparator argument
ALGS = {
    'sort': 2, 'stable_sort': 2, 'partial_sort': 3, 'nth_element': 3, 'is_sorted': 2, 'is_sorted_until': 2,
    'min_element': 2, 'max_element': 2, 'minmax_element': 2, 'binary_search': 3, 'lower_bound': 3,
    'upper_bound': 3, 'equal_range': 3, 'inplace_merge': 3, 'includes': 4, 'lexicographical_compare': 4,
    'merge': 5, 'set_union': 5, 'set_intersection': 5, 'set_difference': 5, 'set_symmetric_difference': 5,
}
TWO_RANGE = {'includes', 'lexicographical_compare', 'merge', 'set_union', 'set_intersection', 'set_difference',
             'set_symmetric_difference'}
NOT_A_TYPE = {'return', 'co_return', 'co_yield', 'throw', 'case', 'else', 'delete', 'new', 'sizeof', 'alignof',
              'typename', 'goto', 'using', 'operator', 'do', 'not', 'and', 'or', 'template', 'class', 'struct'}
CALL = re.compile(r'\bstd::(ranges::)?(' + '|'.join(ALGS) + r')\s*\(')
# comments and literal contents are blanked (newlines kept, so offsets and lines stay true); a pp-number is matched
# first so a digit separator (1'000) is never read as a character literal
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/'
                   r'|(?<![\w])(?:u8|u|U|L)?R"(?P<delim>[^()\\\s]{0,16})\(.*?\)(?P=delim)"'
                   r"|(?<![\w])\d[\w']*"
                   r'|"(?:[^"\\\n]|\\.)*"'
                   r"|'(?:[^'\\\n]|\\.)*'", re.S)


def blank(text):
    return TOKEN.sub(lambda m: m.group(0) if m.group(0)[0].isdigit() else re.sub(r'[^\n]', ' ', m.group(0)), text)


def split_args(text, open_index):
    depth, args, start = 0, [], open_index + 1
    for i in range(open_index, len(text)):
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                args.append(text[start:i])
                return args
        elif c == ',' and depth == 1:
            args.append(text[start:i])
            start = i + 1
    return None


def container_of(arg):
    """(identifier, is_member_access) of the container the first argument ranges over, or None."""
    for pattern in (r'(\w+)\s*(?:\.|->)\s*c?r?(?:begin|end|data)\s*\(\s*\)',
                    r'std::(?:ranges::)?c?r?(?:begin|end|data)\s*\(\s*((?:\w+\s*(?:\.|->|::)\s*)*)(\w+)\s*\)',
                    r'^\s*((?:\w+\s*(?:\.|->)\s*)*)(\w+)\s*$'):
        m = re.search(pattern, arg)
        if not m:
            continue
        if m.lastindex == 1:
            before = arg[:m.start(1)].rstrip()
            return m.group(1), before.endswith('.') or before.endswith('->')
        return m.group(2), bool(m.group(1).strip())
    return None


def type_before(text, pos):
    """The type spelled right before a declarator at `pos`, or None when `pos` is not in declarator position."""
    i = pos - 1
    while i >= 0 and (text[i].isspace() or text[i] in '&*'):
        i -= 1
    if i >= 4 and text[i - 4:i + 1] == 'const' and (i < 5 or not (text[i - 5].isalnum() or text[i - 5] == '_')):
        i -= 5
        while i >= 0 and (text[i].isspace() or text[i] in '&*'):
            i -= 1
    end = i + 1
    if i >= 0 and text[i] == '>':
        if i >= 1 and text[i - 1] == '-':
            return None
        depth = 0
        while i >= 0:
            if text[i] == '>':
                depth += 1
            elif text[i] == '<':
                depth -= 1
                if depth == 0:
                    break
            elif text[i] in ';{}':
                return None
            i -= 1
        i -= 1
        while i >= 0 and text[i].isspace():
            i -= 1
    j = i
    while j >= 0 and (text[j].isalnum() or text[j] in '_:'):
        j -= 1
    head = text[j + 1:i + 1]
    if not head or head[0].isdigit() or head.endswith(':') or head.split('::')[-1] in NOT_A_TYPE:
        return None
    return re.sub(r'\s+', ' ', text[j + 1:end])


def declarations(text, ident, cache):
    if ident not in cache:
        rows = []
        for m in re.finditer(r'\b' + re.escape(ident) + r'\s*([;={(,)\[])', text):
            spelled = type_before(text, m.start())
            if spelled is not None:
                rows.append((m.start(), spelled, m.group(1)))
        cache[ident] = rows
    return cache[ident]


def is_string_view_ordered(spelled, next_char):
    if re.search(r'<.*\bstring_view\b', spelled):
        return True   # a container (or pair/tuple element) of string_view: its operator< is the wrapping one
    return next_char == '[' and re.search(r'\bstring_view$', spelled) is not None   # a C array of string_view


def scan_file(path, rel):
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = blank(fh.read())
    cache, findings = {}, []
    line_starts = [0] + [m.end() for m in re.finditer('\n', text)]
    for m in CALL.finditer(text):
        is_ranges, alg = m.group(1) is not None, m.group(2)
        args = split_args(text, m.end() - 1)
        if args is None:
            continue
        defaults = {ALGS[alg]}
        if is_ranges:
            defaults.add(ALGS[alg] - (2 if alg in TWO_RANGE else 1))
        if len(args) not in defaults:
            continue   # an explicit comparator (or projection) is passed
        statement_start = max(text.rfind(';', 0, m.start()), text.rfind('{', 0, m.start()), text.rfind('}', 0, m.start()))
        if 'static_assert' in text[statement_start + 1:m.start()]:
            continue   # constant evaluation: no sanitizer runs there
        container = container_of(args[0])
        if container is None:
            continue
        ident, is_member = container
        rows = [r for r in declarations(text, ident, cache) if r[0] < m.start() and (not is_member or r[2] in ';={')]
        if not rows or not is_string_view_ordered(rows[-1][1], rows[-1][2]):
            continue
        line = bisect.bisect_right(line_starts, m.start())
        decl_line = bisect.bisect_right(line_starts, rows[-1][0])
        findings.append(f'{rel}:{line}: std::{"ranges::" if is_ranges else ""}{alg} over `{ident}` '
                        f'(declared line {decl_line}: {rows[-1][1]}) with the default comparator')
    return findings


root = sys.argv[1].rstrip('/')
paths = []
for dirpath, dirnames, names in os.walk(root):
    dirnames.sort()
    for name in sorted(names):
        if name.endswith(('.h', '.hpp', '.hh', '.cpp', '.cc', '.cxx', '.inc', '.ipp')):
            paths.append(os.path.join(dirpath, name))
for path in paths:
    for finding in scan_file(path, os.path.relpath(path, os.path.dirname(root))):
        print(finding)
PY
if ! command -v python3 >/dev/null 2>&1; then
    no "#6b needs python3 on PATH to resolve declarations"
else
    mkdir -p "$TMP/svctl/planted" "$TMP/svctl/clean"
    # every line marked PLANT must be found, and nothing else: the #135 shapes plus the other element spellings
    cat > "$TMP/svctl/planted/planted.h" <<'EOF'
inline constexpr int kBig = 1'000'000;
inline constexpr const char* kRaw = R"x(a "quoted" ) paren)x";
struct Scratch
{
    std::vector<std::string_view> names;
};
inline bool has( std::span<const std::string_view> names, std::string_view s )
{
    return std::binary_search( names.begin(), names.end(), s );   // PLANT
}
inline void reset( Scratch& scratch )
{
    std::sort( scratch.names.begin(),   // PLANT
               scratch.names.end() );
}
inline void pairs()
{
    std::vector<std::pair<std::string_view, int>> rows;
    std::sort( rows.begin(), rows.end() );   // PLANT
}
inline void carr()
{
    std::string_view table[ 3 ] = { "b", "a", "ab" };
    std::sort( std::begin( table ), std::end( table ) );   // PLANT
}
inline void ranges( std::vector<std::string_view>& v )
{
    std::ranges::sort( v );   // PLANT
}
EOF
    # none of these may be found: byte comparators, a std::string collision, constant evaluation, text that only spells a call
    cat > "$TMP/svctl/clean/clean.h" <<'EOF'
inline constexpr const char* kRaw = R"x(std::sort( names.begin(), names.end() ) ")x";
struct Scratch2
{
    std::vector<std::string_view> names;
};
inline void reset2( Scratch2& scratch )
{
    std::sort( scratch.names.begin(), scratch.names.end(), rw::sortutil::svLess );
}
inline bool has2( std::span<const std::string_view> names, std::string_view s )
{
    return std::binary_search( names.begin(), names.end(), s, rw::sortutil::svLess );
}
inline void collision()
{
    std::vector<std::string> names;
    std::sort( names.begin(), names.end() );
}
constexpr std::string_view kTable[] = { "a", "ab", "b" };
static_assert( std::is_sorted( std::begin( kTable ), std::end( kTable ) ) );
// std::sort( names.begin(), names.end() );  a comment is not a call
inline const char* help = "std::sort( names.begin(), names.end() )";
inline void sortChars()
{
    std::string_view chars = "cba";
    std::string buf( chars );
    std::sort( buf.begin(), buf.end() );
}
EOF
    wantPlanted="$( grep -n 'PLANT' "$TMP/svctl/planted/planted.h" | cut -d: -f1 | sed 's#^#planted/planted.h:#' )"
    gotPlanted="$( python3 "$SVSCAN" "$TMP/svctl/planted" | cut -d: -f1,2 )"
    if [ -n "$wantPlanted" ] && [ "$gotPlanted" = "$wantPlanted" ]; then
        ok "#6b control: the declaration pass finds exactly the $( printf '%s\n' "$wantPlanted" | wc -l | tr -d ' ' ) planted calls (member, span parameter, pair element, C array, ranges::)"
    else
        no "#6b control: planted default-comparator calls not found exactly — want [$( printf '%s ' $wantPlanted )] got [$( printf '%s ' $gotPlanted )]"
    fi
    gotClean="$( python3 "$SVSCAN" "$TMP/svctl/clean" )"; cleanRc=$?
    if [ "$cleanRc" -eq 0 ] && [ -z "$gotClean" ]; then
        ok "#6b control: byte comparators, a std::string collision, static_assert and call-shaped text are not findings"
    else
        no "#6b control: the clean input produced findings (rc=$cleanRc):"
        printf '%s\n' "$gotClean" | sed 's/^/        /'
    fi
    SVDECL="$( python3 "$SVSCAN" "$ROOT/src" )"; svRc=$?
    if [ "$svRc" -ne 0 ]; then
        no "#6b the declaration pass itself failed on src/ (rc=$svRc) — a crashed scan is not a clean one"
    elif [ -z "$SVDECL" ]; then
        ok "#6b no ordered STL algorithm over a string_view container takes the default comparator (resolved through its declaration)"
    else
        no "#6b ordered STL algorithm over a string_view container with the DEFAULT comparator — aborts the Linux G1 leg (pass rw::sortutil::svLess):"
        printf '%s\n' "$SVDECL" | sed 's/^/        /'
    fi
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
