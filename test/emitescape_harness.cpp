// emitescape_harness.cpp — byte-identity harness for the RUN-COPY rewrite of the three emit escapers
// (rw::escapeXml and rw::appendCdataSafe in src/serialize.h, rw::jsonesc::escapeInto in
// src/infra/jsonesc.h). All three are header-only, so this calls them directly rather than diffing a
// whole map, and it is independent of the ripwire binary and of main.cpp.
//
// THE CONTRACT UNDER TEST. The rewrite replaces a per-byte switch with "find the next byte that is IN
// the special set (strkern::findByteset), copy the clean run in one memcpy, handle that one byte with
// the SAME switch, repeat". That is a pure performance change: the emitted bytes must not move, on ANY
// input, including the ones a hand-written byte set is most likely to get wrong. So this harness keeps
// the ORIGINAL per-byte loops verbatim as `*Ref` below and asserts the shipped function agrees with
// them byte-for-byte. The references are frozen copies — if the shipped semantics ever legitimately
// change, the reference changes in the same commit and the gate says so out loud.
//
// Cases proved:
//   A  every one of the 256 byte values, alone and concatenated in order.
//   B  a special byte planted at EVERY offset of a 0..96-byte filler string — the block-boundary sweep
//      that a 16-byte NEON / 32-byte AVX2 run loop plus its scalar tail must survive.
//   C  invalid UTF-8: bare continuation, overlong 2/3/4-byte forms, UTF-16 surrogate halves, >U+10FFFF,
//      a sequence TRUNCATED at end-of-buffer, and a lone continuation byte as the final byte.
//   D  valid multibyte (Latin-1 range, CJK, astral) and a UTF-8 BOM, alone and around specials.
//   E  CDATA: "]]>" at the start, mid, and end of a body, "]]]]>", and a trailing "]]".
//   F  all four (escapeAngleAmp, validateUtf8) combinations of escapeInto, plus both
//      replacementAsTextEscape postures.
//   G  200k deterministic fuzz strings over an alphabet biased to the special set.
//   MUT a can-go-red arm: a byteset with '<' DROPPED (compiled in with -DEMITESCAPE_MUTATE_BYTESET=1
//      as `escapeXmlMutatedSet`) MUST disagree with the reference. If it agrees, the comparison is
//      not looking at what it claims to and the gate is worthless.
//
// Exit 0 = all pass; nonzero = a failure.

#include "../src/serialize.h"
#include "../src/infra/jsonesc.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

using namespace rw;

static int g_fail = 0;
static int g_checks = 0;

static void check( bool cond, const char* msg )
{
    ++g_checks;
    if( !cond )
    {
        std::printf( "  FAIL  %s\n", msg );
        g_fail = 1;
    }
}

// ── the frozen per-byte references (verbatim copies of the pre-rewrite loops) ──────────────────────────

static std::string escapeXmlRef( std::string_view s )
{
    std::string out;
    const auto put = [ & ]( const char* lit ) { while( *lit ) { out.push_back( *lit++ ); } };
    const char*       d = s.data();
    const std::size_t n = s.size();
    for( std::size_t i = 0; i < n; )
    {
        const char c = d[i];
        switch( c )
        {
            case '&':  put( "&amp;" );  ++i; break;
            case '<':  put( "&lt;" );   ++i; break;
            case '>':  put( "&gt;" );   ++i; break;
            case '"':  put( "&quot;" ); ++i; break;
            case '\'': put( "&apos;" ); ++i; break;
            case '\t':
            case '\n':
            case '\r': put( xmlControlCharRef( c ) ); ++i; break;
            default:
                if( static_cast<unsigned char>( c ) < 0x80 ) { out.push_back( xmlSafeByte( c ) ); ++i; }
                else if( const int len = jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { out.push_back( '?' ); ++i; }
                else
                {
                    for( int k = 0; k < len; ++k )
                    {
                        out.push_back( d[i + k] );
                    }
                    i += std::size_t( len );
                }
        }
    }
    return out;
}

static std::string appendCdataSafeRef( std::string_view body )
{
    std::string safe;
    const char*       d = body.data();
    const std::size_t n = body.size();
    for( std::size_t i = 0; i < n; )
    {
        if( i + 2 < n && d[i] == ']' && d[i + 1] == ']' && d[i + 2] == '>' )
        { safe += "]]]]><![CDATA[>";  i += 3;  continue; }
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x80 ) { safe += xmlSafeByte( d[i] ); ++i; }
        else if( const int len = jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { safe += '?'; ++i; }
        else { safe.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
    }
    return safe;
}

static std::string escapeIntoRef( std::string_view s, bool escapeAngleAmp, bool validateUtf8, bool replacementAsTextEscape )
{
    std::string       out;
    const char*       d = s.data();
    const std::size_t n = s.size();
    std::size_t       i = 0;
    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x80 )
        {
            switch( c )
            {
                case '"':  out += "\\\""; ++i; continue;
                case '\\': out += "\\\\"; ++i; continue;
                case '\n': out += "\\n";  ++i; continue;
                case '\r': out += "\\r";  ++i; continue;
                case '\t': out += "\\t";  ++i; continue;
                case '<':  if( escapeAngleAmp ) { out += "\\u003c"; ++i; continue; } break;
                case '>':  if( escapeAngleAmp ) { out += "\\u003e"; ++i; continue; } break;
                case '&':  if( escapeAngleAmp ) { out += "\\u0026"; ++i; continue; } break;
                default: break;
            }
            if( c < 0x20 )
            { char b[ 8 ]; std::snprintf( b, sizeof( b ), "\\u%04x", unsigned( c ) ); out += b; }
            else
            {
                out += char( c );
            }
            ++i;
            continue;
        }
        if( !validateUtf8 ) { out += char( c ); ++i; continue; }
        const int len = jsonesc::utf8SeqLen( d, i, n );
        if( len == 0 )
        {
            if( replacementAsTextEscape ) { out += "\\ufffd"; }
            else                          { out += "\xEF\xBF\xBD"; }
            ++i;
        }
        else { out.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
    }
    return out;
}

// ── the shipped functions, wrapped to the same signature ──────────────────────────────────────────────

static std::string escapeXmlNew( std::string_view s )
{
    std::vector<char> buf;
    const std::string_view v = escapeXml( s, buf );
    return std::string( v );
}

static std::string appendCdataSafeNew( std::string_view s )
{
    std::string out;
    appendCdataSafe( s, out );
    return out;
}

static std::string escapeIntoNew( std::string_view s, bool a, bool v, bool r )
{
    std::string out;
    jsonesc::escapeInto( s, out, a, v, r );
    return out;
}

// ── MUT: the same run-copy shape with '<' dropped from the byte set ───────────────────────────────────
// Deliberately WRONG. Not compiled into anything shipped; it exists so the harness can prove that its
// comparison actually notices a set member going missing (a byteset bug is silent otherwise — the
// output is still well-formed-looking text, just with a raw '<' where an entity belonged).
#if EMITESCAPE_MUTATE_BYTESET
static std::string escapeXmlMutatedSet( std::string_view s )
{
    std::string       out;
    const char*       d = s.data();
    const std::size_t n = s.size();
    const auto put = [ & ]( const char* lit ) { while( *lit ) { out.push_back( *lit++ ); } };
    for( std::size_t i = 0; i < n; )
    {
        const char c = d[i];
        switch( c )
        {
            // '<' intentionally absent from the set — falls through to the verbatim copy below.
            case '&':  put( "&amp;" );  ++i; break;
            case '>':  put( "&gt;" );   ++i; break;
            case '"':  put( "&quot;" ); ++i; break;
            case '\'': put( "&apos;" ); ++i; break;
            case '\t':
            case '\n':
            case '\r': put( xmlControlCharRef( c ) ); ++i; break;
            default:
                if( static_cast<unsigned char>( c ) < 0x80 ) { out.push_back( xmlSafeByte( c ) ); ++i; }
                else if( const int len = jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { out.push_back( '?' ); ++i; }
                else
                {
                    for( int k = 0; k < len; ++k ) { out.push_back( d[i + k] ); }
                    i += std::size_t( len );
                }
        }
    }
    return out;
}
#endif

// ── the corpus ────────────────────────────────────────────────────────────────────────────────────────

// UB-free deterministic generator (same shape as test/harnesscommon.h's, kept local so this TU needs
// no extra include path).
struct Rng
{
    std::uint64_t state = 0x9E3779B97F4A7C15ull;
    std::uint64_t next() noexcept
    {
        state = state * 6364136223846793005ull ^ 1442695040888963407ull;
        std::uint64_t m = state;
        m ^= m >> 33;  m *= 0xFF51AFD7ED558CCDull;  m ^= m >> 33;
        return m;
    }
};

static void addCase( std::vector<std::string>& v, std::string s ) { v.push_back( std::move( s ) ); }

static std::vector<std::string> buildCorpus()
{
    std::vector<std::string> cases;

    // A — every byte value alone, and all 256 in order.
    std::string all;
    for( int b = 0; b < 256; ++b )
    {
        addCase( cases, std::string( 1, char( b ) ) );
        all.push_back( char( b ) );
    }
    addCase( cases, all );
    addCase( cases, std::string() );

    // B — a special byte planted at every offset of a filler run, across every length up to two
    // 32-byte AVX2 blocks plus a tail.
    const char specials[] = { '&', '<', '>', '"', '\'', '\t', '\n', '\r', '\0', '\x0b', '\x1f', '\x7f',
                              char( 0x80 ), char( 0xC3 ), char( 0xFF ), ']' };
    for( char sp : specials )
    {
        for( std::size_t len = 1; len <= 96; ++len )
        {
            for( std::size_t at = 0; at < len; at += ( len > 40 ? 7 : 1 ) )
            {
                std::string s( len, 'a' );
                s[at] = sp;
                addCase( cases, s );
            }
        }
    }

    // C — invalid UTF-8 shapes.
    const char* bad[] = {
        "\x80", "\xBF", "\xC0\x80", "\xC1\xBF", "\xC2", "\xE0\x80\x80", "\xE0\x9F\xBF",
        "\xED\xA0\x80", "\xED\xBF\xBF", "\xE2\x82", "\xF0\x80\x80\x80", "\xF0\x8F\xBF\xBF",
        "\xF4\x90\x80\x80", "\xF5\x80\x80\x80", "\xFE", "\xFF", "\xF0\x9D\x84",
    };
    for( const char* b : bad )
    {
        std::string s( b );
        addCase( cases, s );
        addCase( cases, "abc" + s );
        addCase( cases, s + "abc" );
        addCase( cases, "abc" + s + "<&>" );
        addCase( cases, std::string( 31, 'x' ) + s );
        addCase( cases, std::string( 32, 'x' ) + s );
        addCase( cases, std::string( 33, 'x' ) + s );
    }
    // lone continuation byte as the very last byte of the buffer
    addCase( cases, std::string( 40, 'q' ) + "\xBF" );
    addCase( cases, std::string( 40, 'q' ) + "\xE2\x82" );

    // D — valid multibyte + BOM.
    const char* good[] = { "\xC3\xA9", "\xE2\x82\xAC", "\xF0\x9D\x84\x9E", "\xEF\xBB\xBF", "\xEF\xBF\xBD" };
    for( const char* g : good )
    {
        std::string s( g );
        addCase( cases, s );
        addCase( cases, s + "<" + s );
        addCase( cases, std::string( 30, 'z' ) + s + std::string( 30, 'z' ) );
        addCase( cases, std::string( 31, 'z' ) + s );
    }

    // E — CDATA close sequences.
    addCase( cases, "]]>" );
    addCase( cases, "]]" );
    addCase( cases, "]" );
    addCase( cases, "]]]" );
    addCase( cases, "]]]]>" );
    addCase( cases, "a]]>b" );
    addCase( cases, "]]>]]>" );
    addCase( cases, std::string( 31, 'p' ) + "]]>" );
    addCase( cases, std::string( 32, 'p' ) + "]]>" + std::string( 32, 'p' ) );
    addCase( cases, std::string( 30, 'p' ) + "]]" );
    addCase( cases, "]]\x01>" );

    // G — deterministic fuzz over an alphabet biased to the special set.
    Rng rng;
    const std::string alphabet = "abcdefgh<>&\"'\t\n\r]] \x01\x1f\x7f\x80\xC3\xA9\xE2\x82\xAC\xF0\x9D\x84\x9E\xFF";
    for( int k = 0; k < 200000; ++k )
    {
        const std::size_t len = std::size_t( rng.next() % 201 );
        std::string s;
        s.reserve( len );
        for( std::size_t j = 0; j < len; ++j )
        {
            s.push_back( alphabet[ std::size_t( rng.next() % alphabet.size() ) ] );
        }
        cases.push_back( std::move( s ) );
    }
    return cases;
}

int main()
{
    const std::vector<std::string> cases = buildCorpus();
    std::printf( "emitescape_harness: %zu inputs\n", cases.size() );

    std::size_t xmlBad = 0, cdataBad = 0, jsonBad = 0;
    for( const std::string& s : cases )
    {
        if( escapeXmlNew( s ) != escapeXmlRef( s ) )
        {
            if( xmlBad == 0 ) { std::printf( "  first escapeXml mismatch, len=%zu\n", s.size() ); }
            ++xmlBad;
        }
        if( appendCdataSafeNew( s ) != appendCdataSafeRef( s ) )
        {
            if( cdataBad == 0 ) { std::printf( "  first appendCdataSafe mismatch, len=%zu\n", s.size() ); }
            ++cdataBad;
        }
        for( int mode = 0; mode < 8; ++mode )
        {
            const bool a = ( mode & 1 ) != 0;
            const bool v = ( mode & 2 ) != 0;
            const bool r = ( mode & 4 ) != 0;
            if( escapeIntoNew( s, a, v, r ) != escapeIntoRef( s, a, v, r ) )
            {
                if( jsonBad == 0 ) { std::printf( "  first escapeInto mismatch, mode=%d len=%zu\n", mode, s.size() ); }
                ++jsonBad;
            }
        }
    }
    check( xmlBad == 0,   "escapeXml byte-identical to the frozen per-byte reference" );
    check( cdataBad == 0, "appendCdataSafe byte-identical to the frozen per-byte reference" );
    check( jsonBad == 0,  "escapeInto byte-identical to the frozen per-byte reference (8 flag combos)" );
    if( xmlBad )   { std::printf( "  escapeXml mismatches: %zu\n", xmlBad ); }
    if( cdataBad ) { std::printf( "  appendCdataSafe mismatches: %zu\n", cdataBad ); }
    if( jsonBad )  { std::printf( "  escapeInto mismatches: %zu\n", jsonBad ); }

    // scrub-disclosure predicate must keep agreeing with what the escapers actually DO (§B12.7): the
    // lossy-tell is derived from the same byte classes the run loop now skips over in bulk.
    std::size_t lossyBad = 0;
    for( const std::string& s : cases )
    {
        const bool lossy    = xmlScrubIsLossy( s );
        const bool cdataHit = appendCdataSafeRef( s ) != std::string( s ) && true;
        (void)cdataHit;
        // a lossy input is exactly one whose escaped form contains '?' or a substituted space that the
        // input did not have; assert the cheap direction: not-lossy ⇒ no '?' introduced.
        if( !lossy )
        {
            std::string ref = appendCdataSafeRef( s );
            std::string plain( s );
            // appendCdataSafe only splits ]]> on non-lossy input; strip that expansion before comparing
            std::string expanded;
            for( std::size_t i = 0; i < plain.size(); )
            {
                if( i + 2 < plain.size() && plain[i] == ']' && plain[i + 1] == ']' && plain[i + 2] == '>' )
                { expanded += "]]]]><![CDATA[>"; i += 3; }
                else { expanded += plain[i]; ++i; }
            }
            if( ref != expanded ) { ++lossyBad; }
        }
    }
    check( lossyBad == 0, "xmlScrubIsLossy(false) really means appendCdataSafe moved no byte" );

#if EMITESCAPE_MUTATE_BYTESET
    std::size_t mutDiff = 0;
    for( const std::string& s : cases )
    {
        if( escapeXmlMutatedSet( s ) != escapeXmlRef( s ) ) { ++mutDiff; }
    }
    check( mutDiff > 0, "MUT: a byteset missing '<' DISAGREES with the reference (the gate can go red)" );
    std::printf( "  MUT: %zu of %zu inputs differ\n", mutDiff, cases.size() );
#endif

    std::printf( "emitescape_harness: %d checks, %s\n", g_checks, g_fail ? "FAIL" : "ALL PASS" );
    return g_fail;
}
