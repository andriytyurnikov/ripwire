#!/usr/bin/env bash
# sidecarsymlinkcheck.sh — CWE-59 + CWE-367: a sidecar writer must refuse a symlink at its own fixed name,
# and the refusal must be the OPEN rather than a check the open then re-resolves behind.
#
# THE DEFECT THIS GATE OWNS (reported externally, reproduced on the shipped v0.6.0 binary). Three sidecar
# writers opened a FIXED-NAME destination with a TRUNCATING open that resolves the final path component
# through the filesystem's symlink layer — no O_NOFOLLOW, no lstat/S_ISLNK check:
#
#     .ripwire_quality_baseline   quality::writeBaseline     ofstream( path, trunc )
#     .ripwire_notes              notes::writeNotes          ofstream( path, trunc )
#     .ripwire_arch_baseline      archWriteBaseline          fopen( path, "w" )
#
# A repository carrying a symlink at one of those names turned ripwire's own write into an arbitrary-file
# truncate/overwrite ANYWHERE the invoking user can write. The reporter's proof-of-concept, reproduced here
# verbatim: a victim file holding `important user data` came back holding ripwire's baseline content, and
# `.ripwire_quality_baseline` was STILL A SYMLINK afterwards — the link was followed and its target
# destroyed, not replaced. Indexing a repository is a read-only-feeling act; it must not be able to eat a
# file outside the tree.
#
# WHY THE SYMLINK SURVIVING IS THE TELL, and why this gate asserts it. A tmp+rename publish (what the fourth
# sidecar, .ripwire_quality_acks, already uses) REPLACES the link entry with a regular file and leaves the
# target alone — data-losing in its own way, but not an arbitrary write. A truncating open does the exact
# opposite. So "the link is still a link and the target changed" is the signature of the vulnerable shape,
# and "the link is still a link and the target did NOT change" is the fixed shape. Both are asserted below.
#
# ROUND 2 — THE SECOND DEFECT, IN THE FIRST FIX (CWE-367, TOCTOU). The first fix was an lstat/S_ISLNK
# REFUSAL placed immediately before an unchanged truncating open. That is check-then-open: the answer was
# true when it was given and the open re-resolved the path afterwards, so a replacement landing in the gap
# made the write follow a link after all. The guard was ADVISORY — it described the destination, it did not
# constrain the open. The remedy is that the check and the create are now ONE syscall:
#
#     ::open( path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0666 )   (src/pathguard.h)
#
# and the three writers hold the resulting descriptor. There is no window because there is no second
# resolution. The pre-open lstat is GONE from all three writers — which is what makes the (a)/(b) arms
# below mean more than they did: with nothing but O_NOFOLLOW left to refuse with, a green (b) IS the open
# refusing. lstat survives only INSIDE pathguard.h, after a failed open, to decide which sentence ELOOP
# earns; it cannot decide whether to write.
#
# The (r) arms exercise the race directly, and it is worth being exact about what they can prove. They plant
# nothing: a fast swapper (python3 symlink/unlink in a loop) runs alongside repeated verb runs, so the
# destination alternates between absent and a symlink while the writer opens it. The swapper has to be fast —
# a fork-per-swap shell loop rarely lands in the window, and would let this arm pass against the defect it
# exists to catch.
#
# WHAT IT CANNOT PROVE. The arm is ONE-SIDED. Its green means "nothing was observed", not "no window
# exists": a window narrower than the swapper's cycle would pass it. It is a detector for the defect being
# closed, not a proof of atomicity. The proof is structural and lives in the (e)/(f) arms, which assert the MECHANISM: the
# one open carries O_NOFOLLOW, all three writers go through it, and no pre-open symlink predicate survives
# at any of them to be relied on again. (e)/(f) are SOURCE arms — they read $ROOT/src and do NOT move when
# $BIN points at another build, which is worth knowing when reading a red-first run against a base binary.
#
# ARM MAP — discriminating arms first:
#
#     per sidecar:  (a) the victim's bytes are UNTOUCHED after the verb runs
#                   (b) the tool REFUSED — non-zero exit AND a stderr line naming the symlink
#                   (r) THE RACE: with the destination alternating absent↔symlink under a fast swapper,
#                       the victim survives EVERY run — red on the check-then-open build, and one-sided
#                       by construction (see above)
#                   (h) a non-symlink open failure (a DIRECTORY at the sidecar name) is reported with the
#                       real OS reason and is NOT dressed up as a symlink — round 2 added the errno
#                       distinction, so this arm was red before it and is what stops "every failure is a
#                       symlink" from passing (a)/(b)
#     per writer:   (e) MECHANISM: each sidecar has ONE named acquire seam (openBaselineSidecar /
#                       openNotesSidecar / openArchBaselineSidecar); it opens through pathguard's atomic
#                       no-follow create and carries the site's unchanged DEGRADED_PATH_ALERT for the ELOOP
#                       case, the writer takes its descriptor from it and opens nothing itself, and neither
#                       body holds an ofstream/fopen following primitive or a pre-open symlink predicate
#     once:         (f) MECHANISM: src/pathguard.h has exactly ONE ::open and it carries all four of
#                       O_WRONLY/O_CREAT/O_TRUNC/O_NOFOLLOW; and refuseSymlinkWrite — the advisory
#                       check-then-open guard — is gone from src/ entirely, not merely unused
#
# Arms that are green before AND after are labelled so rather than left to look like coverage they are not
# (CONTRIBUTING §2, shape 7 — an arm asserting something strictly weaker than its name implies). They still
# assert real properties worth holding:
#
#     (c) the planted symlink is still there, still pointing at the victim — refusing must not quietly
#         unlink or replace the user's own entry. Green before AND after; it pins the no-side-effect half.
#     (d) NEGATIVE CONTROL (the reporter's own): with NO symlink present, the verb writes the sidecar
#         normally, as a REGULAR file with real content. Green before and after by design — it is what
#         stops the fix from being "refuse always", which would pass every (a)/(b) arm and break the tool.
#     (g) MODE CONTROL: under `umask 000` each sidecar is created 0666 — what ofstream( trunc ) and
#         fopen( "w" ) both requested before round 2, measured on the pre-change binary, not assumed. Green
#         before and after; it exists because moving to ::open means naming the mode by hand, and 0644
#         written there is invisible under the usual umask 022 (0666 & ~022 == 0644 & ~022). Observed RED
#         with a deliberate 0600 in the open.
#
# Usage:
#   bash test/sidecarsymlinkcheck.sh                 |  bash test/sidecarsymlinkcheck.sh asan/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/sidecarsymlinkcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams: regression.sh and every differential run pass the binary POSITIONALLY; RIPWIRE_BIN is the
# env form. A gate reading only one of them comes back ALL PASS against whatever is in build/ during a
# red-first run against a BASE binary — the exact way a red-first check fakes itself green (archcheck.sh
# carries the same note for the same reason).
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "sidecarsymlinkcheck: BIN=$BIN  TMP=$TMP"

# The sentinel the reporter used. Its exact bytes are the thing every (a) arm compares against, so the
# comparison can never degrade into "empty matches empty" (CONTRIBUTING §2, shape 3).
VICTIM_BYTES='important user data'

# ── fixture: a tiny indexable tree, deliberately NOT a git checkout ───────────────────────────────────
# Both --quality-baseline and --note-add degrade cleanly on a non-git root (undated note, empty HEAD
# stamp) and still write their sidecar, so the gate owes nothing to git config, committer identity or
# clone depth. The arch rules file produces a real layer pair so --baseline has something to accept.
mkTree()
{
    local dir="$1"
    rm -rf "$dir"; mkdir -p "$dir/sub"
    printf '#include <stdio.h>\nint helper( int x ) { return x + 1; }\nint main( void ) { printf( "%%d\\n", helper( 1 ) ); return 0; }\n' >"$dir/a.c"
    printf 'int other( int y ) { return y * 2; }\n' >"$dir/sub/b.c"
    printf 'layer core = a.c\nlayer consumer = sub/\ndeny consumer -> core\n' >"$dir/rules.txt"
}

# ── one full symlink arm, run for each of the three sidecars ──────────────────────────────────────────
# `label`     — human name for the rows
# `sidecar`   — the fixed file name the writer opens
# `runner`    — a function name; called with the tree dir, must invoke the verb that writes `sidecar`
#
# The victim lives OUTSIDE the indexed tree on purpose: that is the whole claim — a repository reaching a
# file the repository does not contain.
symlinkArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/$label/tree" victim="$TMP/$label/outside/victim.txt"

    mkTree "$tree"
    mkdir -p "$( dirname "$victim" )"
    printf '%s\n' "$VICTIM_BYTES" >"$victim"
    cp "$victim" "$TMP/$label.pristine"

    # PRESENCE GUARDS — assert the things the arm is about to measure actually exist, before trusting any
    # verdict over them. A vanished victim or an un-planted symlink would make (a) pass while proving
    # nothing (CONTRIBUTING §2, "a vanishing probe target").
    if [ -s "$victim" ] && grep -q "$VICTIM_BYTES" "$victim"; then
        ok "$label: (guard) victim file exists outside the tree, holding the sentinel bytes"
    else
        no "$label: (guard) victim file was not created with the sentinel bytes — every arm below is void"
        return
    fi

    ln -s "$victim" "$tree/$sidecar"
    if [ -L "$tree/$sidecar" ] && [ "$( readlink "$tree/$sidecar" )" = "$victim" ]; then
        ok "$label: (guard) symlink planted at $sidecar → the victim"
    else
        no "$label: (guard) could not plant the symlink at $sidecar — every arm below is void"
        return
    fi

    local rc=0
    "$runner" "$tree" >"$TMP/$label.out" 2>"$TMP/$label.err" || rc=$?

    # ── (a) DISCRIMINATING: the victim's bytes survive ────────────────────────────────────────────────
    if cmp -s "$TMP/$label.pristine" "$victim"; then
        ok "$label: (a) victim file is byte-identical after the verb ran"
    else
        no "$label: (a) VICTIM OVERWRITTEN through the symlink — $( wc -c <"$TMP/$label.pristine" | tr -d ' ' ) B became $( wc -c <"$victim" | tr -d ' ' ) B: $( head -c 60 "$victim" )"
    fi

    # ── (b) DISCRIMINATING: the refusal is LOUD ───────────────────────────────────────────────────────
    # Not writing is not enough. A silent skip leaves the user believing a sidecar exists that does not,
    # which is its own defect — so the verb must exit non-zero AND say on stderr that it refused and why.
    if [ "$rc" -ne 0 ]; then
        ok "$label: (b1) verb exited non-zero ($rc) rather than reporting success"
    else
        no "$label: (b1) verb exited 0 — a write that was refused (or worse, redirected) reported success"
    fi
    if grep -q 'refusing to write' "$TMP/$label.err" && grep -q 'symlink' "$TMP/$label.err"; then
        ok "$label: (b2) stderr names the refusal and the reason (symlink)"
    else
        no "$label: (b2) stderr carries no symlink refusal — user is not told why the sidecar is missing: $( head -c 120 "$TMP/$label.err" )"
    fi

    # ── (c) NOT DISCRIMINATING (green before and after): refusing has no side effect on the entry ─────
    if [ -L "$tree/$sidecar" ] && [ "$( readlink "$tree/$sidecar" )" = "$victim" ]; then
        ok "$label: (c) the user's symlink entry is left exactly as it was (not unlinked, not replaced)"
    else
        no "$label: (c) the symlink entry was modified — refusing must not touch the user's own entry"
    fi
}

# ── (d) NEGATIVE CONTROL, run for each sidecar: no symlink → normal write ─────────────────────────────
# This is the arm that keeps the fix honest. "Refuse whenever the destination exists", or "refuse always",
# satisfies every (a) and (b) arm above and breaks the three verbs completely; only this arm notices.
controlArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_ctl/tree"

    mkTree "$tree"
    local rc=0
    "$runner" "$tree" >"$TMP/${label}_ctl.out" 2>"$TMP/${label}_ctl.err" || rc=$?

    if [ "$rc" -eq 0 ]; then
        ok "$label: (d1) no symlink present → verb exits 0"
    else
        no "$label: (d1) no symlink present → verb exited $rc: $( head -c 120 "$TMP/${label}_ctl.err" )"
    fi
    if [ -f "$tree/$sidecar" ] && [ ! -L "$tree/$sidecar" ] && [ -s "$tree/$sidecar" ]; then
        ok "$label: (d2) sidecar written normally as a regular, non-empty file"
    else
        no "$label: (d2) sidecar not written as a regular non-empty file — the guard broke the normal path"
    fi
}

# ── the three runners ─────────────────────────────────────────────────────────────────────────────────
runQualityBaseline(){ "$BIN" "$1" --quality-baseline --no-cache; }
runNoteAdd(){ "$BIN" "$1" --note-add="a.c: sidecar symlink gate" --no-cache; }
# archBaselinePath() returns a BARE file name, resolved against the process CWD rather than the crawl
# root — so this runner must cd into the tree for the sidecar to land there at all. That is current,
# deliberate behaviour (the sidecar is rules-file-independent and repo-committable); the arm is written
# around it rather than against it. If the destination is ever root-qualified, delete the subshell cd
# and nothing else here changes.
runArchBaseline(){ ( cd "$1" && "$BIN" "$1" --arch=rules.txt --baseline --no-cache ); }

symlinkArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
symlinkArm notes           .ripwire_notes            runNoteAdd
symlinkArm archbaseline    .ripwire_arch_baseline    runArchBaseline

controlArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
controlArm notes           .ripwire_notes            runNoteAdd
controlArm archbaseline    .ripwire_arch_baseline    runArchBaseline

# ── (e) MECHANISM (round 2, CWE-367): the refusal IS the open, and nothing before it ──────────────────
# Source arms. They read $ROOT/src and do not follow $BIN, so a red-first run against a base BINARY sees
# the CURRENT tree here — which is the point: what they pin is the shape of the code, and the shape is the
# only place atomicity is observable without an lstat interposer (see the header).
#
# Full-line `//` comments are stripped before the absence checks, because the comments at these sites
# name the ofstream/fopen they replaced — quoting the defect must not read as committing it.
extractFn()
{
    awk -v sig="$2" 'index( $0, sig ) { inFn = 1 } inFn { print } inFn && /^}$/ { exit }' "$1" \
        | grep -v '^[[:space:]]*//'
}

mechArm()
{
    local label="$1" src="$2" acquireSig="$3" writerSig="$4" acquireFn="$5" alert="$6"
    local acq="$TMP/acq_$label.txt" body="$TMP/body_$label.txt"

    extractFn "$ROOT/$src" "$acquireSig" >"$acq"
    extractFn "$ROOT/$src" "$writerSig"  >"$body"

    # PRESENCE GUARD — an extraction that returned nothing makes every absence check below pass for the
    # emptiest possible reason (CONTRIBUTING §2, shape 3: nothing matches nothing).
    local acqLines bodyLines
    acqLines="$( wc -l <"$acq" | tr -d ' ' )"
    bodyLines="$( wc -l <"$body" | tr -d ' ' )"
    if [ "$acqLines" -ge 4 ] && [ "$bodyLines" -ge 5 ] && grep -q 'return' "$acq" && grep -q 'return' "$body"; then
        ok "$label: (e0/guard) extracted $acqLines code lines of $acquireFn and $bodyLines of the writer from $src"
    else
        no "$label: (e0/guard) could not extract both bodies from $src (acquire=$acqLines writer=$bodyLines) — (e1)-(e4) are void"
        return
    fi

    if grep -q 'openNoFollowTruncate' "$acq"; then
        ok "$label: (e1) $acquireFn opens through pathguard's atomic O_NOFOLLOW create"
    else
        no "$label: (e1) no openNoFollowTruncate in $acquireFn — the destination is resolved by something else"
    fi

    # The things that must NOT be there, in EITHER body: a following primitive of either flavour, and any
    # pre-open symlink predicate. The second half is the round-2 finding itself — an advisory check that the
    # code then relies on is the defect, so its ABSENCE is the property, not the presence of a better check.
    local leftovers=""
    grep -qh 'std::ofstream'      "$acq" "$body" && leftovers="$leftovers ofstream"
    grep -qh 'std::fopen'         "$acq" "$body" && leftovers="$leftovers fopen"
    grep -qh 'refuseSymlinkWrite' "$acq" "$body" && leftovers="$leftovers refuseSymlinkWrite"
    grep -qh 'isSymlink'          "$acq" "$body" && leftovers="$leftovers isSymlink"
    grep -qh 'lstat'              "$acq" "$body" && leftovers="$leftovers lstat"
    if [ -z "$leftovers" ]; then
        ok "$label: (e2) no following primitive and no pre-open symlink predicate survives at the site"
    else
        no "$label: (e2) check-then-open shape still present at the site:$leftovers"
    fi

    # "Same exit path, same alert" is a promise about THIS site, so it is asserted at this site.
    if grep -qF "$alert" "$acq"; then
        ok "$label: (e3) the site's own DEGRADED_PATH_ALERT for the symlink case is unchanged"
    else
        no "$label: (e3) the site's DEGRADED_PATH_ALERT text changed — expected: $alert"
    fi

    # The seam is only worth anything if the WRITER actually writes through the descriptor it hands back.
    if grep -q "$acquireFn(" "$body"; then
        ok "$label: (e4) the writer takes its descriptor from $acquireFn and opens nothing itself"
    else
        no "$label: (e4) the writer does not call $acquireFn — it acquires its destination some other way"
    fi
}

mechArm qualitybaseline src/quality.h 'inline int openBaselineSidecar( const std::string& path )' \
        'inline bool writeBaseline( const Snapshot& s, const std::string& path' 'openBaselineSidecar' \
        'quality: refusing to write the baseline sidecar through a symlink'
mechArm notes           src/notes.h   'inline int openNotesSidecar( const std::string& path )' \
        'inline bool writeNotes( const std::string& path' 'openNotesSidecar' \
        'notes: refusing to write the notes sidecar through a symlink'
mechArm archbaseline    src/arch.h    'inline int openArchBaselineSidecar( const std::string& sidecarPath )' \
        'inline bool archWriteBaseline( const std::string&' 'openArchBaselineSidecar' \
        'arch: refusing to write the arch baseline sidecar through a symlink'

# ── (f) MECHANISM: the one open, and the advisory guard that must not come back ───────────────────────
PG="$ROOT/src/pathguard.h"
PGCODE="$TMP/pathguard_code.txt"
grep -v '^[[:space:]]*//' "$PG" >"$PGCODE"
openLines="$( grep -c '::open(' "$PGCODE" | tr -d ' ' )"
if [ "$openLines" = "1" ] \
   && grep -q '::open(' "$PGCODE" \
   && grep '::open(' "$PGCODE" | grep -q 'O_WRONLY' \
   && grep '::open(' "$PGCODE" | grep -q 'O_CREAT' \
   && grep '::open(' "$PGCODE" | grep -q 'O_TRUNC' \
   && grep '::open(' "$PGCODE" | grep -q 'O_NOFOLLOW'; then
    ok "pathguard: (f1) exactly one ::open, carrying O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW"
else
    no "pathguard: (f1) expected exactly one ::open carrying all four flags — found $openLines: $( grep '::open(' "$PGCODE" | head -c 160 )"
fi

if grep -rq 'refuseSymlinkWrite' "$ROOT/src"; then
    no "pathguard: (f2) refuseSymlinkWrite (the advisory check-then-open guard) is still in src/: $( grep -rl 'refuseSymlinkWrite' "$ROOT/src" | tr '\n' ' ' )"
else
    ok "pathguard: (f2) the advisory check-then-open guard is gone from src/, not merely unused"
fi

# ── (g) MODE CONTROL: the hand-written mode must equal what ofstream/fopen asked for ──────────────────
# umask 000 is what makes this discriminating: under the usual 022 a wrong 0644 is indistinguishable from
# the correct 0666. GNU stat and BSD stat disagree about -f, so pick the flavour once (CONTRIBUTING §1).
if stat --version >/dev/null 2>&1; then
    fileMode(){ stat -c '%a' "$1"; }
else
    fileMode(){ stat -f '%Lp' "$1"; }
fi

modeArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_mode/tree"

    mkTree "$tree"
    ( umask 000; "$runner" "$tree" ) >"$TMP/${label}_mode.out" 2>"$TMP/${label}_mode.err"

    if [ ! -f "$tree/$sidecar" ]; then
        no "$label: (g) sidecar was not written under umask 000 — the mode arm is void"
        return
    fi
    local mode
    mode="$( fileMode "$tree/$sidecar" )"
    if [ "$mode" = "666" ]; then
        ok "$label: (g) created 0666 under umask 000 — the mode ofstream/fopen asked for, unchanged"
    else
        no "$label: (g) created 0$mode under umask 000, not 0666 — the open's mode argument changed the permissions"
    fi
}

modeArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
modeArm notes           .ripwire_notes            runNoteAdd
modeArm archbaseline    .ripwire_arch_baseline    runArchBaseline

# ── (h) an open failure that is NOT a symlink must not be reported as one ─────────────────────────────
# A directory at the sidecar name is the cheapest deterministic non-ELOOP failure there is (EISDIR on both
# targets, strerror "Is a directory"). Round 1 mapped nothing to errno at all, so the real reason never
# reached the user; round 2 must report it AND must not reach for the symlink sentence, which would be a
# false security claim rather than a diagnosis.
notLinkArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_dir/tree"

    mkTree "$tree"
    mkdir -p "$tree/$sidecar"
    if [ ! -d "$tree/$sidecar" ] || [ -L "$tree/$sidecar" ]; then
        no "$label: (h/guard) could not plant a directory at $sidecar — the arm below is void"
        return
    fi

    local rc=0
    "$runner" "$tree" >"$TMP/${label}_dir.out" 2>"$TMP/${label}_dir.err" || rc=$?

    if [ "$rc" -ne 0 ]; then
        ok "$label: (h1) a directory at the sidecar name is a refusal, not a success ($rc)"
    else
        no "$label: (h1) verb exited 0 with a directory at the sidecar name — nothing was written and it said so anyway"
    fi
    if grep -qi 'directory' "$TMP/${label}_dir.err" && ! grep -q 'symlink' "$TMP/${label}_dir.err"; then
        ok "$label: (h2) stderr gives the real OS reason and does not dress it up as a symlink"
    else
        no "$label: (h2) stderr is not honest about a non-symlink failure: $( head -c 200 "$TMP/${label}_dir.err" | tr '\n' ' ' )"
    fi
}

notLinkArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
notLinkArm notes           .ripwire_notes            runNoteAdd
notLinkArm archbaseline    .ripwire_arch_baseline    runArchBaseline

# ── (r) THE RACE, run for real ────────────────────────────────────────────────────────────────────────
# The swapper is python3 and not shell on purpose: a fork per swap is too slow to land in the window
# reliably, so a shell swapper would pass this arm against the defect it exists to catch. python3 is a
# documented suite prerequisite
# (CONTRIBUTING §1), so its absence is a FAILURE here, never a skip — a skipped arm reports success for
# work it did not do.
#
# It stops on a FILE, not a signal: no kill, no "Terminated" line landing in the middle of the gate's own
# rows, and no orphan if this script dies (the loop carries its own wall-clock deadline as the backstop).
RACE_MIN_RUNS=25
RACE_MAX_RUNS=150

if ! command -v python3 >/dev/null 2>&1; then
    no "race: python3 is not on PATH — the (r) arms cannot run, and a skipped race arm proves nothing"
else
    cat >"$TMP/swap.py" <<'PY'
import os, sys, time
side, victim, stop, ready = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
deadline = time.time() + 120.0
n = 0
while True:
    try:
        os.symlink( victim, side )
        if n == 0:
            open( ready, 'w' ).close()
    except OSError:
        pass
    try:
        os.unlink( side )
    except OSError:
        pass
    n += 1
    if ( n & 511 ) == 0 and ( os.path.exists( stop ) or time.time() > deadline ):
        break
PY

    raceArm()
    {
        local label="$1" sidecar="$2" runner="$3"
        local dir="$TMP/${label}_race" tree="$TMP/${label}_race/tree" victim="$TMP/${label}_race/outside/victim.txt"

        mkTree "$tree"
        mkdir -p "$dir/outside"
        local side="$tree/$sidecar" stop="$dir/stop" ready="$dir/ready"

        python3 "$TMP/swap.py" "$side" "$victim" "$stop" "$ready" &
        local swapper=$!

        # LIVENESS, part one: the swapper is actually swapping before a single verdict is taken.
        local spin=0
        while [ ! -e "$ready" ] && [ "$spin" -lt 200 ]; do
            spin=$(( spin + 1 ))
            sleep 0.05
        done
        if [ ! -e "$ready" ]; then
            : >"$stop"; wait "$swapper" 2>/dev/null
            no "$label: (r0/guard) the swapper never planted a symlink — the race arm below is void"
            return
        fi

        local runs=0 hits=0 refusals=0 writes=0 rc=0
        while [ "$runs" -lt "$RACE_MAX_RUNS" ]; do
            printf '%s\n' "$VICTIM_BYTES" >"$victim"
            rc=0
            "$runner" "$tree" >/dev/null 2>"$dir/err" || rc=$?
            runs=$(( runs + 1 ))
            grep -q "$VICTIM_BYTES" "$victim" || hits=$(( hits + 1 ))
            if grep -q 'refusing to write' "$dir/err"; then refusals=$(( refusals + 1 )); fi
            if [ "$rc" -eq 0 ]; then writes=$(( writes + 1 )); fi
            if [ "$runs" -ge "$RACE_MIN_RUNS" ] && [ "$refusals" -gt 0 ] && [ "$writes" -gt 0 ]; then
                break
            fi
        done
        : >"$stop"; wait "$swapper" 2>/dev/null

        # LIVENESS, part two — the arm's whole worth rests on this. A run that only ever met a symlink
        # proves the ordinary refusal, not the race; a run that only ever met an absent path never offered
        # the writer a link to follow. Both sides of the flicker have to have been observed, or the zero
        # below is the emptiest kind of green (CONTRIBUTING §2, shape 3).
        if [ "$refusals" -gt 0 ] && [ "$writes" -gt 0 ]; then
            # BRACES ARE LOAD-BEARING HERE. `$refusals×` reads as the identifier `refusals×` under the
            # locale pargates runs gates in — bash takes the multibyte × as part of the name — and `set -u`
            # then kills the gate mid-transcript with "unbound variable". An interactive run in a different
            # locale passes, so the suite is what found it. Brace any expansion a non-ASCII character
            # follows; do not rely on the separator being obvious to a reader.
            ok "$label: (r0/guard) over $runs runs the writer met the symlink ${refusals}× and an absent path ${writes}× — the window was open on both sides"
        else
            no "$label: (r0/guard) over $runs runs: refusals=$refusals writes=$writes — the destination never flickered, so (r1) is void"
            return
        fi

        if [ "$hits" -eq 0 ]; then
            ok "$label: (r1) victim survived all $runs racing runs — no run resolved the destination twice"
        else
            no "$label: (r1) VICTIM DESTROYED on $hits of $runs racing runs — the guard is advisory, not atomic (CWE-367)"
        fi
    }

    raceArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
    raceArm notes           .ripwire_notes            runNoteAdd
    raceArm archbaseline    .ripwire_arch_baseline    runArchBaseline
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
