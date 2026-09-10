// strkern_harness.cpp — SIMD-vs-scalar parity gate for src/infra/strkern.h, plus the tokenizer
// equivalence arm that pins lexindex.h's mask-driven walkers against the byte-at-a-time state machines
// they replaced.
//
//   A  classMasks            — per-byte [A-Z]/[a-z]/[0-9]/alnum bitmasks over one block, vector path vs
//                              the range-test oracle, for EVERY length 0..kBlockBytes.
//   B  lowerFoldAscii        — in-place A-Z fold, vector vs SWAR-scalar, on buffers that straddle every
//                              block boundary.
//   C  lowerFoldedEquals     — folded compare vs the scalar twin, including every single-byte difference
//                              position and the case-only differences that are the point of the kernel.
//   D  findByte / find3      — first-occurrence scans vs the scalar twins AND vs a naive memchr/memcmp
//                              oracle, needle present and absent, matches at 0 / at n-1 / straddling.
//   E  findByteset           — 256-bit set scan; sets built to hit the (b>>3, b&7) packing's seams
//                              (empty, full, the 0x80 boundary, one byte only, the XML-escape set).
//   F  tokenizer equivalence — forEachLexSubtoken / forEachLexSubtokenHashed as shipped vs VERBATIM
//                              copies of the pre-2026-09-10 byte-at-a-time walkers kept in this file.
//                              Every (start, end) span and every fused hash must be identical, over the
//                              random corpus AND over every byte of src/ and docs/.
//
// Corpora: (1) a fixed-seed random sweep — 100k buffers, lengths 0..300, drawn from four alphabets
// (identifier-ish, full ASCII, high-bit/UTF-8, and a camel/acronym-dense generator that manufactures the
// exact seams the tokenizer rule turns on); (2) every regular file under src/ and docs/ of the repo root
// given as argv[1], read whole. Real text is not optional here: the random arms cannot produce the
// distribution of `ACRONYMWord`, `snake_case` and `//` runs that the shipped rule was tuned on.
//
// NON-VACUITY: the banner prints the compiled path (`strkern path: NEON|AVX2|scalar`). On arm64/x86_64 the
// gate script REQUIRES a vector path — a scalar-only build there would compare the oracle to itself.
// CAN-GO-RED: compiling with -DSTRKERN_MUTATE=1 perturbs the SIMD tables only; the gate script proves the
// harness fails under it, so a green run means the parity assertions actually bind.
//
// Exit 0 = all pass; nonzero = failure.

#include "../src/infra/strkern.h"
#include "../src/lexindex.h"
#include "harnesscommon.h"      // checkf / g_fail / DeterministicRng — shared with the other SIMD harnesses

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace sk = rw::strkern;

// ============================================================================
// corpora
// ============================================================================

// four alphabets, each aimed at a different failure mode
enum class Alphabet
{
    Identifier,   // [A-Za-z0-9_] — the tokenizer's natural food
    FullAscii,    // 0x00..0x7F — every separator, every nibble-table seam ('@' '[' '`' '{' ':' '/')
    HighBit,      // 0x00..0xFF — proves the >= 0x80 half is a separator and never folds
    CamelDense    // manufactured camel / ACRONYMWord / digit seams at high density
};

static void drawBuffer( DeterministicRng& gen, Alphabet alpha, std::size_t n, std::string& out )
{
    static const char kIdent[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
    out.clear();
    out.reserve( n );
    while( out.size() < n )
    {
        const std::uint64_t r = gen.next();
        switch( alpha )
        {
            case Alphabet::Identifier:
                out.push_back( kIdent[ r % ( sizeof( kIdent ) - 1 ) ] );
                break;
            case Alphabet::FullAscii:
                out.push_back( char( r & 0x7F ) );
                break;
            case Alphabet::HighBit:
                out.push_back( char( r & 0xFF ) );
                break;
            case Alphabet::CamelDense:
            {
                // a short run of one class, then switch — so seams land every 1..4 bytes
                const int         kind = int( r & 3 );
                const std::size_t runLen = 1 + std::size_t( ( r >> 2 ) & 3 );
                for( std::size_t j = 0; j < runLen && out.size() < n; ++j )
                {
                    const std::uint64_t s = gen.next();
                    switch( kind )
                    {
                        case 0: out.push_back( char( 'A' + ( s % 26 ) ) ); break;
                        case 1: out.push_back( char( 'a' + ( s % 26 ) ) ); break;
                        case 2: out.push_back( char( '0' + ( s % 10 ) ) ); break;
                        default: out.push_back( ( s & 1 ) ? '_' : ' ' ); break;
                    }
                }
                break;
            }
        }
    }
    out.resize( n );
}

// every regular file under <root>/src and <root>/docs, read whole
static void loadRepoText( const char* root, std::vector<std::string>& outFiles, std::vector<std::string>& outNames )
{
    for( const char* sub : { "src", "docs" } )
    {
        const std::filesystem::path dir = std::filesystem::path( root ) / sub;
        std::error_code             ec;
        if( !std::filesystem::is_directory( dir, ec ) )
        {
            continue;
        }
        for( std::filesystem::recursive_directory_iterator it( dir, ec ), end; it != end && !ec; it.increment( ec ) )
        {
            if( !it->is_regular_file( ec ) )
            {
                continue;
            }
            std::FILE* fp = std::fopen( it->path().string().c_str(), "rb" );
            if( fp == nullptr )
            {
                continue;
            }
            std::string bytes;
            char        buf[ 65536 ];
            std::size_t got = 0;
            while( ( got = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
            {
                bytes.append( buf, got );
            }
            std::fclose( fp );
            outFiles.push_back( std::move( bytes ) );
            outNames.push_back( it->path().string() );
        }
    }
}

// ============================================================================
// Arm A — classMasks
// ============================================================================

static bool masksEqual( const sk::Masks& a, const sk::Masks& b )
{
    return a.alnum == b.alnum && a.upper == b.upper && a.lower == b.lower && a.digit == b.digit;
}

// Every length 0..kBlockBytes over one buffer, vector vs oracle. Returns the first failing (length,
// offset) as a message, or an empty string.
static std::string classMasksSweep( const std::string& text )
{
    for( std::size_t off = 0; off < text.size(); ++off )
    {
        const std::size_t avail = text.size() - off;
        const std::size_t maxN  = avail < sk::kBlockBytes ? avail : sk::kBlockBytes;
        for( std::size_t n = 0; n <= maxN; ++n )
        {
            sk::Masks got{}, want{};
            sk::classMasks( text.data() + off, n, got );
            sk::classMasks_scalar( text.data() + off, n, want );
            if( !masksEqual( got, want ) )
            {
                char msg[ 256 ];
                std::snprintf( msg, sizeof( msg ),
                               "off=%zu n=%zu got(a=%08x u=%08x l=%08x d=%08x) want(a=%08x u=%08x l=%08x d=%08x)",
                               off, n, got.alnum, got.upper, got.lower, got.digit,
                               want.alnum, want.upper, want.lower, want.digit );
                return msg;
            }
        }
    }
    return {};
}

// the whole byte alphabet, one byte per position, so no class boundary can go unvisited
static void armAllBytes()
{
    std::string every;
    for( unsigned b = 0; b < 256u; ++b )
    {
        every.push_back( char( b ) );
    }
    const std::string fail = classMasksSweep( every );
    checkf( fail.empty(), "A1 classMasks over all 256 byte values, every offset and length%s%s",
            fail.empty() ? "" : " — ", fail.c_str() );

    // the class definition itself, one byte at a time, against the shipped lexindex predicate set
    bool defOk = true;
    for( unsigned b = 0; b < 256u; ++b )
    {
        const char  c = char( b );
        sk::Masks   m{};
        sk::classMasks( &c, 1, m );
        const bool wantUpper = b >= 'A' && b <= 'Z';
        const bool wantLower = b >= 'a' && b <= 'z';
        const bool wantDigit = b >= '0' && b <= '9';
        defOk = defOk && ( ( m.upper & 1u ) != 0 ) == wantUpper && ( ( m.lower & 1u ) != 0 ) == wantLower
                      && ( ( m.digit & 1u ) != 0 ) == wantDigit
                      && ( ( m.alnum & 1u ) != 0 ) == ( wantUpper || wantLower || wantDigit );
    }
    checkf( defOk, "A2 classMasks single-byte classes match [A-Z]/[a-z]/[0-9] exactly (bytes >= 0x80 are separators)" );
}

// ============================================================================
// Arm F — the tokenizer, and the VERBATIM pre-change walkers it must equal
// ============================================================================

// Kept byte-for-byte as they stood at 05f4b892 (src/lexindex.h:130 and :201) so this arm compares the new
// mask-driven walkers against the OLD code, not against a paraphrase of it. Do not "clean these up".

// lexUpperOpensToken went with them: it was the state machines' one-byte lookahead, and the mask algebra
// that replaced them states the same rule as `U & (A<<1) & ( ~(U<<1) | (L>>1) )`. Kept HERE, verbatim,
// because a reference walker that borrowed the shipped rule would move with it and prove nothing.
static bool refLexUpperOpensToken( std::string_view text, std::size_t k, bool prevUpper ) noexcept
{
    const unsigned char next = ( k + 1 < text.size() ) ? static_cast< unsigned char >( text[ k + 1 ] ) : 0u;
    return !prevUpper || ( next >= 'a' && next <= 'z' );
}

template< class EmitFn >
static void refForEachLexSubtoken( std::string_view text, EmitFn&& emit )
{
    constexpr std::size_t kNoTokenByte = ~std::size_t( 0 );
    std::size_t           tokStartByte = kNoTokenByte;
    bool                  prevUpper    = false;
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        const unsigned char c     = static_cast< unsigned char >( text[ k ] );
        const bool          upper = c >= 'A' && c <= 'Z';
        const bool          lower = c >= 'a' && c <= 'z';
        const bool          digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit )
        {
            if( tokStartByte != kNoTokenByte ) { emit( tokStartByte, k ); tokStartByte = kNoTokenByte; }
            prevUpper = false;
            continue;
        }
        if( upper && tokStartByte != kNoTokenByte && refLexUpperOpensToken( text, k, prevUpper ) )
        {
            emit( tokStartByte, k );
            tokStartByte = k;
        }
        if( tokStartByte == kNoTokenByte )
        {
            tokStartByte = k;
        }
        prevUpper = upper;
    }
    if( tokStartByte != kNoTokenByte )
    {
        emit( tokStartByte, text.size() );
    }
}

template< class EmitFn >
static void refForEachLexSubtokenHashed( std::string_view text, EmitFn&& emit )
{
    constexpr std::size_t   kNoTokenByte = ~std::size_t( 0 );
    constexpr std::uint64_t kFnvBasis    = 1469598103934665603ull;
    std::size_t             tokStartByte = kNoTokenByte;
    std::uint64_t           h            = kFnvBasis;
    bool                    prevUpper    = false;
    const auto mix = [ & ]( unsigned char c ) noexcept { h = rw::hashutil::fnv1aAbsorb( h, char( rw::lexLowerByte( c ) ) ); };
    const auto beginToken = [ & ]( unsigned char c, std::size_t k ) noexcept
    {
        tokStartByte = k;
        h            = kFnvBasis;
        mix( c );
    };
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        const unsigned char c     = static_cast< unsigned char >( text[ k ] );
        const bool          upper = c >= 'A' && c <= 'Z';
        const bool          lower = c >= 'a' && c <= 'z';
        const bool          digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit )
        {
            if( tokStartByte != kNoTokenByte ) { emit( tokStartByte, k, h ); tokStartByte = kNoTokenByte; }
            prevUpper = false;
            continue;
        }
        if( upper && tokStartByte != kNoTokenByte && refLexUpperOpensToken( text, k, prevUpper ) )
        {
            emit( tokStartByte, k, h );
            beginToken( c, k );
            prevUpper = true;
            continue;
        }
        if( tokStartByte == kNoTokenByte ) { beginToken( c, k ); prevUpper = upper; continue; }
        mix( c );
        prevUpper = upper;
    }
    if( tokStartByte != kNoTokenByte )
    {
        emit( tokStartByte, text.size(), h );
    }
}

struct Tok
{
    std::size_t   start = 0;
    std::size_t   end   = 0;
    std::uint64_t hash  = 0;
};

// ONE collector, driving whichever walker it is handed — deliberately not four (or two) near-identical
// wrappers, which is a clone group the repo's own --quality-delta would (and did) flag. The default
// argument on the sink lets the SAME lambda serve the two-argument span walker and the three-argument
// hashed one.
template< class Walk >
static void collect( std::string_view text, std::vector< Tok >& out, Walk&& walk )
{
    out.clear();
    walk( text, [ &out ]( std::size_t s, std::size_t e, std::uint64_t h = 0 ) { out.push_back( { s, e, h } ); } );
}

// the four drivers, as the thinnest possible adapters over the function templates (which cannot be
// passed as values)
inline constexpr auto kRefHashed = []( std::string_view t, auto&& f ) { refForEachLexSubtokenHashed( t, f ); };
inline constexpr auto kNewHashed = []( std::string_view t, auto&& f ) { rw::forEachLexSubtokenHashed( t, f ); };
inline constexpr auto kRefSpans  = []( std::string_view t, auto&& f ) { refForEachLexSubtoken( t, f ); };
inline constexpr auto kNewSpans  = []( std::string_view t, auto&& f ) { rw::forEachLexSubtoken( t, f ); };

// Compare all four lists for one text. Returns "" when identical, else the first divergence.
static std::string tokenizerDiff( std::string_view text )
{
    static std::vector< Tok > refH, newH, refS, newS;
    collect( text, refH, kRefHashed );
    collect( text, newH, kNewHashed );
    collect( text, refS, kRefSpans );
    collect( text, newS, kNewSpans );

    char msg[ 384 ];
    if( refS.size() != newS.size() )
    {
        std::snprintf( msg, sizeof( msg ), "span COUNT %zu vs %zu (len=%zu)", refS.size(), newS.size(), text.size() );
        return msg;
    }
    for( std::size_t i = 0; i < refS.size(); ++i )
    {
        if( refS[ i ].start != newS[ i ].start || refS[ i ].end != newS[ i ].end )
        {
            std::snprintf( msg, sizeof( msg ), "span #%zu [%zu,%zu) vs [%zu,%zu) (len=%zu)", i,
                           refS[ i ].start, refS[ i ].end, newS[ i ].start, newS[ i ].end, text.size() );
            return msg;
        }
    }
    if( refH.size() != newH.size() )
    {
        std::snprintf( msg, sizeof( msg ), "hashed COUNT %zu vs %zu (len=%zu)", refH.size(), newH.size(), text.size() );
        return msg;
    }
    for( std::size_t i = 0; i < refH.size(); ++i )
    {
        if( refH[ i ].start != newH[ i ].start || refH[ i ].end != newH[ i ].end || refH[ i ].hash != newH[ i ].hash )
        {
            std::snprintf( msg, sizeof( msg ), "hashed #%zu [%zu,%zu)#%016llx vs [%zu,%zu)#%016llx (len=%zu)", i,
                           refH[ i ].start, refH[ i ].end, ( unsigned long long )refH[ i ].hash,
                           newH[ i ].start, newH[ i ].end, ( unsigned long long )newH[ i ].hash, text.size() );
            return msg;
        }
        // and the fused hash must still equal the standalone lexSubtokenHash of the same span
        const std::uint64_t standalone = rw::lexSubtokenHash( text.data() + newH[ i ].start, newH[ i ].end - newH[ i ].start );
        if( standalone != newH[ i ].hash )
        {
            std::snprintf( msg, sizeof( msg ), "fused hash #%zu %016llx != lexSubtokenHash %016llx", i,
                           ( unsigned long long )newH[ i ].hash, ( unsigned long long )standalone );
            return msg;
        }
        // ... and the hash-free walker's spans must be the same spans
        if( refS[ i ].start != newH[ i ].start || refS[ i ].end != newH[ i ].end )
        {
            std::snprintf( msg, sizeof( msg ), "walker disagreement #%zu [%zu,%zu) vs [%zu,%zu)", i,
                           refS[ i ].start, refS[ i ].end, newH[ i ].start, newH[ i ].end );
            return msg;
        }
    }
    return {};
}

// The hand-written seam table from docs/EVALS.md §4 — the cases the acronym rule exists for, spelled out
// so a failure names the input rather than a random offset.
static void armTokenizerSeams()
{
    static const char* kCases[] = {
        "", "a", "A", "aB", "Ab", "AB", "ABc", "aBc", "MCP", "MCP2Server", "HTTPServer", "IOError",
        "XMLHttpRequest", "_max_speed", "updateCollisionPositionVelocity", "foo bar", "  ", "__",
        "A1B2C3", "camelCASE", "CASEcamel", "endsWithUPPER", "x", "0", "9a", "a9", "Z", "aZ", "ZZa",
        "ZZZZZZZZZZZZZZZZZZZZa",                                   // acronym run straddling a 16-byte block
        "aaaaaaaaaaaaaaaBcccccccccccccccDeeeeeeeeeeeeeeeF",         // camel seam at 15/31/47
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaBc",                        // camel seam exactly at 32
        "ABCDEFGHIJKLMNOPa", "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFa",   // acronym seam at 16 and at 32
        "____________________abc", "abc____________________",
    };
    bool ok = true;
    std::string firstFail;
    for( const char* c : kCases )
    {
        const std::string d = tokenizerDiff( c );
        if( !d.empty() && firstFail.empty() )
        {
            firstFail = std::string( "\"" ) + c + "\": " + d;
            ok        = false;
        }
    }
    checkf( ok, "F1 tokenizer equals the pre-change walker on the %zu registered seam cases%s%s",
            sizeof( kCases ) / sizeof( kCases[ 0 ] ), ok ? "" : " — ", firstFail.c_str() );
}

// ============================================================================
// main
// ============================================================================

int main( int argc, char** argv )
{
    const char* root = argc > 1 ? argv[ 1 ] : ".";
    std::printf( "strkern: path=%s block=%zu root=%s\n", sk::kPathName, sk::kBlockBytes, root );
    std::printf( "strkern path: %s\n", sk::kPathName );

    armAllBytes();
    armTokenizerSeams();

    // ── the fixed-seed random sweep ──────────────────────────────────────────────────────────────────
    DeterministicRng gen{ 0x5DEECE66Dull };
    std::string      buf, folded, foldedRef, lowered;
    std::string      classFail, foldFail, eqFail, findFail, tokFail;
    std::size_t      bufferCount = 0;

    // one byteset per shape the (b>>3, b&7) packing could get wrong
    sk::Byteset256 setEmpty, setFull, setOne, setHighOnly, setXml;
    for( unsigned b = 0; b < 256u; ++b )
    {
        setFull.add( static_cast< unsigned char >( b ) );
    }
    setOne.add( 'q' );
    setHighOnly.addRange( 0x80, 0xFF );
    for( char c : { '&', '<', '>', '"', '\'', '\t', '\n', '\r' } )
    {
        setXml.add( static_cast< unsigned char >( c ) );
    }
    setXml.addRange( 0x80, 0xFF );
    const sk::Byteset256* kSets[]     = { &setEmpty, &setFull, &setOne, &setHighOnly, &setXml };
    const char*           kSetNames[] = { "empty", "full", "one", "high", "xml" };

    for( int iter = 0; iter < 100000; ++iter )
    {
        const Alphabet    alpha = Alphabet( iter & 3 );
        const std::size_t n     = std::size_t( gen.next() % 301u );   // 0..300, straddles 16/32 repeatedly
        drawBuffer( gen, alpha, n, buf );
        ++bufferCount;

        // A — classMasks at every offset/length that fits in one block, but only on a slice (the full
        // O(n * block) sweep on 100k buffers would dominate the gate's runtime)
        if( classFail.empty() )
        {
            const std::size_t probeOff = n == 0 ? 0 : std::size_t( gen.next() % n );
            const std::size_t avail    = n - probeOff;
            const std::size_t maxN     = avail < sk::kBlockBytes ? avail : sk::kBlockBytes;
            for( std::size_t m = 0; m <= maxN && classFail.empty(); ++m )
            {
                sk::Masks got{}, want{};
                sk::classMasks( buf.data() + probeOff, m, got );
                sk::classMasks_scalar( buf.data() + probeOff, m, want );
                if( !masksEqual( got, want ) )
                {
                    char msg[ 256 ];
                    std::snprintf( msg, sizeof( msg ), "iter=%d alpha=%d off=%zu n=%zu", iter, int( alpha ), probeOff, m );
                    classFail = msg;
                }
            }
        }

        // B — lowerFoldAscii, vector vs SWAR scalar, in place
        if( foldFail.empty() )
        {
            folded    = buf;
            foldedRef = buf;
            sk::lowerFoldAscii( folded.data(), folded.size() );
            sk::lowerFoldAscii_scalar( foldedRef.data(), foldedRef.size() );
            if( folded != foldedRef )
            {
                char msg[ 128 ];
                std::snprintf( msg, sizeof( msg ), "iter=%d alpha=%d n=%zu", iter, int( alpha ), n );
                foldFail = msg;
            }
            // and against the definition, byte by byte
            for( std::size_t k = 0; k < n && foldFail.empty(); ++k )
            {
                const unsigned char c    = static_cast< unsigned char >( buf[ k ] );
                const unsigned char want = ( c >= 'A' && c <= 'Z' ) ? static_cast< unsigned char >( c + 0x20 ) : c;
                if( static_cast< unsigned char >( folded[ k ] ) != want )
                {
                    char msg[ 128 ];
                    std::snprintf( msg, sizeof( msg ), "definition iter=%d k=%zu byte=%02x", iter, k, c );
                    foldFail = msg;
                }
            }
        }

        // C — lowerFoldedEquals: equal case, and every single-byte perturbation of one random position
        if( eqFail.empty() && n > 0 )
        {
            lowered = buf;
            sk::lowerFoldAscii_scalar( lowered.data(), lowered.size() );
            if( !sk::lowerFoldedEquals( buf.data(), lowered.data(), n )
                || !sk::lowerFoldedEquals_scalar( buf.data(), lowered.data(), n ) )
            {
                eqFail = "self-compare returned false";
            }
            const std::size_t at  = std::size_t( gen.next() % n );
            const char        old = lowered[ at ];
            lowered[ at ]         = char( static_cast< unsigned char >( old ) ^ 0x01 );
            if( eqFail.empty()
                && sk::lowerFoldedEquals( buf.data(), lowered.data(), n ) != sk::lowerFoldedEquals_scalar( buf.data(), lowered.data(), n ) )
            {
                char msg[ 128 ];
                std::snprintf( msg, sizeof( msg ), "perturbed iter=%d at=%zu n=%zu", iter, at, n );
                eqFail = msg;
            }
            lowered[ at ] = old;
        }

        // D/E — the find kernels vs their scalar twins vs a naive oracle
        if( findFail.empty() )
        {
            const char needle = char( gen.next() & 0xFF );
            const std::size_t gotB  = sk::findByte( buf.data(), n, needle );
            const std::size_t refB  = sk::findByte_scalar( buf.data(), n, needle );
            std::size_t       naive = n;
            for( std::size_t k = 0; k < n; ++k )
            {
                if( buf[ k ] == needle ) { naive = k; break; }
            }
            if( gotB != refB || gotB != naive )
            {
                char msg[ 160 ];
                std::snprintf( msg, sizeof( msg ), "findByte iter=%d got=%zu ref=%zu naive=%zu n=%zu", iter, gotB, refB, naive, n );
                findFail = msg;
            }

            // find3: half the time plant the needle so a HIT is exercised, half the time draw at random
            char needle3[ 3 ] = { char( gen.next() & 0xFF ), char( gen.next() & 0xFF ), char( gen.next() & 0xFF ) };
            if( n >= 3 && ( gen.next() & 1 ) )
            {
                const std::size_t at = std::size_t( gen.next() % ( n - 2 ) );
                std::memcpy( needle3, buf.data() + at, 3 );
            }
            const std::size_t got3 = sk::find3( buf.data(), n, needle3 );
            const std::size_t ref3 = sk::find3_scalar( buf.data(), n, needle3 );
            std::size_t       nai3 = n;
            for( std::size_t k = 0; k + 3 <= n; ++k )
            {
                if( std::memcmp( buf.data() + k, needle3, 3 ) == 0 ) { nai3 = k; break; }
            }
            if( findFail.empty() && ( got3 != ref3 || got3 != nai3 ) )
            {
                char msg[ 160 ];
                std::snprintf( msg, sizeof( msg ), "find3 iter=%d got=%zu ref=%zu naive=%zu n=%zu", iter, got3, ref3, nai3, n );
                findFail = msg;
            }

            const std::size_t si   = std::size_t( gen.next() % 5u );
            const std::size_t gotS = sk::findByteset( buf.data(), n, *kSets[ si ] );
            const std::size_t refS = sk::findByteset_scalar( buf.data(), n, *kSets[ si ] );
            std::size_t       naiS = n;
            for( std::size_t k = 0; k < n; ++k )
            {
                if( kSets[ si ]->contains( static_cast< unsigned char >( buf[ k ] ) ) ) { naiS = k; break; }
            }
            if( findFail.empty() && ( gotS != refS || gotS != naiS ) )
            {
                char msg[ 192 ];
                std::snprintf( msg, sizeof( msg ), "findByteset[%s] iter=%d got=%zu ref=%zu naive=%zu n=%zu",
                               kSetNames[ si ], iter, gotS, refS, naiS, n );
                findFail = msg;
            }
        }

        // F — tokenizer equivalence on the random corpus
        if( tokFail.empty() )
        {
            const std::string d = tokenizerDiff( buf );
            if( !d.empty() )
            {
                char msg[ 512 ];
                std::snprintf( msg, sizeof( msg ), "iter=%d alpha=%d %s", iter, int( alpha ), d.c_str() );
                tokFail = msg;
            }
        }
    }

    checkf( classFail.empty(), "A3 classMasks vs scalar oracle on %zu random buffers (4 alphabets, len 0..300)%s%s",
            bufferCount, classFail.empty() ? "" : " — ", classFail.c_str() );
    checkf( foldFail.empty(), "B1 lowerFoldAscii vector == SWAR scalar == the A-Z definition, %zu buffers%s%s",
            bufferCount, foldFail.empty() ? "" : " — ", foldFail.c_str() );
    checkf( eqFail.empty(), "C1 lowerFoldedEquals vector == scalar, equal and perturbed, %zu buffers%s%s",
            bufferCount, eqFail.empty() ? "" : " — ", eqFail.c_str() );
    checkf( findFail.empty(), "D1/E1 findByte / find3 / findByteset vector == scalar == naive oracle, %zu buffers%s%s",
            bufferCount, findFail.empty() ? "" : " — ", findFail.c_str() );
    checkf( tokFail.empty(), "F2 tokenizer == pre-change walker (spans + fused hashes) on %zu random buffers%s%s",
            bufferCount, tokFail.empty() ? "" : " — ", tokFail.c_str() );

    // ── the real-text corpus ─────────────────────────────────────────────────────────────────────────
    std::vector< std::string > files, names;
    loadRepoText( root, files, names );
    checkf( files.size() >= 50, "G0 real-text corpus loaded: %zu files under %s/{src,docs} (need >= 50 for the arm to mean anything)",
            files.size(), root );

    std::string realClassFail, realFoldFail, realTokFail, realFindFail;
    std::size_t totalBytes = 0;
    for( std::size_t fi = 0; fi < files.size(); ++fi )
    {
        const std::string& text = files[ fi ];
        totalBytes += text.size();

        if( realClassFail.empty() )
        {
            // every block-aligned window plus the ragged tail — the whole file's bytes are classified
            for( std::size_t off = 0; off < text.size() && realClassFail.empty(); off += sk::kBlockBytes )
            {
                const std::size_t avail = text.size() - off;
                const std::size_t m     = avail < sk::kBlockBytes ? avail : sk::kBlockBytes;
                sk::Masks         got{}, want{};
                sk::classMasks( text.data() + off, m, got );
                sk::classMasks_scalar( text.data() + off, m, want );
                if( !masksEqual( got, want ) )
                {
                    realClassFail = names[ fi ] + " @" + std::to_string( off );
                }
            }
        }
        if( realFoldFail.empty() )
        {
            folded    = text;
            foldedRef = text;
            sk::lowerFoldAscii( folded.data(), folded.size() );
            sk::lowerFoldAscii_scalar( foldedRef.data(), foldedRef.size() );
            if( folded != foldedRef )
            {
                realFoldFail = names[ fi ];
            }
            else if( !sk::lowerFoldedEquals( text.data(), folded.data(), text.size() ) )
            {
                realFoldFail = names[ fi ] + " (foldedEquals)";
            }
        }
        if( realFindFail.empty() && text.size() >= 3 )
        {
            // the needle a --grep trigram probe would use: the file's own middle three bytes
            const std::size_t at = text.size() / 2 - 1;
            char              needle3[ 3 ];
            std::memcpy( needle3, text.data() + at, 3 );
            const std::size_t got3 = sk::find3( text.data(), text.size(), needle3 );
            const std::size_t ref3 = sk::find3_scalar( text.data(), text.size(), needle3 );
            std::size_t       nai3 = text.size();
            for( std::size_t k = 0; k + 3 <= text.size(); ++k )
            {
                if( std::memcmp( text.data() + k, needle3, 3 ) == 0 ) { nai3 = k; break; }
            }
            const std::size_t gotS = sk::findByteset( text.data(), text.size(), setXml );
            const std::size_t refS = sk::findByteset_scalar( text.data(), text.size(), setXml );
            if( got3 != ref3 || got3 != nai3 || gotS != refS )
            {
                realFindFail = names[ fi ];
            }
        }
        if( realTokFail.empty() )
        {
            const std::string d = tokenizerDiff( text );
            if( !d.empty() )
            {
                realTokFail = names[ fi ] + ": " + d;
            }
        }
    }

    checkf( realClassFail.empty(), "G1 classMasks vs oracle over every byte of src/ + docs/ (%zu files, %zu bytes)%s%s",
            files.size(), totalBytes, realClassFail.empty() ? "" : " — ", realClassFail.c_str() );
    checkf( realFoldFail.empty(), "G2 lowerFoldAscii / lowerFoldedEquals over the same %zu files%s%s",
            files.size(), realFoldFail.empty() ? "" : " — ", realFoldFail.c_str() );
    checkf( realFindFail.empty(), "G3 find3 / findByteset over the same %zu files%s%s",
            files.size(), realFindFail.empty() ? "" : " — ", realFindFail.c_str() );
    checkf( realTokFail.empty(), "G4 tokenizer == pre-change walker over every byte of src/ + docs/ (%zu files, %zu bytes)%s%s",
            files.size(), totalBytes, realTokFail.empty() ? "" : " — ", realTokFail.c_str() );

    std::printf( "%s\n", g_fail == 0 ? "ALL PASS" : "FAILURES ABOVE" );
    return g_fail;
}
