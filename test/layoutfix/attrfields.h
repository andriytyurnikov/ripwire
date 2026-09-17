#pragma once

// attrfields.h — layout fixture: a field whose declaration carries a `(` that is NOT a parameter list —
// `alignas(N)`, `__attribute__((...))`, `decltype(...)` or a `std::function<...>`'s template-nested paren.
// Never compiled; ripwire indexes it as C++ and test/layoutcheck.sh asserts the computed table.
//
// parameterListParen (src/layout.h) used to take the FIRST `(` in the statement as a member-function's
// parameter list, whichever `(` that was. All four shapes below put an unrelated `(` before the real
// field, so the field was read as a member function and dropped — while the struct still reported
// modeled="1" with a size short by exactly that field's bytes. Each must now come back REFUSED
// (modeled="0", a named caveat, the field still counted) rather than silently missing.

struct AlignasFieldCase
{
    int          n;
    alignas( 8 ) int x;
    char         c;
};

struct AttributeFieldCase
{
    int n;
    int x __attribute__( ( aligned( 8 ) ) );
    char c;
};

struct DecltypeFieldCase
{
    int            n;
    decltype( 1 ) x;
};

#include <functional>
struct StdFunctionFieldCase
{
    int                       n;
    std::function<void(int)> cb;
};
