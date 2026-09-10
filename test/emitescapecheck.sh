#!/usr/bin/env bash
# emitescapecheck.sh — gate for the RUN-COPY rewrite of the three emit escapers: rw::escapeXml and
# rw::appendCdataSafe (src/serialize.h) and rw::jsonesc::escapeInto (src/infra/jsonesc.h).
#
# WHY A HARNESS AND NOT A GOLDEN DIFF. The rewrite is "find the next byte in the special set with
# strkern::findByteset, memcpy the clean run, handle that one byte with the SAME switch". Nothing in a
# golden map exercises the inputs that shape gets wrong — an escaper is only interesting on the bytes a
# repo does not normally contain. So the harness (test/emitescape_harness.cpp) keeps the ORIGINAL
# per-byte loops verbatim as `*Ref` and asserts byte-identity over an adversarial corpus: every one of
# the 256 byte values; a special byte at EVERY offset of a filler run up to two 32-byte AVX2 blocks
# (the block-boundary sweep a SIMD run loop plus its scalar tail must survive); overlongs, surrogate
# halves, >U+10FFFF, truncated sequences, a lone continuation byte as the final byte of the buffer, a
# BOM; "]]>" at the start/middle/end and "]]]]>"; all eight escapeInto flag combinations; and 200k
# deterministic fuzz strings over an alphabet biased to the special set.
#
# ARMS
#   (A) harness compiles and passes — the shipped escapers agree with the frozen references.
#   (B) CAN-GO-RED: the same harness recompiled with -DEMITESCAPE_MUTATE_BYTESET=1, which adds a
#       byteset with '<' DROPPED. That build asserts the mutant DISAGREES with the reference. A
#       comparison that could not see a missing set member would report zero differences and this arm
#       would fail — which is the point: it proves arm (A) is looking at what it claims to.
#   (C) END TO END: a fixture tree (in a temp dir, NEVER inside the repo — see the
#       "gate fixture is the live repo" trap) whose doc-comment carries every byte value 0x01..0xFF
#       except '\n'. The map of that tree must pipe clean through `xmllint --noout` (G4), and the
#       --json map of the same tree must be accepted by python3's json parser. Both surfaces are the
#       ones the rewritten escapers write, so a set bug that produced a raw '<' or a broken UTF-8
#       sequence turns this red without any reference to compare against.
#
# Usage:  bash test/emitescapecheck.sh                (binary from RIPWIRE_BIN, else ./build/ripwire)
#         CXX=clang++ bash test/emitescapecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
CXX="${CXX:-c++}"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/emitescape_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

echo "emitescapecheck: CXX=$CXX  BIN=$BIN"

compile_arm()   # $1=output  $2...=extra flags
{
    local out="$1"; shift
    "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
        -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
        "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$out" 2> "$WORK/cc.log"
}

# ── (A) the shipped escapers vs the frozen per-byte references ────────────────────────────────────────
if compile_arm "$WORK/plain"; then
    if "$WORK/plain" > "$WORK/plain.out" 2>&1; then
        ok "escapers byte-identical to the frozen per-byte references over the adversarial corpus"
        sed -n 's/^/    /p' "$WORK/plain.out" | head -4
    else
        no "harness reported a mismatch"; sed 's/^/    /' "$WORK/plain.out" | head -20
    fi
else
    no "harness failed to compile"; sed 's/^/    /' "$WORK/cc.log" | head -20
fi

# ── (B) can-go-red: a byteset with '<' dropped must be VISIBLE to the comparison ───────────────────────
if compile_arm "$WORK/mut" -DEMITESCAPE_MUTATE_BYTESET=1; then
    if "$WORK/mut" > "$WORK/mut.out" 2>&1; then
        ok "MUT arm: a byteset missing '<' is detected (the comparison can go red)"
        grep -n 'MUT:' "$WORK/mut.out" | sed 's/^/    /'
    else
        no "MUT arm did not detect a byteset missing '<' — arm (A) proves nothing"
        sed 's/^/    /' "$WORK/mut.out" | head -20
    fi
else
    no "MUT arm failed to compile"; sed 's/^/    /' "$WORK/cc.log" | head -20
fi

# ── (C) end to end: every byte value through a real map, XML and JSON ─────────────────────────────────
[ -x "$BIN" ] || { no "binary not found: $BIN"; echo "emitescapecheck: FAIL"; exit 2; }

FIX="$WORK/fixture"
mkdir -p "$FIX"
python3 - "$FIX" <<'PY'
import os, sys
d = sys.argv[1]
# every byte 0x01..0xFF except '\n' (0x0A), which would end the line comment, on ONE doc-comment line;
# 0x00 is left out on purpose — an ingest that classifies a NUL-bearing file as binary would skip the
# file and the arm would prove nothing. NUL's escape path is covered by the harness instead.
soup = bytes( b for b in range( 1, 256 ) if b != 0x0A )
body = b"// bytesoup: " + soup + b"\n// ]]> and <![CDATA[ and & < > \" ' inside a comment\n" \
       b"void fixtureAlpha( int n ) { (void)n; }\n" \
       b"/** every byte again in a block comment: " + soup + b" */\n" \
       b"int fixtureBeta( int n ) { return fixtureAlpha2( n ); }\n" \
       b"int fixtureAlpha2( int n ) { return n; }\n"
open( os.path.join( d, "soup.cpp" ), "wb" ).write( body )
open( os.path.join( d, "plain.cpp" ), "wb" ).write( b"int plainOne( int n ) { return n + 1; }\n" )
PY

# The FLAGLESS map carries no doc-comment and no body, so it would prove nothing about the escapers.
# --for puts the doc-comment through escapeXml (entities + &#9;/&#13; + the invalid-UTF-8 '?' scrub) and
# --expand puts the whole file through appendCdataSafe (including the "]]>" split); their --json twins
# put the same bytes through jsonesc::escapeInto. All four surfaces are checked.
run_arm()   # $1=label  $2=validator(xml|json)  $3...=ripwire args
{
    local label="$1" kind="$2"; shift 2
    if ! "$BIN" "$FIX" "$@" > "$WORK/out.$kind" 2>"$WORK/err.$kind"; then
        no "ripwire failed on the every-byte fixture ($label)"; sed 's/^/    /' "$WORK/err.$kind" | head -10; return
    fi
    if ! LC_ALL=C grep -q 'bytesoup' "$WORK/out.$kind"; then
        no "$label: the byte soup never reached the output — this arm proves nothing"; return
    fi
    if [ "$kind" = xml ]; then
        if xmllint --noout "$WORK/out.$kind" 2>"$WORK/xmllint.err"; then
            ok "$label: well-formed XML over every byte value (G4)"
        else
            no "$label: xmllint rejected the map"; sed 's/^/    /' "$WORK/xmllint.err" | head -10
        fi
    else
        if python3 -c 'import json,sys; json.load(open(sys.argv[1],encoding="utf-8"))' "$WORK/out.$kind"; then
            ok "$label: parses as JSON (valid UTF-8, valid escapes) over every byte value"
        else
            no "$label: output is not parseable JSON"
        fi
    fi
}

run_arm "--for (escapeXml)"          xml  --for="bytesoup fixture"
run_arm "--expand (appendCdataSafe)" xml  --expand=fixtureAlpha
run_arm "--for --json (escapeInto)"  json --for="bytesoup fixture" --json
run_arm "--pack-task --json (bodies)" json --pack-task="bytesoup fixture" --json

if [ "$fail" -eq 0 ]; then
    echo "emitescapecheck: ALL PASS"; exit 0
else
    echo "emitescapecheck: FAIL"; exit 2
fi
