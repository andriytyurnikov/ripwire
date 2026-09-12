#!/usr/bin/env bash
# ceilingverdictcheck.sh — THE CEILING VERDICT IS A PROPERTY OF THE DOCUMENT, NEVER OF THE TASK TEXT.
#
# THE BUG (M3, 0.6.1). --for's root carries over_ceiling="1" when the bundle could not be trimmed to fit.
# The ladder that decides that (serialize.h climbCeilingLadderBy) KNOWS which rung it took — it is the
# branch that built the candidate — and verbs_for.h threw that away and RE-DERIVED the verdict by
# substring-searching the finished header for the rung's own note:
#
#     const bool ladderFired = !f.lastRungNote.empty() && header.find( f.lastRungNote ) != std::string::npos;
#
# The verbatim task echo is INSIDE that header. So a caller whose task text happens to contain the note
# is indistinguishable from a bundle that really hit the wall, and the document contradicts itself:
#
#     ripwire src --token-budget=100000 --for='… [over_ceiling= is 1 on the root: …no payload left to trim]'
#     → budget_tokens="100000" est_tokens="3880" over_ceiling="1"     (9701 B — nowhere near any ceiling)
#
# est_tokens far UNDER budget_tokens with over_ceiling="1" is exactly the shape the source comment beside
# these two numbers forbids ("both numbers sit on ONE root in ONE unit, so a reader can subtract them").
# PR #135 widened the blast radius by reading the same flag inside the ladder's FIT predicate, so injected
# text also priced phantom bytes onto every rung and could push an honest bundle down the ladder.
#
# THE DEFECT CLASS, which is what this gate is really for: a verdict re-derived by searching output text
# for a marker. Output text is attacker-supplied here (the task echo is verbatim by contract, routeoncecheck
# pins that), so ANY marker sniff over it is forgeable. packtask.h and tracelocus.h have had their own
# versions of this; tracelocus' §F5 comment records removing one. The fix is structural — the ladder
# RETURNS its rung — and arm (5) below is the recurrence guard for the source shape.
#
# WHAT IS ASSERTED, and why it is not simply "over_ceiling must be absent". forLensOverCeiling fires on two
# independent grounds (verbs_for.h): the token comparison est_tokens > budget_tokens, and the BYTE comparison
# the ladder's last rung is — the document past ceilingAllowanceBytes( budget ) = budget x 2.36 x 1.15
# (serialize.h). The second is deliberately WIDER than the first, so "over_ceiling implies est > budget" would
# be a false invariant. The honest one, which is what arm (4) sweeps, is the disjunction: the label may ride
# only on a document that is over one of the two ceilings its own root states, in numbers a reader can check.
#
#   bash test/ceilingverdictcheck.sh                    # build/ripwire
#   bash test/ceilingverdictcheck.sh build_base/ripwire # or RIPWIRE_BIN=… — both seams honored

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
CORPUS="$ROOT/src"
[ -d "$CORPUS" ] || { echo "missing corpus $CORPUS"; exit 2; }

echo "ceilingverdictcheck: BIN=$BIN"

# The forged marker is the ladder's LAST-RUNG note, verbatim. Pinned here as a literal rather than parsed out
# of the C++ (it is a two-line string concatenation), with a PRESENCE GUARD below so a re-worded note reds
# this gate instead of silently turning the probe into a task that forges nothing (trap: a vanishing probe
# target). Both halves are checked, because the source splits the constant between them.
MARK_A='over_ceiling= is 1 on the root: the header floor (verbatim task echo + fixed legend) exceeds this budget'
MARK_B='- no payload left to trim]'
MARK="[$MARK_A $MARK_B"
FORGED="serialize the header $MARK"
PLAIN='serialize the header ranking'

# (0) the probe is live: the note this task impersonates is still the note the code splices.
SRC="$ROOT/src/verbs_for.h"
if grep -qF -e "$MARK_A" "$SRC" && grep -qF -e "$MARK_B" "$SRC"; then   # -e: MARK_B starts with '-'
    ok "(0) the forged marker is still the ladder's last-rung note in src/verbs_for.h (the probe can forge)"
else
    no "(0) the last-rung note in src/verbs_for.h no longer matches this gate's MARK_A/MARK_B — re-pin them, or the forgery probe is inert and every arm below passes for the wrong reason"
fi

run(){ "$BIN" "$CORPUS" --no-cache --token-budget="$1" --for="$2" 2>/dev/null; }
attr(){ grep -o " $2=\"[0-9]*\"" <<< "$1" | head -1 | tr -cd '0-9'; }   # leading space: est_tokens must not match inside a longer name

WIDE=100000
"$BIN" "$CORPUS" --no-cache --token-budget="$WIDE" --for="$FORGED" > "$TMP/forged.wide" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget="$WIDE" --for="$PLAIN"  > "$TMP/plain.wide"  2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget=300     --for="$FORGED" > "$TMP/forged.tight" 2>/dev/null

# (1) the vector really reaches the emitted document — the task echo carries the marker into the header the
#     old code searched. Without this the forgery arm could pass because nothing was injected at all.
if grep -qF "$MARK_A" "$TMP/forged.wide"; then
    ok "(1) the forged marker reaches the emitted header (the injection vector is exercised)"
else
    no "(1) the forged task text does not appear in the emitted document — the injection never happened, so arm (2) proves nothing"
fi

# (2) THE HEADLINE: a document 27x inside its own byte allowance must not be labelled over its ceiling, and
#     must not state a self-contradicting pair of numbers.
fw_est="$( attr "$( cat "$TMP/forged.wide" )" est_tokens )"
fw_bud="$( attr "$( cat "$TMP/forged.wide" )" budget_tokens )"
fw_over="$( grep -c 'over_ceiling="1"' "$TMP/forged.wide" || true )"
if [ -z "$fw_est" ] || [ -z "$fw_bud" ]; then
    no "(2) the wide-budget forged run emitted no est_tokens=/budget_tokens= pair to judge (est='$fw_est' budget='$fw_bud')"
elif [ "$fw_over" -ne 0 ]; then
    no "(2) FORGED: task text put over_ceiling=\"1\" on a root that states est_tokens=$fw_est under budget_tokens=$fw_bud ($( wc -c < "$TMP/forged.wide" | tr -d ' ' ) B) — the verdict was read off the task echo, not off the document"
elif [ "$fw_est" -ge "$fw_bud" ]; then
    no "(2) the wide-budget probe is not wide enough to be unambiguous: est_tokens=$fw_est is not under budget_tokens=$fw_bud — raise WIDE"
else
    ok "(2) task text cannot forge over_ceiling=\"1\" (est_tokens=$fw_est under budget_tokens=$fw_bud, attribute absent)"
fi

# (3) CONTRAST — the SAME task at a budget it genuinely blows must still be labelled. Arms (2) and (3) differ
#     in NOTHING but the number after --token-budget, so (2) cannot be green because the attribute was deleted.
ft_est="$( attr "$( cat "$TMP/forged.tight" )" est_tokens )"
ft_over="$( grep -c 'over_ceiling="1"' "$TMP/forged.tight" || true )"
if [ "$ft_over" -ge 1 ]; then
    ok "(3) the same task at --token-budget=300 still carries over_ceiling=\"1\" (est_tokens=$ft_est) — the verdict still fires when it is real"
else
    no "(3) --token-budget=300 emitted no over_ceiling=\"1\" (est_tokens=$ft_est) — the label is gone, not fixed, and arm (2) is green for the wrong reason"
fi

# (4) THE INVARIANT SWEEP — over_ceiling="1" may ride only on a document that is over one of the two ceilings
#     its own root names: est_tokens > budget_tokens (tokens) or bytes > budget x 2.36 x 1.15 (the ladder's
#     allowance, serialize.h ceilingAllowanceBytes). Swept over both tasks so a pass needs the property to hold
#     on the forged AND the honest text, and counted so the arm cannot be vacuous.
labelled=0; violations=0
for b in 300 500 1000 2000 4000 20000 100000; do
    for t in "$FORGED" "$PLAIN"; do
        doc="$( run "$b" "$t" )"
        [ -n "$doc" ] || { no "(4) --token-budget=$b produced no document"; continue; }
        printf '%s' "$doc" | grep -q 'over_ceiling="1"' || continue
        labelled=$(( labelled + 1 ))
        est="$( attr "$doc" est_tokens )";  bytes="$( printf '%s' "$doc" | wc -c | tr -d ' ' )"
        allow="$( awk -v b="$b" 'BEGIN{ printf "%d", b * 2.36 * 1.15 }' )"
        if [ -n "$est" ] && [ "$est" -le "$b" ] && [ "$bytes" -le "$allow" ]; then
            violations=$(( violations + 1 ))
            no "(4) budget=$b: over_ceiling=\"1\" on a document inside BOTH ceilings it names (est_tokens=$est <= $b, bytes=$bytes <= allowance $allow) — task: $( printf '%.40s' "$t" )…"
        fi
    done
done
if [ "$labelled" -eq 0 ]; then
    no "(4) no swept run carried over_ceiling=\"1\" at all — the invariant held vacuously; the sweep's tight budgets must produce at least one labelled document"
elif [ "$violations" -eq 0 ]; then
    ok "(4) every one of the $labelled labelled documents in the sweep is genuinely over a ceiling its own root states"
fi

# (5) RECURRENCE GUARD on the source shape, because the behavioural arms above can only see the forgeries
#     someone thought to write. The verdict must arrive as a value from the ladder, never be recovered by
#     searching the finished header: no `header.find(` anywhere in the --for header-finishing path, and no
#     `lastRungNote` field for one to search for. spliceBefore's `doc.find( boundary )` is a different
#     operation on a different string (a structural boundary the emitter itself wrote) and is not matched.
badfind="$( grep -c 'header\.find(' "$SRC" || true )"
badnote="$( grep -c 'lastRungNote' "$SRC" || true )"
if [ "$badfind" -eq 0 ] && [ "$badnote" -eq 0 ]; then
    ok "(5) the rung verdict is carried, not re-derived: no header.find( and no lastRungNote in src/verbs_for.h"
else
    no "(5) src/verbs_for.h still recovers the ladder's rung from the header text ($badfind header.find( site(s), $badnote lastRungNote reference(s)) — the forgery is one re-worded note away from coming back"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "ceilingverdictcheck: FAILURES ABOVE"
exit "$fail"
