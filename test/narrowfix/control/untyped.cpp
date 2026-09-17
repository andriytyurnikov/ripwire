// narrowfix/control/untyped.cpp — the NEGATIVE control for P2-D Rule 2 receiver-variable narrowing.
//
// Same two-classes-share-a-method setup as cpp/recv.cpp, but the receiver is a local whose type the capture
// cannot read: `auto p = pool[ slot ];` writes no type and its initializer is a subscript, not a constructor
// call, so no var→type binding exists for `p`. Rule 2 CANNOT fire: `p->run()` falls through to the §2a
// ladder and stays HONESTLY AMBIGUOUS (an edge to BOTH Foo::run and Bar::run, `ambiguous=1`). This is what
// makes the narrowcheck gate meaningful — it proves the cpp/recv.cpp `ambiguous=0` is a REAL narrow on a
// real binding, not a vacuously-unambiguous fixture: remove the binding and the very same call shape goes
// ambiguous again.
//
// This control used to be a function PARAMETER (`void h( Foo* p )`). A parameter's written type is a real
// binding now (Rule 2 reads it lexically, see narrowcheck arms 7-18), so a parameter no longer demonstrates
// the absence of one.

struct Foo
{
    void run();
    int  value = 0;
};

struct Bar
{
    void run();
    int  value = 0;
};

void Foo::run()
{
    value = 1;
}

void Bar::run()
{
    value = 2;
}

Foo* pool[ 2 ];

void h( int slot )
{
    auto p = pool[ slot ];
    p->run();   // p has NO var→type binding (subscript initializer, `auto`) → Rule 2 cannot fire → AMBIGUOUS (§2a)
}
