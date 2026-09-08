package com.example;

public class JavaBridge {
    public static int helper(int n) {
        return n + 1;
    }

    public int callGreeter() {
        Greeter g = Greeter.of("java");
        return g.greet().length();
    }
}

// Same-name-as-Kotlin-enum-class collision, deliberately UNRELATED to Util.kt's `enum class Mode` —
// see that file's comment. Package-private so it can live alongside the public JavaBridge class in
// this one file.
class Mode {
    void run() { }
}

// Same-name-as-Kotlin-interface collision, deliberately UNRELATED to Util.kt's bodyless
// `interface Taggable` — see that file's comment (§11).
class Taggable {
    void tag() { }
}
