package com.example

import com.example.util.square

class Greeter(private val name: String) {
    companion object {
        fun of(name: String): Greeter = Greeter(name)
    }

    fun greet(): String {
        val doubled = square(2)
        return "Hello, $name ($doubled)"
    }
}

fun Int.doubled(): Int = this * 2

fun useJavaHelper(): Int = JavaBridge.helper(5)

// The genuine negative-collision case: a BARE, unqualified call with no receiver at all — the shape
// that gives the resolver no structural evidence to prefer one same-name candidate over the other.
// Util.kt's Extra.helper (Kotlin) and JavaBridge.java's helper (Java) are both real, unrelated
// definitions this name could mean.
fun ambiguousCall(): Int = helper(5)

fun runAll(): Int {
    val g = Greeter.of("world")
    return g.greet().length + 1.doubled() + useJavaHelper() + ambiguousCall()
}
