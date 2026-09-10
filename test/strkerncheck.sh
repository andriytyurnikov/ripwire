#!/usr/bin/env bash
# strkerncheck.sh — SIMD-vs-scalar parity gate for src/infra/strkern.h, and the tokenizer equivalence
# gate for the mask-driven walkers in src/lexindex.h.
#
# Compiles test/strkern_harness.cpp under the FULL G1 sanitizer set and runs it against (a) 100k
# fixed-seed random buffers over four alphabets, lengths 0..300, and (b) every byte of this repo's src/
# and docs/. The harness restates each kernel's contract as an independent scalar oracle; the shipped
# vector path (NEON on arm64, AVX2 on x86-64, the scalar twins elsewhere) must match it exactly, and the
# rewritten tokenizer must reproduce the pre-2026-09-10 byte-at-a-time walkers' spans AND fused hashes.
#
# THREE THINGS THIS GATE PROVES, in the order they can go wrong:
#   1  PARITY      — vector == scalar == the definition, on random and on real text.
#   2  NON-VACUITY — on arm64 the banner must say NEON, on x86-64 AVX2. A scalar-only build on those
#                    arches would compare the oracle to itself and pass while proving nothing.
#   3  CAN GO RED  — a second build with -DSTRKERN_MUTATE=1 flips one bit of the SIMD-only nibble table,
#                    narrows the fold's range by one and drops findByteset's high half. That build MUST
#                    fail. If it passes, the parity assertions above are not binding and this gate is
#                    decoration.
#
# A FOURTH, BEST-EFFORT ARM: on Apple Silicon the AVX2 path is compiled with `-arch x86_64
# -march=x86-64-v3` and run under Rosetta 2, so the x86 mirror is exercised on this machine rather than
# only on CI's ubuntu legs. It is a SKIP, never a failure, when the SDK or Rosetta is unavailable — the
# authoritative AVX2 proof is the ubuntu-24.04 CI leg.
#
# Independent of the ripwire binary and of main.cpp (pinned in test/binoverridecheck.sh's EXEMPT dict).
# Usage:  bash test/strkerncheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/strkerncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# ask THIS front end how it spells C++23 (see scripts/cxxstd.sh — AppleClang 15 rejects -std=c++23)
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/strkern_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
ARCH="$( uname -m )"
fail=0

echo "strkerncheck: CXX=$CXX arch=$ARCH"

# G1's 'integer' / float-cast groups are Clang spellings; GCC only has the address,undefined core.
# Probe THIS front end rather than guessing from its name (same posture as scripts/cxxstd.sh).
SAN="-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow"
printf 'int main(){return 0;}\n' > "$WORK/probe.cpp" 2>/dev/null || true
if ! "$CXX" $SAN -fsyntax-only "$WORK/probe.cpp" 2>/dev/null; then
    SAN="-fsanitize=address,undefined"
fi

# compile one flavour of the harness; $1 = label, remaining args = extra compile flags. Echoes the binary
# path on success, nothing on failure (the caller decides whether a compile failure is fatal).
compile_harness()
{
    local LABEL="$1"; shift
    local BIN="$WORK/harness_$LABEL"
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
            -I"$ROOT/src/infra" -I"$ROOT/src" -I"$ROOT/third_party" \
            "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$BIN" 2> "$WORK/cc_$LABEL.log"; then
        return 1
    fi
    printf '%s\n' "$BIN"
}

# ── 1 + 2: the shipped path, sanitized, must pass and must not be vacuous ─────────────────────────────
# -fno-sanitize-recover=all is the linchpin: a nibble-table read one lane past the end, or an unaligned
# load the compiler was allowed to assume away, must ABORT rather than report and exit 0.
BIN="$( compile_harness main $SAN -fno-sanitize-recover=all )"
if [ -z "$BIN" ]; then
    echo "  FAIL  harness failed to compile"; sed 's/^/    /' "$WORK/cc_main.log" | head -40; exit 2
fi

if ! "$BIN" "$ROOT" > "$WORK/out_main.log" 2>&1; then
    echo "  FAIL  parity/equivalence assertion failed:"
    grep -A 2 'FAIL' "$WORK/out_main.log" | sed 's/^/    /' | head -30
    exit 2
fi
if ! grep -q '^ALL PASS$' "$WORK/out_main.log"; then
    echo "  FAIL  harness did not reach its ALL PASS line (truncated run?)"
    tail -5 "$WORK/out_main.log" | sed 's/^/    /'
    exit 2
fi
printf '  PASS  %s harness arms green (%s)\n' "$( grep -c '  PASS  ' "$WORK/out_main.log" )" "$( head -1 "$WORK/out_main.log" | sed 's/strkern: //' )"

WANT=""
case "$ARCH" in
    arm64|aarch64) WANT="NEON" ;;
    x86_64|amd64)  WANT="AVX2" ;;
esac
if [ -n "$WANT" ]; then
    if grep -q "^strkern path: $WANT$" "$WORK/out_main.log"; then
        ok_path="$( grep '^strkern path: ' "$WORK/out_main.log" )"
        printf '  PASS  non-vacuity: %s on %s\n' "$ok_path" "$ARCH"
    else
        echo "  FAIL  non-vacuity ($ARCH must compile the $WANT path; banner says '$( grep '^strkern path: ' "$WORK/out_main.log" )')"
        echo "        a scalar-only build here compares the oracle to itself — the parity arms prove nothing"
        fail=1
    fi
fi

# ── 3: CAN GO RED ─────────────────────────────────────────────────────────────────────────────────────
# The mutation touches ONLY code inside `#if defined( STRKERN_MUTATE )` in the SIMD branches, never the
# scalar oracle — so a red run here is the parity assertion biting, not a broken build. Sanitizers are
# off for this arm: it is expected to fail, and we want it to fail on the assertion, not on a slow abort.
REDBIN="$( compile_harness mutate -DSTRKERN_MUTATE=1 )"
if [ -z "$REDBIN" ]; then
    echo "  FAIL  can-go-red arm failed to COMPILE (the mutation must build, then fail at runtime)"
    sed 's/^/    /' "$WORK/cc_mutate.log" | head -20
    fail=1
elif "$REDBIN" "$ROOT" > "$WORK/out_mutate.log" 2>&1; then
    echo "  FAIL  can-go-red: -DSTRKERN_MUTATE=1 build PASSED — the parity assertions are not binding"
    fail=1
else
    printf '  PASS  can-go-red: -DSTRKERN_MUTATE=1 fails %s arm(s) as designed\n' "$( grep -c '  FAIL  ' "$WORK/out_mutate.log" )"
fi

# ── 4: best-effort x86_64 / AVX2 mirror under Rosetta 2 ───────────────────────────────────────────────
# COMMON_RULES for this round: the x86-64 floor is -march=x86-64-v3 (AVX2 + BMI1/2 + FMA + LZCNT + MOVBE).
# Compiled without sanitizers — the ASan runtime for a cross-arch slice is not reliably present, and this
# arm's job is to run the AVX2 kernels at all, not to re-prove memory safety the native arm already did.
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    if X86BIN="$( compile_harness x86 -arch x86_64 -march=x86-64-v3 )" && [ -n "$X86BIN" ]; then
        if "$X86BIN" "$ROOT" > "$WORK/out_x86.log" 2>&1 && grep -q '^ALL PASS$' "$WORK/out_x86.log"; then
            if grep -q '^strkern path: AVX2$' "$WORK/out_x86.log"; then
                printf '  PASS  x86_64/AVX2 mirror runs green under Rosetta 2 (%s arms)\n' "$( grep -c '  PASS  ' "$WORK/out_x86.log" )"
            else
                echo "  FAIL  x86_64 slice built but did NOT compile the AVX2 path: $( grep '^strkern path: ' "$WORK/out_x86.log" )"
                fail=1
            fi
        else
            printf '  SKIP  x86_64 slice built but did not run here (no Rosetta 2, or it aborted); CI ubuntu-24.04 is the AVX2 proof: %s\n' \
                   "$( tail -2 "$WORK/out_x86.log" | tr '\n' ' ' )"
        fi
    else
        printf '  SKIP  no x86_64 cross slice on this toolchain (no macOS x86_64 SDK); CI ubuntu-24.04 is the AVX2 proof\n'
    fi
fi

if [ "$fail" = 0 ]; then
    echo "strkerncheck: PASS"
else
    echo "strkerncheck: FAILURES ABOVE"
fi
exit "$fail"
