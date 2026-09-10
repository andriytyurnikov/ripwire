#pragma once
// tschildren.h — O(children) child collection for UNBOUNDED-WIDTH tree-sitter walks.
//
// WHY THIS EXISTS. `ts_node_child( n, i )` restarts tree-sitter's child iterator from the FIRST child on
// every call (vendored `ts_node__child`, third_party/deps/tree_sitter/lib/src/node.c:139 — it builds a
// fresh `ts_node_iterate_children` each time and calls `ts_node__relevant_child_count` on each skipped
// invisible child), so an indexed loop over a node's C children costs O(C²). Width is
// attacker-controlled: ONE 980 KB file of 14 000 line comments hands the root 14 000 children and turned
// ingest into ~2 s of user CPU, quadratic in line count (gate: test/padscalecheck.sh). Every
// unbounded-width walk therefore collects the child list ONCE per node with a TSTreeCursor — the same
// child set (named + anonymous + extras) in the same left-to-right order, O(C) total. The cursor and the
// out vector are caller-owned and reused across nodes, so a warm walk allocates nothing per node.
// Bounded-shape scans (base clauses, argument lists, a declaration's declarators) keep the indexed form —
// their widths come from the grammar, not from the input file.
//
// WHY IT IS ITS OWN HEADER AND NOT A SECTION OF ingest.cpp. It was one, inside ingest_metrics.h's unnamed
// namespace, and that made it unreachable from the two headers that ALSO walk whole subtrees and are
// compiled outside that translation unit — src/preprocdead.h (shared with src/slice.h). The result was
// audit P1-0 (2026-09-10): `collectPreprocDeadRanges` kept the indexed form, and on a cold llvm-project
// run `ts_node_child_iterator_next` was 62.99% of busy leaves with that ONE walk's inclusive subtree at
// 56.67% of busy CPU. Converting it took that cold run from 202.14 s CPU to 170.46 s (wall 26.60 ->
// 18.99 s) with a byte-identical map. A rule that only some translation units can obey is a rule that
// gets broken, so the rule and the helper now live where every walk can reach them. Gates:
// test/padscalecheck.sh (the comment flood) and test/preprocdeadscalecheck.sh (the include-guard flood,
// which the `#if`-text gate in preprocdead.h hides from the first).
//
// WHICH WIDE NODES ACTUALLY COST O(C²) — MEASURED, 2026-09-10 (lane W2, test/childwalkscalecheck.sh). A
// FLAT child list does; a grammar REPEAT does not. tree-sitter stores a repetition as a balanced tree of
// invisible `_repeat` nodes, and `ts_node__child` skips a whole invisible subtree in O(1) by reading its
// stored `visible_child_count` (`ts_node__relevant_child_count`, node.c) — so indexing the 128 000th
// declaration of a file scope is ~O(log C), and a declaration flood measured dead linear on the
// pre-change binary (8k/64k/128k children = 0.04 / 0.33 / 0.63 s). What is NOT balanced is anything the
// parser splices into the child array itself: EXTRAS (comments, above all) and preprocessor-conditional
// bodies. A root of 16 000 COMMENTS measured 117× its own control on the same binary. The practical rule
// is therefore not "wide node" but "wide node whose width can come from EXTRAS", which — since a comment
// can appear between any two children of anything — is every walk whose node comes from the FILE. It is
// also why a scaling gate must flood with comments: a declaration flood of identical width goes green
// over a live defect.

#include <vector>

#include <tree_sitter/api.h>

namespace rw
{

struct ChildCursor   // RAII — several walkers return mid-loop, so deletion must not depend on fallthrough
{
    TSTreeCursor cur;
    explicit ChildCursor( TSNode n ) noexcept : cur( ts_tree_cursor_new( n ) ) {}
    ChildCursor( const ChildCursor& ) = delete;
    ChildCursor& operator=( const ChildCursor& ) = delete;
    ~ChildCursor() { ts_tree_cursor_delete( &cur ); }
};

// VISIT n's children, left to right, without materialising them — the one spelling of the cursor idiom
// every other function here is written on. `fn( TSNode ) -> bool` returns false to STOP, which is the
// `break` a filtering or searching walk needs and the `continue` case falls out of returning true.
//
// It takes the node AND the cursor because the two lifetimes differ: a walk that only filters can hand
// the same cursor to every node it visits, while a walk that RECURSES from inside `fn` cannot — the
// recursive call resets the cursor out from under the loop — and must own one per frame (`ChildCursor
// cursor( n ); forEachChild( n, cursor.cur, … )`). Making the cursor implicit would have hidden exactly
// that distinction, which is the bug this whole header exists to prevent.
template< class Fn >
inline void forEachChild( TSNode n, TSTreeCursor& cur, const Fn& fn )   // A4-F25: NOT noexcept — `fn` may allocate
{
    ts_tree_cursor_reset( &cur, n );
    if( ts_tree_cursor_goto_first_child( &cur ) )
    {
        do
        {
            if( !fn( ts_tree_cursor_current_node( &cur ) ) )
            {
                return;
            }
        }
        while( ts_tree_cursor_goto_next_sibling( &cur ) );
    }
}

// APPEND n's children, left to right, to whatever `out` already holds. This is the form a DFS-STACK walk
// needs: there the collected list IS the work list, so clearing it would throw the frontier away. Routing
// such a walk through collectChildren instead costs it a scratch vector plus a copy of every node; the two
// forms measured indistinguishably on this box (both inside a ±3% noise band that a same-binary control
// reproduced with the opposite sign), so this exists for the shape, not for a measured win.
inline void appendChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    forEachChild( n, cur, [ &out ]( TSNode child ) { out.push_back( child ); return true; } );
}

// REPLACE `out` with n's children — the form a walker uses when it wants one node's child list as a
// standalone array to scan or index. Delegates, so there is exactly one spelling of the cursor idiom.
inline void collectChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    out.clear();
    appendChildren( n, cur, out );
}

}   // namespace rw
