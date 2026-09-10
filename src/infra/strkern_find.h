#pragma once

// strkern_find.h — the SHIPPED byte-set scan, sibling to strkern.h's kernels.
//
// WHY THIS IS NOT `strkern::findByteset`. strkern.h's `findByteset` ends every call — SIMD path or not —
// in `findByteset_scalar`, and that function is deliberately an ORACLE: it re-derives a four-word bitmap
// from the 32-byte set on every call (a 256-iteration loop) using a DIFFERENT representation, precisely
// so a bug in the (b >> 3, b & 7) packing cannot hide behind a reference that shares it. That is exactly
// right for the gate it was written for and exactly wrong for a hot path whose inputs are SHORT: a
// symbol name, a path, a signature. Measured on this box (see the lane's report — 20k strings, best of 5,
// escapeXml end to end), routing escapeXml through `strkern::findByteset` made it 3.5x-7x SLOWER than
// the per-byte switch it replaced on 6..40-byte inputs, and `escapeXml` went from 4.62% of a warm
// `--top-k=100000` map to 22.46% of one. The 256-iteration preamble dominates everything else.
//
// So the shipped scan is this: one pass, one O(1) bit test per byte, no per-call preamble, the SAME
// `strkern::Byteset256` representation (one definition of the set, shared with the oracle that checks it).
//
// AND NO SIMD, ON PURPOSE. A NEON/AVX2 block loop over the set was measured beside this one across
// three length bands (6..40, 60..200, 200..900) and two special-byte densities. It is a wash below
// ~200 bytes — the strings ripwire actually emits — and worth at most ~1.3x on long sparse text, which
// is a slice of a slice: the whole escaper is 4.62% (XML) / 6.34% (JSON) of a warm map on ripwire's own
// tree and under 2% on the go corpus. Duplicating strkern.h's block loop here to chase that would buy a
// clone of another lane's kernel for a fraction of a fraction. The run-copy shape is where the win is
// (1.5x-3x, every band, every density); the scan under it is not.
//
// The headroom is real and recorded rather than taken: if `findByteset_scalar` ever stops being the tail
// of `findByteset` — i.e. if strkern.h grows a shipped tail beside its oracle — this file collapses into
// a call to it and the SIMD path comes along for free. That is the fold-back, and it belongs to the lane
// that owns strkern.h.

#include "strkern.h"

#include <cstddef>
#include <string>
#include <vector>

namespace rw::strkern
{

// Index of the first byte of [p, p+n) that is IN `set`, or n when none is. Pure, allocation-free,
// locale-independent; n == 0 returns 0.
inline std::size_t findBytesetRun( const char* p, std::size_t n, const Byteset256& set ) noexcept
{
    std::size_t k = 0;
    while( k < n && !set.contains( static_cast<unsigned char>( p[k] ) ) )
    {
        ++k;
    }
    return k;
}

// THE RUN-COPY STEP, so that neither escaper grows a shape around it. Appends the bytes from d[i] up to
// (not including) the next byte that is in `set` — the run the caller's per-byte switch has no opinion
// about — and returns the index of that byte, or n when the rest is clean. A zero-length run appends
// nothing, so the caller needs no emptiness test.
//
// Written to sit in a `for`'s INIT and INCREMENT slots:
//     for( std::size_t i = appendCleanRun( d, 0, n, set, out ); i < n; i = appendCleanRun( d, i, n, set, out ) )
// which is why it takes the index rather than a pointer and returns the next one. That placement is not
// cosmetic: the increment expression also runs on `continue`, so an escaper whose switch arms end in
// `continue` (jsonesc::escapeInto) keeps every one of them, and the loop keeps the SINGLE branch it had
// before the rewrite — the run-copy costs the escapers no measured complexity, which is the difference
// between a gated --quality-delta row and none.
//
// ONE template, not two overloads — a second body differing only in how it spells "append k bytes" is a
// 48-token clone of the first, and --quality-delta says so out loud. The spelling is picked by
// `if constexpr`: std::string (jsonesc's sink) has the (pointer, count) append and it is measurably the
// faster of the two, std::vector<char> (serialize's sink) has only the iterator-pair insert. Both take a
// contiguous-range memcpy underneath; the difference is the length arithmetic libc++ has to redo when it
// is handed iterators instead of a count, and on strings this short that arithmetic is not free.
template< typename Sink >
inline std::size_t appendCleanRun( const char* d, std::size_t i, std::size_t n, const Byteset256& set, Sink& out )
{
    const std::size_t clean = findBytesetRun( d + i, n - i, set );
    if constexpr( requires { out.append( d + i, clean ); } )
    {
        out.append( d + i, clean );
    }
    else
    {
        out.insert( out.end(), d + i, d + i + clean );
    }
    return i + clean;
}

}   // namespace rw::strkern
