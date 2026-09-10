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

// APPEND n's children, left to right, to whatever `out` already holds. This is the form a DFS-STACK walk
// needs: there the collected list IS the work list, so clearing it would throw the frontier away. Routing
// such a walk through collectChildren instead costs it a scratch vector plus a copy of every node; the two
// forms measured indistinguishably on this box (both inside a ±3% noise band that a same-binary control
// reproduced with the opposite sign), so this exists for the shape, not for a measured win.
inline void appendChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    ts_tree_cursor_reset( &cur, n );
    if( ts_tree_cursor_goto_first_child( &cur ) )
    {
        do
        {
            out.push_back( ts_tree_cursor_current_node( &cur ) );
        }
        while( ts_tree_cursor_goto_next_sibling( &cur ) );
    }
}

// REPLACE `out` with n's children — the form a walker uses when it wants one node's child list as a
// standalone array to scan or index. Delegates, so there is exactly one spelling of the cursor idiom.
inline void collectChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    out.clear();
    appendChildren( n, cur, out );
}

}   // namespace rw
