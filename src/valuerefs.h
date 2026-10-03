#pragma once
// valuerefs.h — the ONE resolution of reference-as-value rows (RefRole::Value / RefRole::Through, captured by
// src/ingest_valuerefs.h), shared by every surface that discloses them: --callers/--callees and their MCP twins
// (callhierarchy.h), --impact, --safe-delete, --dead-code, --uses and --path.
//
// WHAT A ROW IS, AND IS NOT. A <vr> row says a function is USED AS A VALUE at bind= — stored into a table, field or
// variable, or passed as an argument — and names where it lands (into=). It is NOT a call: the call, if any, happens
// wherever the slot is later invoked. called_by= (callers side) and through= (callees side) name a function that MAY
// call through that slot — a called parameter, or a `tbl[k](…)` / `tbl.k(…)` on the same declaration — a clue an
// agent can follow, never a proven call. No count= / reaches= / callers= / impact_reaches= ever includes a row.
//
// MATCHED BY NAME, with the call graph's visibility: a definition in the reference's own file wins; otherwise a
// C/C++ definition with external linkage (a `static` one is reachable only from its own file), a Go definition in
// the same package directory, or a JS/TS/Python definition the file imports by that very name. A file-scope
// non-function declaration of the same name in the reference's file hides every definition elsewhere. Only
// functions and methods are targets (a class used as a value is out of scope).

#include "graph.h"             // jsImportKey — the "fileId#name" key, reused for containers
#include "graphlegend.h"       // countFieldOrEmpty — the absent-at-zero count spelling
#include "mention.h"           // pathStem — a module path's file stem
#include "resolve.h"           // includerDir — a path's directory
#include "infra/Diagnostics.h"   // EXPECTS/ENSURES — the window and index invariants
#include "model.h"
#include "sarif.h"
#include "serialize.h"   // escapeXml / jsonStr

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The default display window of the <vrs> rows (the runaway guard): value_refs= and total= stay whole, the rows
// beyond it are counted (capped="1") and the next= verb (--uses=SYM) pages every site.
inline constexpr std::size_t kValueRefRowCap = 64;

using VrLangFamily = ValueRefFamily;   // model.h: the armed-language table the capture indexes too

// A Through key matches a Value key: "*" (a computed subscript) reaches every keyed or indexed slot, "" (a bare
// call through the variable) only the variable itself, anything else only its own key.
inline bool vrKeyMatches( std::string_view throughKey, std::string_view valueKey ) noexcept
{
    if( throughKey == "*" )
    {
        return !valueKey.empty() && ( valueKey.front() == '.' || valueKey.front() == '[' );
    }
    return throughKey == valueKey;
}

// The index every verb queries. Built from one IngestResult in O(refs + symbols); no graph needed.
class ValueRefIndex
{
public:
    explicit ValueRefIndex( const IngestResult& ing ) : m_ing( ing )
    {
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && valueRefFamily( s.lang ) != VrLangFamily::None )
            {
                m_fnByName[ s.name ].push_back( id );
            }
        }
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            const Reference& r = ing.references[i];
            if( r.role == RefRole::Value )
            {
                m_values.push_back( i );
                if( !r.recvVar.empty() )
                {
                    m_valueByContainer[ jsImportKey( r.fileId, r.recvVar ) ].push_back( i );
                }
            }
            else if( r.role == RefRole::Through )
            {
                if( scopeOf( r ) == 'p' )
                {
                    m_throughParamBySym[ r.fromSymbol ].push_back( i );
                }
                else
                {
                    m_throughByContainer[ jsImportKey( r.fileId, r.calleeName ) ].push_back( i );
                }
            }
        }
        for( const Binding& b : ing.bindings )
        {
            if( b.kind == LocalBindKind::JsImport || b.kind == LocalBindKind::Import )
            {
                m_importsByFile[ b.fileId ].push_back( &b );
            }
        }
        ENSURES( std::is_sorted( m_values.begin(), m_values.end() ), "m_values is built in reference order — targetsOf binary-searches it" );
        m_targets.resize( m_values.size() );
        for( std::size_t k = 0; k < m_values.size(); ++k )
        {
            m_targets[k] = resolveName( ing.references[ m_values[k] ], ing.references[ m_values[k] ].calleeName );
            for( const NodeId t : m_targets[k] )
            {
                m_valuesByTarget[ t ].push_back( static_cast<std::uint32_t>( k ) );
            }
        }
    }

    // Value references (indices into ing.references) whose resolved target is any of `defs`, in served order.
    std::vector<std::uint32_t> valueRefsTo( std::span<const NodeId> defs ) const
    {
        std::vector<std::uint32_t> out;
        for( const NodeId d : defs )
        {
            if( const auto it = m_valuesByTarget.find( d ); it != m_valuesByTarget.end() )
            {
                for( const std::uint32_t k : it->second )
                {
                    out.push_back( m_values[k] );
                }
            }
        }
        std::ranges::sort( out );
        out.erase( std::ranges::unique( out ).begin(), out.end() );
        return out;
    }

    // True when at least one value reference resolves to `def`.
    bool isValueReferenced( NodeId def ) const
    {
        return m_valuesByTarget.find( def ) != m_valuesByTarget.end();
    }

    // The resolved targets of value reference `refIdx` (an index into ing.references).
    std::vector<NodeId> targetsOf( std::uint32_t refIdx ) const
    {
        const auto it = std::lower_bound( m_values.begin(), m_values.end(), refIdx );
        if( it == m_values.end() || *it != refIdx )
        {
            return {};
        }
        return m_targets[ static_cast<std::size_t>( it - m_values.begin() ) ];
    }

    // called_by=: the functions that may call through the slot value reference `refIdx` lands in, sorted by name.
    std::vector<NodeId> calledBy( std::uint32_t refIdx ) const
    {
        std::vector<NodeId> out;
        for( const std::uint32_t t : throughsFor( refIdx ) )
        {
            const NodeId f = m_ing.references[t].fromSymbol;
            if( f != kNoNode )
            {
                out.push_back( f );
            }
        }
        std::sort( out.begin(), out.end(), [ & ]( NodeId a, NodeId b )
        {
            const Symbol& sa = m_ing.symbols[a];
            const Symbol& sb = m_ing.symbols[b];
            return sa.name != sb.name ? sa.name < sb.name : a < b;
        } );
        out.erase( std::unique( out.begin(), out.end() ), out.end() );
        return out;
    }

    // The Through references matching value reference `refIdx` (indices into ing.references).
    std::vector<std::uint32_t> throughsFor( std::uint32_t refIdx ) const
    {
        const Reference&           v = m_ing.references[refIdx];
        std::vector<std::uint32_t> out;
        const char                 sc = scopeOf( v );
        if( sc == 'f' || sc == 'l' )
        {
            if( const auto it = m_throughByContainer.find( jsImportKey( v.fileId, v.recvVar ) ); it != m_throughByContainer.end() )
            {
                for( const std::uint32_t t : it->second )
                {
                    const Reference& tr = m_ing.references[t];
                    if( scopeOf( tr ) == sc && ( sc == 'f' || tr.fromSymbol == v.fromSymbol ) && vrKeyMatches( tr.composeRel, v.composeRel ) )
                    {
                        out.push_back( t );
                    }
                }
            }
        }
        else if( sc == 'a' || sc == 'p' )
        {
            // an argument of a bare callee: the callee's definitions that CALL that parameter; a parameter default: the
            // function the default belongs to.
            std::vector<NodeId> owners = sc == 'a' ? resolveName( v, v.recvVar ) : std::vector<NodeId>{ v.fromSymbol };
            for( const NodeId o : owners )
            {
                const auto it = m_throughParamBySym.find( o );
                if( o == kNoNode || it == m_throughParamBySym.end() )
                {
                    continue;
                }
                for( const std::uint32_t t : it->second )
                {
                    const Reference& tr = m_ing.references[t];
                    if( paramMatches( v.composeRel, tr ) )
                    {
                        out.push_back( t );
                    }
                }
            }
        }
        std::ranges::sort( out );
        out.erase( std::ranges::unique( out ).begin(), out.end() );
        return out;
    }

    // The value references a Through reference reaches (the callees side of the same join).
    std::vector<std::uint32_t> valuesThrough( std::uint32_t throughIdx ) const
    {
        const Reference&           t = m_ing.references[throughIdx];
        std::vector<std::uint32_t> out;
        const char                 sc = scopeOf( t );
        if( sc == 'f' || sc == 'l' )
        {
            if( const auto it = m_valueByContainer.find( jsImportKey( t.fileId, t.calleeName ) ); it != m_valueByContainer.end() )
            {
                for( const std::uint32_t v : it->second )
                {
                    const Reference& vr = m_ing.references[v];
                    if( scopeOf( vr ) == sc && ( sc == 'f' || vr.fromSymbol == t.fromSymbol ) && vrKeyMatches( t.composeRel, vr.composeRel ) )
                    {
                        out.push_back( v );
                    }
                }
            }
        }
        else if( sc == 'p' && t.fromSymbol != kNoNode )
        {
            // every argument of a bare call that resolves to this function, at this parameter; and its own default
            const Symbol& owner = m_ing.symbols[ t.fromSymbol ];
            for( const std::uint32_t v : m_values )
            {
                const Reference& vr  = m_ing.references[v];
                const char       vsc = scopeOf( vr );
                if( vsc == 'p' && vr.fromSymbol == t.fromSymbol && paramMatches( vr.composeRel, t ) )
                {
                    out.push_back( v );
                }
                else if( vsc == 'a' && vr.recvVar == owner.name && paramMatches( vr.composeRel, t ) )
                {
                    const std::vector<NodeId> owners = resolveName( vr, vr.recvVar );
                    if( std::find( owners.begin(), owners.end(), t.fromSymbol ) != owners.end() )
                    {
                        out.push_back( v );
                    }
                }
            }
        }
        std::ranges::sort( out );
        out.erase( std::ranges::unique( out ).begin(), out.end() );
        return out;
    }

    // Through references (role Through) or Value references (role Value) made inside any of `fns`.
    std::vector<std::uint32_t> madeIn( std::span<const NodeId> fns, RefRole role ) const
    {
        std::vector<std::uint32_t> out;
        const auto inFns = [ & ]( std::uint32_t i ) { return std::ranges::find( fns, m_ing.references[i].fromSymbol ) != fns.end(); };
        if( role == RefRole::Value )
        {
            std::ranges::copy_if( m_values, std::back_inserter( out ), inFns );
            return out;
        }
        for( const auto& [ key, list ] : m_throughByContainer )
        {
            std::ranges::copy_if( list, std::back_inserter( out ), inFns );
        }
        for( const auto& [ sym, list ] : m_throughParamBySym )
        {
            if( std::ranges::find( fns, sym ) != fns.end() )
            {
                out.insert( out.end(), list.begin(), list.end() );
            }
        }
        std::ranges::sort( out );
        return out;
    }

    static char scopeOf( const Reference& r ) noexcept
    {
        return r.qualifier.empty() ? 'x' : r.qualifier[0];
    }

private:
    // A value key "#N" (an argument position) or "#name" (a keyword / a parameter default) against a parameter Through.
    static bool paramMatches( std::string_view valueKey, const Reference& through ) noexcept
    {
        if( valueKey.size() < 2 || valueKey.front() != '#' )
        {
            return false;
        }
        const std::string_view tail = valueKey.substr( 1 );
        if( tail.front() >= '0' && tail.front() <= '9' )
        {
            return through.argCountKnown && std::to_string( through.argCount ) == tail;
        }
        return through.calleeName == tail;
    }

    // `name` as seen from reference `r`'s file, under the visibility rules in the header comment.
    std::vector<NodeId> resolveName( const Reference& r, std::string_view name ) const
    {
        const auto it = m_fnByName.find( std::string( name ) );
        if( it == m_fnByName.end() )
        {
            return {};
        }
        const VrLangFamily  fam = valueRefFamily( r.lang );
        std::vector<NodeId> sameFile, other;
        for( const NodeId id : it->second )
        {
            const Symbol& s = m_ing.symbols[id];
            if( valueRefFamily( s.lang ) != fam )
            {
                continue;
            }
            ( s.fileId == r.fileId ? sameFile : other ).push_back( id );
        }
        if( !sameFile.empty() )
        {
            return sameFile;
        }
        const bool fileShadow = r.qualifier.size() >= 2 && r.qualifier[1] == '1';
        if( fileShadow || other.empty() )
        {
            return {};
        }
        const std::string_view refPath = m_ing.files[ r.fileId ];
        std::vector<NodeId>    out;
        switch( fam )
        {
            case VrLangFamily::C:
            {
                for( const NodeId id : other )
                {
                    if( m_ing.symbols[id].internalLinkage == 0 )
                    {
                        out.push_back( id );
                    }
                }
                break;
            }
            case VrLangFamily::Go:
            {
                for( const NodeId id : other )
                {
                    if( includerDir( m_ing.files[ m_ing.symbols[id].fileId ] ) == includerDir( refPath ) )
                    {
                        out.push_back( id );
                    }
                }
                break;
            }
            case VrLangFamily::Js:
            case VrLangFamily::Py:
            {
                const auto imp = m_importsByFile.find( r.fileId );
                if( imp == m_importsByFile.end() )
                {
                    break;
                }
                for( const Binding* b : imp->second )
                {
                    const bool named = b->kind == LocalBindKind::JsImport ? ( b->var == name && b->importedName == name )
                                                                         : ( b->var == name && b->importedName.empty() );
                    if( !named )
                    {
                        continue;
                    }
                    const std::string_view mod  = b->typeName;
                    const std::size_t      cut  = mod.find_last_of( "/." );
                    std::string_view       stem = cut == std::string_view::npos ? mod : mod.substr( cut + 1 );
                    if( b->kind == LocalBindKind::JsImport )
                    {
                        stem = mention_detail::pathStem( mod );
                    }
                    for( const NodeId id : other )
                    {
                        const std::string_view defStem = mention_detail::pathStem( m_ing.files[ m_ing.symbols[id].fileId ] );
                        if( defStem == stem || ( defStem == "__init__" && mention_detail::pathStem( includerDir( m_ing.files[ m_ing.symbols[id].fileId ] ) ) == stem ) )
                        {
                            out.push_back( id );
                        }
                    }
                }
                break;
            }
            case VrLangFamily::None: break;
        }
        std::sort( out.begin(), out.end() );
        out.erase( std::unique( out.begin(), out.end() ), out.end() );
        return out;
    }

    const IngestResult&                                  m_ing;
    HashMap<std::string, std::vector<NodeId>>            m_fnByName;
    std::vector<std::uint32_t>                           m_values;            // Value reference indices, ascending
    std::vector<std::vector<NodeId>>                     m_targets;           // parallel to m_values
    HashMap<NodeId, std::vector<std::uint32_t>>          m_valuesByTarget;    // target def → positions in m_values
    HashMap<std::string, std::vector<std::uint32_t>>     m_valueByContainer;  // "file#container" → Value refs
    HashMap<std::string, std::vector<std::uint32_t>>     m_throughByContainer;
    HashMap<NodeId, std::vector<std::uint32_t>>          m_throughParamBySym;
    HashMap<std::uint32_t, std::vector<const Binding*>>  m_importsByFile;
};

// ── the rows every surface serves ─────────────────────────────────────────────────────────────────────────────
// One <vr> row. Callers side: in = the enclosing symbol of the binding site, calledBy = may-call functions.
// Callees side: to = the referenced function, through = the written callee of the call through the slot, sites =
// how many binding sites one (to, through) pair joins.
struct ValueRefRow
{
    std::uint32_t ref     = 0;          // the Value reference (bind=, into=)
    NodeId        in      = kNoNode;    // callers side: the enclosing symbol
    NodeId        to      = kNoNode;    // callees side: the referenced function
    std::string   calledBy;             // callers side: comma-joined names
    std::string   through;              // callees side
    std::uint32_t sites   = 1;
};

struct ValueRefRows
{
    std::vector<ValueRefRow> rows;      // every row, served order; the window is the caller's
};

inline bool vrBindLess( const IngestResult& ing, const Reference& a, const Reference& b )
{
    if( a.fileId != b.fileId )
    {
        return ing.files[a.fileId] < ing.files[b.fileId];
    }
    return a.startByte < b.startByte;
}

// --callers side: every value reference resolving to one of `defs`.
inline ValueRefRows valueRefCallerRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> defs )
{
    ValueRefRows out;
    for( const std::uint32_t r : idx.valueRefsTo( defs ) )
    {
        ValueRefRow row;
        row.ref = r;
        row.in  = ing.references[r].fromSymbol;
        for( const NodeId f : idx.calledBy( r ) )
        {
            if( !row.calledBy.empty() )
            {
                row.calledBy.push_back( ',' );
            }
            row.calledBy += ing.symbols[f].name;
        }
        out.rows.push_back( std::move( row ) );
    }
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& a, const ValueRefRow& b )
    {
        return vrBindLess( ing, ing.references[a.ref], ing.references[b.ref] );
    } );
    return out;
}

// --callees side: the functions `fns` store/pass as values (through= absent unless the same function also calls
// through that very slot), and the functions they may call through a parameter or a container (through= the written
// callee; one row per (to, through), bind= its first site, sites= the count).
inline ValueRefRows valueRefCalleeRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> fns )
{
    ValueRefRows out;
    for( const std::uint32_t v : idx.madeIn( fns, RefRole::Value ) )
    {
        for( const NodeId t : idx.targetsOf( v ) )
        {
            ValueRefRow row;
            row.ref = v;
            row.to  = t;
            out.rows.push_back( std::move( row ) );
        }
    }
    std::vector<ValueRefRow> via;
    for( const std::uint32_t t : idx.madeIn( fns, RefRole::Through ) )
    {
        const Reference& tr = ing.references[t];
        for( const std::uint32_t v : idx.valuesThrough( t ) )
        {
            for( const NodeId target : idx.targetsOf( v ) )
            {
                // the same function stores AND calls through the slot: the stored row carries through=
                auto same = std::find_if( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& r )
                {
                    return r.ref == v && r.to == target && r.through.empty();
                } );
                if( same != out.rows.end() )
                {
                    same->through = tr.fieldName;
                    continue;
                }
                auto grouped = std::find_if( via.begin(), via.end(), [ & ]( const ValueRefRow& r )
                {
                    return r.to == target && r.through == tr.fieldName;
                } );
                if( grouped != via.end() )
                {
                    if( vrBindLess( ing, ing.references[v], ing.references[grouped->ref] ) )
                    {
                        grouped->ref = v;
                    }
                    ++grouped->sites;
                    continue;
                }
                ValueRefRow row;
                row.ref     = v;
                row.to      = target;
                row.through = tr.fieldName;
                via.push_back( std::move( row ) );
            }
        }
    }
    for( ValueRefRow& r : via )
    {
        out.rows.push_back( std::move( r ) );
    }
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& a, const ValueRefRow& b )
    {
        const Reference& ra = ing.references[a.ref];
        const Reference& rb = ing.references[b.ref];
        if( ra.fileId != rb.fileId || ra.startByte != rb.startByte )
        {
            return vrBindLess( ing, ra, rb );
        }
        return a.to != b.to ? ing.symbols[a.to].name < ing.symbols[b.to].name : a.through < b.through;
    } );
    return out;
}

// ── rendering ────────────────────────────────────────────────────────────────────────────────────────────────
struct VrRender
{
    bool             singleRoot = true;
    std::string_view rootPrefix;
};

inline std::string vrPath( const IngestResult& ing, std::uint32_t fileId, const VrRender& rr )
{
    return std::string( rr.singleRoot ? sarif::rootRelativeUri( ing.files[fileId], rr.rootPrefix ) : std::string_view( ing.files[fileId] ) );
}

// The <vrs total= shown= capped= [next=]> window and its rows, or "" when there is no row (byte identity).
inline std::string valueRefsXml( const IngestResult& ing, const ValueRefRows& rows, bool callersSide, const VrRender& rr,
                                 std::string_view nextVerb, std::size_t cap = kValueRefRowCap )
{
    if( rows.rows.empty() )
    {
        return {};
    }
    EXPECTS( cap > 0, "a window of zero rows would cut every row while saying shown=0 — the cap is a runaway guard, never a hide" );
    const std::size_t total = rows.rows.size();
    const std::size_t shown = std::min( total, cap );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    std::string out = "<vrs total=\"" + std::to_string( total ) + "\" shown=\"" + std::to_string( shown ) + "\" capped=\"" + ( shown < total ? "1" : "0" ) + "\"";
    if( shown < total && !nextVerb.empty() )
    {
        out += " next=\"" + ex( nextVerb ) + "\"";
    }
    out += ">";
    for( std::size_t i = 0; i < shown; ++i )
    {
        const ValueRefRow& row = rows.rows[i];
        const Reference&   r   = ing.references[row.ref];
        out += "<vr";
        if( callersSide )
        {
            if( row.in != kNoNode )
            {
                out += " in_id=\"" + ex( ing.symbols[row.in].name ) + "\"";
            }
        }
        else
        {
            const Symbol& t = ing.symbols[row.to];
            out += " to=\"" + ex( t.name ) + "\" def=\"" + ex( vrPath( ing, t.fileId, rr ) ) + ":" + std::to_string( t.line ) + "\"";
        }
        out += " bind=\"" + ex( vrPath( ing, r.fileId, rr ) ) + ":" + std::to_string( r.line ) + "\"";
        out += " into=\"" + ex( r.fieldName ) + "\"";
        if( callersSide && !row.calledBy.empty() )
        {
            out += " called_by=\"" + ex( row.calledBy ) + "\"";
        }
        if( !callersSide && !row.through.empty() )
        {
            out += " through=\"" + ex( row.through ) + "\"";
        }
        if( !callersSide && row.sites > 1 )
        {
            out += " sites=\"" + std::to_string( row.sites ) + "\"";
        }
        out += "/>";
    }
    out += "</vrs>";
    return out;
}

// The JSON twin: `,"KEY":{"total":N,"shown":M,"capped":0|1[,"next":"…"],"rows":[{…}]}`, or "" when there is no row.
inline std::string valueRefsJson( const IngestResult& ing, const ValueRefRows& rows, bool callersSide, const VrRender& rr,
                                  std::string_view key, std::string_view nextVerb, std::size_t cap = kValueRefRowCap )
{
    if( rows.rows.empty() )
    {
        return {};
    }
    const std::size_t total = rows.rows.size();
    const std::size_t shown = std::min( total, cap );
    std::string out = ",\"" + std::string( key ) + "\":{\"total\":" + std::to_string( total ) + ",\"shown\":" + std::to_string( shown )
                    + ",\"capped\":" + ( shown < total ? "1" : "0" );
    if( shown < total && !nextVerb.empty() )
    {
        out += ",\"next\":\"" + jsonStr( nextVerb ) + "\"";
    }
    out += ",\"rows\":[";
    for( std::size_t i = 0; i < shown; ++i )
    {
        const ValueRefRow& row = rows.rows[i];
        const Reference&   r   = ing.references[row.ref];
        out += i == 0 ? "{" : ",{";
        bool first = true;
        const auto kv = [ & ]( std::string_view k, std::string_view v )
        {
            out += first ? "\"" : ",\"";
            first = false;
            out.append( k );
            out += "\":\"" + jsonStr( v ) + "\"";
        };
        if( callersSide )
        {
            if( row.in != kNoNode )
            {
                kv( "in_id", ing.symbols[row.in].name );
            }
        }
        else
        {
            const Symbol& t = ing.symbols[row.to];
            kv( "to", t.name );
            kv( "def", vrPath( ing, t.fileId, rr ) + ":" + std::to_string( t.line ) );
        }
        kv( "bind", vrPath( ing, r.fileId, rr ) + ":" + std::to_string( r.line ) );
        kv( "into", r.fieldName );
        if( callersSide && !row.calledBy.empty() )
        {
            kv( "called_by", row.calledBy );
        }
        if( !callersSide && !row.through.empty() )
        {
            kv( "through", row.through );
        }
        if( !callersSide && row.sites > 1 )
        {
            kv( "sites", std::to_string( row.sites ) );
        }
        out += "}";
    }
    out += "]}";
    return out;
}

// The --uses / MCP uses site filter, ONE copy for both surfaces. A role="value" site is served only when the resolver
// binds it to `valueDefs` (empty = any function of that name); a call THROUGH a value is never a use site; and a value
// site replaces the value scanner's role="read" row at the same identifier (one site, one row).
class UsesValueFilter
{
public:
    UsesValueFilter( const IngestResult& ing, std::string_view name, std::span<const NodeId> valueDefs )
    {
        const ValueRefIndex vri( ing );
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            const Reference& r = ing.references[i];
            if( r.role != RefRole::Value || r.calleeName != name )
            {
                continue;
            }
            const std::vector<NodeId> targets = vri.targetsOf( i );
            const bool chosen = !targets.empty()
                             && ( valueDefs.empty() || std::any_of( targets.begin(), targets.end(), [ & ]( NodeId t )
                                                                    { return std::find( valueDefs.begin(), valueDefs.end(), t ) != valueDefs.end(); } ) );
            if( chosen )
            {
                m_accepted.push_back( i );
                m_sites.push_back( ( std::uint64_t( r.fileId ) << 32 ) | r.startByte );
            }
        }
        std::sort( m_sites.begin(), m_sites.end() );
    }
    // True when reference `refIndex` is NOT a use-site row of this answer.
    bool skip( std::uint32_t refIndex, const Reference& r ) const
    {
        if( r.role == RefRole::Through )
        {
            return true;
        }
        if( r.role == RefRole::Value )
        {
            return !std::binary_search( m_accepted.begin(), m_accepted.end(), refIndex );
        }
        if( ( r.role == RefRole::Read || r.role == RefRole::Write ) && !m_sites.empty() )
        {
            return std::binary_search( m_sites.begin(), m_sites.end(), ( std::uint64_t( r.fileId ) << 32 ) | r.startByte );
        }
        return false;
    }
    bool any() const noexcept { return !m_accepted.empty(); }

private:
    std::vector<std::uint32_t> m_accepted;   // ascending (built in index order)
    std::vector<std::uint64_t> m_sites;
};

// --path / path_between: with NO directed call path (`unreachable`), how often `dstDefs` are used as values; 0 when a
// path exists, so the attribute is absent and the answer byte-identical.
inline std::size_t toValueRefsCount( const IngestResult& ing, bool unreachable, std::span<const NodeId> dstDefs )
{
    return unreachable ? valueRefCallerRows( ing, ValueRefIndex( ing ), dstDefs ).rows.size() : 0;
}

inline std::string valueRefsCountAttrXml( std::size_t n ) { return countFieldOrEmpty( "value_refs", n, /*json=*/false ); }
inline std::string valueRefsCountKeyJson( std::size_t n ) { return countFieldOrEmpty( "value_refs", n, /*json=*/true ); }

}   // namespace rw
