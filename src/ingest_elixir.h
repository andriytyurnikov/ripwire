#pragma once

#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_elixir.h is a section of ingest.cpp; include it only there"
#endif

namespace rw
{
namespace
{

// Included by ingest.cpp after the shared AST helpers.
// Elixir keywords are identifiers, so tags.scm alone cannot distinguish def f(x) from
// ordinary(f(x)). Keep the text gates local to this grammar instead of changing every tags pass.
/// Return an identifier call target as a view into src, or an empty view for null or remote targets.
std::string_view elixirTarget( TSNode node, std::string_view src ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const TSNode target = fieldChild( node, NodeField::Target );
    if( ts_node_is_null( target ) || std::strcmp( ts_node_type( target ), "identifier" ) != 0 )
    {
        return {};
    }
    return nodeTextOf( target, src );
}

/// Return whether target introduces a function, macro, guard, or delegate definition.
bool elixirFunctionKeyword( std::string_view target ) noexcept
{
    constexpr std::string_view keywords[] = { "def", "defp", "defmacro", "defmacrop", "defguard", "defguardp", "defdelegate" };
    return std::find( std::begin( keywords ), std::end( keywords ), target ) != std::end( keywords );
}

/// Return whether target introduces a statically named module or protocol, excluding defimpl.
bool elixirModuleKeyword( std::string_view target ) noexcept
{
    return target == "defmodule" || target == "defprotocol";
}

/// Find the direct arguments child of node; return a null node when node or its arguments are absent.
TSNode elixirArguments( TSNode node ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    // O(children): tree-sitter-elixir accepts comments between a call's head and its do-block and splices
    // them into the call node itself — 16 000 of them measured 82x under elixirBody's twin of this scan
    // (test/childwalkscalecheck.sh, arm B30, attributed by `sample`; the rule is on src/infra/tschildren.h)
    return firstChildOfKind( node, /*namedOnly=*/true, { "arguments" } );
}

/// Return the first direct call argument, or a null node for an absent or empty argument list.
TSNode elixirFirstArgument( TSNode node ) noexcept
{
    const TSNode args = elixirArguments( node );
    return ts_node_is_null( args ) ? TSNode{} : ts_node_named_child( args, 0 );
}

// Both `do ... end` and `do: expression` carry a body, but neither has a body: field.
/// Find the value of a `key:` entry in node's own keyword arguments (`def f(), do: 1`, `defimpl P, for: T`).
/// key carries its trailing colon. Return a null node when node has no such keyword.
TSNode elixirKeywordValue( TSNode node, std::string_view key, std::string_view src ) noexcept
{
    const TSNode args = elixirArguments( node );
    if( ts_node_is_null( args ) )
    {
        return {};
    }
    // O(children) at both levels: `def f(x), # … do: x` puts the comments in the arguments (81x at 16 000,
    // test/childwalkscalecheck.sh arm B29). Two cursors: the pair walk runs while the argument walk is open.
    TSNode      value   = {};
    bool        matched = false;
    ChildCursor argCursor( args );
    ChildCursor pairCursor( args );
    forEachNamedChild( args, argCursor.cur, [ & ]( TSNode arg )
    {
        if( std::strcmp( ts_node_type( arg ), "keywords" ) != 0 )
        {
            return true;
        }
        forEachNamedChild( arg, pairCursor.cur, [ & ]( TSNode pair )
        {
            auto found = nodeTextOf( fieldChild( pair, NodeField::Key ), src );
            while( !found.empty() && std::isspace( static_cast<unsigned char>( found.back() ) ) )
            {
                found.remove_suffix( 1 );
            }
            if( found != key )
            {
                return true;
            }
            value   = fieldChild( pair, NodeField::Value );
            matched = true;
            return false;
        } );
        return !matched;
    } );
    return value;
}

/// Find a definition's direct do-block or do-keyword value without adopting an ancestor's body.
/// node must be non-null; src must contain its source span. Return a null node when no body exists.
TSNode elixirBody( TSNode node, std::string_view src ) noexcept
{
    // O(children) — arm B30 in test/childwalkscalecheck.sh; the note is on elixirArguments
    const TSNode block = firstChildOfKind( node, /*namedOnly=*/true, { "do_block" } );
    return ts_node_is_null( block ) ? elixirKeywordValue( node, "do:", src ) : block;
}

/// Count syntactic parameters in an ordinary or guarded definition head, saturating at UINT16_MAX.
/// Missing argument lists count as zero; this does not infer callable arities from default values.
std::uint16_t elixirParams( TSNode node ) noexcept
{
    TSNode head = elixirFirstArgument( node );
    if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 )
    {
        head = fieldChild( head, NodeField::Left );
    }
    const TSNode args = elixirArguments( head );
    const auto count = ts_node_is_null( args ) ? 0u : ts_node_named_child_count( args );
    return std::uint16_t( std::min( count, std::uint32_t( 65535 ) ) );
}

/// Decide whether a candidate definition or call capture represents supported executable Elixir syntax.
/// role and name are non-null query captures into src. Reject quoted, attributed, dynamic, and defimpl
/// syntax; retain executable defaults while excluding declaration heads and argument patterns.
bool elixirKeepCapture( TSNode role, TSNode name, bool isDef, SymKind kind, std::string_view src ) noexcept
{
    // Quoted syntax and module attributes (notably @spec/@type) are not runtime call sites.
    for( TSNode parent = ts_node_parent( role ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        if( elixirTarget( parent, src ) == "quote"
            || ( std::strcmp( ts_node_type( parent ), "unary_operator" ) == 0 && nodeFieldText( parent, NodeField::Operator, src ) == "@" ) )
        {
            return false;
        }
    }
    const auto target = elixirTarget( role, src );
    if( isDef )
    {
        if( target == "test" && std::strcmp( ts_node_type( name ), "string" ) == 0 )
        {
            const auto title = nodeTextOf( name, src );
            if( title.size() < 2 || title.front() != '"' || title.back() != '"' || title.starts_with( "\"\"\"" ) )
            {
                return false; // only complete, ordinary string titles have a static display name here
            }
            // indexed on purpose: a string's children come from the external scanner, which owns every byte
            // between the quotes, so no comment token can be lexed into this list (src/infra/tschildren.h)
            for( std::uint32_t childId = 0; childId < ts_node_named_child_count( name ); ++childId )
            {
                if( std::strcmp( ts_node_type( ts_node_named_child( name, childId ) ), "interpolation" ) == 0 )
                {
                    return false;
                }
            }
            return true;
        }
        // `defimpl` defines a real module (`Protocol.For`); its row is named by elixirImplName at capture.
        return kind == SymKind::Other ? ( elixirModuleKeyword( target ) || target == "defimpl" ) : elixirFunctionKeyword( target );
    }
    const TSNode firstArg = elixirFirstArgument( role );
    if( target == "test" && !ts_node_is_null( firstArg ) && std::strcmp( ts_node_type( firstArg ), "string" ) == 0 && !ts_node_is_null( elixirBody( role, src ) ) )
    {
        return false; // the test declaration itself is not a call
    }
    const TSNode callTarget = fieldChild( role, NodeField::Target );
    if( !ts_node_is_null( callTarget ) && std::strcmp( ts_node_type( callTarget ), "dot" ) == 0 )
    {
        const TSNode receiver = fieldChild( callTarget, NodeField::Left );
        if( ts_node_is_null( receiver ) || std::strcmp( ts_node_type( receiver ), "alias" ) != 0 )
        {
            return false; // runtime receiver / anonymous function dispatch cannot name a module
        }
    }
    constexpr std::string_view special[] = { "defimpl", "defstruct", "defexception", "defoverridable", "alias", "import", "require", "use",
                                            "quote", "unquote", "unquote_splicing", "case", "cond", "for", "if", "unless", "with", "receive", "try" };
    if( elixirFunctionKeyword( target ) || elixirModuleKeyword( target )
        || std::find( std::begin( special ), std::end( special ), target ) != std::end( special ) )
    {
        return false;
    }
    bool inDefault = false;
    for( TSNode parent = ts_node_parent( role ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        if( std::strcmp( ts_node_type( parent ), "binary_operator" ) == 0 && nodeFieldText( parent, NodeField::Operator, src ) == "\\\\" )
        {
            const TSNode value = fieldChild( parent, NodeField::Right );
            inDefault = inDefault || ( !ts_node_is_null( value ) && ts_node_start_byte( role ) >= ts_node_start_byte( value )
                                      && ts_node_end_byte( role ) <= ts_node_end_byte( value ) );
        }
        if( !elixirFunctionKeyword( elixirTarget( parent, src ) ) )
        {
            continue;
        }
        TSNode head = elixirFirstArgument( parent );
        if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 )
        {
            head = fieldChild( head, NodeField::Left );
        }
        if( !ts_node_is_null( head ) && ts_node_start_byte( name ) >= ts_node_start_byte( head ) && ts_node_end_byte( name ) <= ts_node_end_byte( head ) )
        {
            return inDefault;
        }
    }
    return true;
}

/// Return the module name `defimpl` generates for node — `Protocol.For`, or `Protocol` when the `for:`
/// is implicit (Elixir then adopts the enclosing module, which alias resolution cannot name here).
/// Return an empty string when node is not a defimpl or its protocol is not statically named.
std::string elixirImplName( TSNode node, std::string_view src )
{
    if( elixirTarget( node, src ) != "defimpl" )
    {
        return {};
    }
    const auto protocol = nodeTextOf( elixirFirstArgument( node ), src );
    if( protocol.empty() )
    {
        return {};
    }
    const TSNode forNode = elixirKeywordValue( node, "for:", src );
    const auto   target  = ts_node_is_null( forNode ) ? std::string_view{} : nodeTextOf( forNode, src );
    return std::string( protocol ) + ( target.empty() ? "" : "." + std::string( target ) );
}

/// Build the enclosing static module/protocol scope, outermost first, from ancestors of node.
/// Return an owned dotted name, or an empty string at file scope; alias resolution is not inferred.
std::string elixirScope( TSNode node, std::string_view src )
{
    std::string scope;
    for( TSNode parent = ts_node_parent( node ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        const auto implName = elixirImplName( parent, src );
        if( !implName.empty() )
        {
            // A defimpl module name is absolute in Elixir, so this is the outermost scope there is.
            return implName + ( scope.empty() ? "" : "." + scope );
        }
        if( elixirModuleKeyword( elixirTarget( parent, src ) ) )
        {
            const auto name = nodeTextOf( elixirFirstArgument( parent ), src );
            if( !name.empty() )
            {
                scope = std::string( name ) + ( scope.empty() ? "" : "." + scope );
            }
        }
    }
    return scope;
}

} // namespace
} // namespace rw
