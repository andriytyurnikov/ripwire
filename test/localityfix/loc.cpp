// localityfix/loc.cpp — gate fixture for the S6-C locality tie-break (adversarial HIGH-1 regression).
//
// THE BUG (now fixed): the locality tie-break used to compare canonical ids `path::scope::name` by RAW BYTE
// prefix. Two UNRELATED classes whose names merely start with the same letter (`Xenon` caller vs class `Xtra`)
// then scored a longer shared byte-run — *inside* the scope segment — than the genuinely-correct class
// (`Bravo`). So a call inside `Xenon` resolved CONFIDENTLY to `Xtra::go` (WRONG) and the header reported
// `ambiguous=0`. The legitimate `Bravo::go` edge the §2a ladder reached was silently dropped.
//
// THE FIX: `sharedLocality` compares on WHOLE `/`- and `::`-delimited SEGMENTS. A partial overlap inside a
// segment (`Xenon` vs `Xtra`) counts as ZERO locality. So both `Xtra` and `Bravo` share only the file PATH with
// the caller — they TIE — no candidate is strictly more local, and the call stays HONESTLY AMBIGUOUS (count=2,
// ambiguous=1) instead of a false-confident wrong pick.
//
// THE RECEIVER is `this->` inside a class template whose base is its own template parameter — the CRTP/mixin
// shape, where the called method lives in a base the index cannot see. Rule 1 finds no `Xenon::go` and no base
// to walk, so the call reaches the tie-break WITH the scope-segment credit (`this->` is the enclosing class).
// Until 2026-09-16 the receiver was an untyped `auto` local; an explicit receiver whose type no receiver rule
// established no longer earns the scope-segment credit at all (test/localitycheck.sh arms 5-9), so that call
// could no longer tell a byte-prefix tie-break from a segment-aware one.
//
// Out-of-line method defs (the realistic C++ layout) give each `go` its enclosing scope, so the canonical ids
// `…::Xtra::go` / `…::Bravo::go` exist and the tie-break has scopes to (correctly NOT) discriminate on.

struct Xtra
{
    int go();
};

struct Bravo
{
    int go();
};

int Xtra::go()  { return 1; }
int Bravo::go() { return 2; }

template <class Base>
struct Xenon : Base
{
    void call()
    {
        this->go();  // FIXED: stays AMBIGUOUS (Xtra/Bravo tie on path-only locality) — never a confident Xtra::go pick
    }
};
