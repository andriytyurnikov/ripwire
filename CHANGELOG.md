# Changelog

All notable changes to ripwire are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Everything here is pre-1.0: the flag surface may still change. When a flag is superseded it is
deprecated with a stderr pointer at its replacement and kept working; removals wait for a major
version. A `v0.1.0` tag exists (2026-08-02) but its GitHub Release carries no binaries; **v0.2.0 is
the first release with published, SHA-256-checked archives**, and it contains everything below.

Every measured number in this file names its corpus and method. Numbers without a stated method are
not published here — see `docs/EVALS.md` for the instruments behind the headline figures.

---

## [Unreleased]

### Added — Ruby has inheritance edges: `class Child < Parent` reaches the lego view and the resolver's base walk

No Ruby corpus has ever carried an inheritance edge. `captureBases` turns a class's base clause into
inherit refs, which `buildGraph` reads into the CHA-lite name graph the resolver walks after a type's
OWN method set misses — and Ruby reached none of it. The clause kind was never the problem
(`superclass` is already in the table; Java's `extends` clause carries the same node name): the
base-TYPE table held no node kind Ruby uses. Ruby names a base with `(constant)` — `class Child <
Parent` — or `(scope_resolution)` — `class Derived < Space::Base`. Both are now read, under a
language test rather than appended to the shared table, because both kind names are generic enough
to mean something else in another grammar.

This is floor (a) of the constant-receiver round above, lifted — and it is what held that round's
gem numbers down, since a gem reaches its class methods up an `ActiveRecord::Base` hierarchy. Two
things follow at once: `--lego` answers for Ruby, and `Child.build` resolves to `Parent::build`.

| corpus | `--lego` implementors | edges | ambiguous |
| --- | --- | --- | --- |
| activerecord 8.1.3 `lib`, `--lego=Base` | 0 → 11 | 9,152 → 9,001 | 1,479 → 1,288 |
| activesupport 8.1.3 `lib` | — | 3,912 → 3,915 | 434 → 422 |
| actionpack 8.1.3 `lib` | — | 3,140 → 3,127 | 364 → 355 |
| Rails app A, `--lego=ApplicationRecord` | 0 → 130 | 24,376 → 24,390 | 1,263 → 1,260 |
| Rails app A, `--lego=ApplicationController` | 0 → 132 | — | — |
| Rails app B | — | 15,257 → 15,301 | 451 → 451 |

`ambiguous` falls because a two-way split collapses into one pinned edge, which is also why `edges`
falls where it does — 151 fewer on activerecord is 151 calls that stopped naming two candidates.

Stated floors, each pinned by an arm of `test/rubyinheritcheck.sh`: a COMPUTED superclass (`class
Dynamic < Struct.new( :a )`) is a call, not a name, and mints nothing; a MIXIN (`include Helper`) is
NOT an inheritance edge in this round — it is a receiver-less call in the class BODY, the same shape
and the same decision as PHP's in-body `use SomeTrait;`, and Ruby's ancestor chain really does hold
included modules, so it is a stated residue rather than a claim that it is not inheritance; a
QUALIFIED base is keyed by its final segment alone — the byName convention every other language's bases
use — so an out-of-tree `class Rec < ActiveRecord::Base` lists as an implementor of any in-tree class
named `Base` (the gate's `Space::Base`), and telling the two apart needs the Ruby constant index from
#57. A fourth floor, of
`queries/ruby/tags.scm` rather than of this round, is pinned beside them: a receiver-less call
written with no parentheses and no arguments parses as `(identifier)`, not `(call)`, and is not a
call site at all.

`--deps` is byte-identical on activerecord, and the default map is byte-identical on four Ruby-free
corpora, with this repository's `--report` totals unchanged. `kParserVer` 97 → 98 (new records, same
layout; `kCacheVersion` stays 22 — a Ruby cache written at 97 holds no inheritance refs and must be
re-parsed), with the `quality.h` mirror and `test/qschemetrip.hash` moved in the same commit.

### Added — a Ruby constant receiver now pins the call, instead of splitting it across every same-named method

`Calc.add( 1, 2 )`, `Outer::Engine.run( 3 )`, `::Top.ping` and `Util.format( 5 )` resolved to EVERY
method of that name in the corpus, each edge marked `prov="split"`. The resolver's Rule 2c already
says "the receiver token IS the type" (`docs/EVALS.md` "Phase 4b"), but it could not fire for Ruby:
`classifyReceiver` accepted a receiver node of kind `(identifier)` only, and Ruby's class/module
receiver is its own node kind — `(constant)` for `Calc`, `(scope_resolution)` for `Outer::Engine`
and `::Top`. Every such call classified `RecvKind::None`, and the resolver fell through to the
name spray. Ruby's one call form that carries a type was the one the type rule never saw.

The receiver's FINAL constant segment is the type name (`Outer::Engine` → `Engine`), the same
final-segment convention the existing type bindings use (`ns::Foo` → `Foo`), because `Symbol::scope`
is the IMMEDIATE enclosing name by design. A Ruby MODULE is a receiver of class methods as much as
a class is (`Util.format`), so Ruby's `SymKind::Other` symbols — which `queries/ruby/tags.scm` can
only reach through `module` — join Rule 2c's class-name set.

Measured with `--no-cache` on five Ruby corpora, before → after (map header gauges):

| corpus | files | edges | ambiguous | declined |
| --- | --- | --- | --- | --- |
| activesupport 8.1.3 `lib` | 290 | 3,868 → 3,912 | 468 → 434 | 1,022 → 985 |
| activerecord 8.1.3 `lib` | 398 | 9,116 → 9,152 | 1,496 → 1,479 | 4,576 → 4,497 |
| actionpack 8.1.3 `lib` | 157 | 3,151 → 3,140 | 390 → 364 | 943 → 923 |
| Rails app A | 4,683 | 23,784 → 24,376 | 1,328 → 1,263 | 12,485 → 11,624 |
| Rails app B | 2,174 | 14,859 → 15,257 | 275 → 431 | 3,264 → 3,050 |

`declined` falls on all five: those are call sites the resolver refused to guess at and now has
evidence for. Edges fall on actionpack because a pinned call is ONE edge where a two-way split was
two. App B's `ambiguous` rises while its `declined` falls by 214: a receiver that names two
same-final-segment classes both defining the callee produces an honest split where there was
previously no edge at all — the disclosed floor below, not a regression.

Stated floors, each pinned by an arm of `test/rubyrecvnarrowcheck.sh`: Ruby feeds no
class-hierarchy edges (`captureBases` has no Ruby arm), so a method inherited from a superclass does
not narrow — this is what holds the gem numbers down, where deep `ActiveRecord::Base` hierarchies are
the idiom; matching is by final segment, so two same-named classes in different namespaces both
defining the callee keep both candidates; and a variable receiver (`c.scale`) or a chained one
(`Calc.new.scale`) is untouched. A narrow that misses degrades to the unchanged ladder — it never
deletes an edge and never invents one (`Time.now` still mints nothing).

The default map is byte-identical to the previous build on five Ruby-free corpora (this repo's
`src/`, npm, a Clojure project, CPython 3.14's stdlib, and this whole repository), and this
repository's `--report` totals are unchanged at 2,052 files · 18,979 symbols · 22,529 edges.
`kParserVer` 96 → 97 (record layout unchanged, `kCacheVersion` stays 22; the VALUES of `recv`/
`recvVar` move, so Ruby extraction facts are re-parsed), with `quality.h`'s mirror and
`test/qschemetrip.hash` re-pinned in the same commit.

### Fixed — a cache blob, a file in the tree, or an MCP preview could crash, hang or starve the process

Each of these was reproduced before it was fixed, and each now has a gate that fails on the old code.

- **A checksum-valid qsnap or qchurn cache blob with a huge record count aborted.** `deserializeSnapshot` and
  `deserializeRawCommitStream` passed a count read from the blob straight to `reserve`: 2^32−1 records is 32 GiB for
  the qsnap vectors and 96–128 GiB for the qchurn commit and path lists. On Linux that is `std::bad_alloc`, which
  nothing on the CLI path catches, so `--quality-delta`, `--edit-check`, `--for`, `--metrics` and `--exemplar` died
  with SIGABRT on every run until the blob was evicted (reproduced on Ubuntu, exit 134). Every count is now measured
  against the bytes left in the blob first, and a count that cannot fit makes the blob corrupt: recompute, as for any
  other damage. Gate: `test/cachefuzzcheck.sh`, Part 2's three vector-count rows and the new Part 5. The rows run
  under an allocation bound (`ulimit -v` on Linux, ASan's `max_allocation_size_mb` anywhere), because macOS
  overcommits the reservation and exits 0 against the defect. The old map-count and wrong-sha rows wrote at stale
  offsets, so an earlier guard rejected the blob before the count was ever read; they now write where
  `deserializeSnapshot` reads, and both tables check the good blob's layout first and fail loudly if a header change
  would re-aim a row.
- **A short read leaked a file descriptor.** The parse pool's `readFile` closed its stream inside
  `( got == want ) && ( std::fclose( fp ) == 0 )`, so a file that came up short (truncated between the size probe
  and the read) was never closed. A long-lived `--mcp` server re-ingesting such a tree ran out of descriptors, and
  every file it could then not open dropped out of the answer at exit 0. With an interposed short-read shim, 300 of
  600 short-read streams stayed open, and under `ulimit -n 200` all 20 ordinary files vanished from a `--grep`
  answer. The stream now has an owner, `rw::OwnedFile` (`src/infra/ownedfile.h`), whose destructor closes it on
  every path, and the whole-file readers in `ingest_crawl.h`, `docparse.h` and `editpreview.h` use it. Gate:
  `test/crashsweepcheck.sh` B1.
- **A FIFO, a directory or a device link at `.ripwire_config` or `.ripwire_quality_acks` hung or aborted.** Both
  were read through a blocking open on the name. A FIFO hung `--quality-delta` before any output, and a committed
  symlink from the acks ledger to `/dev/zero` or `/dev/urandom` never reached end of file. A directory at
  `.ripwire_config` opens on Linux; where a directory's seek reports `LLONG_MAX` (overlayfs), the string that length
  asks for aborts, the failure `ingest_crawl.h`'s `PathShape` note measured for `--cache=<dir>`. Both files now go
  through `docparse::detail::openRegularFileStream`: it opens with `O_NONBLOCK`, asks the descriptor what it opened,
  and reads anything but a regular file as absent, with a stderr line saying so. The ledger is still read one line at a
  time. Gate: `test/crashsweepcheck.sh` B2
  (eight shapes).
- **`edit_check` with `new_body` raced the HEAD-snapshot prefetch worker.** The preview's two ingests ran after the
  verb's own ingest had released the process-wide ingest lock, so they could run alongside the detached prefetch
  worker's ingest. `ingest()` installs compiled tags queries into a process-global cache and deletes the entry each
  install displaces, and that is single-writer by design. On the ThreadSanitizer build the server reported a data
  race at the parse-pool call and aborted (exit 134) mid-session. The preview's ingest now takes
  the same lock as every other ingest a server runs. Gate: `test/qsnapprefetchcheck.sh` (f), whose red needs the
  TSan build (`RIPWIRE_BIN=tsan/ripwire`).
- **A file dated after 2262 overflowed a signed multiply.** `tv_sec * 1000000000 + tv_nsec` does not fit in
  `long long` past 2262-04-11, a date ext4, XFS, tmpfs or a tar restore can store. That is undefined behaviour in
  release and an abort in the sanitizer build (reproduced on Linux tmpfs: `signed integer overflow: 10000000000 *
  1000000000`). Both stat readers now saturate through `rw::saturatingNanoseconds` (`src/infra/statclock.h`); size
  and ctime still tell apart two saturated timestamps. Gate: `test/crashsweepcheck.sh` B3. APFS clamps timestamps
  at 2262, so on macOS the arm says it cannot build its input.

Three of these shapes can be seen in the source, so `test/crashsweepcheck.sh` now also runs ripwire's own `--match`
over `src/` and fails on them. Each rule is proven live against a probe tree that holds one violation and one
compliant twin.

- **S1:** an allocation sized by a count a byte reader decoded must be bounded earlier in the same function.
- **S2:** every raw `fopen`/`open`/`fdopen`/`opendir`/`open_memstream`/`popen` site must be registered with the fact
  that makes it safe, and a new one points at `rw::OwnedFile`. A close as the right operand of `&&`/`||` or an arm
  of `?:` is refused outright.
- **S3:** every body handed to a `std::thread` must be `noexcept` or a single try block. The eight bodies that were
  neither are now declared `noexcept`, as are three that were already one try block. None of them had a throw that
  could escape except allocation failure, which already ended in `std::terminate`.

Red on the base, in order: S1 finds the three unbounded counts, S2 the short-circuited `fclose`, S3 eight bare
bodies. The gate's header states what each rule catches and what it misses.

### Fixed — a diagnostic notice could be split across lines by another thread's output, which is what kotlincheck §12 kept tripping on

The `DEGRADED_PATH_ALERT` notice, and the assert, panic and thread-violation banners, were built from a chain of
`std::cerr` insertions. With stdio sync on, each insertion is its own write to stderr, so a line another thread
wrote at the same moment could land inside a notice. kotlincheck §12 refuses two Kotlin files at once; when the
second parse worker's refusal line landed straight after `[math degraded] `, the arm's one-line grep failed with
"raised no DEGRADED_PATH_ALERT" although the alert was on stderr, whole, one line further down. That is the
failure eight CI jobs hit since Kotlin landed, three of them on `main`. Measured on f8e6087c by running §12's map
over its own fixture: 18 gate failures in 5,700 runs, and the notice torn in 32–73% of runs depending on load.
Every reporter now formats its whole notice into a fixed 4,096-byte stack buffer and hands it to stderr in ONE
stdio call, which no other stdio writer in the process can interleave, and which needs no heap in a reporter that
may be running because memory ran out. The text is byte-identical for every notice under the cap; a longer one is
cut and says so at its end (`... [notice truncated: kept K of N bytes]`). The reporters still flush stdout
before the notice, as `std::cerr`'s tie to `std::cout` always did, so a trap or an abort right after it loses no
buffered output and `>file 2>&1` keeps its order. Measured after the fix on §12's fixture, alternating
run by run with the f8e6087c binary under four busy loops: 0 gate failures and 0 torn notices in 2,100 runs,
against 6 failures and 726 torn notices from the old binary in the same 2,100 interleaved runs. The new gate
`test/diagnoticecheck.sh` counts the write(2) calls each reporter makes by giving it a datagram socket as fd 2,
which keeps write boundaries: red on the old reporters (9 writes for the degraded notice, 15 to 21 for the banners,
every one still byte-exact), green at one write each. Three `2>&1` cases leave text in stdout's buffer before a
degraded notice, an assert and a panic, and require it first and whole: byte-identical to the old reporters. It also carries a static arm with a mutation control, a
12,000-notice race against raw and stdio writers (red in 200 of 200 runs on the old reporters), a zero-allocation
arm (global `operator new`) measured with `src/alloccount.cpp` as a delta between otherwise identical runs, and an
ASan/UBSan pass. kotlincheck §12 now prints the first five lines of stderr when that arm fails, because
none of the eight CI logs could show what the notice had looked like. Not fixed here: the default map over the same
fixture says `files=4` with no sign of the two refused files, a disclosure gap tracked by #157.

### Changed — Intel macOS binaries end with 0.6.1

0.6.1 is the last release with a prebuilt Intel macOS binary. The `macos-x64` release leg has had no Intel machine since
GitHub retired its `macos-13` runner pool, which left v0.1.0's leg and the first v0.2.0 run queued for 24 hours until
the auto-cancel. From then on it cross-compiled on an arm64 runner with `-DCMAKE_OSX_ARCHITECTURES=x86_64` and ran its
PGO training, its determinism diff and its smoke test under Rosetta 2, pinned to the one runner image whose Rosetta was
verified to execute the binary's x86-64-v3 instructions. Every step that proved the binary ran did so under a
translator. The leg is gone from `release.yml`, along with the deployment-target step and the `minos` check that only it
used. The Linux x86-64 binary and its x86-64-v3 floor are unchanged, and an Intel Mac can still build from source.

The installer was not told. Its arch map sends `x86_64` to `x64` on every OS, so an Intel Mac asking for a later release
would have heard `release vX has no asset named ripwire-X-macos-x64.tar.gz`: true, and silent on both the decision and
the two routes that still work. `scripts/install.sh` now stops an Intel Mac before any download for every release after
0.6.1, says Intel macOS binaries end with 0.6.1, and prints the exact command that pins `RIPWIRE_VERSION=v0.6.1` and the
exact source build. Pinning 0.6.1 still installs its Intel binary. A Rosetta shell on Apple silicon, which also reports
`x86_64`, is sent to a native arm64 shell rather than told it owns an Intel Mac.

Gate: `test/releaseinstallcheck.sh` section H, nine rows. Five were red on main: the unpinned one-liner on an Intel Mac
(two rows), a v0.10.0 pin whose release still listed a `macos-x64` asset and installed it, the Rosetta shell, and
`release.yml` still building the asset. The three installer controls (a v0.6.1 pin on an Intel Mac, Linux x86-64,
macOS arm64 on a later release) each went red against a mutant installer that refused one release too many, or keyed on
the arch or the OS alone. `test/portablebuildcheck.sh` #2h, which held the leg to its verified runner, Xcode and
deployment target, retires with it.

### Fixed — a deep or odd-shaped argument, source file or skills tree could crash or stall a verb

Each of these was reproduced before it was fixed, and the gate that already owns each verb now fails on the old code.

- **`--graph-query` nested deep enough overflowed the stack.** The evaluator recurses once per `(`, and a 50,000-level
  `kind(kind(…all…))` chain died with SIGSEGV (exit 139). Nesting past 256 levels is now refused before evaluation,
  exit 1 with the reason. Gate: `test/graphqueryrefusecheck.sh` arm 6.
- **A `--layout` array extent could crash its evaluator.** A `#define` extent nested 200,000 parentheses deep overflowed
  the stack (exit 139). `((0-1099511627776)*8388608/(0-1))` divides INT64_MIN by −1, which is SIGFPE (exit 136) on
  Linux x86-64, and `1099511627776*1099511627776` is signed overflow, which aborts the sanitizer build. Arithmetic is
  now checked, that quotient is refused, and parenthesis nesting depth is bounded at 64 (a macro of many sibling
  parenthesised terms nests one level and still sizes). Any of these reads as an unknown extent, with its caveat.
  Gate: `test/layoutcheck.sh` §12.
- **`--layout` dropped a data member whose extent or initializer holds a parenthesis, and still said the size was
  right.** `char a[(4)];`, `int x = (3);` and `int x{ (3) };` were taken for member functions, because the test looked
  for the first `(` anywhere in the statement. The field vanished while the struct reported `modeled="1"` and a size
  short by its bytes. Only a `(` before the first `[`, `=`, `{` or bitfield `:` now opens a parameter list, and an
  `operator` member is still a function. Gate: `test/layoutcheck.sh` §13.
- **`--eval-skills` aborted on a skills directory it could not fully read.** A `SKILL.md` symlinked to itself, a
  directory link loop or a mode-000 skill raised an uncaught `filesystem_error` from the throwing
  `std::filesystem` overloads (exit 134). The walk now uses the `error_code` forms, skips an unreadable entry, the
  directory link loop included, and names it on stderr; a skills root that cannot be listed at all says "cannot list".
  Gate: `test/skillevalcheck.sh`.
- **`ripwire wrap` aborted on a `./skills` tree it could not descend.** The pre-recipe scan advanced a
  `recursive_directory_iterator` with its throwing `operator++` inside a `noexcept` function, so a tree it could not
  open mid-walk (measured with more nested folders than free descriptors) was `std::terminate` (exit 134). The walk
  now stops early instead, says so, scores the scan WARN and still prints the recipe. The same scan used to skip a
  mode-000 skills folder in silence — a skill carrying injection text scored CRITICAL while readable and nothing once
  sealed — and now names the folder it cannot enter and scores WARN. Gate: `test/codexwrapcheck.sh`.
- **A deeply nested `--match` query overflowed the query compiler.** `ts_query_new` recurses per level on a worker
  thread with a 512 KB stack: 4,000 levels died with SIGBUS (exit 138), and 2,000 ran past a minute. A query or
  `--lint-rules` spec nested past 256 levels is refused before any compile. Gate: `test/matchgrammarcheck.sh` arm 6.
- **`--slice` and the MCP `slice` verb stalled on a deeply nested function.** Every occurrence climbed to its
  statement anchor through `ts_node_parent`, which descends from the tree root each time, so the walk's cost grew with
  the cube of the nesting: 1,000 chained `if (x)` took 5.7 s, 2,000 took 48 s, and 4,000 did not finish. Over MCP that
  one call wedged the server, and a real CPython test method (a chained assignment 808 levels deep) took 21.8 s. The
  scan now builds a parent table in one cursor pass and memoizes the anchor, so the walk is linear: 2,000 / 4,000 /
  8,000 nested ifs in 0.05 / 0.06 / 0.08 s, the 808-level chain in 0.06 s, and the output is byte-identical. Past
  2,048 syntax levels the slice is refused by name: the walks still recurse once per level on the main thread, and
  nested loops, the widest frame per level, need ~1.8 MB at that depth on a plain build and 2-3× under a sanitizer, so
  this is a stack guard, not a time guard. That is still 2.5× the deepest function in 47,795 parsed files (808).
  Gate: `test/slicecheck.sh` (15), including 2,040 nested `for` loops that must be answered just under the guard.

The four new bounds are listed in `docs/LIMITS.md` as BOUNDARY.

### Changed — the macOS arm64 release and the macOS CI legs build with Xcode 26.6, whose loop vectorizer reads the no-alias promises

Through 0.6.1 the `macos-arm64` release asset and every macOS CI leg were built with Xcode 16.2 on `macos-14`. Its
AppleClang 16 is LLVM 17, and LLVM 17's loop vectorizer never reads `__builtin_assume_separate_storage`
(llvm/llvm-project#64666, fixed in LLVM 18). There, a `VERIFY_NO_ALIAS_BUF` promise removed scalar reloads but left each
vectorized loop's runtime overlap check and its scalar fallback in place. The release leg, the eight macOS gate shards
and the macOS sanitizer leg now build with Xcode 26.6 (17F113, Apple clang 21.0.0), the default Xcode on `macos-26`.
GitHub retires the `macos-14` images on 2026-11-02. On Xcode 26.6, with no flag beyond the release's own
`-O2 -mcpu=apple-m1`, a two-buffer loop carrying the promise vectorizes with no overlap check. objdump counts 57
instructions against 64 for the same loop without the promise, and 64 again with `-mllvm -basic-aa-separate-storage=false`.
`test/noaliascheck.sh` classifies this compiler `CONSUMED_DEFAULT` and `LOOP_CONSUMED`. No speed is claimed: the promises
that would use this land later, with the macro rename.

The minimum macOS is now pinned instead of inherited from the runner. With no deployment target, clang takes the lower of
the runner's macOS and the SDK default. The published `ripwire-0.6.1-macos-arm64` binary reads `minos 14.0` (otool), and
the same build on `macos-26` would have read 26.x and dropped every macOS 14 and 15 user. The release leg exports
`MACOSX_DEPLOYMENT_TARGET=14.0` before its PGO build and reads `minos` back off the binary it packages. The CI legs build
at the same 14.0, where Xcode 26.6's libc++ still defines `__cpp_lib_print`. The leg also records its Xcode, compiler and
`llvm-profdata`, and fails if `DEVELOPER_DIR` is empty or either tool is not the pinned Xcode's, so PGO trains, merges and
optimizes with one toolchain. None of these checks skips a leg that lost its pin. A macOS release leg without a
deployment target fails, and so does a CI leg whose CMake cache did not receive the pinned target.

Gate: `test/portablebuildcheck.sh` #2i, sixteen rows. It holds the release leg's runner, Xcode and quoted minimum macOS;
the export before the first configure; a single deployment-target source across the leg and the build job's env and
steps (no `-DCMAKE_OSX_DEPLOYMENT_TARGET`, `-mmacosx-version-min` or second `MACOSX_DEPLOYMENT_TARGET`); the exact
`otool` compare between PGO staging and packaging; and each fail-loudly guard: the empty-target refusal, the toolchain
record step ahead of the first build, and ci.yml's two CMake-cache checks. It also holds ci.yml's nine macOS runner
labels, five `matrix.os` conditions, two Xcode paths and two deployment targets to the release's values, so a half-done
runner move (an `ASAN_OPTIONS` condition still naming `macos-14`) is refused. Three mutated copies must each be refused
by exactly their own row: no minos step, `ASAN_OPTIONS` back on `macos-14`, and `-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0`
added to the pgobuild step. Red before this change: 14 FAIL, 2 PASS. All sixteen pass after.

A local emulation of the release leg on the same Xcode build (`scripts/pgobuild.sh`, Release,
`MACOSX_DEPLOYMENT_TARGET=14.0`) passed every post-step: the PGO determinism diff, `emit=std::print`, `minos 14.0`, and
xmllint. Its output was byte-identical to the plain build on `test/fixture`, the repo map and a `--for` query.

The move also exposed a test-harness defect. Under a UTF-8 locale, macOS 26's `/usr/bin/sort` sorts case-insensitively,
where macOS 14 and Linux sorted these lists in byte order. `test/scroundtripcheck.sh` compared a `sort`ed expected list
with Python's `sorted()` and went red on both macos-26 CI shards. A sweep of every `sort`, `comm`, `join`, `uniq` and
`ls` call in the gate and bench scripts found 27 sites in 20 files that compare an order with something else: Python's
`sorted()`, a literal, a pinned hash, ripwire's own byte-sorted output, or `git status`. Only that one fails today; the
other 26 pass by luck of their current names. All 27 now run under `LC_ALL=C`, and each fixed gate passes under both
`LC_ALL=C` and `LC_ALL=en_US.UTF-8`.

### Fixed — a cached enum byte past its enum's last value was believed, and a span-tier memo byte wrote past a stack array

Two on-disk readers built enums straight from bytes with no range check. **The ingest cache** read ten of them —
`SymKind` and `Lang` on a definition, `Lang`/`RecvKind`/`RefRole` on a reference, `Lang`/`LocalBindKind` on a
binding, `BindKind` on an FFI alias, `HttpMethod` on both route records. **The span-tier memo** (`ripwire-stier-*`,
the `--grep` classifier's per-file blob) read one `SpanTier` byte per span.

What an out-of-range value did, measured on the unfixed binary at `3bf884e2` over a 15-file fixture
(`test/fixture` + `test/ffifix` + `test/routeedgefix`), one field class set to 255 at every site with every digest
rebuilt, 24 verbs each diffed against `--no-cache`: every record was accepted (`cached_records=15` of 15), and the
answer changed on 18 verbs for `SymKind` (served as `t="other"`; a field became a map symbol), 18 and 17 for a
definition's and a reference's `Lang`, 17 for `RefRole` (a call demoted to `role="read"` and out of the call graph),
13 for `RecvKind`, 12 for `BindKind` and 11 for `LocalBindKind`. A `Lang` of 32 or more is also undefined behaviour:
`src/clones.h:135` shifts a 32-bit language mask by it, and UBSan stops `--for`, `--clones`, `--readability` and
`--pack-task` there. The memo was worse: a tier byte of 3 or more indexes the three-element per-tier hit counter in
`grepApplySpanTiers` (`src/search.h:2174`), an out-of-bounds **write** on the stack that AddressSanitizer reports as
`stack-buffer-overflow`, and the plain binary served a different `--grep` answer.

How reachable, stated plainly. An ingest-cache record is covered by its own 32-bit digest and the offset table by
another, so a random bit flip is refused before any enum is read; an out-of-range byte gets there only from a blob
written wrong or edited with its digests rebuilt — a committed team artifact handed to `--cache=`, a copied cache
directory. For that cache this is defence in depth, and hardening rather than an integrity boundary: a blob whose
digests were rebuilt can still carry wrong in-range facts. The span-tier memo is read ONLY from the per-user cache
directory ladder (`$TMPDIR/ripwire`, `$XDG_CACHE_HOME/ripwire`, `/tmp/ripwire-<uid>`; mode 0700 and owner-checked,
failing closed otherwise), never from a repository or a `--cache=` path, so a cloned repository cannot supply one;
reaching the out-of-bounds write took storage corruption or a write by the same user. And the memo still has **no
checksum**: an in-range flip (a tier re-labelled, a span offset moved) is still believed and still changes a
`--grep` answer. This change bounds out-of-range bytes only.

Every enum byte is now validated at the read. The ingest readers go through one helper, `ByteR::enumU8`, which folds
a failure into the reader's existing `ok` flag, so the record takes the refusal path a short read already takes:
that file reparses and the rest of the blob stands. The memo refuses the whole blob and re-parses the file. Each
bound is a count constant beside its enum (`kSymKindCount`, `kRecvKindCount`, `kRefRoleCount`,
`kLocalBindKindCount`, `kBindKindCount`, `kHttpMethodCount`, `kSpanTierCount`; `kLangCount` already existed), and
each is proven exact at compile time by `src/infra/enumcount.h`, which asks the compiler whether `count - 1` names
an enumerator and `count` does not. So appending an enumerator without moving its count is a build error, not a
validator that quietly refuses the new value's every record. The proof is evaluated under clang only; GCC's
spelling was not verified, and the macOS and Linux clang legs carry it. On `-DNDEBUG` Apple clang the warm load
function `loadCache` grows from 3,936 to 3,962 instructions: the checks become compares folded into the `ok` flag
with `csel`, plus 4 conditional branches. No cache format, `kCacheVersion` or parser version moved.

`test/cachefuzzcheck.sh` gains Part 3 and Part 4. Part 3 changes ONE enum byte per field class in an otherwise
valid blob, rebuilds every digest, and asserts that the one record is refused (`cached_records` 14 of 15), that
the output is byte-identical to `--no-cache`, and that the ASan binary with `--clones` stays silent. An in-range
edit of the same byte must be accepted (15 of 15), which proves the refusal comes from the range check and not
from a digest. The enumerator counts are read from `src/model.h`, not written into the gate. Part 4 does the same
for a memo tier byte, and its control re-labels a comment span as code, which changes the answer. Against the
unfixed binaries the new arms gave 27 FAIL rows: 20 accepted mutants, the `clones.h:135` UBSan report, the
`search.h:2174` stack-buffer-overflow, and the memo serving a different answer. Against the fixed build the whole
gate is 161 PASS, 0 FAIL.

### Fixed — git runs with the file-system monitor off, temp files are created exclusively, and edit-plan reads the path it confined

- ripwire runs its git commands with `--no-optional-locks -c core.fsmonitor=false`; the one read of that setting
  runs without them, since the flag would mask the value it reads.
- the atomic-publish writers create their temp file exclusively and without following a symlink.
- `--edit-plan` reads a payload through the same confined path its containment check judged.

### Fixed — a `--pin-census` row no longer splits on a line break, TAB or `|` inside an id

A C++ out-of-line member of a class template whose template-argument list spans source lines has a scope that holds
the line break verbatim, and the census wrote it raw. One `C` row became a six-field line plus a continuation line
starting with neither `C`, `S`, `O` nor `#`, and the symbol's `S` row broke the same way; a reader splitting lines
dropped or mis-keyed the site. It was seen once, on a large private C++ corpus. The map was never affected: it writes
the same scope as `&#10;`. Five more spellings of the defect reproduce on the pre-fix binary: a TAB or a form feed
inside the argument list, a backslash line splice, CRLF source, and a `|` inside an id. `|` separates targets, and on
this repository that case is real: Markdown heading symbols such as ``--token-budget=N[K|M|G]`` made a `|`-split read
18 single-target rows as two to six targets.

Every id and callee field is now escaped. A backslash is written `\\`, TAB, LF and CR are `\t`, `\n` and `\r`, and every
other control byte and `|` is `\xHH`. Nothing else changes, so the columns are the same and an id without those bytes
is spelled exactly as before. The first line now reads `pin-census v3` and the header documents the escape.
`bench/scip_match_diag.py` decodes the fields, because it opens files by an id's path; `bench/scip_pin_precision.py`
joins ids as opaque keys and needs no decode.

Measured by running the pre-fix and fixed binaries with `--pin-census --no-cache` over a clean export of this
repository at `a55b118e`: 99 of 51,821 rows change, 18 `C` and 81 `S`. 98 of them hold a `|` and one holds a backslash,
each decodes back to its pre-fix bytes exactly, and every other row is byte-identical. Before the fix all 18 of those
`C` rows had target lists a `|`-split misread; after it, none do. Gate: `test/pincensuscheck.sh`
arm (L), over a generated fixture. Every non-comment line must be a `C`, `S` or `O` row with its full field count, and
the check also runs over arm (B)'s and arm (G)'s censuses. Each awkward caller id must decode to its source bytes,
re-encode byte-identically and appear verbatim as an `S` id. The `|` target must split into one id, and the
dispositions and summary counts must agree with what a line reader parses. Against the pre-fix binary the gate printed
12 FAIL rows: a line reader parsed 2 of 6 decision rows and 12 of 16 symbols.

## [0.6.1] — 2026-09-14

**A header selector answers only with the definitions it can tie to that header, every number a compact answer prints
comes with its definition, and the answers an agent reads got smaller.** Outside contributors wrote the Elixir
module-and-arity resolution (**@henry-hz**), taught `--scip` to read the indexes scip-java writes (**@dpunosevac**),
made the callers answer's `next=` pointer land on the call site it promises (**@antoleod**, in their first
contribution to ripwire), wrote the README's reference guide (**@heliocipher**), and taught the Ruby dependency view
that a constant argument and a rescue class are dependencies (**@andriytyurnikov**). Each is named below, beside the
entry their work produced.

### Highlights

**The release ran against ripwire's own instruments, and the instruments say what moved.**

*What the instruments are.* Three readouts, all registered before the work began, and none of them a model's opinion.
A frozen bank of 30 retrieval questions, each answered in ONE call on a 2,066-file C++ corpus pinned at one commit,
scored on the gold files the question's answer must name. A follow-up ladder over the same bank: six deterministic
steps per tool, no model in the loop, scored on how many questions reach a complete answer by step N. And a held-out
draw registered separately, so a round cannot be tuned onto the bank it is graded on. Every figure below is the same
question asked of two binaries on the same corpus at the same commit, `wc -c` on stdout, warm cache.

*What got better.* The work this round was routing and shape, not ranking: giving a question a scope it could not
state before (`--in=DIR`), a widening page when the single-call answer is thin (`--for … --limit=N`), and one row per
group where the answer had been repeating one fact per row. Complete answers and bytes-to-a-complete-answer are the
two numbers that decide whether that paid; the re-measure on those instruments is not part of this release's record, so
what this section stands on is the per-verb measurement in each entry below, every one naming its corpus and method.

*Where the bytes went.* Three shapes account for nearly all of it: a "what changed recently in this directory"
question that used to be answered with a whole-repository map now collapses that map to a 61-byte stub and adds a
scoped window; every scoped symbol row on a map drops the canonical id it had just printed the path half of, keeping
`sc=` instead; and a tests-to-run list on a corpus whose harnesses have no derivable runner states that fact once per
group instead of once per row. None of the three drops a row, a path or a disclosure — the multiset of answers is
unchanged in each case, and each entry below names its corpus and its method.


**Elixir resolves modules and arities statically.** Calls resolve to the module, name and arity they name, instead of
by name alone: lexical aliases, filtered imports, default arguments, pipes, captures and delegates. Nested modules and
each target of a multi-target `defimpl` have separate identities, types and callbacks are navigable, and CLI and MCP
use-site queries share one set of rules. Macro expansion, `__using__` and calls inside `unquote(…)` / `bind_quoted:`
remain static-analysis limits and are documented as such (@henry-hz,
[#81](https://github.com/redhat-et/ripwire/issues/81), landed as
[#207](https://github.com/redhat-et/ripwire/pull/207)).

**`--scip` works with scip-java.** SCIP writers encode an occurrence's range in one of two ways, and ripwire read only
the deprecated one, so every index scip-java writes was silently ignored and `--scip` changed nothing. It now reads the
typed form first, as `scip.proto` asks. On spring-petclinic the precise overlay went from no matches to 79% of
occurrences (@dpunosevac, [#198](https://github.com/redhat-et/ripwire/pull/198)).

**Numbers that shipped without a definition now have one.** `graph_unindexed=` shipped in 0.6.0 with no definition on
`--lego`, `--verify` and `--nonlocal-state`, and under `--legend=compact` on every XML verb except `--connect`
([#169](https://github.com/redhat-et/ripwire/pull/169)). Compact answers also carried `declined_calls=`,
`unproven_defs=`, `pr_iters=`, the map header's own counts, `--impact`'s blast-radius counts, `--safe-delete`'s verdict
fields and the `--communities`/`--community` structure counts with no definition; each is defined now, and the compact
pins follow the definitions rather than the definitions being trimmed to fit one pin
([#185](https://github.com/redhat-et/ripwire/pull/185), [#189](https://github.com/redhat-et/ripwire/pull/189),
[#203](https://github.com/redhat-et/ripwire/pull/203)). A budgeted `--for` that drops legend clauses to fit its
allowance now names the attributes whose definitions it dropped ([#174](https://github.com/redhat-et/ripwire/pull/174)).

**A header selector answers only with what it can prove, and says what it dropped.** A `file:name` selector that names
a C++ header declaration is widened to the definitions the declaration stands for. The widening matched on the name and
the enclosing scope, and that scope drops namespaces, so `--callers=a/Store.h:putObject` counted `callB` in
`b/Store.cpp`, a caller of a different `Store`, and a free function matched on its name alone. A definition is now kept
only when its file is the header or includes it, resolved path-precisely
([#173](https://github.com/redhat-et/ripwire/pull/173)). What the proof drops is counted as `unproven_defs=` on
`--callers`, `--callees`, `--impact`, `--safe-delete`, `--path`, `--uses`, `--mentions`, `--verify` and `--affected` —
all but the first two had answered from the declaration alone and printed a clean zero
([#190](https://github.com/redhat-et/ripwire/pull/190), [#195](https://github.com/redhat-et/ripwire/pull/195)) — and on
every verb that resolves a focus symbol at all, `--edit-check` included, where an `incompatible="0"` beside
`unproven_defs=` is now stated to be an incomplete read rather than a safe edit
([#210](https://github.com/redhat-et/ripwire/pull/210)). On ripwire's own tree, over every `file:name` selector whose
selection is all declarations, the binary after #173 shrank 89 of 4,322 answers compared with the one before it, and
grew none.

**The declined-call index fits in memory on a tree the size of llvm.** The call graph keeps, for every call the
resolver declines to bind, the list of candidates it declined between. Those lists were stored once per call, so the
structure grew with calls × candidates: 27.9 M entries, 114 MB, on llvm-project. One stored copy per distinct list
makes that 9,879 distinct lists and 62,359 entries — **368 KB** — with every count and every byte of output unchanged
([#208](https://github.com/redhat-et/ripwire/pull/208)).

**The commands ripwire writes for an agent ask for the compact legend, and say how to get the full one back.** Every
`ripwire <dir>` command in the skills, in the `ripwire wrap` paste block, in the prompt routers and in the tool routes
now carries `--legend=compact` where the verb accepts it — 158 skill commands, 9 wrap commands, 26 `--help-task`
routes and 2 tool-call routes. One sentence per surface, and not one more, says to add `--legend=full` when a
definition's reasoning is needed. The bare CLI is unchanged: it still answers with the full legend
([#215](https://github.com/redhat-et/ripwire/pull/215)). Alongside them, `--for` now pages its answer one file per row
and says when the single-call answer is thin enough to widen
([#213](https://github.com/redhat-et/ripwire/pull/213)), and `--rank-by=churn-decay --in=DIR` answers "what changed
recently in this directory" without a whole-repository map
([#212](https://github.com/redhat-et/ripwire/pull/212)).

**An agent can ask for the recency answer in words, and every new shape of this release is named where an agent
reads.** The task router had no churn or recency intent at all, so `what changed recently in db` and `who touched this
lately` abstained at `score="0"` and the churn window was unreachable from a task said in words. It routes now, and
composes `--in=DIR` only when the task names a directory of the corpus and the running build's own flag table ships
the flag. Every `--for`-shaped recommendation carries the widening page on the FIRST call rather than only after a
thin answer, four skills name the shapes this round adds, and a new ratchet keeps it that way: a flag `--help`
advertises with no agent surface, or a surface promising a shape the build refuses, goes red
([#218](https://github.com/redhat-et/ripwire/pull/218)).

### Upgrade notes

- **One cold parse.** The parser version moves to 93 (#139), then 94 (#172), then 95
  ([#207](https://github.com/redhat-et/ripwire/pull/207)); the cache format moves from 20 to 21 (#139) and stays there.
  `loadCache` returns empty on a version-or-parser-version mismatch, so the first run after upgrading reparses the tree
  and rewrites its cache. The quality snapshot scheme moves from 10 to 11 (#207), so the first `--quality-delta` after
  upgrading recomputes its snapshot.
  The parser version moves once more, to 96, and the cache format from 21 to 22, for the internal-linkage bit on
  every C and C++ definition ([#216](https://github.com/redhat-et/ripwire/pull/216)); a cache written by 0.6.0 is
  rejected and rebuilt on the first run either way.
- **A sidecar must be a regular file: a symlink at a sidecar name is refused, on read as well as on write.**
  `.ripwire_notes`, `.ripwire_quality_baseline` and `.ripwire_arch_baseline` are opened with `O_NOFOLLOW`, so a
  link at one of those names is not opened, wherever its target is. Anything else at the name that is not a regular
  file, a FIFO for example, is refused as well instead of being waited on. If you symlinked one on purpose (into a
  shared config directory, say), replace the link with a regular copy of its target. Until you do, every read of it
  prints a refusal on stderr, no notes surface, `--quality-delta` reports `baseline="git-HEAD (symlinked sidecar
  refused)"` and compares against HEAD, `--arch` reports every violation as new, and `--note-add`,
  `--quality-baseline`, `--arch --baseline` and `--baseline-update` exit 1 without writing. `.ripwire_config` and
  `.ripwire_quality_acks` are unchanged (#178, [#191](https://github.com/redhat-et/ripwire/pull/191)).
- **New flags and flag behaviour.**
  - `--in=DIR` is new, on the default map's churn-decay branch only (`--rank-by=churn-decay --in=DIR`). DIR is
    root-relative and must exist under the root; absolute paths and `..` are refused. Under `--in`, the symbol map
    collapses to a `<symbols stubbed="1" would_show=N next="--rank-by=churn-decay"/>` stub and a second
    `<recent scope= n= of= merge_bombs_skipped=>` block follows the global one, which stays byte-identical. `--in`
    joins the house `--offset=`/`--limit=` paging set; it is refused, naming the remedy, with any other verb, with
    multi-root, with `--top-k=0` and with `--json` — and, since the CI round, refused rather than silently ignored
    when a report verb wins dispatch (#212).
  - `--for=TASK --limit=N` no longer means what it meant: it now serves a file-grain widening page, one
    `<f p= score= n= sym=/>` row per positive-score file, paged with `--offset=M`. `--top-k` stays inert on `--for`,
    and `--help` now says which flag widens. Beside the page every bundle-shaping flag is refused, never ignored
    (#213).
  - `--legend=compact` is what the generated agent commands now ask for — the skills, the `ripwire wrap` paste block,
    the prompt routers and the tool routes. Add `--legend=full` to any of them to get the full legend back; the MCP
    `legend` argument's schema description now says so too. The bare CLI default is unchanged (#215).
- **Output that changes by design.** Each change is described in its entry below.
  - **`sc=` replaces `id=` on map and lens symbol rows.** A scoped row carries `sc=`, the enclosing scope; the full id
    composes as `p::sc::n`, with `p=` read from the row or from its `<f>` wrapper, and the legend states that
    composition. **Every selector still accepts the composed `id=` spelling on input** — `--expand`, `--callers`,
    `--impact`, `--uses` and the MCP twins are untouched. `<cand>` rows, `--expand`'s whole-file anchors and
    `--merge-scout` rows keep `id=`, because their path does not repeat on the row. `--json` twins print `"sc"`.
    `route=` on `--for` becomes a code rather than a sentence, and same-named callees of one `calls` block merge into
    one `<c n= l=>` row (#215).
  - **`<g>` grouped test rows.** A consumer that parses `tests_to_run` must learn one new row shape: contiguous
    runner-less rows whose other attributes are byte-equal are served as a single `<g hops= n= p="a,b,c"
    run_unknown="1"/>` row in XML, as one object with an array `"p"` (or `"test"`) in JSON, and as one
    `[hops=N] (n): a, b, c   (run: not derivable)` line in `--situ` text. Rows that carry a runner stay single
    `<t>`/`<test>` rows, a group of one stays a single row, a `,` inside an XML path is `&#44;`, and every path is kept
    verbatim — the multiset of paths is identical before and after (#214).
  - A `file:name` selector on a C++ header declaration keeps only the definitions tied to that header, so `--callers`,
    `--callees`, `--impact`, `--safe-delete`, `--path`, `--uses`, `--mentions`, `--verify` and `--affected` can answer
    fewer rows. They carry `unproven_defs=` when they dropped any (#173, #190, #195), as do `--edit-check`, `--lego`,
    `--connect`, `--around`, `--slice`, `--expand`/`--outline`, `--owners`, `--note-add` and the MCP twins (#210).
  - A C/C++ declaration without a body yields the focus to the lowest-id C/C++ definition with a body in the same
    scope; every other case keeps the lowest id. Four legend sentences that called the pick "the lowest-id one" are
    reworded (#210).
  - `--callers` on a narrowed selector with declined calls points `next=` at the bare-name `--uses` call, and its legend
    says so (#182).
  - `--lego`, `--verify` and `--nonlocal-state` define `graph_unindexed=`. `--legend=compact` answers define the
    attributes they print, so some compact answers are larger, and each compact schema is now pinned at its own
    measured size rather than at one 400 B pin: map 810 B, communities 820 B, map-diff 800 B, impact 780 B,
    community 730 B, safe-delete 720 B, around 720 B, metrics 720 B, pack-signatures 680 B, pack-top-n 660 B,
    query 630 B, and the remaining schemas between 140 B and 410 B. `--help` states the sizes and, restated from
    measurement, a saving of "at least 45%" rather than "at least 50%"; the measured savings on a small answer are
    `--callers` 65.91%, `--uses` 63.79%, `--impact` 46.17% and `--affected` 64.73%, a per-call drop of 2.8–5.8 KB
    (#169, #185, #189, #203). `--for`'s own compact dialect is present-only and pinned at 690 B (#215), and the
    pack-task schema moves to 880 B where a fixture's runner-less rows now define `run_unknown=` (#214).
  - A budgeted `--for` that takes rung zero names the legend definitions it dropped (#174).
  - Every churn-decay `<recent>` block carries `merge_bombs_skipped=`, `"0"` included, and an all-bomb window prints
    `<recent n="0" of="0" merge_bombs_skipped="N"></recent>` where it printed no block at all (#212).
  - Records inside a literal `#if 0` no longer serve any role: reads, writes, imports (`using ns::x;` and `#include`
    alike), `extends`, types, `#else` branches, variable-to-type bindings and definitions are all excluded, where 0.6.0
    excluded only calls. `--uses` counts can fall, `amb=`, `prov="split"` and `overloads=` can lose rows minted by code
    that cannot compile, and `--expand=deadType` refuses with a suggestion instead of serving a dead body. `--grep` is
    unchanged: text inside `#if 0` is still findable (#172).
  - `--connect`'s `est_tokens=` reads higher on a tree that has an unindexed file (#171).
  - `--help` lists twelve flag rows it had left out, and the `--scip` help row says a missing index refuses (#170, #184).
  - The map header, `--skipped`, `<flags>` and `<doc-drift>` can carry `escaped_root=` (#179).
  - `--scip` naming an empty file, a directory, a FIFO or a device exits 1 (#197).

### Added — `--for` pages its answer one file per row, and says when to widen

On the pre-registered follow-up ladder (a 2,066-file C++ corpus pinned at one commit, the frozen 30 questions, six
deterministic steps per tool, no model in the loop), every ripwire follow-up completed 0 answers through step 4:
`--for`'s `next=` pointed at `--expand` (a body, not a wider list), `--top-k` was inert on `--for`, and
`--format=candidates` is symbol-grain (40 symbols is about 18 files in 11 KB). The one follow-up that completed answers
in that ladder was a file-grain page — one row per file, about 6 KB. Local telemetry had `--for` → `--expand` followed
0 of 259 times.

`--for=TASK --limit=N` (`--offset=M` pages it) is now that page: a `<files>` document of one `<f p= score= n= sym=/>`
row per positive-score file, `p=` spelled root-relative exactly as every other verb spells it, ranked file-first by
`score=` — the IDF-weighted share of the query's subtokens the file's top 8 symbols cover between them (a term counts
once however often it recurs, so one huge file cannot monopolise; ties by the best symbol's lens score, then path).
The root carries the house paging vocabulary (`shown= total= capped= has_more= next_offset= offset= limit=`) and a
`next=` naming the next page. When the answer is THIN — the top-ranked symbol's name, doc or body carries under 50% of
the query's IDF-weighted subtokens (an unmatched subtoken weighs as the rarest, so a `(#12147)` token lowers the share
honestly), or the ranked head spreads over fewer than 3 files — `--for`'s root carries `coverage=` (that share, whole
percent) with its legend clause, and the r=1 row's `next=` names `--for=TASK --limit=40` instead of the body. A
confident answer carries none of the three and is byte-identical to before; the `--json` and MCP twins follow the same
present-only rule. The MCP `for` twin takes the same `limit`/`offset` and serves the same page through the same
renderer. Beside the page every bundle-shaping flag is refused, never ignored (`--limit=0` and non-numeric values were
already refused). `--top-k` stays inert on `--for` and `--help` now says which flag widens.

Measured, on the ladder re-registered with the page as step 2 on the `--for` shapes: ripwire's complete@step row is
unchanged at 14/14/14/14/17/17 — the page completed no question, because the seven misses it ran on hold 3–21 gold
files each — while adding gold files on four of the seven (+2, +1, +3 and +6 files) at 5,539–6,212 B per page (mean
5,841 B), and the thin rule named the page on 4 of those 7 misses. The frozen-30 single-call instrument is unchanged at
14/30 complete and 42/129 gold files named; its median bytes-to-answer is 6,348 B (5,988 B before: 10 of the 12
`--for` questions on that instrument are thin — commit subjects with a `(#NNNN)` token, "how does A reach B" questions
— and carry the clause; the 2 confident ones read the base again, and the 18 non-`--for` questions moved by the 2–4 B
the git stamp moved on every verb). Gate: `test/forwidencheck.sh` — a generated 33-file fixture whose gold file sits at
page rank 13 and is absent from the default head and tail; one row per file, determinism, paging with no overlap,
`coverage=` defined in both dialects, thin versus confident `next=`, the refusals, MCP parity — red on the pre-change
binary. The byte pins that ride a thin `--for` header (forrankordercheck's fixture rows, forrootlegendcheck,
compactlegendcheck's loop, the two `--no-route` goldens) were re-anchored with the measured number; the confident ones
read the base again ([#213](https://github.com/redhat-et/ripwire/pull/213)).

### Added — `--in=DIR` scopes "what changed recently", and the churn window discloses the merge bombs it skipped

Three defects, one lane.

**The churn window hid the commits its merge-bomb rule skipped.** The decayed git walk skips any commit touching more
than 100 indexed files and counted nothing about it, so a `<recent>` block could omit the very commit a question was
about — a held-out gold commit touching 71 source files was invisible — with no trace in the output. Every churn-decay
block now carries `merge_bombs_skipped=`, `"0"` included; the threshold is the named `kChurnMergeBombMaxFiles = 100`,
listed in `docs/LIMITS.md` and `static_assert`-pinned to its legend text, and defined in both the full and the compact
dialect. A window in which every commit is a bomb — a shallow clone of a large tree; llvm-project at depth 1 is one
183,835-file commit — used to print no `<recent>` block at all, which made the new count vanish on exactly the run that
needed it; it now prints `<recent n="0" of="0" merge_bombs_skipped="N"></recent>`. A tree with no git still prints no
block.

**There was no directory scope for "what changed recently in DIR".** `--rank-by=churn-decay` answered with a
whole-repository symbol map plus one global `<recent n="40">` block that a directory with more than 40 recently-touched
files never fits into, and the sub-root workaround loses the global block and spells `p=` sub-root-relative.
`--in=DIR` keeps the global block byte-identical, adds a second `<recent scope="DIR" n= of= merge_bombs_skipped=>`
block built from the same mining pass and spelled on serialize's own root-relative rule, pages it with the house
`--offset=`/`--limit=` (40 rows, then `capped="1"` and a `next=` carrying the page verbatim), and collapses the symbol
map to a `<symbols stubbed="1" would_show=N next="--rank-by=churn-decay"/>` stub.

Measured (RocksDB at `0e2801ac`, read-only corpus, scratch cache, warm, `wc -c` on stdout): the bare
`--rank-by=churn-decay` answer is 39,813 B; `--in=db` is 10,241 B, `--in=util` 10,165 B and `--in=table` 10,711 B.
The saving is the stub — 68 B in place of the 200-row map — and the scoped block itself *costs* 2.2–2.75 KB per
answer; RocksDB reads `merge_bombs_skipped="30"`. On this repository, `--in=src` takes 46,843 B to 9,259 B and reads
`"5"`. The compact legend grows 1,783 B → 1,939 B under `--in=` (+156 B: `scope=`, `total=`, the window terms). On
llvm-project (183,835 tracked files, `/usr/bin/time -l`, scratch cache, two warm samples each) the per-file scope pass
costs nothing measurable: warm bare and warm `--in=llvm/lib/Analysis` both run 2.41–2.44 s real at 2.2 GB max RSS,
while the answer falls from 47,967 B to 5,676 B. Honest caveat: that clone's single commit is a merge bomb, so every
file weight is 0 and the prefix predicate short-circuits — the 183k-file loop is exercised, but the path compare is
exercised at scale only on RocksDB's 1,857 touched files.

Gates: `test/recentscopecheck.sh` (58 PASS, 42 arms red on the pre-lane binary) and `test/churndecaycheck.sh` arm 7
(red on the pre-change binary: no attribute anywhere), both also clean under ASan
([#212](https://github.com/redhat-et/ripwire/pull/212)).

### Added — the task router reaches the recency question, and this round's shapes are named where an agent reads

Three defects, one lane. The framing for the round: for this to work the whole system has to be put together — the
answers need shortening, but the agent also has to know how to use them.

**The recency question routed nowhere.** `what changed recently in db`, `who touched this lately`, `the newest commits
here` — every phrasing abstained with `score="0"`, so `--rank-by=churn-decay`, and the `--in=DIR` scope landing beside
it, could not be reached from a task said in words. The cause was simply that no churn or recency intent existed.
`recent` is on `kWeakSymbolStopWords`, but that list governs symbol resolution only — it is why `--expand='recent'`
can never be minted out of prose — and it has never had any bearing on which INTENT a task reads as. Nothing came off
the stop list, since those words must still never name a definition; they became intent evidence instead, which is
what the list's own comment says they are, and the correction is recorded in the source beside the new route so the
next reader does not re-derive it.

The new `recency-window` route is CONJUNCTIVE in three parts, because two are not enough: a TIME word, a MOTION word,
and a word naming the corpus or a directory of it the task named. A time word alone is usually part of a compound noun
(`the recent-file cache`); a time word and a motion word together is also a sentence about a supplier revising their
terms last quarter. An EXPLANATORY question is never this route however many of the three it holds. Cues are matched
word-bounded — the explanatory ones included, since a phrase delimits its interior and nothing at its two ends, and a
word ending in `how` followed by one beginning `do` is how `show documentation` swallowed a cue. The route runs LAST,
only when the weighted tier named nothing, which is both the argument that it costs the older routes nothing and how
it reads a dirty worktree: `is my diff safe to merge, i changed these files recently` is still `review-diff`'s
question, and `review-diff` wins before this route is reached.

**`--in=DIR` is composed only when both halves hold.** The task must name a directory of the CORPUS in a locating slot
— the same cue discipline the symbol slot uses, matched on `rw::sarif::rootRelativeUri`, the one root-relative
spelling the map's `p=` and `--in=` both use — and the running build must ship the flag, which `cli.h`'s new
`shipsViewFlag` reads from the flag table itself. A router that composes a flag its own parser has no row for hands
back a command that exits non-zero on the first paste, which is the prerequisite violation this file refuses from
every other direction. When the task names a directory this build cannot scope to, the `reason=` says so instead of
handing back a whole-repository answer to a question about one directory with nothing marking the drop. The directory
walk takes the EARLIEST slot in the sentence rather than whichever cue sits earlier in an array.

**The widening page was discoverable only from a thin answer** — one call too late for an agent choosing what to run
FIRST, and the first call is what `--help-task` exists to pick. Every `--for`-shaped recommendation now carries
`next="… --limit=40"` on its `<choice>`, keyed off the INTENT rather than off finding `--for=` anywhere in the command
text (a task that quotes the flag inside another verb's argument had handed `--pack-task` a page width it refuses,
measured: exit 1), and spelled by `forpage.h`'s own `forWidenNext`, so the recommendation's follow-up and the answer's
own follow-up are one spelling under one 120-byte ceiling rather than two spellings at 197–236 B. Present-only: a
recommendation that is not `--for`-shaped carries no attribute at all.

**`--help-task` had no legend in the default dialect.** Every attribute a reader met on its only screen was undefined,
with the compact layer's present-only legend the only place any of them was explained. One line defines all twelve
plus `<run>`, ending in the shared `kNextLegendClause`, and `--help-task` joins `legendcoveragecheck`'s enumeration
and `nextverbcheck`'s population.

**No new shape of this release was named where an agent reads.** Measured on main's skills, `--for`'s
`--limit`/`--offset` page and its `coverage=` gauge appeared in no skill body and no wrap primer within reach of the
verb they belong to: `--limit` is named, `--for` is named, in different files, and naming the two apart does not tell
anyone the page exists — the PAIR is the instruction. Four skills gain one or two sentences each, no frontmatter
touched. `ripwire-fresh-eyes` gains the history question (`--rank-by=churn-decay`, `--in=DIR` and what it does to the
map, `merge_bombs_skipped=` read as the disclosure it is, `scope=`); `ripwire-orient` gains the thin-answer rule
(`coverage=`, and that the step after a thin answer is `--for=TASK --limit=40`, not a body) and how to compose a
selector out of a row whose identity is `sc=` (`p::sc::n`); `map-before-you-read` gains the same in its pagination row
(on `--for` a `--limit` is not a cut but a wider net, and the bundle-shaping flags are refused beside it); and
`ripwire-change-check` gains the grouped `<g hops= n= p= run_unknown="1"/>` row beside `--affected`, with the
invariant it preserves.

Measured (`bench/taskroute_eval.py`, the committed content-hash split; only the binary and the corpus change between
rows):

| stage | binary | rows test / dev / all | accuracy test | dev | all | precision | harmful |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| before the lane | `origin/main` | 114 / 111 / 225 | 0.939 | 0.946 | 0.942 | 1.000 | 0.000 |
| after the first review round | `aaa3baa6` | 128 / 119 / 247 | 0.945 | 0.950 | 0.947 | 1.000 | 0.000 |
| this head | `342d16d9` | 130 / 119 / 249 | **0.946** | **0.950** | **0.948** | 1.000 | 0.000 |

Coverage at this head is 0.917 test, 0.933 dev, 0.925 all, and **every miss is an abstention**: `precision=1.000` and
`harmful=0.000` on all three splits, with `want=… got=abstain` the only confusion row, and negative specificity 1.000.
The control is this head's binary scoring the pre-lane 225 rows — 0.939 / 0.946 / 0.942 at coverage 0.907 / 0.929 /
0.918, the same three numbers as the first row, so no inherited row moved. The lane added 24 rows (225 → 249): ten
positives, four of them naming a directory, and four decoys in the first round; then four NEGATIVES, one per
word-boundary class a review found (`here` in where/there, `source` in outsource, `file` in profile, `code` in codec),
one for a dirty working tree, three positives for vocabulary that abstained (a verb below the motion floor,
`since <a day or a date>`, `what is new in DIR`), and two for the cross-word explanatory cue. Two of the review rows
are labelled `instrumented-cli` rather than `handwritten`, by the rule the corpus's own section states: their trigger
is a small closed phrase list, so a sentence that routes necessarily reuses one of its phrases.

Two claims an earlier revision of this lane made were WITHDRAWN by review, and are corrected in
`test/taskroutefix/PROVENANCE.md` rather than left standing. That the 225 pre-existing rows are byte-identical on
(status, intent) across the new route is true and nearly vacuous — measured, 0 of those 225 prompts reach the recency
route at all, so the identity was never in question, and a number that cannot move is not a measurement; the evidence
that the route steals nothing is the corpus's own negatives and the gate's arms. And the contamination screen is not
down to one flagged line from two: measured with one binary at three points it reports the same 2 flagged lines every
time, neither of them a row this lane wrote.

Gates. `test/taskroutecheck.sh` gains 11 arms in the first round and 20 more in review; against the pre-change binary
4 FAIL — both recency phrasings answer `status="abstain" … score="0"`, and the locate-task recommendation carries no
widening `next=` for the follow-up arm to recover. The emitted commands are EXECUTED, not merely matched: the bare
recency command must return a `<recent>` block, and the widening `next=`, unquoted with `shlex`, must return the
`<files>` page. Every arm reads the COMMENT-STRIPPED body, so a legend that names an attribute can never satisfy an
assertion about a row carrying one. `test/agentsurfacecheck.sh` is new, and red against main's skills with 3 FAIL —
no skill body or wrap primer named `--limit=`, `--offset=` or `coverage=` within five lines of `--for`, so the
file-grain page and its thin-answer gauge were unreachable from a skill. Its arm (A) is a RATCHET over all 163 long
flags `--help` advertises: each is named in a skill body or the `ripwire wrap` primer, or recorded in
`test/agentsurfacefix/unnamed_flags_baseline.txt` with the reason it is still a gap (5 lines today: `--eval-skills`,
`--eval-stray`, `--pin-census`, `--max-file-size`, `--sarif`), a floor that may only be edited DOWNWARD and that also
fails when a recorded line stops being a gap, so a closure cannot be filed and forgotten. The match is word-bounded,
because 23 advertised flags are a strict prefix of another (`--in` inside `--index-out`, `--not` inside `--notes`,
`--for` inside `--format`) and a substring test would report every one of them as named by its longer sibling; the arm
prints that count, so the population the bounded match protects is visible. Arm (B) pairs each of this round's new
shapes with its verb within five lines on one surface, PROBED by RUNNING the verb — `--help` advertising a flag is not
evidence that the flag emits anything — with what the binary emits (`<g`) split from what a skill must spell (`<g `)
so `<graph-query` cannot satisfy a row about grouped test rows, and it asserts its own population, 8 of 8 rows probed.
A shape that has not landed is declared PENDING with the lane that ships it, and the arm is SELF-HEALING on arrival: a
pending shape that appears in the binary with its pairing already satisfied PASSES, so #212, #214 and #215 turn those
rows green without touching a skill. What stays red is the dishonest direction — a surface promising a shape this
build refuses, with no lane declared. `docs/COMMANDS.md` is deliberately NOT an accepted surface: it names every flag
by construction, so accepting it would make this gate one that cannot fail; it is the reference, not the file an agent
loads mid-task. Gate count 613 → 614, `--quality-delta` at `gating="0"` with no ack, and the five gating rows the
review round would otherwise have raised were fixed by REUSE rather than acked — two scorers became one with the match
mode as a parameter, four hand-written membership tests became `isOneOf`, and three one-line call-through wrappers
were folded into their single call sites
([#218](https://github.com/redhat-et/ripwire/pull/218)).

### Added — Elixir module and arity resolution (parser version 95)

Elixir calls now resolve by module, name and arity, with lexical aliases, filtered imports, default arguments, pipes,
captures and delegates. Nested modules and each target of a multi-target `defimpl` have separate identities. Types,
callbacks and attributes are navigable, and protocol/behaviour relationships appear in the existing relationship views.
CLI and MCP use-site queries share the same resolution rules; unknown modules and excluded imports no longer fall back
to unrelated functions.

The implementation uses the existing vendored parser and cache records, with no Elixir runtime dependency. Macro
expansion and runtime dispatch remain static-analysis limits; the supported syntax and boundaries are documented in
[Elixir extraction](docs/ARCHITECTURE.md#elixir-extraction).

`kParserVer` 94 → 95 with `quality.h`'s `kIngestParserVerMirror` in the same commit — the branch carried 87, main
spent 87..92 while it was open and the 0.6.1 round takes 93 and 94, so it was re-bumped to the next free number over
the merged tip, per the rule in `src/ingest_cache.h`; `kCacheVersion` stays 21.

Four review findings were closed as maintainer commits on the branch, each with a row in
`test/elixirnamearitycheck.sh`. A call that only a `use`-injected import could answer minted no edge and was dropped
silently; it now counts in the map header's `unresolved=` and every answer's `graph_unresolved=` (an undefined spelling
stays undefined, modelling `__using__` stays open). A variable bound on the right of `=` inside a pattern —
`def join(%Socket{} = socket, _)`, a `case` clause, a `with` generator — is a binding, not a zero-arity call of a
same-named function. The quality key folds the arity out of an Elixir name, so `run(x)` → `run(x, y)` is an
`--edit-check` contract change on `run` (params 1 → 2) with every caller of the old arity listed and flagged, and a
`--quality-delta` params row, rather than a dead symbol beside a new one; a default (`run(x, y \\ 1)`) still reports the
change but flags nobody (`kQSnapCacheScheme` 10 → 11). `--for` by an exact function name (`generate_app`, `text`)
routes name-exact and ranks the `name/N` symbol first.

Five resolution rules the branch got wrong, found by reproducing against Elixir 1.20.3 / OTP 29 before the merge, each
with a row and a control in `test/elixirnamearitycheck.sh` over `test/elixirresolvefix`. `import M, except: [...]` after
`import M, only: [...]` subtracts from the only-list instead of replacing it (a function the only-list never named
minted an edge, silently; the refusal is now counted). A dotted nested `defmodule Inner.Deep` aliases `Inner` →
`Outer.Inner` from its declaration on, so the later `Inner.Deep.f()` names the nested module rather than a top-level one
— or, with no top-level one, rather than nothing. `alias __MODULE__, as: Current` inside a multi-target `defimpl`
reaches each implementation's own function, not the first implementation's. `&_seed/0` names the underscore-named
function (the underscore rule is for unused variables; a bare `_seed` read still is one). And `f()` on a bodyless
`def f(x \\ default())` head reaches the head beside the clauses, so `--path=caller,default` and `--impact=default` see
the caller; `f(1)` still reaches the clauses alone. Every one was a wrong answer or an uncounted drop. They ride parser
version 95 — the number this entry introduces, which no released binary has written — with `kCacheVersion` 21 and
`kQSnapCacheScheme` 11 unchanged. Still open, and documented in
[Elixir extraction](docs/ARCHITECTURE.md#elixir-extraction): calls inside `unquote(...)` / `bind_quoted:` under `quote`.

Contributed by **@henry-hz**, whose ten commits carry the authorship
([#81](https://github.com/redhat-et/ripwire/issues/81), landed with the review round as
[#207](https://github.com/redhat-et/ripwire/pull/207)).

### Added — a Ruby constant argument and a rescue class are dependencies; `lazy_edges=` counts distinct pairs (parser version 93)

Round three of the Ruby constant work, on the same corpus-own index as round one (superclass, mixins, autoload —
parser version 82) and round two (constant receivers — 83). Ruby's rule is that EVALUATING a constant is what makes
the autoloader load its file, and a receiver is only one of the places a constant is evaluated. Round two pinned the
other two as its disclosed floor; this round lifts them.

**A constant argument is a directive.** A constant chain that is a direct positional child of an `argument_list`,
or the value of a keyword pair written directly in that list, is a symbolic Include: `raise Errors::Boom`,
`validates_with Validator`, `delegate :name, to: Helper`, `record.is_a?(User)`, `super(Validator)`, `yield User`.
The `argument_list` is the grammar's one node for the arguments of a call (with or without parens), a `super` and a
`yield`, so one read covers all three. The lists of `include`/`extend`/`prepend`/`autoload` stay round one's, one
record per statement. An argument is lazy inside a closure and load-time at class-body or file level, exactly like
a receiver — `validates_with Validator` in a class body is a load-time dependency on validator.rb, which is what a
Rails model file's structure actually is.

**A rescue class is a directive, and it is lazy always.** Every constant chain in a `rescue` clause's exception list
(`rescue Errors::Bust, Errors::Boom => e`) is a symbolic Include. Ruby evaluates that list only while matching an
exception, never when the clause is loaded — `class X; begin; 1; rescue Nope; end; end` is silent, and the same
`begin` with a `raise` inside names `Nope` in a NameError (ruby 4.0.6) — so a class-body rescue is a use, not a
load-time dependency, and it stays out of the ccd/godfiles structure like every other lazy pair.

**One dedupe key.** Arguments and rescue classes share round two's (file, innermost open, written name) record with
receivers: a `raise Errors::Boom`, a `rescue Errors::Boom` and an `Errors::Boom.new` in one nesting are one
directive, and the parser-86 AND rule still decides the lazy bit — a rescue above a class-body receiver of the same
name is one load-time directive.

**`lazy_edges=` over-counted, and the fixture for this round is the shape that showed it.** `<health lazy_edges=>`
and a row's `lazy_edges=` are documented as DISTINCT (file, target) pairs, but the count walked an un-deduped
adjacency that is in directive order, not sorted, and counted a pair once per run of equal ids: `Errors::Boom`,
`User`, `Errors::Bust` in one method resolve to errors.rb, user.rb, errors.rb and read as 3 for 2 pairs. It now
sorts the dropped ids and counts unique ones. At this round's parser version the old count read 1 546 / 1 147 / 6 398 / 2 549
on the four corpora below against the distinct 1 381 / 1 015 / 6 342 / 2 519; every other byte of `--deps` is
identical between the two counts (checked on activerecord). Round two's own fixture never interleaved two spellings
of one file with another target, so its pins were right by shape rather than by the count.

**A value-position constant is a dependency, not import evidence — and the call graph is byte-identical to main.**
The first cut of this round let the new records feed buildGraph's include narrow, which reads a file's resolved
includes as evidence for which definition a bare call means. That is wrong for a value position: `notify(Dev::Config)`
beside `record.update!` says nothing about what `record` is, and the narrow bound `update!` to `Config#update!` on that
reading — on discourse 1,017 call sites newly bound or narrowed, 19 of 20 sampled wrong (the PR #139 review). `Include`
gains `isValueUse` (cache format 21), set for argument and rescue records and cleared by any receiver occurrence of the
same name, and `buildPreciseIncludeAdjWithContext( …, forCallNarrow=true )` — called only for buildGraph's
`fileIncludes` — leaves those records out; `--deps`, `--impact`'s importer tier and the lazy-pair count read them as
before. Measured against main's binary, built from the same merge base: the default map is
**byte-identical** on the four corpora below and on this repository, and `--report`'s totals match to the unit
(activesupport 3 650 edges / 410 modules, activerecord 8 638 / 912, the Rails apps 23 784 / 2 067 and 12 108 / 1 384).
The pre-fix branch had moved every one of them (23 447 / 2 030 and 55 more isolated symbols on the first app). Gate:
the review's own repro, `test/rubyargnarrowfix` — two `update!` definitions in different directories, a caller in a
third that passes `Dev::Config` and then calls `record.update!` — declines the call as main does (0 callers,
`declined_calls="1"`) while `dev/config.rb` keeps notifier.rb as a lazy importer; red on the pre-fix binary (1 false
caller).

**Disclosed floor, pinned to yield nothing** (`test/rubyargfix/lib/app/floor.rb`): a `when` pattern (evaluated
eagerly by Ruby — the next round's first candidate), an array or hash-literal element, a splat, an assignment's
right-hand side, string interpolation, a binary operand. Each is an evaluation Ruby performs that this round does
not read.

Measured (`--deps --limit=100000 --no-cache`, parser version 88 → 93, measured on the branch's pre-merge binaries; the
gems are Rails 7.2.3.2, the apps the same two Rails apps as rounds one and two, aggregates only):

| corpus | ccd | nccd | shape | load-time importees | lazy_edges | bytes |
| --- | --- | --- | --- | --- | --- | --- |
| activesupport `lib/` (282) | 15 299 → 15 775 | 7.59 → 7.83 | tangled | 201 → 202 | 935 → 1 381 | 75 988 → 85 530 |
| activerecord `lib/` (395) | 4 325 → 4 657 | 1.44 → 1.55 | vertical | 310 → 310 | 1 023 → 1 015 | 114 763 → 129 011 |
| a Rails app, 4683 files / 3532 `.rb` | 13 172 → 17 798 | 0.32 → 0.43 | horizontal | 414 → 1 015 | 5 630 → 6 342 | 750 915 → 855 559 |
| a second Rails app, 2002 / 1895 `.rb` | 6 543 → 7 577 | 0.34 → 0.39 | horizontal | 200 → 557 | 1 878 → 2 519 | 370 991 → 471 865 |

The importee column is the finding: on the two applications the files with a load-time importer went 414 → 1 015
and 200 → 557, because a class-body DSL argument (`validates_with Validator`, `delegate … to: Helper`, `rescue_from
Errors::Boom`) is where a Rails file names what it loads. No shape moved; ccd grew and stayed horizontal,
which is the structure/use cut doing its job. The `lazy_edges` column carries BOTH mechanisms above — new lazy
pairs in, the over-count out — and activerecord is the corpus where the second outweighs the first. The default map
of this repository (no Ruby) is byte-identical before and after.

Gate `test/rubyargcheck.sh` + fixture `test/rubyargfix/` (19 files, written RED against the parser-88 binary: 22
arms red, every control green); `test/rubyrecvcheck.sh`'s floor arm inverts and its report.rb pins move by the one
`raise`/`rescue` directive; `test/rubyrequirecheck.sh`'s main.rb counts its `rescue LoadError` as a shown,
out-of-tree row (12 → 13). `kParserVer` 92 → 93 with the mirror (the branch spent 89 while main spent 89..92 on the
extent detector, Kotlin and the yaml patch); cache format 20 → 21 (`Include::isValueUse`); re-pins with reasons
in-file: `test/qschemetrip.hash`, `test/printf_parity.manifest` (the `--impact` help and legend name the two new
closure kinds; the `--deps` legend's lazy definition gains the rescue class). `docs/COMMANDS.md` regenerated
(2026-09-11).

Contributed by **@andriytyurnikov**, round three of their Ruby constant work
([#139](https://github.com/redhat-et/ripwire/pull/139)).

### Changed — short symbol ids on maps, a compact legend on `--for`, and compact by default on the agent surfaces

**`sc=` on symbol rows.** Every scoped symbol row printed its canonical id in full —
`id="src/mcpverbs.h::rw::applyCompactToBatchSubs"` under an `<f p="src/mcpverbs.h">` wrapper that had just printed the
path, or beside the row's own `p=` on a lens `<d>` row. The row now carries `sc=`, the enclosing scope, the one segment
nothing else on the page holds; the legend states the composition `p::sc::n`, and **every selector still accepts the
composed spelling** — the resolver is untouched, and a new `test/scroundtripcheck.sh` (17 arms) proves the composed
multiset equals the old `id=` multiset. `route=` becomes a code (`name-exact(X)`, `subtoken+body`, `:broad`,
`:declined(word;carriers,defs)`) with one shared spelling for the CLI lens, the MCP `for` twin and the compact dialect,
so a code cannot acquire two readings; the fuller reading lives once in `--help`'s `--no-route` entry. Same-named
callees of one `calls` block merge into `<c n="pick" l="70,69"/>`, and `shown=` still counts callees.

Measured (`wc -c` on stdout; a build of the merge base run on the same merged tree, so no corpus drift rides the
numbers): this repository's flagless map falls from 26,449 B to 22,407 B — **−4,042 B, −15.3%, the same rows** —
`test/cppqualfix` −5.2%, `test/nestedqualfix` −5.3%, and `test/accessshapefix` **+9 B**, where four scoped rows do not
pay for the longer reading. On `--for` the bundle is byte-shaped, so the row saving becomes rows rather than bytes:
`pagerank power iteration` goes from 9,470 B at `shown="20"` to 9,880 B at `shown="25"`, and `rank graph teleport` from
10,134 B at 19 rows to 10,022 B at 22 rows.

**`--for`'s compact legend is present-only.** Every other XML verb under `--legend=compact` answers with a present-only
legend pinned per schema; `--for`'s native compact dialect was the default sentences behind a schema id (1,177–1,216 B
on the gate's fixture) and exempt from the pin by name. It is now one present-only comment — a reading per attribute
the bundle actually prints — measured by the gate's own splitter at 678 B on the fixture probe (915 B before) and
pinned at 690 B as the `ripwire.for/v1` row. Per call on this tree, default legend → compact: `pagerank power
iteration` −537 B, `rank graph teleport` −309 B, `escapeXml` −1,222 B.

**The agent surfaces ask for the compact legend, and say how to get the full one back.** Every command ripwire writes
for an agent carries `--legend=compact` where the verb accepts it: 158 `ripwire <dir>` verb commands in 17 skill files
(bodies only — no description, stop rule or boundary moved), 9 commands in the `ripwire wrap` paste block, 26
`--help-task` routes and the 2 tool-call routes. One sentence per surface, and not seventeen, says to add
`--legend=full` when a definition's reasoning is needed: the wrap blurb, one new section in the router skill's shared
conventions, a parenthetical in the three route hooks' injected context, and the MCP `legend` argument's own schema
description. `--for` keeps the default legend; the text, JSON and writer verbs are untouched; the bare CLI is
unchanged. Separately, the `--observe` arm of both prompt routers now counts a call only when the command word really
is the binary, so `cd …/ripwire && git log --oneline` no longer burns an adoption-window slot. Gate:
`wrapverbscheck` arm 8, six rows — the wrap blurb, the router skill, the three route hooks and a live `tools/list` over
`--mcp` — verified red against the merge base's tree and binary, 0 hits on every one of the six
([#215](https://github.com/redhat-et/ripwire/pull/215)).

### Changed — tests-to-run rows without a runner are grouped, and the disclosure is stated once per group

A tests-to-run row with no derivable runner said so on the row — `run_unknown="1"` (XML, 16 B), `"run_unknown":true`
(JSON), `   (run: not derivable)` (`--situ` text, 23 B). On a corpus where almost no harness has a derivable runner
that is one fact repeated per row: on RocksDB, `--affected=db/write_batch.cc` lists 127 tests, 126 of them runner-less,
and spent 2,016 B of XML and 2,898 B of text on the repetition. The disclosure is right — an absence is not a
disclosure — its per-row placement was the cost.

Rows already come in evidence order, so a contiguous run of runner-less rows whose other attributes are byte-equal is
served as ONE `<g>` row, emitted where its first member stood. Rows that carry a runner stay single rows, a group of
one stays a single row, a `,` inside an XML path is escaped `&#44;`, and **every path is kept verbatim**: the multiset
of paths before and after is identical, and the emitted order is preserved by construction, because a group covers a
contiguous run only. All twelve emitter sites in nine files render through one seam, and the legend clause is spliced
rows-gated, so a `tests="0"` answer pays nothing for it.

Measured (RocksDB, read-only corpus, scratch cache, same commit, `wc -c` on stdout), on the 127-row
`db/write_batch.cc` list: `--affected` 10,668 → 6,878 B (−35.5%), `--test-gate` 13,242 → 9,633 B (−27.3%),
`--test-gate --json` 11,055 → 7,163 B (−35.2%), `--situ` 11,769 → 7,357 B (−37.5%),
`--affected --legend=compact` 9,312 → 5,313 B (−42.9%) and `--test-gate --legend=compact` 11,223 → 7,596 B (−32.3%).
Eight `<g>` rows replace 124 single rows; three rows stay single. The bytes still spent on the disclosure after
grouping are 160 B of 2,016 B in XML and 230 B of 2,898 B in text. A three-row list pays rather than saves
(`--affected=cache/tiered_secondary_cache.cc` 2,352 → 2,690 B: that verb had never defined `run_unknown=` at all), and
on this repository, where every harness has a `.sh` runner, nothing groups and the deltas are the legend alone
(`--affected` +371 B, `--test-gate` +180 B, `--situ` +79 B). `--pack-task="change WriteBatch::Put"` serves
`<tests shown="54" total="109">` where it served `shown="28"`.

Gate: `test/testrowruncheck.sh` arm 12 (the multiset-of-paths and order invariants in all four dialects on a fixture
with three hop groups and a runner-bearing row inside one) red on the pre-change binary, plus arm 13 sweeping
`--token-budget` 1000..1700 to prove a byte cap can no longer drop two paths that each fit alone. Two new
`prcontextcheck` arms hold the third finding: the run clause is now priced and written from the RENDERED body, so a
bundle whose selected range reaches no test cannot buy the clause
([#214](https://github.com/redhat-et/ripwire/pull/214)).

### Changed — one absolute root per change report, `--situ`'s disclosures become gauges, and a changed file's lexical siblings

Three items from the output-routing loop's list, one commit each, stacked on the grouped test rows above.

**A runner command pasted the whole checkout prefix on every row that had one.** A change report states its absolute
root once, in the envelope, and every path below it is relative to that root — which is what makes the document
independent of where the tree is checked out. One emitter never joined: `testmap.h`'s `spell()`, which builds the
`run=` command, pasted the disk path verbatim. On an absolute root `--test-gate` printed the checkout prefix three
times — the `root=` anchor, `next=`, and every `<t>` row's `run=` — and `--situ` once per runnable test line, a
per-ROW cost against a per-DOCUMENT fact. The sweep could not see it: `test/fixture` holds no runner script at all, so
every test row there reads `run_unknown="1"`, and the one emitter that pastes a PATH INSIDE A COMMAND was never
exercised. `TestRunnerIndex` now takes the run's crawl root and spells the command through the same
`rw::sarif::rootRelativeUri` every `p=` beside it uses, with the hand-rolled leading-`./` strip becoming that one
call; the root is passed at all fourteen construction sites, so the twelve emitters sharing the index cannot disagree.
**The relativity is gated to single-root runs.** A multi-root run, whose disk path is under no single root, keeps the
absolute command, because an unrelativizable command must stay pasteable rather than become relative to a root that
does not contain it — and the spelling and the sentence that describes it now answer to ONE predicate,
`runsAreRootRelative`, read by the index and by all eight legend sites, so the clause can no longer tell a multi-root
reader that a command is relative to a root the document never names. `kRunHintLegendClause` gains the sentence
(rows-gated, like the rest of that clause), `--situ`'s `[2]` header says a `(run: …)` is relative to `root:`, and
`--help` and the regenerated `docs/COMMANDS.md` say what the code does — including the multi-root exception — where
they had said `run=` is spelled with the same root you scanned. Two more surfaces that hand a caller something to
PASTE gained the anchor they lacked: `--flags --flip` emitted root-relative `p=` and declared no root, and the MCP
edit receipt had relative `file`, `run` and `next:` and no root; both carry `root=` now, single-root only, with the
one sentence that defines it. `rootRelativeUri` itself returned on a leading `./` before it tried the root prefix —
right for the root `.`, wrong for every other relative spelling: `ripwire ./corp` stores `./corp/test/x.sh`, the early
return yielded `corp/test/x.sh`, and pasting that from the declared root is rc 127. Both sides drop the optional `./`
first and compare what is left; the root `.` case stays byte-identical.

**`--situ`'s disclosures are gauges, and every gauge keeps its reading.** `--situ` is the only report with no XML root
to hang attributes on, so every disclosure it owed was a sentence, and the sentences grew: a floor clause, a decl/def
partner header, a tests-to-run header and a script-gate caveat, about 1.2 KB of prose per call carrying facts a reader
can act on only once they are named. Each is now an attribute line, spelled as the XML and JSON dialects already spell
the same fact, so the three share one vocabulary: `counts_floor=1` beside `graph_ambiguous=`, `graph_unresolved=` and
`graph_unindexed=`; `not_dependents=1`; `prcontext_cap=20`; `order=evidence`, the attribute `--affected`'s root
already carries; and `script_gates_unmodelled=`, the counter `--affected` publishes. Nothing is dropped — every floor,
cap and caveat survives, and the two readings with no attribute form, how to read a zero and what
`[changed]`/`[partner]`/`hops` mean on a row, stay as the shortest sentence that defines them. **An attribute without
a reading is a token, not a disclosure**, so each gauge keeps a short gloss: the floor's CAUSE (call edges are
name-based), what an unindexed file IS, which header the resolver gauges come from, and whose cap `prcontext_cap=` is.
`--situ` refuses `--legend=compact` and is the one dialect with no legend to look a name up in, which is why the gloss
is not optional here.

**The files a change drags with it were the ones no walk could reach.** The files that move WITH a changed file are
its neighbours by name, and the caller walk reaches none of them: a header does not call the source that implements
it, an `.inl` is not indexed by any grammar in any build, and a harness the graph cannot link is reached by nothing —
two answers on the frozen 30-question set were incomplete for exactly that reason. Section `[1]` now lists them under
the decl/def partners and the floor clause: same directory, and the same filename stem or the stem-partner convention
`testmap.h` already owns (`<stem>_test`, `test_<stem>`, `<Stem>Test`, `_unittest`, `_spec`). Same directory is
load-bearing — a same-stem file in another directory is a namesake, and listing namesakes would make the block noise
on exactly the large trees it is for. The rule is **stricter than the design that simulated it**, an exact stem plus
the test-partner affixes rather than a shared stem TOKEN, so it lists fewer files and costs less; whether the stricter
rule still completes those two questions is for the re-measure, and no completeness claim is made here. The candidate
population is the CRAWL's, not the index's, so the `.inl`/`.ipp`/`.tcc` partner a C++ change most often has to edit is
named; the crawl's unsupported-extension row list is itself capped, which is the one way this list can be short of the
truth, and that is disclosed as `unindexed_rows_floor=1`. The floor is a property of the CANDIDATE LIST, so it is
recorded whenever that list was short and the block speaks at zero as well — a crawl cut that removed the only
candidate used to print nothing at all, the silent zero `docs/METHODOLOGY.md` §9 forbids. The block is capped at 8
with `shown=`/`total=`/`capped=1` and a pasteable `next:`, raisable with `--limit`, and with no offset: `--situ=F
--offset=20` had printed `shown=0 total=9 capped=1` with a `next:` offering relief that cannot restore rows an OFFSET
removed, and `--offset=7` had dropped six rows silently. It is additive to the decl/def partners above it —
suppressing the overlap was tried and reverted, because it removed `widget.h` from "the siblings of widget.cc" to save
about 20 B. The MCP `situational_awareness` twin carries the same list as `siblings`, with a `siblings_total` that is
now the population and an explicit `siblings_capped`, emitted and never omitted, rather than the length of the array
beside it, which was a tautology.

Measured (`wc -c`, same warm cache, same commit, absolute root; the tip of the lane this one is stacked on against
this head over the SAME tree, so each pair carries all three items together):

| corpus | verb | before | after |
| --- | --- | ---: | ---: |
| this repository (root 131 chars) | `--situ=src/graph.h` | 4,448 B | 2,955 B |
| this repository | `--situ=src/situ.h` | 2,332 B | 2,040 B |
| this repository | `--situ=src/testmap.h` | 2,325 B | 2,033 B |
| this repository | `--test-gate=src/testmap.h` | 5,455 B | 5,247 B |
| RocksDB @ `0e2801ac` (root 66 chars) | `--situ=db/write_batch.cc` | 7,489 B | 7,376 B |
| RocksDB | `--test-gate=db/write_batch.cc` | 9,946 B | 9,868 B |
| RocksDB | `--affected=db/write_batch.cc` | 7,124 B | 7,113 B |

Per item. The root spelling saves one echo per row that has one, less the 56 B the conditional root sentence adds, so
it grows with checkout depth and with how many rows carry a runner: two echoes of a 132-character root on this
repository's `--test-gate`, one echo of a 66-character root on RocksDB's. The four compressed `--situ` lines, measured
by `situshapecheck`'s own `${#line}` on this repository at `--situ=src/graph.h` (the partner header on the gate's
fixture, since `graph.h` has no decl/def partner here), go 601 → 344, 228 → 209, 233 → 220 and 167 → 132: **1,229 B →
905 B**. Said plainly, that is about 20% less than the byte attribution predicted, because the prediction assumed the
gauge names could go unglossed and they carry a gloss instead — and it supersedes this lane's own first figures, which
were measured before the readings were restored and on a different corpus than the gate's. The sibling block costs
what it lists: **276 B** on RocksDB at `--situ=db/write_batch.cc`, a 244 B header and one 30 B row naming
`db/write_batch_test.cc`, which no other section of that report reaches.

Gates. `test/situshapecheck.sh` is new and red on the base binary with 17 FAIL rows — the floor line 601 B over its
ratchet, the partner header 228 B, the `[2]` header 233 B, the four missing attributes, the whole sibling block, the
offset arm's premise, both silent-zero arms and the MCP twin arm. Its sibling fixture is a
`.h`/`.cc`/`_test.cc`/`.inl` quadruple, a same-stem DECOY in another directory and a same-directory different-stem
file (both of which must be absent from the block), a nine-sibling stem for the cap and for `--limit`'s relief, a
no-git copy of the same tree proving the block is static — which is also why it cannot leak — and the MCP twin
agreeing row for row; the silent-zero arm runs on a 700-`.inl` fixture that really does cut the crawl's 500-row
unsupported list, and asserts that premise before it asserts the floor. `test/rootrelemitcheck.sh` ARM 9 is red on the
unchanged binary with 8 FAIL rows and builds its own fixture with a real runner script at two checkout depths,
EXECUTING the printed `run=` from the declared root, because a relative command that cannot be pasted would be worse
than an absolute one; ARM 9b is a matrix over `.`, `corp`, `./corp`, `corp/`, an absolute path and a symlink, all of
which must print the SAME command, ARM 9c pins the spelling and the sentence against each other, and ARM 9d covers
`--flags --flip` at two checkout depths. `receiptpostcheck` (18) covers the MCP receipt, which (13) already holds key
for key against the CLI's, and `runhintcheck` 2c/2d the `--affected` twin. Two gate self-checks were wrong the same
way the code was and now red on that outcome: an empty `run=` made `eval ""` succeed, so `runhintcheck`'s execution
arm passed on the one outcome it exists to forbid, and `rootrelemitcheck` ARM 9's empty-`next=` case fell out of an
if/elif chain printing neither PASS nor FAIL. The suite also caught a dangling `string_view`: `runHintClauseIfRows`
BUILDS its clause now, because the root sentence is conditional, and `PackTaskHeaderParts` holds views, so binding
`runClause` straight to the returned temporary read freed memory — it showed as `packtaskcheck` reporting a bundle
that was both malformed and non-deterministic (two runs, two hashes) and `xmlwellformed` red on `--pack-task --json`.
Pins moved: `runhintcheck`'s nine expected values lose their root prefix, which is the contract change, stated;
`testgatelegendbudgetcheck` 3,000 → 3,070 B for the conditional root sentence (measured 2,957 → 3,013 B on its own
fixture); `situshapecheck`'s own byte ratchets 200 → 360 and 140 → 220, because a ratchet that forbids a disclosure is
aimed at the wrong thing; `printf_parity.manifest` for `pack_task` and `help_all`, the latter regenerated from the
merged binary's own hash because neither side of the merge was the answer; the gate count 612 → 614; and
`docs/LIMITS.md` and `docs/TUNING.md` regenerated for the new row cap, which takes the tree's cap inventory from 210
to 211. `.ripwire_quality_acks` gains nine rows for `TestRunnerIndex`'s new root parameter and the eight sites that
pass it, and three more by symbol (`prLegendText`, `writeFlipHeader`, `runsAreRootRelative`); a duplication finding —
`situDirOf` was a 44-token copy of `siblift.h`'s `dirOf`, and `situStemOf` a fourth spelling of
`stripExt( baseNameOf( p ) )` — and a six-parameter new symbol were fixed rather than acked, and the default
`--quality-delta` reads `gating="0"` with no acks at all. ASan and LSan are clean on both fixtures and on `--situ`,
`--flags --flip` and the MCP twin, as are determinism and `xmllint --noout` on every changed verb
([#219](https://github.com/redhat-et/ripwire/pull/219)).

### Changed — the declined-call index no longer grows with calls × candidates

The call-graph build keeps, for every call the resolver declines to bind, the list of candidates it declined between,
so `--callers` and its neighbours can say how many calls were declined for a symbol. Those lists were stored once per
call, so the structure grew with calls × candidates: 27.9 M entries, 114 MB, on llvm-project, where most declined calls
repeat a handful of identical lists. Each distinct list is now stored once — keyed by its exact candidate sequence, an
FNV-1a hash picking the bucket and a hit confirmed by length and `memcmp` — as a CSR of distinct lists plus a call
count per list. On llvm-project that is 9,879 distinct lists and 62,359 entries: **368 KB instead of 114 MB**, with
peak footprint down about 145 MiB (median of 3 cold runs; the machine was loaded, so treat the timing and RSS figures
as indicative). Every count stays the same and the output is byte-identical to the merge base: 14 of 14 commands on
this repository, 14 of 14 on llvm-project, and `mcpclidiffcheck` 21 of 21. A uint32 offset overflow takes
`DEGRADED_PATH_ALERT`, and a new `verifyOffsetCsr` checks the list CSR beside `verifyCsr`. Gate:
`test/declinedlistcheck.sh`, 30 rows, of which a mutation that shares lists by name instead of by content fails 12
([#208](https://github.com/redhat-et/ripwire/pull/208)).

### Changed — the README and the docs

- **The call for help.** The pitch now comes before the release line and the call for help
  ([#167](https://github.com/redhat-et/ripwire/pull/167)). The call for help sits below the quality panel, where the
  reader has already seen the tool work ([#183](https://github.com/redhat-et/ripwire/pull/183)). It says what to run
  ([#175](https://github.com/redhat-et/ripwire/pull/175)) and offers a range of ways in: starter kits in
  `prompts/help-wanted/`, three open-ended prompts (a full audit, adding a language, and logging every gap while using
  ripwire on a real task), and open directions for research of your own
  ([#181](https://github.com/redhat-et/ripwire/pull/181)).
- **Who the output is for.** Under the four commands worth learning first, the README now says every command prints
  compact XML sized for an AI agent to read, and that human-readable output is on the roadmap
  ([#196](https://github.com/redhat-et/ripwire/pull/196)).
- **A solved kit says so.** `prompts/help-wanted/` lists `next-uses-bare-name` under Solved, crediting @antoleod's
  #182, and the README no longer counts the kits by hand. The reference guide's `--scip` sentence now names every
  path that refuses, not only a missing one ([#202](https://github.com/redhat-et/ripwire/pull/202)).
- **Just want to use it?** The top of the README now says what most people do: install it, then tell your agent to
  use it. The reference guide is marked as optional detail
  ([#204](https://github.com/redhat-et/ripwire/pull/204)).
- **The showcase deck is 33 slides.** The "What `--quality-delta` catches" slide is pulled until better examples replace
  it, and the rebuilt deck states the current gate count ([#205](https://github.com/redhat-et/ripwire/pull/205)).
- **What's new** had not changed since 2026-08-30 and did not mention 0.6.0. It now says what the release changed and
  points at this file, which is the record ([#177](https://github.com/redhat-et/ripwire/pull/177)).
- **The project's voice is written down.** `CONTRIBUTING.md` §7 says commit subjects state what was wrong and the number
  is the punchline. Where style and the honesty rules disagree, honesty wins
  ([#176](https://github.com/redhat-et/ripwire/pull/176)).
- **Lua `require`.** `docs/ARCHITECTURE.md` said a `require` is a plain call and a `.lua` file is never a dependency
  node. Since parser version 81, a string-literal `require` that resolves to exactly one file adds an edge, and the
  paragraph now states that contract ([#184](https://github.com/redhat-et/ripwire/pull/184)).

### Changed — the README gains a reference guide

A numbered, plain-language reference guide goes at the bottom of the README, with a pointer to it near the top. It
covers install, first use, command families, output format, the accuracy and disclosure rules, determinism, agent
integration, languages and limits. Every existing README line stays. Written by **@heliocipher**
([#168](https://github.com/redhat-et/ripwire/pull/168)), landed in [#192](https://github.com/redhat-et/ripwire/pull/192).

### Fixed — the reference guide said things the binary does not

@heliocipher's reference guide was verified claim by claim against a 0.6.0 build, and its flags held up: of the 82
`--` tokens it named, the 72 that are ripwire flags all exist and are spelled as it spells them (the other ten
belong to `cmake`, `xmllint`, `graphify`, `skills/install.sh`, or are anchor fragments). What it got wrong it
mostly inherited from this repository.
**"Dynamic dispatch contributes no edge"** was the opposite of the truth — a virtual call emits one edge per
candidate in the receiver's inheritance cone, each `prov="split"` and counted in `amb=`; a four-class fixture
returns three edges, not zero, with CHA-lite correctly dropping the same-name method of the unrelated class. The
honesty section was understating the tool, which costs a reader's trust the way overstating it does.
**`MSVC 19.36+`** was offered as a supported compiler beside an operating-system row naming only macOS and Linux;
it is not a target, and the row now points Windows users at WSL2. **"18 task-shaped skill files"** was one of three
defensible counts of one directory — 17 routable (`skills/*/SKILL.md`), 18 `SKILL.md` files in all
(`skills/hermes/` holds a Hermes-native one), 16 activated for every agent (`ripwire-opt-remarks` carries
`audience: contributor`) — and the README stated two of them, neither labelled. **"208 compile-time caps"** is 210
by `docs/limits_build.py`'s own derivation from `src/`. **"Directory symlinks are not followed"** understated the
limit: no symlink is followed, and a symlinked source file is not indexed at all, so a tree that reaches its
sources through links reads as if they were not there. **Exit code 2 was missing** from the exit-code table, which
is the one a CI script most needs — a policy gate fired (`--arch`, `--scan-skill`, `--quality-delta`), not an
unknown failure. And one sentence sent a reader to `--scan-skills` to check a single file, which is the directory
verb; the file verb is `--scan-skill=FILE`.

Unstated, and now stated: `git` is a runtime dependency for the history-backed verbs, which refuse with exit 1 and
a named reason rather than answering thin — `--map-diff` and `--rank-by=churn` answer and disclose the uniform
fallback, `--dmm` and `--pr-context` return an explicit unavailable row. A git URL as the root is the one thing
that touches the network. The write verbs return a receipt — region, `blob_sha`, contract check, tests to run —
so an agent never re-reads the file, and their payload is a whole definition, signature included, not a braced
body. Test coverage is read from call edges out of indexed test symbols, so a shell suite that runs a built binary
as a subprocess is invisible to it (`harness=script`, `reaches=0`) — which is this repository's own shape. `--json`
is an allow-list of nine verbs. `--quality-panel` has a `strict` preset that drops the two families which reshuffle
on unchanged code. Several verbs stay single-root in a multi-root run. Section 3.2 now splits by why a reader is
there — `scripts/pgobuild.sh` for a binary to use, the plain tree for work on the tool — and scopes the
`NDEBUG`/`DEGRADED_PATH_ALERT` warning to the development tree, where it belongs.

`--replace-symbol-body`'s one-line `--help` summary said it replaces a definition's *body*. It replaces the whole
definition, signature included, as its own long help already said and as both insert verbs say. An agent that
believed the summary sent a braced body and deleted the signature — disclosed in the receipt as
`post_check_unavailable`, not refused.

`test/readmedriftcheck.sh` gains three arms, so these counts cannot drift again: **(J)** the skills count, pinned to
the routable set and to the install fold's "sixteen of the seventeen"; **(K)** the `--json` allow-list, harvested
from `--help=--json` and required to match the guide in both directions, so a verb that gains `--json` support fails
the gate until the guide is updated; **(L)** the cap inventory, pinned to `docs/limits_build.py`'s derivation. Each
carries its own mutation control. Arm **(B)** took `head -1`, and so pinned one of the *two* sites stating the flag
count — the reference guide's copy had been free to drift since it was written; it now checks every site and names
the line that disagrees. `CONTRIBUTING.md` gains the rule those arms encode — an advertised count is an enumeration,
and if a set can be counted more than one way the prose must say which set — and the stale-object build hazard,
which until now lived only in `CLAUDE.md` ([#217](https://github.com/redhat-et/ripwire/pull/217)).

### Changed — published captures withhold the rename rows from the project's own history

The naming-calibration demo in the showcase captures and in `docs/COMMANDS.md` no longer reprints the rename rows from
the project's own renaming. Each withheld block is replaced by one line that says how many rows it withheld
([#193](https://github.com/redhat-et/ripwire/pull/193)).

### Changed — CI, the gate harness and internals, with no change to output

None of this changes the binary's output.

**The gate harness.**
- **A passing arm can no longer print FAIL.** Gates reported with `A && ok || no`, where `ok` is a `printf`. A blocked
  write to a full pipe can be interrupted by SIGCHLD and fail with EINTR, and the `||` then printed FAIL for an arm whose
  condition held. That happened on a macOS CI shard for #126. `ok()` now always returns 0 and records a failed write as a
  failure of its own. Every single-line site of that shape becomes an `if`/`else`: 1,782 sites on the base commit, as
  counted by `test/gateexitcheck.sh` arm (G2)'s scanner. `test/pargates.py` captures each gate into a regular file,
  where a write never blocks ([#142](https://github.com/redhat-et/ripwire/pull/142)).
- **`dispatchordercheck`** compared two runs of `--whereis`, which scans every branch of the repository around its
  fixture. A branch created between the two runs changed the answer. The gate now builds a private repository for its
  fixture ([#186](https://github.com/redhat-et/ripwire/pull/186)).
- **`pagingsweepcheck`** compared two cold `--whereis` runs that read the repository's shared ref namespace, so a
  branch created by anything else between the runs failed the gate. Those arms now run on the gate's own fixture
  ([#206](https://github.com/redhat-et/ripwire/pull/206)).
- **Three `--listen` gates share one HTTP client**, `test/lib/gatehttp.sh`. Readiness is an answered request, every
  request has a deadline, and a missing answer is its own FAIL rather than a verdict about the server. A server still
  warming up on a loaded macOS runner had read as "transports DIFFER"
  ([#188](https://github.com/redhat-et/ripwire/pull/188)).
- **The public-tree check reads decks, not just text.** A private pre-release name had reached public files — prompt
  text, an error message, a grader regex, docstring examples, `docs/EVALS.md`, three `src/` comments and six gates —
  and was fixed forward, with history left alone. `ripwirepubliccheck` arm 1b now stores only the SHA-256 and the length
  of the lowercase token, scans every tracked text file and every tracked deck (a deck it cannot read FAILS the arm),
  and prints `path:line` only, so a red run's log does not republish what it is looking for. Other command names for
  the agent-loop instrument come from `AGENTLOOP_TOOL_ALIASES`; the grade header and the grader's audit summary state how many
  aliases are in force, never the names. The `release` CI job installs `pdftotext` for the deck extractor. Red first:
  run against the merge base's checkout the arm fails with 36 locations in 13 files
  ([#209](https://github.com/redhat-et/ripwire/pull/209)).

### Changed — `mcpremotecheck` moves to the shared HTTP client

The last `--listen` gate that still had its own HTTP client gets the same deadlines and no-answer FAILs. Against a
listener that stalled, it had hung. Against one that died, it had judged the silence as verdicts
([#194](https://github.com/redhat-et/ripwire/pull/194)).

### Changed — aliasing contracts, checked in debug and read by the optimizer in release

**`VERIFY_NO_ALIAS` is an optimizer fact in release, not an inert assume.** `src/infra/Diagnostics.h` §6's macro now
expands to `__builtin_assume_separate_storage` under `NDEBUG` on clang 17 and later (`__has_builtin`-guarded,
`( (void)0 )` elsewhere), beside the debug check, so codegen matches `__restrict__` on the parameters: the gate's
`out=a; out+=b; out+=a;` arm goes 10 → 6 instructions on arm64. The previous
`__builtin_assume( &a != &b )` form was never consumed by alias analysis, so it was a debug check that promised an
optimization it did not deliver. The promise is scoped honestly to the shipped binaries: the macOS x64 release binary
consumes it fully, the macOS arm64 binary — AppleClang 16, which is LLVM 17 — consumes it for scalar accesses only,
because BasicAA reads the bundle there only with the `-mllvm -basic-aa-separate-storage` flag CMake now probes for and
passes — to our targets and to the ld64 link under LTO — that switch being `cl::init(false)` in LLVM 17 (AppleClang 16
/ Xcode 16.2: the macos-14 CI runners and the macos-arm64 release leg) and true from LLVM 18, and even then LLVM 17
does not carry it into loop vectorization (fixed upstream in LLVM 18); the Linux release binaries, built with GCC,
keep the debug check alone. A new `VERIFY_NO_ALIAS_BUF` is the form for two owning
containers, where the promise has to land on the buffer rather than the object; views that can share one allocation are
refused at compile time. `test/noaliascheck.sh`, eight arms red against the old definition, compiles the real slice three ways with a `=false`
negative control and a cross-check against the cached CMake probe, and WARNs, naming the compiler and the upstream issue, where the loop
path is not consumed ([#200](https://github.com/redhat-et/ripwire/pull/200)).

**Twenty-one functions state the contract at entry.** Fifteen functions whose two-or-more same-element-type
out-parameters would silently mis-compute or invalidate an iterator if a caller passed the same object twice now say so
at entry and abort on it in debug builds ([#201](https://github.com/redhat-et/ripwire/pull/201)); the last six —
`splitNoteTail` (`src/notes.h`), `takeAckNamedToken` and `computeDelta` (`src/quality.h`), `waterFillRecallShares`
(`src/recall.h`), `markCandidateFilesIncludingDecl` (`src/graph.h`) and `partitionByScope` (`src/verbs_quality.h`) —
complete the audit's apply list ([#211](https://github.com/redhat-et/ripwire/pull/211)), `computeDelta` with a
null-safe `VERIFY_TEXT` rather than the object form, because both of its out-pointers default to null. These are correctness contracts, not a
performance claim: for the object form the promise measured no codegen change, because it says nothing about a
container's heap buffer. One function is the tree's only codegen row — `waterFillRecallShares` in `src/recall.h` reads
`demand[i]` while writing `alloc[i]` and never resizes either, so it takes the buffer form: release codegen **309 → 301
instructions** under the build's own flags.

**House rule, with a finding behind it.** `CONTRIBUTING.md` now requires the `__restrict__` spelling. On macOS,
`<sys/cdefs.h>` defines `__restrict` to nothing in every C++ translation unit, because `__STDC_VERSION__` is undefined
there, so any `__restrict` after a libc include was silently a no-op. Ripwire had none in `src/`, so this is a rule
rather than a fix ([#199](https://github.com/redhat-et/ripwire/pull/199)).

### Fixed — a C++ header selector answered with definitions it could not tie to that header (`unproven_defs=`)

A `file:name` selector that names only declarations is widened to the definitions they stand for. The candidate test
compared the name and `Symbol::scope`, the immediately enclosing class or namespace with namespaces dropped. So `a::Store`
and `b::Store` compared equal, and for a free function the test was the name alone. `--callers=a/Store.h:putObject`
answered `count="1"` for a caller in `b/Store.cpp`. `--callers=api.h:helper` counted two callers of different
internal-linkage `helper`s, in files that never include `api.h`. The true count for both is zero, and both answers
carried `counts_floor="1"`, a floor above the truth.

A candidate definition is now kept only when its file is a declaration file or includes one. The include is resolved
path-precisely, never by basename, and a definition the proof cannot tie to the header is not widened to
([#173](https://github.com/redhat-et/ripwire/pull/173)). What the proof drops is counted, not left silent. `--callers` and
`--callees` carry `unproven_defs=` (#173). So do `--impact`, `--safe-delete` and `--path`, and MCP `impact` and
`path_between`. Those verbs had answered from the declaration alone, which has no call edges: `--safe-delete=api.h:helper`
printed `risk="none-found"`. Its legend now says that `risk="none-found"` beside `unproven_defs=` is an incomplete read,
never a sign that the name can go ([#190](https://github.com/redhat-et/ripwire/pull/190)).

On ripwire's own tree, over every `file:name` selector whose selection is all declarations, 89 of 4,322 answers shrank
between the binaries before and after #173, and none grew. Two losses are known, and `unproven_defs=` counts both. A
`.cu`/`.cuh` include does not resolve for this proof, so a CUDA header selector can under-count. A body kept in a section
file that is pasted into a translation unit without including the declaring header is no longer reached; ripwire's own
`src/ingest.h:astQuery` is one. The one over-retention this left — an internal-linkage definition kept for another file's declaration of the same
name — is fixed below (#216). Gate: `test/decltodefcheck.sh`.

### Fixed — the remaining silent zeros from a declaration selector

`--uses`, `--mentions`, `--verify` and `--affected` answered a header selector from the declaration alone when the proof
dropped its definitions: `--uses` printed `count="0"`, `--mentions` `docs="0"`, `--affected` `tests="0"`, and
`--verify`'s `uses()`, `unused()`, `calls()` and `reaches()` answered from one declaration. Each now carries
`unproven_defs=` with a clause worded for that verb; `--verify` keeps its three verdicts and says that `not-established`
beside `unproven_defs=` is an incomplete read ([#195](https://github.com/redhat-et/ripwire/pull/195)).

### Fixed — every verb that resolves a focus now says what it could not prove, and a declaration yields to its definition

#173 stopped a `file:name` selector from following a declaration to a definition it could not prove belongs to it, and
#190 and #195 disclosed that drop on the graph and listing verbs. The verbs that resolve a *focus* symbol were still
silent. `resolveFocus` now returns the count, and the answer's root carries `unproven_defs="K"` — absent at zero — with
a per-verb clause: on `--edit-check` (including `--dry-run` and the MCP twin with and without `new_body`) it sits beside
`incompatible=` and says that an `incompatible="0"` next to it is an incomplete read, not a sign the edit is safe; on
`--lego`, `--connect` (summed over its terminals), `--around`, `--slice` and their MCP twins; on the `<ctx>` root
`--expand` and `--outline` share, summed in every serving mode and charged in `est_tokens`; beside `--owners`' `defs=`;
as a JSON key on MCP `fetch_body`; and as its own stderr line on `--note-add`.

A C/C++ declaration without a body also now yields the focus to the lowest-id C/C++ definition with a body in the same
scope. The rule is scoped on purpose: measured over all 12,996 names in this repository, an unscoped "prefer a body"
moved 132 picks, 69 of them wrongly (Python and JSON keys, TypeScript overloads, jumps between languages), while the
scoped rule moves 54, each a C/C++ declaration to its own definition. Four legend sentences that called the pick "the
lowest-id one" are reworded. `test/decltodefcheck.sh` grew 36 rows red on the merge base for the disclosure, 18 more for
the narrower sites and 9 for the focus pick; 212 of 212 pass now, also under ASan
([#210](https://github.com/redhat-et/ripwire/pull/210)).

### Fixed — the callers answer's `next=` pointed at a `--uses` call that could not list the declined site

0.6.0 gave `--callers` a `declined_calls=` count and a `next=` pointer to the `--uses` call that shows those call sites.
On a bare name the pointer landed. On a narrowed selector (`file:name`, `@FILE:LINE`, a canonical id or `Scope::name`) it
repeated the narrowed selector. That `--uses` answer keeps only sites that resolve to the chosen definition, and a
declined call resolves to none, so a reader who followed the pointer got `count="0"`.

When a narrowed selector has declined calls, `next=` now names the bare-name `--uses` call in the XML, columnar and MCP
`find_referencing_symbols` answers. The callers legend says that list includes sites bound to other same-named
definitions. Every other answer keeps its bytes. `test/declinecheck.sh` arm (E) follows the pointer and requires the
declined site to appear, across Java, C++, Python and Rust spellings.

Contributed by **@antoleod**, in their first contribution to ripwire
([#182](https://github.com/redhat-et/ripwire/pull/182)), closing [#158](https://github.com/redhat-et/ripwire/issues/158).

### Fixed — a `#if 0` block stopped serving calls in 0.6.0 and went on serving every other role

0.6.0 stopped serving CALL sites from preprocessor-dead ranges and left every other role serving them. A `role="write"`
inside `#if 0` is a write that cannot compile, and `--uses` counted it: on the gate's fixture `--uses=Owner.field`
answered `count="4"` carrying `counts_floor="1"` where the truth is 2 — a floor above the truth, which is the contract's
own failure direction. Reads, writes, both emitters of `role="import"` (`using ns::x;` and `#include`, the second living
in a code path #62 never touched), `extends`, types, the `#else` of `#if 1` and of `#if 0`, variable-to-type bindings and
dead definitions are all excluded now. The question is asked once per file and answered once per record, keyed on the
record's own site byte, rather than as five more `continue`s.

Excluding dead *definitions* was the invasive half, so it was measured: on llvm-project (8,861 C-family files, 381,811
symbols) it is **−14 symbols, +3 edges, −16 declined**, with `ambiguous`, `unresolved`, `est_tokens`,
`extent_suspect_syms` and the unindexed roll-up all unchanged; every dropped row is a real `#if 0` definition, among them
five in `Descriptor.cpp` that LLVM itself comments as not needed, whose names had been minting `overloads="2"` against a
live macro. Ripwire's own map is byte-identical to the base, and user CPU on llvm is 59.1 s against 59.4 s, interleaved.
The honest costs: `--grep` is unchanged (text inside `#if 0` is still findable, hit rows byte-identical), and
`--expand=deadType` now refuses with a suggestion rather than serving a dead body. A residual is disclosed rather than
left to be found: the FFI `BindingAlias` records carry no site byte, so an `extern "C"` block inside `#if 0` still
contributes its aliases; giving them one is a record-shape change this defect does not earn. `kParserVer` 93 → 94 with
its mirror; `kCacheVersion` stays 21, because no record gains or loses a field — only which records are extracted. Gate:
`test/ppdeadrolescheck.sh`, written and run red against the unmodified base binary first
([#172](https://github.com/redhat-et/ripwire/pull/172)).

### Fixed — attributes an answer printed with no definition (`graph_unindexed=`, `--legend=compact`)

`graph_unindexed=` counts the files no grammar in this build can read. It shipped in 0.6.0 on roots whose legend never
defined it: `--lego` on the CLI and over MCP, `--verify` and `--nonlocal-state`, whose legends are fixed text rather
than the shared builders. `--legend=compact` rebuilds its definitions from a table of terms, and that table had no row
for it, so it was also undefined under compact on every XML verb that can carry it except `--connect`. Both now define it
([#169](https://github.com/redhat-et/ripwire/pull/169)).

The same table had no row for `declined_calls=`, `unproven_defs=`, `bodyless_defs=`, the `--uses=Owner.field` member
form, the multi-root `<root label= p=>` table, `--lego`'s `methods="0" caveat=`, or `pr_iters=` on every PageRank root.
It also lacked the map-header fields whose `hdr:` definitions compact strips, among them `declined=`, `external=`,
`max_tokens=` and `over_ceiling=`, plus `--around`'s `defs=` and `--rank-by`'s `rank_by=` and `window=`. Each now has a
term that prints only when its attribute is present. Answers that carry these attributes can exceed the dialect's nominal
400 B; the alternative was a number with no definition ([#185](https://github.com/redhat-et/ripwire/pull/185)).

### Fixed — twelve more attributes get compact definitions

Under `--legend=compact`, these attributes now carry definitions: `--tree`'s `files=`; `--zoom`'s `symbols=`,
`isolated=`, `top_modules=` and `levels_shown=`; a cut `<module>`'s `children=`; churn-decay's `<recent of=>` and
`<rc age_d= w=>`; and the map rows' `lpin=`, `overloads=` and `prov=` ([#189](https://github.com/redhat-et/ripwire/pull/189)).

### Fixed — compact definitions that did not fit the byte pins, so the pins now follow the definitions

Several answers still printed attributes their compact legend never defined: the map header's own counts, `--impact`'s
blast-radius counts, `--safe-delete`'s verdict fields, the `--communities` and `--community` structure counts, and
`tested="1"` rows on `--callers`, `--callees`, `--impact` and MCP `impact`. Defining them honestly did not fit the
dialect's single 400 B per-answer pin, so the pins follow the definitions: each compact schema is pinned at its measured
size rounded up to the next 10 B plus 10 B — map 810 B (measured 799), communities 820 B (807), map-diff 800 B (789),
impact 780 B (770), community 730 B (719), safe-delete 720 B (708), around 720 B (707), metrics 720 B (702),
pack-signatures 680 B (663), pack-top-n 660 B (649) and query 630 B (611), with the remaining schemas between 140 B and
410 B. The ten-verb loop total goes from 4,100 B to 4,900 B (measured 4,849 B), and MCP `impact` is pinned at 780 B.

A read-only review of every definition against the code that emits it found three readings that were wrong, all
corrected here: `--safe-delete`'s `t=`/`p=` name the lowest-id *match*, not the lowest-id definition, because a
header-qualified selector keeps its declarations; `changed=` counts only indexed git-changed files and is 0 when git
cannot be read; and `--communities`' `bridges=` counts community pairs, one-symbol communities included.

`--help` no longer claims a fixed "≤400 B legend": it states the per-verb sizes and, restated from measurement, a saving
of "at least 45%" on a small `--callers`/`--uses`/`--impact`/`--affected` answer, down from "at least 50%" — the measured
savings are 65.91%, 63.79%, 46.17% and 64.73%, a per-call drop of 2.8–5.8 KB. Byte identity was checked against the
pre-change binary: 39 of 40 non-compact answers are identical (`--help=all` is the only difference), and all 26 compact
answers keep every row and data comment byte-identical, with only legend text changing. Left for a follow-up:
`tested="1"` is still undefined under compact on `--pack-task`'s `<d>` body rows and in the columnar `tested` column
([#203](https://github.com/redhat-et/ripwire/pull/203)).

### Fixed — `--for`'s `over_ceiling=` verdict could be written by the task text, and rung zero dropped legend clauses without a word

`--for` found which ceiling-ladder rung had fired by searching the finished header for that rung's note, and the header
also carries the task echo verbatim. A task containing that note got `over_ceiling="1"` on a document well inside its
budget. Since 0.6.0 the same search also ran inside the fit predicate, where matching text could push a real bundle down
the ladder. The ladder now returns the rung it took, so no task text reaches the verdict.

Rung zero, which drops legend clauses to fit, dropped the definitions of `confidence=`, `margin_pct=` and
`budget_tokens=` while keeping the attributes. It now names each attribute whose definition it drops, in the same shape
as the rungs above it. `test/ceilingverdictcheck.sh` is new, and `test/legendcoveragecheck.sh` gains a budgeted `--for`
row ([#174](https://github.com/redhat-et/ripwire/pull/174)).

### Fixed — `--connect`'s `est_tokens=` left out a legend clause it printed

When a file in the tree was unindexed, `--connect` added the `graph_unindexed=` attribute and a legend comment defining
it, but charged only the attribute to its estimate. `est_tokens=`, the `--max-tokens` fit and `over_ceiling=` therefore
measured a smaller document than the one emitted. The v0.6.0 binary was run on a matched pair of corpora, identical except
for one unreadable file: the document grew by 205 B while `est_tokens=` stayed at 1,068. The fixed binary reads 1,142.
The clause is now one named string that both the charge and the write read
([#171](https://github.com/redhat-et/ripwire/pull/171)).

In the same change, `skills/install.sh --hermes` links only the `ripwire-*` directories under `skills/hermes/`, as its
other two loops already did. The only directory there today is `ripwire-repo-map`, so no install changes.

### Fixed — `--help` left out twelve flag rows, and `--help=--FLAG` said they did not exist

`--help`'s one-line tier treats a row indented four spaces as a flag and anything else as prose. Twelve rows in
`src/cli.h` were indented six, so the flags on them were culled from `--help`, among them `--and`, `--not`, `--scope`,
`--partition`, `--dry-run`, `--apply` and `--grep-context`. `--help=--and` answered that it matched no flag, while
telling the reader that `--help` lists every row. The flags themselves always worked.

The rows now sit at four spaces, and the `docs/COMMANDS.md` generator accepts exactly what the binary accepts.
`test/helpbudgetcheck.sh` arm (K) takes its population from the flags `parseArgs` accepts, so a new flag missing from
`--help` turns it red. The eleven flags still unadvertised are listed in the gate, each with a reason
([#170](https://github.com/redhat-et/ripwire/pull/170)).

### Fixed — a client that dropped a large reply killed the `--listen` server

`ripwire --listen` wrote replies with a plain `send()`, and nothing handled SIGPIPE. A client that closed its connection
before reading a reply larger than the socket send buffer raised SIGPIPE, which ended the server, and every later client
was refused. Each socket now suppresses the signal, with `MSG_NOSIGNAL` on Linux and `SO_NOSIGPIPE` on macOS, so the
failed send drops that one connection and the server keeps serving. The CLI's stdout behaviour is unchanged.
`test/mcpremotecheck.sh` drops a client three ways against a reply larger than 4 MiB, and requires the same listener to
answer the next request ([#187](https://github.com/redhat-et/ripwire/pull/187)).

### Fixed — `--scip` ignored every index scip-java writes

ripwire read only SCIP's deprecated `Occurrence.range` field. scip-java writes the `typed_range` form instead
(`single_line_range` / `multi_line_range`), so no occurrence ever joined, and `--scip` produced output byte-identical to a run
without it. The reader now takes the typed form, and it outranks a deprecated `range` on the same occurrence whichever
arrives first, as `scip.proto` asks. On spring-petclinic the overlay went from no matches to 79% of occurrences, and
`graph_ambiguous` from 6 to 0. `test/scipcheck.sh` arm 10 re-encodes its fixture in the typed form (red on the old
reader), and arm 10b proves the fixture cannot pass without the typed fields. Contributed by **@dpunosevac**, in their
first contribution to ripwire ([#198](https://github.com/redhat-et/ripwire/pull/198)).

### Fixed — three surfaces said a missing `--scip` index degrades; it refuses

Since v0.4.0, a `--scip` path that cannot be opened exits 1 and serves no map, while a corrupt index still warns on
stderr and proceeds name-based. The `--scip` help row, the README and `skills/ripwire-navigate/SKILL.md` said a missing
index degrades and never fails. They now say what the binary does
([#184](https://github.com/redhat-et/ripwire/pull/184)).

### Fixed — `--scip` refuses a path that is not a regular index file

A `--scip` path that is empty, a directory, a FIFO or a device now exits 1, as a missing one does, instead of serving
the name-based map at exit 0. A FIFO had hung the run. The index is opened again when it is loaded, and that open no
longer blocks either: a path replaced after the check by something that is not a regular file degrades with the usual
warning ([#197](https://github.com/redhat-et/ripwire/pull/197)).

### Fixed — a symlink at a sidecar name is refused, not written through

`.ripwire_notes`, `.ripwire_quality_baseline` and `.ripwire_arch_baseline` are opened for writing with `O_NOFOLLOW`. When
one of those names is a symbolic link, the link is not followed: the write exits 1 with a message on stderr, and the link
is left in place. A sidecar that is a regular file is written as before. The arch baseline writer now also reports a
failed write, where before it could report success ([#178](https://github.com/redhat-et/ripwire/pull/178)).

### Fixed — a symlink at a sidecar name is not read through

The readers of the same three sidecars open them with `O_NOFOLLOW` too, so a symlink at a sidecar name is refused on
read as well as on write. Anything at a sidecar name that is not a regular file, a FIFO for example, is refused
instead of waited on, and a sidecar is emptied for rewriting only after it has been confirmed to be a regular file
([#191](https://github.com/redhat-et/ripwire/pull/191)).

### Fixed — the crawl does not follow a symlink out of its root

A symlink inside the crawl root whose target resolves outside that root is not followed. Every walk that reads files
skips it and lists it on `--skipped` in a new `escaped` class. It is counted as `escaped_root=` on the map header (XML and
JSON), `<flags>` and `<doc-drift>`. The attribute is absent at zero, so a tree without such a link gives byte-identical
output, and a symlink that stays inside its root is indexed as before
([#179](https://github.com/redhat-et/ripwire/pull/179)).

### Fixed — the suite's `skip=` count stopped depending on where the checkout lives

`test/pargates.py` decided whether a gate had SKIPPED — ran, but proved nothing — from the word SKIP in the first
400 CHARACTERS of its transcript, and 515 of the 628 transcripts of one full run open with a banner naming the
checkout's own absolute paths. The same commit and binary reported `skip=2` from a 137-character checkout and
`skip=3` from a 38-character one; 24 gates print a skip marker downstream of an absolute-root mention, the nearest a
real standing skip declared 145 characters in. The rule is written down instead of measured in bytes: **a gate that
proves nothing says so before it claims anything** — the first verdict marker decides, and a SKIP after a PASS or
FAIL is an arm-level skip inside a gate that did prove something. Replayed over those 628 transcripts, the new rule
and the old one disagree on ZERO gates. One direction is newly open and disclosed rather than left to be found: a
whole-gate skip printing a PASS row above its skip marker would read as a pass, which no gate does today and nothing
yet enforces. Gate: `test/skipclassifycheck.sh`, driving the real harness over one byte-identical probe from two
corpus roots about 130 characters apart, with `test/gateexitcheck.sh` arm (D) as the gate side of the contract
([#223](https://github.com/redhat-et/ripwire/pull/223)).

### Fixed — a relative command with no anchor, and a cap that bounded the answer and not the work

Fifteen defects from four review rounds over the three `--situ` entries above. **A `run=` is a command, and its path
comes from the corpus:** the runner verb and the path were concatenated, so an unusual but legal filename could
produce a `run=` that does not parse as the single command it presents itself as. The path is now always one shell
argument — quoted whenever it is not provably safe, by an allowlist that quotes any unenumerated byte, and preceded
by an option terminator so no path reaches an interpreter as an option. Every tracked path here is inside the
allowlist, measured at 0 outside it, so the emitted bytes are unchanged on every real corpus and no pin moved;
`test/runhintcheck.sh` arms (5) and (6) EXECUTE the emitted command in a scratch corpus, each with the pre-fix
spelling as its control. **A relative command is only as good as its anchor:** four surfaces spelled a path or a
command relative to a root they never declared — the shared run-hint clause on a multi-root run, `--flags --flip`,
the MCP edit receipt, and `--help` — and the one relativizer every `p=`/`uri=` emitter routes through returned early
on a leading `./` and matched a prefix only when the next byte was `/`, which the filesystem root can never satisfy.
`test/rootrelemitcheck.sh` arm 9b prints one command for six root spellings and executes each; `test/sarifcheck.sh`
arm 11 drives the function over 22 rows, 4 red before. **A cap bounded the answer and not the work:** the new
lexical-siblings block compared every unchanged indexed file against every changed path with the row cap applied
only after collection, O( (F + U) × C ). Changed paths are indexed by directory once into a sorted vector searched
with `lower_bound` (no `std::map`), the predicate still called on the narrowed range. Interleaved, best of 5, `-O2`
with the shipped flags, on a host at load 38 on 18 cores — so the absolutes are upper bounds and the ratio is the
measurement — llvm-project `4d5358b1` (8,856 paths, C=2,000) reads 333 ms → 11.6 ms and golang/go (12,555 paths)
449 ms → 42.8 ms, its second pass 1,005 ms → 136.5 ms; that llvm population grown to `docs/EVALS.md`'s 182,555-file
rung, synthetic in SIZE only, reads 9.10 s → 22.6 ms. Emitted rows are byte-identical on all nine rungs (1,413
rows). The same block paged on another section's offset and went silent on an empty candidate list — a silent zero,
which `docs/METHODOLOGY.md` §9 forbids — and four disclosures compressed into attributes kept a short reading each,
since `--situ` has no legend to look a name up in. Measured with `wc -c` against this lane's base binary:
`--situ=src/graph.h` 4,448 → 2,955 B and `--test-gate=src/testmap.h` 5,455 → 5,247 B. Gates:
`test/situshapecheck.sh` (17 rows red on that base binary), `rootrelemitcheck`, `runhintcheck`,
`test/receiptpostcheck.sh` (18). The lane's own sibling-row cap makes the cap inventory 211, republished by its
generators rather than edited ([#219](https://github.com/redhat-et/ripwire/pull/219)).

### Fixed — two generated documents, a scoped run's ranking notice, and a tilde no shell expands

Three from the scoped-recency lane's own review. **`docs/COMMANDS.md`'s generated table of contents minted anchors
by substituting a hyphen for every run of non-alphanumeric characters where the renderer DELETES that punctuation**,
so all 169 links resolved to nothing and had done since the document was first generated; markdownlint's MD051 had
been reporting it 28 times on one line. The generator states the renderer's own rule now and assigns anchors in
emission order, audited by `test/docscommandscheck.sh` arm (J), which restates that rule rather than importing the
generator's — a gate that asks the generator what an anchor should be agrees with its mistake. `docs/TUNING.md`,
likewise generated, asserted a sum instead of deriving one ("`112 + 12` accounts for the 128 NAMES" is 124) in the
one paragraph whose subject is that quoting a wrong pair would be wrong in both halves at once; recounted from the
data its table is built from, `src/` declares 129 caps under 128 distinct names, 111 tunable, 12 that must stay
`constexpr` and 5 declared after the sweep was frozen, and `capsweep.py emit` now REFUSES to render a partition that
does not add up. **A scoped run said its ranking fell back, having run no ranking:** under `--in=DIR` the
uniform-prior notice was false three ways at once — nothing is ranked on a scoped run (the rank vector is
zero-filled, which is why the header carries no `pr_iters=`), "this map" named a document the run does not contain
since the map IS the stub, and the comparison it offered is refused beside `--in`. **And a pasteable `next=` quoted
a tilde no shell expands:** `nextFlag` quoted any value whose first character is `~` whether or not a flag name
preceded it, so a run under `--exclude=~tmp` published `--exclude=&apos;~tmp&apos;` against an expansion that cannot
happen — the guard is "word-initial AND no flag name" now, a narrowing rather than a deletion. The worse half was
the gate, which pinned the corrupted form and explained it with a belief about POSIX that is wrong twice over; a gate
that pins a false belief defends the bug against the next person to fix it, so the explanation is deleted rather
than reworded and the measured rule stated in its place. Gates: `test/recentscopecheck.sh` 13e/13f,
`test/capsweepcheck.sh` (C), `test/nextverbcheck.sh` (9)
([#212](https://github.com/redhat-et/ripwire/pull/212)).

### Fixed — an unmeasured `est_tokens` said nothing, a no-throw contract threw, and two test-row readers went quiet

Six defects from one review, each a surface that was silently wrong rather than loudly broken. **`--pr-context`
shipped a modelled `est_tokens` with no disclosure:** when a trim level's measurement render fails it returns an
empty body, the ladder priced that empty body and the root printed the price, while the verb correctly streamed the
untrimmed floor. The only signal was a `DEGRADED_PATH_ALERT`, which is `do {} while (0)` under `NDEBUG`, so the
binary a user installs published a modelled number with nothing saying so (non-negotiable #3). The bytes were never
the bug and are unchanged: `truncated=` carries `;est-unmeasured`, defined in the legend in the same voice as
`budget-floor-exceeded`, which takes the tail's worst case from 248 B to 263 B and its buffer from `tail[256]` —
seven bytes of margin, as `test/fixedbufsweep.sh` had warned in terms — to `tail[320]`. **`renderToString`'s
no-throw contract had a throwing last statement:** the one allocation on the success path sat outside the handler, so
a `std::bad_alloc` escaped a function documented to return `ok == false` and jumped the `free()` below it. It is
caught in its own handler now and the buffer is released exactly once on every path, proved by a fault switch in
`test/prcontextcheck.sh` arm (G), red on the parent commit and honest in both build flavours. **The shared test-row
reader scanned arbitrarily far forward for a `[`**, so a `null` field's answer came out of the NEXT field's array at
exit 0 where its docstring promised a parse error; the value is read adjacently now. And two `test/` path readers
had never been converted to that reader — one splitting every row on `,`, one matching single rows only and
returning the empty set on a two-row fixture ([#214](https://github.com/redhat-et/ripwire/pull/214)).

### Fixed — a ceiling priced in the wrong unit, two price lists for one comparison, and shapes that outlived their output

Fifteen findings from two review rounds of the short-id and compact-legend lane. **The ceiling was priced in the
wrong unit, and then stopped being a byte test at all.** `--for` and `--pack-task` tested their ceiling rungs at
`kMinBytesPerToken` (2.36) while `est_tokens=` prices the delivered document per kind — markup at 2.50, bodies at
3.80 — so a lens spent rungs against a ceiling it was not measured against and dropped legend definitions from
documents its own root reports as conformant. Measured on a five-symbol fixture at `--detail=1`: at every budget in
1069..1099 the kept document prices at `est_tokens="1069"` with no `over_ceiling=`, and the rung dropped all three
clauses anyway to deliver 715 — 354 tokens of headroom spent to buy nothing. The exact ceiling is the token
comparison itself now, asked once on the finished document; the allowance rungs stay byte-based, which is their
contract, and no tolerance was widened. Separately the 1.15 overshoot tolerance had gated the first free drop as
well, so a document 1–15% over budget shipped `over_ceiling="1"` with all three explanatory clauses riding; that
drop is now tried against the number the root promises. **Rung zero also stopped being byte-negative:** it removed
110–164 bytes of clauses and spliced a 161-byte note naming them, +51 bytes on a route-less compact answer, so the
candidate is built and compared and a drop that does not pay is not taken. **`--expand` chose its serving mode on
two different price lists:** the whole-file candidate was charged its raw bytes and its legend — no envelope, no root
attributes, no closing tag — so on a fixture whose symbol sits in an 864 B file the root said `reason="file 1100B
&lt; bundle 1193B"` over a document that came out 1,262 B, selecting and reporting the whole-file form while the
bundle it rejected was smaller. Both candidates are one document type now, priced by one function that charges the
whole served document and settles the self-referential `mode=`/`reason=` disclosure with the same ≤4-pass fixpoint
`est_tokens=` uses; `expandmodecheck` (4a)–(4d) assert that `reason=`'s own count equals `wc -c` of the delivered
document in all three modes and sweep seven paddings across the decision boundary. **Three surfaces answered in
shapes the tool no longer produces:** the MCP file page's hand-composed `route=`, `--expand`'s whole-file serving
printing a full canonical id inside a `<src p=>` that had just printed the path, and a benchmark keyed on the retired
`id=` that collapsed two same-named methods into one key. A merged callee row was charged `name+16` while printing
about four bytes, so a block of overloads wrote `capped="1"` over a listing that would have fit, and `l=` is sorted
rather than appended in rank order. The route hooks' command-word rule asked the shell to split a line, which never
separates a control operator from the word attached to it, so `true; ripwire .` read as not-a-call; it lexes the line
itself now, quote-aware, executing nothing. Four gates were enforcing or reporting the wrong thing — one matching map
rows by the retired spelling, checking zero rows and printing PASS; one holding a hand-typed verb list that made it
enforce a command the binary refuses; one counting two of three droppable clauses; one discarding every exit status
under `eval … || true` — and every compact-legend pin was re-derived from its own stated rule, which seven rows had
not been following. And the compact-legend policy was audited in the direction that matters for the first time: both
existing arms started from a command that already carried the flag, so a command that should carry it and does not
was invisible to the gate; seven spans across six skills are fixed, and the gate asks the binary both halves of the
question now. `docs/LINEAGE.md`'s unqualified "no network" names its one documented exception in the same round: a
git URL is shallow-cloned before it is mapped ([#215](https://github.com/redhat-et/ripwire/pull/215)).

### Fixed — a header's declaration no longer widens to an internal-linkage definition (parser version 96)

The decl-to-def widening behind every `file:name` selector (`--callers=api.h:helper`, `--impact`,
`--uses`, `--safe-delete`, the MCP twins) kept a same-named definition when its file `#include`d the
declaring header. That proof is per FILE, and a translation unit that includes `api.h` for its own
reasons may define an unrelated `helper` in an anonymous namespace or as a namespace-scope `static` —
an overload (`helper(double)` beside the declared `helper(int)`) compiles, and by name it was gathered
and served. Internal linkage makes a definition visible to its own translation unit alone, so no other
file's declaration can stand for it. Raised by CodeRabbit on #139 after merge, outside the diff.

Every C and C++ definition now carries a syntactic `internalLinkage` bit — inside an anonymous
`namespace { }` at any depth, or carrying a namespace-scope `static` (a class-scope `static` member has
external linkage and is not marked). The widening keeps such a definition only for a declaration in its
own file and otherwise counts it in `unproven_defs=`, so the reader still learns that same-named
definitions exist which no row covers; the bare-name selector still shows them, as the legend says.

Measured on the gate fixture (`test/decltodefcheck.sh` arm B2: a header, its defining `.cpp`, one real
caller, and two including TUs with an anonymous-namespace and a `static` overload): `api.h:helper`
answered `count="3"` on main where `api.cpp:helper` answered `count="1"`; it now answers `count="1"`
naming the one real caller, with `unproven_defs="2"`. On this repository at `1cf3086e` the default map
is byte-identical and none of the 11 header-qualified `--callers` selectors over `src/ingest.h`'s
declarations moved (the tree has no colliding internal-linkage overload). `kParserVer` 95 → 96 and
`kCacheVersion` 21 → 22 (the def record gains one byte) with `quality.h`'s mirrors in the same commit;
old caches are rejected and rebuilt
(@andriytyurnikov, [#216](https://github.com/redhat-et/ripwire/pull/216)).

### Planned for 0.6.2

- **A redone "What `--quality-delta` catches" slide.** It left the showcase deck in 0.6.1, and returns with stronger
  examples, each reproduced from a real repository.
- **Faster cold Elixir ingest.** Elixir parsing walks each node's ancestors to find its scope, and costs about three
  times the CPU of other languages; one top-down pass that keeps a scope stack should recover it.
- **Calls brought in by Elixir's `use`.** 0.6.1 counts them as unresolved, so the drop is disclosed; 0.6.2 aims to
  model `__using__` so they resolve.
- **Header selectors that know C++ namespaces.** `scope` drops the namespace chain, so a definition in a *different*
  namespace with the same name is still kept for a header's declaration; 0.6.1 closed the internal-linkage half of
  that over-retention (#216) and recording the chain itself is what closes the rest.
- **A full head-to-head, measured on a quiet machine.** Cold index time, per-query latency, peak memory
  and answer size in tokens for equivalent questions, each axis pre-registered with its corpus, method, N and medians,
  both versions named, and a reproducible harness published beside the result. Nothing from it is published until the
  run is done on a machine that is not doing anything else.
- **The same comparison with an agent in the loop.** Several agent sessions per task across the frozen retrieval
  questions, change-safety tasks, real merged PRs and a SWE-bench Verified subset, starting from a pilot sized against
  the pre-registered instruments. Every loss is traced, fixed and re-measured before any result is published, wins and
  losses both.
- **`--legend=compact` as the CLI default.** The agent surfaces ask for it in 0.6.1 and the bare CLI does not. Flipping
  the default moves a published contract, so it happens under a pre-registered terminality readout — does the compact
  answer still end the task in one call — rather than on a byte count.
- **`--for --in=DIR`.** `--in` scopes the churn-decay map in 0.6.1; the same scope belongs on the ranked bundle and on
  its widening page.
- **A hunk-seeded `--situ`.** `--situ` reads changed files; seeding it from the diff's hunks would let the blast radius
  start from the lines that moved rather than the files that contain them.
- **De-ranking test paths.** A ranked answer to a question about production code still spends rows on the tests that
  exercise it; the ranker should know the difference and say when it has applied it.
- **`install.sh` served as a release asset.** The one-line install command will fetch the installer from the latest
  release, next to its checksum, instead of from `main`.

## [0.6.0] — 2026-09-11

**Languages and integrations from outside the project, much faster on the largest trees, and answers that say where
they stop.** Outside contributors wrote the Kotlin support (@xCatG), the Dart support (@calvinchengx), the Hermes
installer mode and Hermes-native skill (@AnkitArya, @ashutoshsinghpr7), JavaScript and TypeScript default-import
resolution (@PollyBot13), `CLAUDE_CONFIG_DIR` support (@s0undt3ch) and the Ruby constant-dependency work
(@andriytyurnikov). Outside reports caught the tool being confidently wrong (@YogevKr, @mariadb-KyleHutchinson,
@snrmwg) and asked how to remove it (@luisdavim). Each is named below, beside the entry their work produced.

### Highlights

**Kotlin.** `.kt` files are indexed: classes, objects and companion objects, functions, calls, imports and
inheritance. Calls cross the Kotlin/Java boundary in both directions, and a reference reaches the other JVM language
only when its own defines no candidate of that name, so adding `.kt` files never moves a Java-only edge. nowinandroid
indexes to 1,850 symbols across 384 files, ktor to 19,906 across 2,527, and retrofit's `Response.java:body` keeps its
279 callers (@xCatG, [#126](https://github.com/redhat-et/ripwire/pull/126)).

**Dart.** The 23rd grammar. On flutter/packages (3,706 `.dart` files) it indexes 71,726 Dart symbols (@calvinchengx,
[#75](https://github.com/redhat-et/ripwire/pull/75), landed in
[#106](https://github.com/redhat-et/ripwire/pull/106)).

**Ruby: the dependencies a Rails application actually has.** A Zeitwerk application spells almost none of its
dependencies with `require`. 0.6.0 reads the ones it does use: superclass constants, `include`/`extend`/`prepend`,
`autoload`, and constant receivers such as `User.find` — the reference that makes the autoloader load the file, where
nothing else in the file says so (@andriytyurnikov, [#57](https://github.com/redhat-et/ripwire/pull/57),
[#65](https://github.com/redhat-et/ripwire/pull/65), and [#78](https://github.com/redhat-et/ripwire/pull/78) landed in
[#91](https://github.com/redhat-et/ripwire/pull/91)).

**Faster where it hurt.** Warm `--grep` on llvm-project falls from 159.7 s to 9.2 s, and the warm default map from
248 s to 10 s ([#83](https://github.com/redhat-et/ripwire/pull/83)). The cold parse on that tree drops from 194.1 s to
155.6 s of CPU ([#127](https://github.com/redhat-et/ripwire/pull/127),
[#130](https://github.com/redhat-et/ripwire/pull/130)), warm `--pack-task` on go from 8.13 s to 5.88 s, and a repeated
`--for` on llvm-project from 274 s to 26 s once the cache stopped evicting its own working root
([#127](https://github.com/redhat-et/ripwire/pull/127)).

**Answers that say where they stop.** A `std::`-qualified call no longer binds an in-repo definition, so memgraph's
`SafeString::move` goes from 2,107 false callers to 3 ([#134](https://github.com/redhat-et/ripwire/pull/134)). A call
the resolver declines to guess is counted and named instead of silently dropped: 65,516 of memgraph's 295,086 call
references ([#136](https://github.com/redhat-et/ripwire/pull/136)). A parse derailed by a member macro carries
`extent_suspect=` and leaves the `--hotspots` ranking, and a budgeted `--for` stops shipping past its allowance
without saying so ([#135](https://github.com/redhat-et/ripwire/pull/135)). And YAML parses the same on aarch64 Linux
as everywhere else ([#140](https://github.com/redhat-et/ripwire/pull/140)).

**Agent integrations.** Initial Hermes and OpenClaw support, activated by `skills/install.sh --hermes` or `--openclaw`,
with `ripwire wrap` printing the MCP setup ([#51](https://github.com/redhat-et/ripwire/pull/51),
[#46](https://github.com/redhat-et/ripwire/pull/46)). `CLAUDE_CONFIG_DIR` is respected wherever ripwire looks for
Claude Code's configuration (@s0undt3ch, [#101](https://github.com/redhat-et/ripwire/pull/101)). `INSTALL.md` lists
every install route and how to remove all of it ([#121](https://github.com/redhat-et/ripwire/pull/121), asked for in
[#111](https://github.com/redhat-et/ripwire/issues/111)).

### Upgrade notes

- **Prebuilt x86-64 binaries now need an x86-64-v3 CPU, on Linux and on macOS.** x86-64 builds target
  `-march=x86-64-v3`: AVX2, BMI1/BMI2, FMA, LZCNT and MOVBE, the floor RHEL 10 sets, found on roughly Intel Haswell (2013)
  or AMD Excavator (2015) and newer. On an older x86-64 CPU the 0.6.0 binary will not run. The Intel macOS binary
  carries the same floor and still runs on macOS 14 and later; on Apple silicon, use the arm64 binary. arm64 builds need
  nothing new, because NEON is in the arm64 baseline. A plain build from source on x86-64 targets the same level;
  `-DRIPWIRE_NATIVE=ON` builds for the configuring machine only, and `./install.sh` from a checkout builds a Release
  binary tuned for that machine's CPU ([#127](https://github.com/redhat-et/ripwire/pull/127),
  [#137](https://github.com/redhat-et/ripwire/pull/137)).
- **The installer checks the CPU before it downloads.** On an x86-64 machine below v3, `scripts/install.sh` stops before
  the download and lists the missing features. `RIPWIRE_SKIP_CPU_CHECK=1` skips the check, for a VM that hides CPU flags
  its host still executes. When a downloaded binary cannot run, the installer now says why instead of reporting a
  version mismatch ([#138](https://github.com/redhat-et/ripwire/pull/138)).
- **The first run on each tree is a cold parse.** The cache format moves from 16 to 20 and the parser version from 81 to
  91, so a cache written by 0.5.0 is not reused. Separately, the cache root key is now one derivation for every cache
  family, so lean, rich, qchurn and MCP blobs written by older builds are clean misses, one cold parse per root, and the
  age pass sweeps them ([#127](https://github.com/redhat-et/ripwire/pull/127)).
  The parser version moves once more, to 92, for the YAML scanner fix below
  ([#140](https://github.com/redhat-et/ripwire/pull/140)); the cache format stays 20.
- **Output that changes by design.** Each change is described in its entry below.
  - `--quality-delta` dials each kind separately, and `churn="self"` no longer gates (#127).
  - `--help` prints one line per flag; `--help=all` prints the whole catalog (#92).
  - `--regex` anchors `^` and `$` match per line, and a match can no longer span lines. The `--grep` root gains
    `corpus_pruned_dirs=` (#85).
  - `--grep` and `--regex` no longer read gitignored files of an extension the indexer skips; `--no-ignore` restores
    them (#87).
  - `--recall` spends its budget on sections in rank order, and its disclosure names what was served (30b72ec0).
  - `--expand` lists up to 100 sibling names per body, where it listed 8 (3367d537).
  - `--handoff` shows up to 50 symbols per code file and 12 per prose file, where it showed 6. `--situ` lists every
    tests-to-run row, and `--doc-drift` and `--flags`/`--flip` page (#127).
  - `--help-task` no longer answers a "how does …" question with a symbol, and the MCP answer can carry `no_route`
    (#127).
  - A call inside a literal `#if 0` is no longer a call site, and graph verb roots carry `graph_unindexed=` (#72).
  - A `std::`-qualified C++ call no longer binds an in-repo definition outside namespace `std`. It counts toward
    `external=` instead, so `external=` reads higher (#134).
  - The map header can carry `declined=`, and `--callers`, `--callees` and `--impact` can carry `declined_calls=`
    (#136).
  - Cuts disclose themselves where they fire: `line_bytes=` on long matched lines, `…` on cut signatures,
    `budget_bytes="7500"` on a trimmed default `--for`, and cut markers on several listings (#100, #108). A cut
    `<calls>` listing keeps the callees ranked for the query (#95).
  - `--for --detail` says `over_ceiling="1"` when the answer passes `--max-tokens` (#77).
  - `--version` prints `emit=`, the formatted-output emitter the binary compiled in (88a5503b).
  - `--since`, `--merge-scout` and `--pr-context` refuse a revision that begins with `-` or does not resolve to a
    commit (#115, #116, #117).
  - A malformed `RIPWIRE_*` ranking calibration variable falls back to its default with one stderr line (#120).
  - `skills/install.sh --openclaw --hook` exits 2 instead of being silently ignored, and `--hermes --hook` is refused
    the same way (#51). `ripwire wrap claude` leads with the CLI (75ed8d3a).
  - `--hotspots` leaves functions flagged `extent_suspect=` out of its ranking and counts them in
    `unranked_extent_suspect=` (#135).
  - A file whose scanned sample holds invalid UTF-8 now reports a degraded parse (#126).
  - A budgeted `--for` that cannot fit its allowance takes the ladder's last rung and discloses the overflow, where it
    used to ship past the allowance silently, so a few already-over-budget bundles come out larger (3d98f84d).

### Added — Kotlin, with calls that cross into Java (parser version 91, cache format 20)

Kotlin (`.kt`) is indexed from a vendored `fwcd/tree-sitter-kotlin` grammar: classes, objects and companion objects,
functions, calls, imports and inheritance, with scope-qualified canonical ids and complexity scoring. A JVM interop
bridge in `graph.h`'s `langCompatible` resolves calls between Kotlin and Java in both directions. Contributed by
**@xCatG** ([#126](https://github.com/redhat-et/ripwire/pull/126)).

- **A disclosure hole closed on the way.** File health never validated UTF-8 on the sample it scans, so a file with
  invalid UTF-8 but no tree-sitter `ERROR` or `MISSING` node reported no degraded parse at all, and `--skipped`'s
  disclosure had a hole. The same sample is now checked with the existing UTF-8 validator.
- **Checked.** `test/kotlincheck.sh` runs a fixture with calls in both directions between Kotlin and Java, a constructed
  same-name collision pair (including an `enum class` and a plain class), cross-file calls and imports, with every number
  pinned from a real run and mutation arms. The contributor found no ASan, UBSan or LSan report across 501 real `.kt`
  files from 8 Android/JVM repositories, a 41-file adversarial corpus (merge-conflict markers, mid-edit fragments,
  invalid UTF-8, Unicode, emoji and RTL identifiers, deep nesting), and about 9,500 more `.kt` files across nowinandroid,
  compose-samples, architecture-samples, ktor and Signal-Android. Output was deterministic and well-formed on every one.

### Added — Dart, the 23rd grammar (parser version 88)

Dart (`.dart`) is indexed as a first-class language: definitions, call edges and metrics, from a vendored
tree-sitter-dart grammar. Contributed by **@calvinchengx** ([#75](https://github.com/redhat-et/ripwire/pull/75)), landed
in [#106](https://github.com/redhat-et/ripwire/pull/106) with four maintainer commits on top. On flutter/packages (3,706
`.dart` files) it indexes 71,726 Dart symbols, and none of that corpus's 289 degraded parses is a `.dart` file. The
binaries before and after produce identical bytes on `src/` and on a 1,406-file multi-language corpus, so no other
language moves.

**The tree shape is why this is more than a table row.** tree-sitter-dart makes `function_body` a *sibling* of the
signature, never a child. A definition's span therefore stopped at the signature's closing paren, and every call in the
body was attributed to the nearest enclosing symbol. On the gate's fixture that meant 5 edges where 8 are expected, a
method's call landing on its class, and three top-level edges gone. The Dart arm adopts the following body for the byte
extent, the row extent and complexity. The call query is adapted from upstream rather than copied, so the cascade
`this..add(1)..reset()` is two call edges and the receiver is not one.

**A latent bug it exposed, fixed for every language.** Six per-language arrays took their extent from the last
enumerator written out by hand (`std::size_t( Lang::Elixir ) + 1`) instead of `kLangCount`, so appending a language
dropped it silently. With the two `--skipped` tallies reverted, a corpus of two `.cpp` and two `.dart` files prints
`indexed="4"` and a single `cpp` row, and nothing says a row is missing. The same landing registered Dart in two more
places where the honesty contract applies:
- `--nonlocal-state` had printed no `unanalyzed_langs=` on a corpus that was half Dart;
- `--lint` printed `count="1"` beside `applicable="0"` on naming rules that do fire on Dart names.

**Stated floors.**
- Named constructors and factories index under the class name, so a `C.seeded(1)` call site is unresolved rather than
  wrong.
- `noSuchMethod` dispatch names its callee at run time and is not an edge.
- `part` / `part of` is not resolved.

ASan/UBSan is clean over a 6,554-file Dart corpus, and a libFuzzer run of 109,431 executions produced no crash, leak or
timeout. Gate: `test/dartcheck.sh`, red against a pre-Dart binary and against a binary with the span arm alone disabled.

### Added — initial Hermes and OpenClaw support

`skills/install.sh` gains `--hermes` and `--openclaw`, and `ripwire wrap` prints a setup recipe for `hermes` and
`openclaw`. **This is initial support.** CI checks what the installers write on disk. For Hermes, **@ashutoshsinghpr7**
also ran the installer and the MCP registration against a real Hermes install when support landed; the maintainers have
not re-verified it since. OpenClaw has not been verified against a real install. If you use either,
[#69 (Hermes)](https://github.com/redhat-et/ripwire/issues/69) and
[#68 (OpenClaw)](https://github.com/redhat-et/ripwire/issues/68) ask for exactly that check.

**Hermes.**
- **Install.** `--hermes` deploys 17 skills into `${HERMES_HOME:-~/.hermes}/skills`: the 16 flat user-facing skills,
  plus the Hermes-native `ripwire-repo-map` skill from `skills/hermes/`. The release one-liner activates them when that
  home exists.
- **MCP.** `ripwire wrap hermes` prints the `hermes mcp add` registration. In the live run it connected and discovered
  31 tools.
- **No hook yet.** `--hermes --hook` is refused with exit 2. Hermes has a `pre_tool_call` slot, but ripwire's nudge hook
  still switches on Claude Code's tool names, so the installer says the port has not landed instead of printing a hook
  line it cannot honour.
- **Credit.** The installer mode, the release-installer branch and the `wrap` recipe are **@AnkitArya**'s
  ([#51](https://github.com/redhat-et/ripwire/pull/51)). They landed in
  [#76](https://github.com/redhat-et/ripwire/pull/76), which adds a gate arm checking that `wrap hermes` names the flag and
  directory the installer really uses. The Hermes-native skill is **@ashutoshsinghpr7**'s
  ([#46](https://github.com/redhat-et/ripwire/pull/46)), as is the widening of both skill-vetting sweeps so that a skill
  in a subdirectory cannot escape them.

**OpenClaw.** Agent support in `src/wrap.h` used to live in five hand-maintained lists that nothing forced to agree. It
is now one table, `kAgentTargets`, and OpenClaw is a row in it
([75ed8d3a](https://github.com/redhat-et/ripwire/commit/75ed8d3ac9e155618acf6317aa88a084e4f207b5)). Dispatch, usage
text, the skills line, `--all` detection and the README block all read from that table.
- **Skills root.** OpenClaw's is `~/.agents/skills`, which it reads only while its state directory is the default
  `~/.openclaw`. The recipe prints that caveat.
- **Context file.** It is `~/.openclaw/workspace/AGENTS.md`, not the repository's `AGENTS.md`.
- **No hook.** OpenClaw has no shell hook slot, so `--openclaw --hook` is now refused with exit 2 instead of being
  silently ignored ([#51](https://github.com/redhat-et/ripwire/pull/51)).
- **`wrap claude` changed too:** it now leads with the CLI, as `codex` and `opencode` do.
- **Gate.** `test/agenttablecheck.sh` iterates the table, so the next row is covered without editing the gate.

How to install and remove both is in `INSTALL.md` ([#121](https://github.com/redhat-et/ripwire/pull/121)).

### Added — derailed C-family parses disclose their guesses (`extent_suspect=`), and a member-macro re-parse repairs the commonest derailment (parser version 90, cache format 20)

**The problem.** A function-like macro invoked without `;` as the last member of a class or struct, such as
`EXC_NAME(Foo)` right before `};`, sends tree-sitter-cpp's error recovery off course. The earlier structs dissolve into
an ERROR region, and the last struct's body swallows what follows. The same shape derails tree-sitter-c and
tree-sitter-objc. On memgraph, one file had 472 of its 487 definitions misfiled. A 14-line function,
`PrintFuncSignature`, was reported with `cx=749 ccx=920` and ranked #4 in `--hotspots`, and nothing on the row said
anything was wrong.

**The detector.** `src/extentsuspect.h` makes one linear pass per file over spans that are already sorted. A definition
a derailed parse filed in the wrong place carries `extent_suspect=`, naming the rules that fired:
- `name`: a name outside its own definition's signature;
- `head` (C family): a definition in another definition's return-type position, before its name;
- `scope` (C++): filed under `C::` while lying inside a different class;
- `error`: a class whose body holds an error inside an ERROR region, and what it contains.

Map, `--for`, `--expand` and `--json` rows carry the attribute. The header carries `extent_suspect_syms=`, and
`--skipped` gets per-file rows plus `extent_suspect_files=`. Each is absent at zero, and its legend line appears only on
output that carries it. `--hotspots` leaves flagged functions out of its ranking instead of ranking a number the tool
itself calls an artifact. It says so with `extent_suspect_syms=` on the row and a fourth partition bucket,
`unranked_extent_suspect=`, so the partition still sums to `files=`.

**The re-parse.** `src/macroreparse.h` touches only a C, C++ (including CUDA and Metal) or ObjC file whose first parse
holds error bytes. It blanks ALL-CAPS function-like macro invocations that sit alone on a line as class, struct or union
members, keeping newlines and byte offsets. It re-parses the blanked text and adopts the new tree only if that tree holds
strictly fewer error bytes. A blanked invocation stays a `role=type` use of the macro name, so `--uses` is unchanged.
Disclosure: `why=macro-blanked` and `macro_blanked=N` on the `--skipped` row, and `macro_blanked_files=` on the map,
`--json` and `--skipped` headers, absent at zero.

**Measured** on memgraph, main `096e3544` against the change:

| | before | after |
| --- | --- | --- |
| `PrintFuncSignature` | a method, `cx=749 ccx=920 loc=5479` | a free function, `cx=3 ccx=2 loc=15` |
| `mg_procedure_impl.cpp` in `--hotspots` | ccx 1871, top function 920 | ccx 960, top function 40, 0 flagged |
| degraded-parse files | 307 | 289 |
| extent-suspect definitions | — (no detector) | 241 in 9 files (detector alone: 1,613 in 31) |
| re-parsed files | — | 24 |
| cold CPU, 5 alternating runs | 8.114 s | 8.108 s |

On an llvm-project checkout, extent-suspect definitions go from 1,650 to 1,483, and 24 files are re-parsed. A file that
is not re-parsed keeps every definition, scope and complexity; only graph knock-on effects, such as caller counts and
rank, move.

**Limits, stated.**
- Only the ALL-CAPS class-body shape is repaired. Lowercase and namespace-scope macro runs still derail, and the detector
  keeps flagging them: on memgraph 241 flags remain, 93 of them in `eval.hpp`.
- A partial repair is still adopted when it holds fewer error bytes. `err=` describes the adopted parse, so it can rise
  while `err_ratio` falls: on `mg_procedure_impl.cpp` it goes from 1 to 50 nodes while error bytes fall from 271,971 to
  376.
- `--match`, `--lint` and `--slice` parse files themselves, so they still see the first parse.
- The `name` and `scope` rules have no real-world trigger today; they are guards, pinned by unit cases.
- This repository's own map always carries the new legend lines, because the fixtures live in the tree (about +430
  `est_tokens` on ripwire itself). Corpora with nothing flagged are unaffected.

`kParserVer` goes 88 → 90 and `kCacheVersion` 18 → 20, because the per-file cache record gains a field. Gates:
`test/extentcheck.sh` (55 checks) and `test/macroreparsecheck.sh` (103 checks), both red on their pre-change binaries
([#135](https://github.com/redhat-et/ripwire/pull/135)).

### Added — `INSTALL.md`: every install route, and how to remove all of it

A new `INSTALL.md` gathers every way to install ripwire:
- the prebuilt one-liner and its variables;
- building from source, and `./install.sh`;
- activating skills for Claude Code, Codex, Hermes, OpenClaw or any directory;
- the optional advisory hooks;
- the MCP server via `ripwire wrap <agent>`;
- checking and upgrading.

It ends with how to uninstall, which **@luisdavim** asked for in
[#111](https://github.com/redhat-et/ripwire/issues/111). The uninstall section covers:
- the binary and staged files;
- the `ripwire-*` skill links;
- ripwire's hook entries;
- MCP registrations, per agent;
- pasted rules blocks;
- the cache;
- the per-repository files ripwire writes only on request.

Every path comes from the code. The uninstall snippets were extracted from the page itself and run against a sandboxed
`HOME` with synthetic installs, and all 15 checks passed. They cover both what must be removed and what must be kept,
such as an unrelated binary, another tool's hook and non-hook settings keys. A `.bak` is written before each config edit,
and a second run is a no-op ([#121](https://github.com/redhat-et/ripwire/pull/121)).

### Added — `--help` in two tiers: one line per flag, every disclosure one call away

`--help` now prints one line per row, saying what exists and roughly what it does, in **4,473 tokens instead of
46,385** (10.4×). Nothing is deleted:
- `--help=<flag>` returns that row's every disclosure;
- `--help=<section>` returns one family at full detail;
- `--help=all` returns the whole catalog exactly as before.

The evidence made this a split rather than a trim. A third-party evaluation (callstack/agent-device #2400) measured
ripwire spending about 10% more tokens than grep-and-read and traced the cost to the per-call legend. The fix,
`--legend=compact`, was already documented, but 92% of the way down a 1,597-line document. Asking for the one row that
answers a question now costs 90 tokens. `test/helpbudgetcheck.sh` holds tier 1 to a token ceiling and proves every
advertised row is still retrievable from tier 2, so the ceiling cannot be met by deleting content
([#92](https://github.com/redhat-et/ripwire/pull/92)). Before the split, the `--legend` entry was rewritten to lead with
what the full legend costs, a fixed ~3 KB, and `test/legendcostcheck.sh` reads that floor out of `--help` and measures
against it ([8c20e108](https://github.com/redhat-et/ripwire/commit/8c20e108)).

### Added — `.rst`, `.adoc`, `.org` and `.mdx` reach `--recall` (parser version 85)

These extensions were not indexed at all, so a `--recall` over a repository that documents itself in reStructuredText
or AsciiDoc returned nothing and, correctly but unhelpfully, said zero. They now reach `--recall`, `--for` and
`--handoff` on the markdown grammar tier. Gate: `test/textdocscheck.sh`
([#80](https://github.com/redhat-et/ripwire/pull/80)).

### Changed — `--recall` serves ranked passages, not document prefixes

`--recall` scored a document's markdown sections by relevance, then put them back in document order and let the byte
budget cut from the front. On a document larger than its share of the budget, the best section could be unreachable at
every ceiling: on a 616 KB `docs/COMMANDS.md`, the `--field-affinity` section at line 3570 of 4755 ranked #1 and was
served at none of 1,500, 4,000, 12,000 or 40,000 tokens, while the table of contents at the front of the file was.
Sections are now own-prose units that tile the document, the allowance is spent in rank order one whole unit at a time,
and the disclosure reports what was served: `[sections: S of R selected (N in doc) ... dropped_by_budget=D]`, with
`lines=` naming exactly the ranges in the body. An enclosing section no longer outranks the subsection that holds the
answer, because a unit's score is scaled by its own-prose evidence over the strongest own-prose evidence in its subtree.

Measured on a frozen 1.88 MB corpus: answer reachability went from 5 of 14 to 9 of 14, natural-language-first from 43
to 79 at 1,600 tokens, and query-term coverage rose by 58, 56 and 40 at 4,000, 8,000 and 16,000 tokens. Budget
monotonicity holds within a document over 1,380 ceilings with 0 shrinks, but not across documents, and the surfaces
that claimed otherwise now say so. Gate: `test/recallpassagecheck.sh`, written before the fix
([30b72ec0](https://github.com/redhat-et/ripwire/commit/30b72ec0)).

### Changed — one header of SIMD string kernels, and the quadratic child walks gone

For every invocation below, output is byte-identical before and after; the verbs whose output this round changes on
purpose are in their own entries. Main's binary (source `9356cf23`) was measured against the merged tip of the round,
with the same argv and interleaved arms. CPU is user+sys, the median over n pairs, on a shared machine at load 7–14:

| corpus | invocation | before (CPU s) | after (CPU s) | Δ median | n |
| --- | --- | ---: | ---: | ---: | ---: |
| llvm-project | cold map `--no-cache` | 194.14 | 155.60 | −19.9% | 1 |
| go | warm `--pack-task` | 8.13 | 5.88 | −27.6% | 5 |
| go | warm `--lint` | 18.43 | 15.18 | −17.7% | 5 |
| rocksdb | warm `--lint` | 6.77 | 5.60 | −17.3% | 5 |
| rocksdb | warm `--pack-task` | 0.68 | 0.60 | −10.9% | 5 |
| rocksdb | cold map `--no-cache` | 7.96 | 7.42 | −6.7% | 5 |
| ripwire (own tree) | warm `--pack-task` | 0.45 | 0.38 | −15.5% | 5 |
| ripwire (own tree) | warm `--lint` | 4.21 | 3.91 | −7.3% | 5 |

A warm map, `--for` and `--grep` are within noise; their floors are the serial resolve loop and file opens.

**The O(C²) child walks.** An indexed child walk over a tree-sitter node restarts the vendored iterator on every call, so
the loop is quadratic in the number of children. It only bites on wide, flat child lists, which C/C++ include guards
and comment floods produce, which is why the llvm-project cold parse moved most. `collectPreprocDeadRanges` and the other
23 quadratic walks move to one cursor helper, `src/infra/tschildren.h`, with 18 isolation arms proven red first at
11–125× ([#127](https://github.com/redhat-et/ripwire/pull/127)). [#130](https://github.com/redhat-et/ripwire/pull/130)
converts 22 more, each proven quadratic on the pre-change binary first at 13×–126× its control under a 16,000-comment
flood. Three loops stay indexed, with the reason written at the loop, and 156 generated fixture × verb pairs plus the 21
committed ones are byte-identical.

**One header of string kernels.** `src/infra/strkern.h` holds nibble-table byte classification, an A–Z fold, and byte,
byte-set and 3-byte finds, each with a NEON path, an AVX2 path and a scalar twin. The query tokenizer is rewritten on it
as mask algebra, proven against verbatim copies of the old walkers, beside a BM25 head-mask index; that is the
`--pack-task` row. The XML and JSON escapers copy clean runs between the bytes a 256-bit set finds (escaper share 4.6% →
2.0% and 6.3% → 2.6%). A SIMD scan for `--grep` was measured and refused: that verb is bound by file opens, and the scan
is 0.4% of busy samples.

**Lookups hoisted out of the per-node path.** 199 `ts_node_child_by_field_name` sites now read a per-grammar `TSFieldId`
table, checked on 1,189,205 enumerated (node, field) pairs. The `#match?` predicate's regex is compiled once per query,
not once per match, which is the `--lint` row.

The techniques are credited in `docs/LINEAGE.md`, which now folds 49 repositories and 70 papers, among them Langdale &
Lemire (VLDB J. 2019) for nibble-table classification, Daniel Lemire's 2023-07-13 blog code, StringZilla and Tempesta
fast_str. The kernel tests are a doctest target, `ripwire_test_strkern`.

### Changed — `--quality-delta` dials each kind separately

On 12 landed commits, `--quality-delta` had gated all 12, with a true-positive share of 2%. Each kind now has its own
rule:
- `churn="self"` is informational; what gates is two committed rewrites inside the window.
- Dead-code sees header files, where 96.8% of this repository's `src/` lines live, and excludes language-invoked symbols
  instead.
- Verbosity counts code lines.
- Complexity and verbosity gate on a threshold crossing or on growth of at least 25%.
- New api-surface symbols become a count, `api-new-surface=`.

On the same 12 commits, gating went from 12 of 12 to 8 of 12, the true-positive share rose from 2% to 12% with 0 wrong
rows, and the synthetic regressions caught rose from 5 to 7. The legend gains the `api-new-surface=` count and the churn
facets' gating rule ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Changed — `--handoff` shows more, and three listing verbs page instead of cutting

Caps are blow-up guards on the way to one complete answer, and none of this lowers a value to shrink a byte count.
- **`--handoff`** shows up to 50 symbols per code file and 12 per prose file, where it showed 6. Containment rises from
  16% to 54%, and the change only adds rows.
- **`--doc-drift`, `--flags`/`--flip` and `--situ`** disclose their cuts and page. Answer rows never page, so `--situ`'s
  25-row cap on tests-to-run is retired: every row is listed, and no cut is disclosed because none is made. The gate has
  33 checks, 24 of them red before the change.
- **The cap sweep was re-derived** once six honesty defects in its harness were fixed: 64 of 151 answering rows, where
  59 of 195 had been published ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Changed — `--expand` lists up to 100 sibling names, and every cap is listed in `docs/LIMITS.md`

A body's `sibs=` list on `--expand` was capped at 8 names. On this repository the median file holds 4 symbols but p99
holds 85, and symbols concentrate in large files, so the cap fired on 68.5% of bodies and hid 89.3% of sibling names. The
cap is now 100, above p99: 15.8% of bodies are cut, 56.2% of sibling names are visible where 10.7% were, and a
single-symbol `--expand` answer grows 36%. `sibs=` reaches only `--expand`, so `--for` and `--pack-task` are
byte-identical at every cap value tested. The README's `--pack-signatures` figure moves as a consequence (top-50 71.0% →
81.8%), because `--expand`'s bodies are that ratio's denominator; the cap was chosen on recall grounds and the figure
re-derived afterwards ([3367d537](https://github.com/redhat-et/ripwire/commit/3367d537)).

That cap is why caps now have an inventory. `docs/LIMITS.md` lists every cap in `src/` with its value, its site and
whether its file discloses a cut when it fires. It is generated by `docs/limits_build.py`, and `test/limitstablecheck.sh`
fails when it drifts. It began at 120 caps across 51 files (3367d537).
[#108](https://github.com/redhat-et/ripwire/pull/108) added the INDEXING/OUTPUT column, the hyperparameter register,
`docs/TUNING.md` and the `bench/capsweep` harness. [#123](https://github.com/redhat-et/ripwire/pull/123) pins each cap by
what it is rather than the line it sits on, so a comment above a cap no longer reddens CI.
[#127](https://github.com/redhat-et/ripwire/pull/127) adds a BOUNDARY class, and
[#128](https://github.com/redhat-et/ripwire/pull/128) gives the per-file tables their own `## Caps, by file` heading;
they had been filed under "Not caps". On main the register counts 208 caps across 83 files.

### Changed — faster ingest and graph building: the per-node dispatch, the include closure, three loop hoists

These build on the cone memo in the Fixed entries below. Every result here is an interleaved A/B, and output is
byte-identical before and after.

**The per-AST-node `strcmp` dispatch goes inline.** The ingest walk chooses a branch with chains of about forty
`std::strcmp` calls against `ts_node_type()`, once per AST node. `strcmp` is an external symbol that LTO cannot inline,
and on macOS each call also hops two dyld stubs. Sized before any change, `strcmp` was this share of busy samples:

| corpus | `strcmp` share of busy samples |
| --- | --- |
| rust-analyzer | 12.31% |
| go | 10.76% |
| llvm-project | 10.56% |
| django | 9.31% |
| rails | 6.14% |

`rw::kindIs` (`src/infra/nodekind.h`) is the same compare, unrolled inline against a literal, and it replaces `strcmp` at
569 call sites. On llvm-project `strcmp` is now 0.23% of busy samples.
- **Why not SIMD.** On llvm-project, 92.96% of 4,861,917,534 compares decide at byte 0, and clang compiles the chain to a
  shared-prefix decision tree that uses no vector registers.
- **The claim.** As a range over llvm-project, django, go and this repository: **cold CPU 1–7% lower, cold wall 0.3–8%
  lower**, with all 32 statistics in the same direction.
- **Same output.** Byte-identical on seven corpora. `test/argvdiffcheck.sh` finds 640 of 642 vectors identical; the
  other two differ only in `--version`'s `built_from=`.
- **Gate.** `test/nodekindcheck.sh` checks `kindIs` against `strcmp` on 1,348,096 enumerated pairs, and uses a guard page
  to catch any read past the NUL ([#107](https://github.com/redhat-et/ripwire/pull/107)).

**The include closure's sort goes radix, above 128 elements.** On rails, 38.7 ms of the ~62 ms transitive include
closure (`buildGraph/2b`) was one `std::sort`. With radix above a crossover of 128:

| on rails | before | after |
| --- | --- | --- |
| `buildGraph/2b` | 65.21 ms | 35.01 ms (−46%) |
| `buildGraph` | 223.0 ms | 186.7 ms (−16%) |
| whole `--callers=main` run | | 7.8% and 8.5% faster at the median, two independent A/Bs |

Five control corpora stay within ±1.7%. The threshold is what makes the change safe: without it, the same conversion
regresses django 7.9×, a private C++ tree 7.7× and rust-analyzer 4.7×. Three more sites were refused with numbers.
django's `implementors` would be 2.87× slower, because its records arrive already sorted, which `std::sort` detects and
radix cannot. A `std::unique` that removed 0 duplicates in 24,216 calls is gone
([#97](https://github.com/redhat-et/ripwire/pull/97)).

**Three loop hoists; two candidates refuted.**
- The CHA-lite ancestor closure is memoised: −13.2% warm on rust-analyzer.
- `lexicalNormalize` builds one string: −6.0% on rails.
- The shadow guard asks its cheap question first: −26% on that phase.

A candidate-spray optimisation was 53% of scan volume and 0% of wall, so it was not built, and another candidate
measured inside the noise. After the cone fix, no single phase dominates on any corpus, and which phase is largest
depends on the corpus's language. `bench/PROFILE.md` carries the six-corpus table
([#96](https://github.com/redhat-et/ripwire/pull/96)).

**timsort is vendored and routed nowhere.** It was measured against `std::sort`, radix, pdqsort, an `is_sorted` guard and
`std::stable_sort`, on the real id sets of three call sites across seven corpora, and was not recommended for any of
them:
- on presorted input, a three-line `is_sorted` guard measured 0.35× where timsort measured 0.58×;
- on scattered input, timsort measured 1.71×, 6.0× slower than radix.

It ships in `src/infra/` for parity with the portable layer it belongs to. The measurement is in its header, and a gate
checks that no call site uses it ([#93](https://github.com/redhat-et/ripwire/pull/93)).

### Changed — `est_tokens` measured against a real tokenizer

`est_tokens` had been checked for being present, positive and deterministic, but never for being accurate. It is now
measured: 25 invocations on 2 corpora, counted with `o200k_base` and `cl100k_base`, which agree to within 1.4%. Three
findings are published in `docs/EVALS.md`:

- **Only 9 of 25 invocations print a price at all.** The sixteen that do not include every navigation verb. One
  `--edit-check` emitted 99,006 real tokens priced at nothing.
- **The signed error runs −18.4% to +41.7%**, with a median of +16–18%. It follows document shape, not corpus language:
  real bytes per token run from 2.44 on dense signature rows to 4.66 on legend prose. So no extra `kTokenCalib` row can
  fix it.
- **`--token-budget=N` delivers 48–82% of N.** The budget is a ceiling on the estimate, and at binding budgets the
  estimate over-reads by 25–42%.

`kTokenCalib` is unchanged on purpose. A single rate cannot correct a +40% bundle and a −16% body at once, and the
per-span charge that could is a change of its own. What landed is the instrument for that change:
`test/tokenbudgetcheck.sh` #18 holds every pinned invocation inside a measured band and the set's error under a 30%
ceiling. A comment in `src/serialize.h` saying the estimate "never systematically under-reads" was false on two corpora
and is gone. `--legend=compact` is a wash or a small loss on `--for`, whose budget refills the bytes the legend frees
([#79](https://github.com/redhat-et/ripwire/pull/79)).

### Changed — one emitter for formatted output, and `--version` says which one it compiled in

`src/infra/emit.h` is now the one place the formatted-output path is chosen: `std::print` where the standard library
defines `__cpp_lib_print` (libstdc++ 14 and later; libc++ at a macOS 14 or later deployment target), and `std::format`
plus `fputs` where it does not, so every toolchain still builds. `--version` prints the choice as `emit=`, and every CI
and release leg asserts `emit=std::print` off the binary it built. Behind it, `src/` no longer holds a single
`std::printf`, `std::fprintf`, `std::snprintf` or `std::sprintf` call site: 1,526 became 0, converted in batches against
a byte-parity fence that was widened before anything was converted
([88a5503b](https://github.com/redhat-et/ripwire/commit/88a5503b),
[25d901cd](https://github.com/redhat-et/ripwire/commit/25d901cd)).

### Changed — Shotgun Surgery is named where ripwire already measures it

Fowler's Shotgun Surgery, one change that touches many modules, has two measurable forms. The historical one is change
coupling, which `--cochange` mines and `--situ` and `--pr-context` turn into a check; the name now appears on the
`--cochange` and `--situ` help entries, the MCP `cochange` and `situational_awareness` descriptions, the README and four
skills. The static one, Lanza & Marinescu's CM×CC detection strategy, was prototyped on the call graph on two corpora and
not built: its top flags were stable hubs, and per-file static fan-in tracked how widely edits actually scatter at
Spearman +0.158 and +0.163. The shipped `--situ` co-change rule, backtested against prior history only, scores
precision@8 of 0.352 and 0.427 on the same two corpora. The tables are in `docs/EVALS.md` and re-derive from
`bench/shotgun/` ([8dfd7380](https://github.com/redhat-et/ripwire/commit/8dfd7380)).

### Changed — skill descriptions get their routing triggers and stop rules back

Six skill descriptions get back discovery triggers that had been cut to fit a 320-character per-description ceiling, and
four one-sentence stop rules return to the frontmatter. The 320 was a design number, not a client limit: Codex rejects a
description over 1,024 characters, and Claude Code caps an entry at 1,536. `test/skilldescbudgetcheck.sh` now fails only
a description over 1,024 characters and keeps the 5,400-character ceiling on the set
([#112](https://github.com/redhat-et/ripwire/pull/112)).

The quality-bar description also stops promising that `--quality-delta` "exits non-zero on new debt". Exit 2 fires only
when pre-existing code got materially worse, and new-symbol rows never gate, so a clean exit is not a verdict on new code
([#114](https://github.com/redhat-et/ripwire/pull/114)).

### Changed — the README and the docs

- **The goal.** The README states what the tool is for: one question, one complete answer, with honest limits and token
  budgets as the two stair-steps toward it. It is worded so it does not promise a hard cap the tool deliberately exceeds
  with `over_ceiling="1"` ([#88](https://github.com/redhat-et/ripwire/pull/88)).
- **The top of the page.** It leads with what a stranger can check in ten seconds. The four negations are a local badge,
  `docs/assets/no-deps.svg`, rather than images fetched from a badge service. The H1 says "Fewer Tokens", and the tagline
  under it is bold text rather than a second heading. The hero keeps the Trendshift badge; the paddle-out wave moves to
  the presentation deck ([#82](https://github.com/redhat-et/ripwire/pull/82),
  [#90](https://github.com/redhat-et/ripwire/pull/90), [#103](https://github.com/redhat-et/ripwire/pull/103),
  [#113](https://github.com/redhat-et/ripwire/pull/113), [#119](https://github.com/redhat-et/ripwire/pull/119),
  [#133](https://github.com/redhat-et/ripwire/pull/133)).
- **The banner** reads "shaped in '76, finned last month, every guess says how many it chose from, see the rip before
  you're in it", and ends on "Paddle out with a map." The lineage line claims both halves of the ledger: fifty years of
  software-engineering results, and research from last month. The 5.0% token row now carries the strict-satisfaction
  caveat beside it instead of 1,150 lines away, and `test/readmedriftcheck.sh` arm (H) holds the lineage summary's counts
  to the ledger (ca3ce335, ef6168b1, a46a514d, 61d84eef, 441e35cf, 64c81d47).
- **The task example's 4.3K figure** is described as what one run produced, not an enforced budget, since the example
  passes no budget flag. Contributed by **@PollyBot13** ([#54](https://github.com/redhat-et/ripwire/pull/54)).
- **The lineage ledger** gains three rows (tgrep, codeburn, markitdown), going from 43 to 46 repositories, with a gate
  arm requiring every copy of that count in the README to agree ([#86](https://github.com/redhat-et/ripwire/pull/86)). The
  string-kernel credits in #127 take it to 49 repositories and 70 papers.
- **The head-to-head tables say what they predate.** An italic note beside both Round 4 tables records that they were
  measured on 2026-08-08, before the performance work that ships in 0.6.0, and names two of the figures that have moved
  since: llvm-project's cold parse, on 182,555 files, from 194.1 s to 155.6 s of CPU, and `--pack-task` on a Go
  repository from 8.13 s to 5.88 s. No number in the tables changes; they still show what was measured that day
  ([#141](https://github.com/redhat-et/ripwire/pull/141)).
- **The README links `INSTALL.md` again.** The sentence under the quick-install block naming every install route was
  lost when #127's merge took a branch side that predated it, and main had not linked the page since. It goes back in
  the same place ([#141](https://github.com/redhat-et/ripwire/pull/141)).
- **Adding a language, for contributors.** `prompts/add-a-language.md` is derived from the diff of the Elixir landing
  rather than from memory. It starts by measuring the parse rate on a real corpus before any code is written, and it ends
  with the traps earlier PRs actually hit (7780e4d3, d582d0de).
- **Three places where the docs contradicted the repository** ([#131](https://github.com/redhat-et/ripwire/pull/131)):
  - `THIRD_PARTY.md` gains the MIT attribution row the vendored `tree-sitter-markdown` shipped without, and a gate arm
    now derives the required rows from the directories under `third_party/deps/`;
  - `INSTALL.md` says Hermes was run live by a contributor when it landed, and OpenClaw has not been;
  - `docs/ARCHITECTURE.md` said PageRank's power iteration is parallelized; it is single-threaded, and its fixed row
    blocks exist for determinism, not parallelism.

### Changed — CI, the gate harness and internals, with no change to output

None of this changes the binary's output.

**CI.**
- macOS legs shard four ways like every other leg, which halves the gates per macOS job. A run grows from 26 checks to
  30 ([#110](https://github.com/redhat-et/ripwire/pull/110)).
- The HEAD comparison binary is built once per job, in its own step, never inside a gate's time budget, where a parallel
  `cmake` build under contention had been killed at 900 s and again at 1200 s
  ([#118](https://github.com/redhat-et/ripwire/pull/118)).
- A declared gate budget is now a floor. Under CI's 4× budget scale, 15 of 18 declared budgets had been smaller than what
  an undeclared gate got ([#109](https://github.com/redhat-et/ripwire/pull/109)).
- Every non-Ubuntu apt source is removed before `apt-get update`, after a vendor source took down every Linux leg for the
  second time ([#99](https://github.com/redhat-et/ripwire/pull/99)).
- The advisory clang-tidy step lints a real parse. `version.h` was not generated before it ran, so the translation unit
  that includes nearly every header failed to parse and 64 diagnostics were hidden. One of them is the file-handle leak
  fixed below ([#120](https://github.com/redhat-et/ripwire/pull/120)).
- Its `bugprone-easily-swappable-parameters` options are set to reveal rather than silence: of the 209 rows the check
  reports at upstream defaults, 208 are genuine, and the two options add 18 more genuine rows while silencing none
  ([#124](https://github.com/redhat-et/ripwire/pull/124)). Eight of the flagged functions, among them the whole-file
  readers, then stop filling an out-parameter and return what they produce; the flagged sites drop from 237 to 229, and a
  36-case byte-for-byte differential is identical ([#132](https://github.com/redhat-et/ripwire/pull/132)).
- `test/*.sh` is marked `linguist-detectable=false`. The gate scripts had come within 5% of the C++ source's byte count
  (8,921,478 against 9,398,027), and a few dozen more gates would have relabelled the repository's language as Shell
  ([f2589419](https://github.com/redhat-et/ripwire/commit/f2589419)).

**The gate harness.**
- The published gate count is generated from `test/regression.sh` by `docs/gatecount_build.py`. Two lanes that each add a
  gate both write N+1, and git merges that cleanly against a loop of N+2; it collided seven times in one night
  ([#104](https://github.com/redhat-et/ripwire/pull/104)).
- `test/pargates.py` watches the checkout while gates run. It samples `git status` every 0.25 s and fails the run on any
  new file a gate leaves in the tree, naming the gates in flight, and it says the count is a floor. A transient probe file
  had been flipping stamped determinism arms by marking builds `+dirty`; the writer is fixed, and `CONTRIBUTING.md` states
  the rule ([4c10be9d](https://github.com/redhat-et/ripwire/commit/4c10be9d)).
- Gates run with `PYTHONDONTWRITEBYTECODE=1`. A gitignored `__pycache__/` had changed what the crawl counts
  (`corpus_pruned_dirs=` 3 → 4), which made a paging gate nondeterministic
  ([#122](https://github.com/redhat-et/ripwire/pull/122)).
- Gates check out commits as private shared clones rather than with `git worktree add`, so a gate killed with SIGKILL
  leaves nothing registered in the shared `.git` ([#125](https://github.com/redhat-et/ripwire/pull/125)).
- A timed-out gate is stopped whole. `test/pargates.py` used to SIGKILL only the gate's `bash`, and 5 of 6 probe processes
  outlived the timeout. Each gate now leads its own process group, which gets TERM and then KILL after a 10 s grace, and a
  Ctrl-C or SIGTERM to pargates stops every running gate the same way
  ([#129](https://github.com/redhat-et/ripwire/pull/129)).
- The installer gates clear inherited agent-home variables before setting up their fixtures, so a gate run from inside an
  agent session no longer writes into that agent's real home. Contributed by **@PollyBot13** (#55, landed as fed2e2b1 and
  d05af44e, with a5c95aa6 on top); `test/agenttablecheck.sh` got the same fix for `XDG_CONFIG_HOME` (1fdf70d3).
- Four gates that could fail for reasons outside what they check now fail only as themselves: a gate whose command died
  no longer reports a missing feature ([#94](https://github.com/redhat-et/ripwire/pull/94)); a partition arm that ties
  skips with its numbers instead of failing (cb32e0dd); a truncated pipeline no longer reads as a missing attribute
  (321ee839); and the skill-eval sweep counts directories that contain a `SKILL.md`, not every directory under
  `skills/` (5e96a6a5).
- `scripts/optremarks.py --hot` covers the 14 headers the ingest split moved work into. It had been reading 0.20% of the
  ingest translation unit ([#98](https://github.com/redhat-et/ripwire/pull/98)).

### Fixed — the macOS x86-64 release binary is built for its own architecture

`cmake/PortableFlags.cmake` picked its flags from `CMAKE_SYSTEM_PROCESSOR`, which CMake takes from the build host. The
release job builds the macOS x86-64 binary on an arm64 runner, so every x86-64 compile line got `-mcpu=apple-m1` and no
`-march`. Releases through v0.5.0 therefore most likely shipped a baseline x86-64 macOS binary; no release log shows the
flags, so that is an inference. With the Xcode pinned after v0.5.0 the same flag is a hard compiler error, so the 0.6.0
macOS x86-64 job, and with it the whole release, would have failed.

Flags now follow `CMAKE_OSX_ARCHITECTURES` when it names exactly one architecture, so the macOS x86-64 binary gets
`-march=x86-64-v3` like Linux, and a build tree naming more than one architecture stops at configure ("ripwire builds one
architecture per build tree"). The job moves to a `macos-26` runner, whose Rosetta can run x86-64-v3 code for PGO
training, with Xcode 26.6 and `MACOSX_DEPLOYMENT_TARGET=14.0` pinned; without the pin the move would silently have raised
the minimum macOS to 26. A new release step reads `minos` back off the binary. Gates: `test/portablebuildcheck.sh` arms
#2d–#2h ([#137](https://github.com/redhat-et/ripwire/pull/137)).

### Fixed — the installer names an x86-64 CPU below v3 instead of reporting a version mismatch

On a CPU below x86-64-v3, `scripts/install.sh` downloaded the binary and ran `--version` to verify it; the binary died
with SIGILL inside a pipeline whose status came from `head`, and the user was told
`release vX contains ripwire <unknown> — refusing version mismatch`, which never names the requirement.
- **Before downloading**, on x86-64 and for 0.6.0 and later, the installer reads the CPU flags (`/proc/cpuinfo` on Linux,
  the `sysctl` feature keys on an Intel Mac). Below v3 it stops, lists the missing features and points to a source build
  with `./install.sh`, which builds for the local CPU. It never blocks when the flags cannot be read, under Rosetta, for
  0.5.x and older, or with `RIPWIRE_SKIP_CPU_CHECK=1`, which covers a VM that hides flags its host still executes.
- **After downloading**, the verification run's exit code is read. Exit 132 on x86-64 names the v3 requirement and the
  source-build route, and under Rosetta suggests a native arm64 shell. Any other failure, such as a glibc loader error,
  is shown with the binary's own output. "Version mismatch" is reported only when the binary ran and printed a different
  version.
- `INSTALL.md` states the requirement and the new variable. Gate: `test/releaseinstallcheck.sh` section G, 12 arms, five
  of them red on main ([#138](https://github.com/redhat-et/ripwire/pull/138)).

### Fixed — a `std::`-qualified C++ call binds only a definition inside namespace `std`

A call written `std::X(...)` bound to the repository's lone in-repo definition named `X`, at full confidence and with no
`amb=` or `prov=` marker. On memgraph, `SafeString::move` became map row #1 with 2,107 false callers from `std::move`. In
ripwire's own graph, `std::min`, `std::max` and `std::sort` bound `fastmath` and `svector` members.

A call whose written qualifier is `std`, `::std` or a standard-library inline ABI namespace (`__1 __2 __8 __Cr __cxx11
__ndk1`, tabled with sources in `src/externalnames.h`) now keeps only candidates scoped inside `std`. Otherwise it is
counted through the existing external path, `external=`, and gets no edge. Only an exact `qualifier::name` pin exempts a
site; include-based narrowing does not. Unqualified `move(x)`, ADL, using-directives and namespace aliases behave as
before, and the rule is deliberately not generalised to other qualifiers.

| `--no-cache` | before | after |
| --- | --- | --- |
| memgraph `--callers=SafeString::move` | 2,107 | 3 |
| memgraph edges / ambiguous / external | 177,280 / 39,771 / 7,404 | 174,787 / 39,606 / 12,370 |
| ripwire (main `096e3544`) edges / ambiguous / external | 20,857 / 7,626 / 1,003 | 20,413 / 7,528 / 2,498 |
| ripwire `--callers=min` / `max` / `sort` | 131 / 67 / 7 | 5 / 14 / 2 |

`unresolved=` and map wall time are unchanged. Of the three memgraph callers left, two are `SafeString` unit tests and one
is a `std::ranges::move`, the first gap below.

**Known gaps, disclosed.**
- Nested std namespaces (`std::ranges::`, `std::chrono::`) arrive as their last segment only, which cannot be told apart
  from a user namespace.
- In ObjC++, the grammar parses `std::move( x )` as an error node plus a bare `move( x )`, so the qualifier is gone before
  resolution. The gate pins this behaviour.
- A declaration-only `namespace std { void f(); }` would still receive edges. This is not gated.
- `external=` now also counts refused `std::` calls, so it reads higher than before.

No cache or parser version moves: the change is resolution-only, and a warm run on a cache written by the old binary
equals `--no-cache`. Gate: `test/stdqualcheck.sh`, 35 checks. On the pre-fix binary 19 fail, and the 16 that pass are
controls ([#134](https://github.com/redhat-et/ripwire/pull/134)).

### Fixed — the cache evicted its own working root, and every root minted two key families

One llvm-project root needs 1.76 GB of cache, and the cache sweep holds the whole cache to 2 GB. The sweep was evicting
that root's own rich blob, so a repeated same-argv `--for` on llvm-project took 274 s of CPU; with the blob kept it takes
26 s. Eviction now pins every family of the working root, and an eviction is disclosed on stderr only when one happens.
Separately, the lean/rich cache-key builder hashed the root with a truncated FNV basis while the git-metadata families
used the real one, so every root minted two key families. There is one root key for all seven families now, which is why
blobs from older builds are clean misses (see the upgrade notes) ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Fixed — `--help-task` no longer answers "how does <word>" with a symbol

`--help-task` no longer mints a symbol from a "how does <word>…" question, and JSON keys never resolve as symbols.
Harmful recommendations fell from 13 of 25 to 0, and precision rose from 0.797 to 1.000. The skills' stop rules are gated
as present and load-bearing, the router names all 16 skills, and the MCP answer gains `no_route`
([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Fixed — the confident zero: three outside reports, three causes (cache format 18)

Three reports filed on 2026-09-08 described one symptom: a number that reads as authoritative and is not. They turned out
to have three causes, so each got its own fix. A single "blind spot" attribute would have been a false claim on two of
the three.

- **Callers in a file no grammar reads gave `count="0"`, undisclosed.** Reported by **@snrmwg**
  ([#66](https://github.com/redhat-et/ripwire/issues/66)). Every graph verb's root now carries `graph_unindexed=`, folded
  from the same list the map header prints and absent at zero. ripwire also stops reporting its own cache blob as an
  unread language when that file sits inside the crawl root; that had made one query answer differently cold and warm.
- **A header-qualified selector gave `reaches="0"` for seven real callers.** Reported by **@mariadb-KyleHutchinson**
  ([#63](https://github.com/redhat-et/ripwire/issues/63)). `Foo.h:name` resolved to bodyless declarations, which carry no
  edges. A selector that resolves only to declarations now widens to the definitions they stand for, matched on scope and
  name, never on name alone. `docs/EVALS.md` had published "Blast-radius calls returning an empty radius for a symbol
  with real callers: ripwire 0". That sentence is now scoped to the corpora it measured, only one of which was C++.
- **A call inside `#if 0` was served as a live call site.** Reported by **@mariadb-KyleHutchinson**
  ([#62](https://github.com/redhat-et/ripwire/issues/62)). This is an over-count, which breaks the promise of
  `counts_floor="1"` that the true count is at least the reported one. The dead-range rule `--slice` already used moved
  to `src/preprocdead.h`, and the call graph now reads the same implementation, so the two cannot disagree about which
  lines exist. Only literal `#if 0`/`#if 1` counts; `#ifdef X` and `#if EXPR` stay live. The edge is dropped, not flagged,
  because a flagged row still counts.

`kCacheVersion` goes 17 → 18: this changes which references are extracted, so a version-17 blob would replay edges this
build does not produce. Gate: `test/blindspotcheck.sh`, written red first
([#72](https://github.com/redhat-et/ripwire/pull/72)).

### Fixed — `--for --detail` named a `max_tokens` ceiling it did not apply

On a `--for --detail` run, `--max-tokens=N` budgeted the bodies only. Signatures, the header, the legend and the symbol
table were never charged, yet the root printed `max_tokens="N"` regardless. Reported by **@YogevKr**
([#61](https://github.com/redhat-et/ripwire/issues/61)): at `--max-tokens=300` the answer cost 2,640 estimated tokens,
8.8× the ceiling it named, with no `over_ceiling`.

The fix is disclosure, not enforcement, which is what the issue asked for. Thirty small functions is the complete
answer, and trimming it to fit 300 would serve the caller less while looking more obedient. The reproduction now reads
`max_tokens="300" est_tokens="3589" over_ceiling="1"`, and `--help` states what `--max-tokens` bounds on that path and
what it does not ([#77](https://github.com/redhat-et/ripwire/pull/77)).

### Fixed — a budgeted `--for` shipped past its allowance with no ladder rung fired

`--for`'s ceiling ladder priced the header it was about to emit, but not the two pieces spliced on afterwards: the root
`over_ceiling="1"` and the legend clause that defines it, 70 bytes between them. `est_tokens` prices markup at 2.50
bytes per token while the allowance is sized at 2.714, so any bundle in that band carried 70 bytes the ladder never saw,
and a bundle the ladder had fitted within 70 bytes of the allowance shipped past it. It was latent, not new: the
pre-fix binary, on the repository's own `src/`, overshot at 14 of 111 budgets.

The post-ladder splices and the `est_tokens` fixpoint now move inside the shape the ladder prices, so a shape fits only
when the old reserve test passes **and** the finished header plus every other emitted byte fits the allowance. The first
half is the old test verbatim, so a bundle that was already inside its allowance picks the same shape: over 1,971
invocations across three trees, the flag combinations and the MCP `for` twin, 1,918 are byte-identical to the pre-fix
binary. All 53 that move were past their allowance with no rung fired — 29 now fit, and 24 land on the ladder's
disclosed last rung, which is **larger** than what shipped before, because it carries the overflow disclosure the old
path dropped. `--pack-task` and `--from-trace` keep the fixed-payload form of the ladder and are unchanged by
construction. Gate: `test/estchargecheck.sh` #11 A7 and its new 52-budget sweep, red on the parent commit
([7caf968f](https://github.com/redhat-et/ripwire/commit/7caf968f),
[3d98f84d](https://github.com/redhat-et/ripwire/commit/3d98f84d), in
[#135](https://github.com/redhat-et/ripwire/pull/135)).

### Fixed — caps that cut an answer now say so where they fire

A cap that cuts output silently makes an answer look complete. Each cap below now discloses only when it fires, so an
answer the cap did not touch is byte-identical to before. No cap value moved.

- **`--grep` and `--verify` matched lines** are cut at 512 bytes, and a 512-byte source line used to print the same
  payload as a truncated 50 KB minified line. The row now carries `line_bytes="N"`, the whole line's length. The payload
  itself stays raw file bytes, because `--and`/`--not` read the same line and `--at=` must reproduce it
  ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **Signatures** cut at 240 bytes now end in `…`, through the same truncator the other three signature cuts already use.
  This affects `--pack-signatures`, `--for`'s `<sigs>`, `<calls>` callee rows and `--lego`
  ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **A default `--for` named no ceiling.** Its 7,500-byte payload budget applies to every run, but only an explicit
  `--token-budget` was ever named. A trimmed default bundle now carries `budget_bytes="7500"` on its root, in the JSON
  dialect and in the MCP `for` verb ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **Several listings disclose their own cuts** ([#108](https://github.com/redhat-et/ripwire/pull/108)):
  - `--from-trace` discloses its name-ladder cut (`name_ladder_capped`), and `--handoff` its per-file symbol cut
    (`syms_capped`).
  - The expand and sibling lifts say when they re-ranked, and a malformed `RIPWIRE_EXPAND` or `RIPWIRE_SIBLIFT` is
    reported instead of being read silently as off.
  - The seven mention caps and three co-boost caps disclose on `--for`, `--pack-task` and MCP. Across a 195-invocation
    sweep, only four `--for` invocations changed (+106 B, where `doc_mentions_capped="1"` fired), and their ranked rows
    were identical once that attribute was stripped.
- **`--edit-check`** pages its context rows only. Flagged callers and their `sites_l=` never page, the verdict is computed
  before any window, and the root carries `est_tokens=`. A gate arm proves the verdict byte-identical at
  `--limit=1000000` ([#108](https://github.com/redhat-et/ripwire/pull/108)).

One cap was refuted rather than changed. `kSliceRdMaxIter` (64) cannot fire, because each slot of the reaching-definitions
lattice stabilises on the second round. Instrumented, the highest iteration reached was 1, over 4,528 loop fixpoints in
this tree's `src/` and on adversarial C and Python fixtures ([#100](https://github.com/redhat-et/ripwire/pull/100)).
Gate: `test/capdisclosurecheck.sh`, whose nine disclosure arms fail on the parent commit while every crossing and silence
arm passes.

### Fixed — a cut callee listing kept the lowest node ids, not the rows the question was about

A body's `<calls>` listing keeps at most sixteen callee rows. On `--for`'s bodies, `--pack-task`'s `<bodies>` and
`--from-trace`'s rank-1 body, the sixteen kept were the sixteen lowest node ids. The disclosure,
`<calls total="22" shown="14" capped="1">`, was honest about the count and silent about the choice.

A cut listing is now ordered by the query's rank, with ties broken by id:
- **The measured case.** On this repository, `--pack-task="merge scout conflict"` used to keep 13 of
  `computeMergeScout`'s 22 callees, six of them STL noise, with the merge-scout functions last. It now keeps 14, with
  those functions first.
- **`--from-trace`** ranks a callee that is itself a frame of the same trace ahead of the rest, so the edge the trace
  walked survives the cut.
- **Unchanged.** `--expand`, `--around` and `--exemplar` have no query, so they keep node-id order, byte-identical.

Gate: `test/callsrankordercheck.sh` ([#95](https://github.com/redhat-et/ripwire/pull/95)).

### Fixed — `--regex` anchors match per line, and a regex can no longer kill the run

`--regex` handed a whole file to one iterator, so `^` matched only at offset 0 and `$` only at end of file, in a verb
whose every answer is a single line. On llvm-project, `--regex='^#include'` returned 1,487 hits where a line-oriented scan
returns 289,646. Anchors now match per line, as `grep`, `rg` and editors read them. The scan is also faster on that corpus
(3.40 s against 4.48 s warm).

Disclosed narrowing: a match can no longer span lines, which `[\s\S]*` could do before. That is `rg`'s default contract
too.

- **Why not `std::regex::multiline`.** It is the obvious fix and is not used. Apple libc++ reads one byte before the
  buffer when matching at offset 0, and a 40-line standalone with no ripwire code in it faulted on 74 of this
  repository's ~130 headers.
- **A bad regex no longer ends the run.** A `std::regex_error` thrown mid-scan by catastrophic backtracking used to reach
  `std::terminate`. That file now degrades, and the scan continues.
- **`corpus_pruned_dirs=` on the `--grep` root** names the built-in directory denylist, which grep had never disclosed. On
  this repository `--grep='malloc('` served 33 hits with `complete="1"` where `rg` found 78, and the 45 missing lines
  were all under `third_party/`.

Gate: `test/grepanchorcheck.sh` ([#85](https://github.com/redhat-et/ripwire/pull/85)).

### Fixed — `--grep` no longer reads gitignored files the indexer skips

`--grep` and `--regex` also scan text files whose extension the indexer does not handle. That set was recorded before the
ignore rules were consulted, so a file that was both gitignored and of an unindexed extension was read and served. In the
measured case, that was four hits from a `.cpp.bak` that the repository's own `.gitignore` names. The crawl now consults
the ignore verdict before recording such a file, and `--no-ignore` restores it. On the reporting corpus,
`unindexed_files_scanned` went from 409 to 52. `docs/ARCHITECTURE.md` had still said `.gitignore` is not consulted; that
paragraph is corrected. Gate: `test/grepignorecheck.sh` ([#87](https://github.com/redhat-et/ripwire/pull/87)).

### Fixed — a revision reaches git only as a resolved commit (`--since`, `--merge-scout`, `--pr-context`)

Three verbs resolved a caller's revision with their own copy of the `rev-parse` probe. None of the copies held the whole
rule the shared resolver states: refuse a value that begins with `-` before git is asked, and trust only a bare 40- or
64-hex answer. All three now call `gitResolveCommitSha`. This is defence in depth, not a reachable exploit today, but two
of the gaps gave wrong answers at exit 0:

- **`--since`.** For `--since='^HEAD~3'`, `rev-parse --verify` answers `^<sha>` with status 0, so the run stamped
  `window="^HEAD~3" commits="0"` and exited 0. A date value beginning with `-` passed the date check and reached git's
  argv. Both now refuse, and `git log` receives the resolved commit instead of the caller's string
  ([#115](https://github.com/redhat-et/ripwire/pull/115)).
- **`--merge-scout`.** `--merge-scout=^HEAD~1` printed an empty `ok="0"` arm at exit 0. It now refuses with exit 1 and
  names the ref ([#116](https://github.com/redhat-et/ripwire/pull/116)).
- **`--pr-context`.** `--pr-context=--output=FILE` reached git as an argv entry and was stopped only by git's own
  `rev-parse`. ripwire now refuses it before git is asked ([#117](https://github.com/redhat-et/ripwire/pull/117)).

Valid refs give byte-identical output. The gates `test/sincecheck.sh`, `test/mergescoutcheck.sh` and
`test/prrefsafecheck.sh` log every git argv entry through a PATH shim, and each is red on the base binary.

### Fixed — a repository's hook-form `core.fsmonitor` no longer runs under ripwire's git calls

A repository can configure git to run an arbitrary command on git operations, and ripwire shells out to git during a
crawl. A hook-form `core.fsmonitor` in the crawl root would therefore have run under ripwire. It is now neutralised for
ripwire's own git children and disclosed on stderr and in `--doctor`. Gate: `test/githardencheck.sh`
([#80](https://github.com/redhat-et/ripwire/pull/80)).

### Fixed — JavaScript and TypeScript default imports resolve by what the module exports (parser version 83)

`import save from './storage.js'` bound to whichever function happened to be spelled `save`. It now binds to what
`storage.js` exports as default, with `prov="import"`:
- default declarations, local identifier defaults and `export { local as default }` are all covered;
- the existing lexical-shadow and module-ambiguity handling is reused;
- an anonymous default expression stays unresolved;
- conflicting default exports cannot pick a function just because it is the only function-shaped symbol.

Contributed by **@PollyBot13** ([#56](https://github.com/redhat-et/ripwire/pull/56)). The gate covers TS, TSX, MTS, CTS,
JS, JSX, MJS and CJS, with a same-spelled decoy in each arm. The version is 83 because #57 had already spent 82; the
record shape is unchanged.

### Fixed — an 8-bit counter overflow in four vendored grammar scanners (parser version 87)

Markdown's external scanner added a `size_t` column count into a `uint8_t`. One Rails guide, whose pipe-table row is
padded to 301 columns, made the ASan build exit 134 on that file alone. On the plain build the damage was a wrong parse at
exit 0, and only at widths just past a wrap. At 256 or 257 columns:
- an indented `# Buried` became a heading;
- a fence of that many marks never opened, so its body leaked out as live markdown.

Markdown's counters now saturate at 255, which every threshold they are compared against reads the same way as a larger
true value. The Rust, Lua and C# scanners take an explicit cast instead. Their counters close a token by matching the
opening count, and at 255, 256, 257 and 300 the output recovered identically in all three.

Output is byte-identical over 3,538 real `.md`/`.rs`/`.lua`/`.cs` files, but a constructed 256-column line does move, so
the parser version moves too. Gate: `test/vendorpatchcheck.sh` arm I, with every width pinned at exactly 256
([#102](https://github.com/redhat-et/ripwire/pull/102)).

### Fixed — the vendored YAML scanner's failure status survives an unsigned `char` (parser version 92)

tree-sitter-yaml returns its scan status through four functions declared plain `char`, and one of the values it returns
is `SCN_FAIL`, `#define`d `(-1)`. **`char` is unsigned on aarch64 Linux**, which is where the `linux-arm64` release
asset is built, so there the `-1` came back as 255, with two consequences:

- **A silent parse difference, in every build type the release ships.** The three `case SCN_FAIL:` labels never matched
  255, so a malformed `%`-escape in a tag or a `%TAG` prefix was swallowed into the token instead of ending it.
  `a: !<tag:x%zz> b` parses as `ERROR` under a signed `char` and as a clean tagged scalar under an unsigned one — the
  same bytes, a different tree, decided by the CPU the binary was built for. At the product level, a ripwire built
  `-funsigned-char` minted a key the signed build does not.
- **A sanitizer abort on ordinary YAML.** `scn_pln_cnt` reaches its `return SCN_FAIL;` on a plain `key: value` line, so
  G1's implicit-conversion check stops the run there. All three `test/yamlfix` files abort, which means an aarch64 Linux
  ASan build dies on the first YAML file it crawls.

CI could not see either symptom: both sanitizer legs have a signed `char`, and there is no aarch64 Linux leg.

The fix backports upstream's own change, **a1c4812a**, which no tagged release of the grammar contains yet: the three
`#define`s become an enum whose negative member forces a signed type, and the four functions return it. Its added and
removed lines are identical to upstream's, with only the vendor-patch markers ours. A cast was rejected because it
silences the sanitizer while still never matching `case SCN_FAIL:`.

Every `char` in the grammar sources was audited, not only the two functions the report named, and the rest of the family
was swept: a detector for negative returns through plain `char`, run over all 18 vendored `scanner.c` files plus the
Kotlin scanner, finds YAML only. On a signed-`char` host the default map, `--json` and `--skipped` are byte-identical
before and after, over the repository root, five fixture directories and the generated YAML corpora. Gate:
`test/vendorpatchcheck.sh` arm K builds the vendored grammar twice, once `-fsigned-char` and once `-funsigned-char`,
and asserts identical trees for ten fixtures — one per audited site, plus a control that reaches no failure path — and
that the unsigned build parses all of them and every `test/yamlfix` file clean under the implicit-conversion sanitizer.
On unpatched main five of the ten trees differ and twelve inputs abort under the sanitizer — nine fixtures, only the
control clean, and all three `test/yamlfix` files. `kParserVer` goes 91 → 92, because the extraction of real input changes
wherever `char` is unsigned and a cache blob cannot tell the two architectures apart; `kCacheVersion` stays 20
([#140](https://github.com/redhat-et/ripwire/pull/140)).

### Fixed — `--help=all` said `--situ` self-budgets through `--token-budget`, which `--situ` refuses

The `--top-k` paragraph listed `--situ` among the verbs that self-budget via `--token-budget`. Passing the two together
exits 1, and the refusal's own roster of honouring verbs does not name `--situ`; `src/situ.h` reads neither the token
budget, the max-tokens value nor `--top-k`. The sentence sent an agent to a flag that fails. Only `--situ` is removed
from it; `--pack-task`, `--from-trace` and `--run-trace` are in the refusal's roster and keep their place.
`docs/COMMANDS.md` mirrors the sentence and is generated, so it was regenerated through the repository's own recipe;
that also drops `--top-k` from `--situ`'s derived "Shaped by" list, which is the true statement
([#140](https://github.com/redhat-et/ripwire/pull/140)).

### Fixed — `CLAUDE_CONFIG_DIR` is respected

Every path that located Claude Code's config directory read `$HOME/.claude` and ignored `CLAUDE_CONFIG_DIR`, the variable
Claude Code itself honours. The installers, `skills/install.sh --hook`, `--scan-skills`, `ripwire wrap`'s detection and
`--doctor --agent=claude` now follow `${CLAUDE_CONFIG_DIR:-~/.claude}`, the pattern `CODEX_HOME`, `AGENTS_HOME` and
`HERMES_HOME` already use. Unset behaves as before, and set-but-empty counts as unset.

Contributed by **@s0undt3ch** ([#101](https://github.com/redhat-et/ripwire/pull/101)), who found six sites. Review found a
seventh, in `--doctor`: with the variable set, the installer deployed into the relocated home and reported success, and
`--doctor --agent=claude` then reported `claude-skills ok="0"` and told the user to re-run the installer that had just
worked. `test/claudeconfigdircheck.sh` is a census over executable code rather than a list of known sites, so an eighth
site would go red on the commit that adds it ([#105](https://github.com/redhat-et/ripwire/pull/105)).

### Fixed — `--edit-check`'s tests-to-run receipt gives the answer `--affected` gives

The receipt walked its own path instead of the one `--affected` serves, so the same change could get two different
answers depending on which verb was asked. It now routes through `--affected`'s answer, emits the same evidence tiers and
carries `order="evidence"`. `--pack-task` keeps its deliberately different row set, with the reason stated in the source.
The divergence surfaced while digging into two reports by **@YogevKr**
([#59](https://github.com/redhat-et/ripwire/issues/59), [#60](https://github.com/redhat-et/ripwire/issues/60)). This
change closes neither report; both remain open.

In the same change, a published capture whose `--at=` seed had drifted onto a different function (right shape, wrong
symbol, exit 0) is regenerated. Captures now derive each seed from source, and a gate arm requires every published seed
to resolve to the symbol its demo is about ([#89](https://github.com/redhat-et/ripwire/pull/89)).

### Fixed — two defects clang-tidy found once it could parse the tree

- **A file-handle leak.** `readWholeFile` skipped `fclose` on a short read. The reader is shared by the git-config probe,
  which runs at startup and per request under `--mcp`, and by the notebook reader.
- **Unchecked calibration variables.** The `RIPWIRE_*` ranking calibration variables were read with `atof`/`atoi`. `nan`
  passed through the clamp into every BM25 score, `8x` read as 8, and `notanumber` read as 0 and was clamped to the floor:
  three rankings nobody configured, each at exit 0. A value must now parse as one whole finite token; otherwise the
  default is used and one stderr line names the variable.

Both fixes are in [#120](https://github.com/redhat-et/ripwire/pull/120).

### Fixed — a call the resolver declined to guess at no longer reads as "no caller exists" (`declined=`, `declined_calls=`)

Tier 3 of the name-based resolver refuses a call whose candidates are two or more same-language definitions, none
in the caller's file or directory, and that no qualifier or receiver rule pins. That rule stands: guessing among
cross-directory same-named definitions is how false edges are born. But the refusal was silent — no edge, no `amb=`,
and `ambiguous=`/`unresolved=`/`external=` unmoved — so `--callers` on either definition answered `count="0"` about
a call the resolver had seen, and nothing said how often. At merge, on the `--no-cache` default map, it was 22.2% of
memgraph's call references (65,516 of 295,086) and 4.6% of ripwire's own (6,263 of 135,449); on the branch base it was
8.6% of retrofit's and 0.15% of llvm `lib/Support`'s.

The decline is now counted and shown, and no edge moves:

- The map header carries `declined=N` (JSON `"declined":N`), absent at zero; its legend entry appears only on a map
  that carries the attribute.
- `--callers`, `--callees` and `--impact` carry `declined_calls="K"` in XML, `--json` and `--format=columnar`, as do
  their MCP twins `find_referencing_symbols`, `find_symbol` and `impact`: declined calls that could have meant the
  selector's definitions (callers), that those definitions make (callees), or that could reach SYM or its radius
  (impact), counted once per call. Absent at zero, defined in the legend when present.
- `--pin-census` ends with a conservation line, `# dispositions calls=N …`: every call reference lands in exactly one
  of bound, self, external, unresolved, undefined, other_root, qualified_external, declined, file_scope or
  unaccounted, and `calls=` is re-derived from the references. A resolver exit that names no bucket lands in
  `unaccounted` and raises a degrade alert on plain builds, so the next silent `continue` is caught, not shipped.

Measured on the `--no-cache` default map, the base binary against the change. memgraph and ripwire were re-measured at
merge, on a tree that already carries the `std::`-qualified call guard; retrofit and llvm `lib/Support` are from the
branch base (5c808487), where each map's byte diff is exactly the new `declined=N` plus one legend comment (+245 to
+248 B) and `edges=`, `ambiguous=`, `unresolved=`, `locality_pinned=` and `external=` are identical on every corpus. At
merge, `edges=`, `ambiguous=`, `unresolved=` and `locality_pinned=` are unchanged everywhere.

| corpus | call references | `declined=` | share |
| --- | ---: | ---: | ---: |
| memgraph (at merge) | 295,086 | 65,516 | 22.2% |
| ripwire (at merge) | 135,449 | 6,263 | 4.6% |
| retrofit (branch base) | 29,983 | 2,587 | 8.6% |
| llvm `lib/Support` (branch base) | 20,425 | 30 | 0.15% |

memgraph peak RSS 621 → 630 MB (+1.5%, the candidate index behind `declined_calls=`); wall time unchanged (0.76 s →
0.75 s). A cache written by the pre-change binary reads back warm to output byte-identical with `--no-cache`, so no
cache or parser version moves. Gate `test/declinecheck.sh` covers 17 languages and was red on the pre-change binary
(50 FAIL / 38 PASS as first committed); `test/resolverhonestycheck.sh` F5 now requires the decline to be disclosed,
not merely edge-free.

The at-merge rows are lower than the branch base's (66,015 of memgraph's calls, 7,279 of 134,739 on ripwire's
5c808487 tree) because the `std::`-qualified call guard refuses some `std::` sites before they reach tier 3. The
`# dispositions` line balances with `unaccounted=0` on both; the guard's refusals count as `external`, and
`test/declinecheck.sh` runs the guard's own fixture (`test/stdqualfix`) to keep them there.

### Fixed — the super-linear warm floor under every graph-building verb (`--grep`, `--callers`, the map)

On llvm-project (182,555 files, warm cache) a `--grep` for an absent literal took 159.7 s, `--callers=main`
152.9 s and the default map 248 s, while the same crawl + cache load + model build without the graph took
3.8 s. Profiled to one operation: the resolver rebuilt a receiver type's inheritance cone (two BFS walks
with quadratic dedup) on every still-ambiguous receiver-typed call — 86,667 rebuilds for 2,984 distinct
types, 143 s of the 154 s run. `ChaConeMemo` (`src/graph.h`) computes each cone once with the identical
walk and cap; warm `--grep` is now 9.2 s, `--callers` 8.6 s, the map 10 s, and default maps are byte-identical
before and after on go and llvm. Gate `test/chaconecheck.sh`; the phase tables are in `bench/PROFILE.md`
and the evidence chain in `docs/EVALS.md` (2026-09-09).

### Fixed — a Ruby receiver's lazy bit is order-blind, and a deep constant chain no longer overflows the stack (parser version 86)

Two defects in the receiver round (parser version 84, the entry below; its branch numbered it 83), both found by
review after the merge and both reproduced before they were fixed. Contributed by **@andriytyurnikov**
([#78](https://github.com/redhat-et/ripwire/pull/78), landed in [#91](https://github.com/redhat-et/ripwire/pull/91)).

**A load-time site below a lazy one was lost.** The receiver dedupe keeps one `Include` per (file, innermost
open, written name), and the first occurrence in source order carried the lazy bit. A `Helper.fmt` inside a
method written *above* the same `Helper.fmt` at class-body level therefore left the directive lazy; resolve.h's
pair rule — one load-time directive makes the pair load-time — never saw the load-time site, and the
structure dropped a real dependency. Two files that differ only in the order of those two lines read `ccd="3"
shape="vertical"` with a god file one way and `ccd="2" shape="horizontal" lazy_edges="1"` the other. The lazy
bit is now the AND over every occurrence: the first site still carries the byte, and a later load-time site
clears the bit on the retained record (`captureIncludes`, `seenReceivers` now maps to the record's index).

**A 5000-segment chain killed the run.** `rubyIsConstantChain` recursed once per segment of a left-nested
`scope_resolution`, and the depth bound in `captureIncludes` sits *after* `directiveTargetOf`, so a generated
`A::A::…::A.call` of 5 000 segments overflowed a parse worker's stack — SIGBUS, exit 138, no output, measured
on macOS; 2 000 survived. The check is a loop now. Nothing else on the path recurses per segment: the walk is
an explicit stack, the resolver splits the text.

**`--help` said `lazy="1"` was TS/JS only.** It has read Ruby closures and autoloads since parser version 84;
the `--impact` line now says so, and `docs/COMMANDS.md` is regenerated from it.

Measured (`--deps --limit=100000`, parser version 83 → 86, the same four corpora as the receiver round; the
gems are Rails 7.2.3.2, the apps are the same two):

| corpus | ccd | nccd | shape | lazy_edges | bytes |
| --- | --- | --- | --- | --- | --- |
| activesupport `lib/` (282) | 15 299 → 15 299 | 7.59 → 7.59 | tangled | 945 → 935 | 75 970 → 75 988 |
| activerecord `lib/` (395) | 4 088 → 4 325 | 1.36 → 1.44 | vertical | 1 026 → 1 023 | 114 745 → 114 763 |
| a Rails app, 4683 files / 3532 `.rb` | 13 170 → 13 172 | 0.32 → 0.32 | horizontal | 5 632 → 5 630 | 750 913 → 750 915 |
| a second Rails app, 1967 / 1895 `.rb` | 6 382 → 6 382 | 0.34 → 0.34 | horizontal | 1 830 → 1 830 | 363 733 → 363 750 |

Read together: the pairs that flip are the ones written lazy-first and load-time-second in one body — ten on
activesupport, three on activerecord, two on the first app, none on the second — and on activerecord three of
them sit on a spine (ccd +237). No shape moves. Wall time unchanged. Cold == warm on activerecord and the
first app; two `--no-cache` runs identical on all four.

**Record shape unchanged**, so cache format 18 holds; the extraction identity moved (a cached lazy bit could be
wrong), so cached Ruby files re-parse once. `kIngestParserVerMirror` moves in the same diff. The version is 86,
not 85: main spent 85 on the plain-text prose tier before this landed, and a collision is resolved by
re-bumping over the tip, never by keeping the fork's value.

Gate: `test/rubyrecvcheck.sh` gains `lib/app/eager_after_lazy.rb` (18 fixture files; ccd 20 → 22, helper.rb
afferent 2 → 3, a row arm with no `lazy_edges=`, the `--impact=Helper` importer tier) and a deep-chain arm that
generates a 150 000-segment receiver at gate time and expects one directive and exit 0. Written red first: six
arms fail against the pre-fix binary — the eager-after-lazy importer reads `lazy="1"`, health reads
`ccd="21" lazy_edges="10"`, the deep chain exits 138. ASan/UBSan clean on both fixtures, the deep chain, and
the cache round-trip. Re-pins with reasons in-file: `qschemetrip.hash` (parser mirror), `printf_parity.manifest`
(`help` and `impact` bytes — the `--impact` import-tier legend moved with the `--help` line).

### Added — a Ruby constant receiver is a dependency (parser version 84)

Round two of the Ruby constant work. Parser version 82 gave the declarative spellings — `class X < Base`,
include/extend/prepend, `autoload :Name`. This round adds the one a Zeitwerk application actually depends
through: a **constant receiver** — `User.find`, `App::Mailer.deliver`, `Struct.new`. The autoloader loads
lib/app/user.rb on that first reference, and nothing else in the file says so.

Contributed by **@andriytyurnikov** ([#65](https://github.com/redhat-et/ripwire/pull/65)). The round was measured and
gated on its branch as parser version 83 and shipped as 84, because the JavaScript and TypeScript default-import fix had
taken 83 first; the version numbers in this entry's tables and gate notes are the branch's.

Four decisions, each stated in `test/rubyrecvcheck.sh`'s header rather than asked:

1. **What counts.** A `call` whose receiver is a constant or a constant chain (`A::B::C`, `::A::B`), spelled
   as written. A chain whose head is not a constant — `repo::Finder`, `self.class`, an identifier, an ivar —
   is nothing (`rubyIsConstantChain`; the round-one reader accepts any scope-resolution text and is right
   for the positions the grammar already restricts to constants, a receiver is not one). A constant used as an
   **argument** (`raise Errors::Boom`, `validates_with Foo`) or as a rescue class is **not** a receiver: a
   disclosed floor of this round.
2. **Dedupe at extraction**, per (file, innermost class/module open, written name). Zeitwerk loads a
   constant once per process, on its first reference; the second `User.find` in the same body is not a new
   dependency. The first occurrence in source order carries the byte and therefore the lazy bit. The nesting
   is in the key: `User` under `module Admin` and `User` under the enclosing module may be two constants, and
   the fixture has that file. `Time` and `::Time` are two spellings, two directives. The declarative shapes
   stay one directive per occurrence — each is a statement. Measured with the Prism prototype: distinct
   (file, nesting, name) is 61 % of raw receiver sites on activesupport, 67 % on activerecord, 56 % and 53 %
   on the two Rails apps.
3. **Lazy inside a closure.** A receiver inside a `method`, `singleton_method`, `lambda`, `block` or `do_block`
   is `lazy="1"` — it runs when and if that closure runs, the parser-72 TS/JS function-body rule on Ruby's
   own closure kinds (`kRubyClosureContainers`). A receiver at class-body or file level runs at load. A
   `do`-block passed to a class-level macro (`included do`, `after_commit do`) is lazy under this rule even
   when the callee runs it at load: the tool cannot see the callee, and a block is a closure it may or may
   not run. `--impact`'s importer tier says `lazy="1"` only when every edge from that importer is lazy.
4. **Resolution is round one's, unchanged.** Module.nesting innermost-first then Object, `::` absolute,
   wrapper opens define nothing, genuine reopenings fan out, a same-file reference is shown and dropped as a
   self-include. An out-of-tree receiver (`Time`, `Struct`, `Object`) is a shown `<inc t=>` row with no edge —
   the posture every Python `import os` row already has.

**The Ruby walk now descends every node.** A receiver is an expression — under an assignment, an argument
list, a lambda, a binary, a string interpolation — so the statement-level container allowlist Ruby had through
parser version 82 (19 kinds) would have needed ~40 and every kind it missed would have been a receiver
silently dropped, a floor the tool could not disclose because it could not see it. The full descent is the
cost the reference pass already pays once per Ruby file. The depth bound (256) still degrades loudly.
`--deps --limit=100000 --no-cache` wall time on a 4683-file Rails app: 1.04 s → 0.92 s (noise); on
activerecord `lib/` 0.21 s → 0.18 s.

**Structure versus use — the decision this round adds, and it reaches TS/JS too.** With receivers counted
like every other edge, a Ruby codebase is one strongly-connected core at the file level: models name each
other, base classes name their subclasses through registries, and the cone of a controller is most of the
application. Measured before the cut, `--deps --limit=100000` on a 4683-file Rails app went ccd
12 740 → 1 407 232, nccd 0.31 → 33.74, and every Ruby corpus read `shape="tangled"`. That is a true fact
about runtime references and a useless one for a lens: a reading that is the same everywhere is not a
reading. So a **lazy edge** — a (from, to) pair every one of whose directives is written inside a closure
(a Ruby method/lambda/block, a TS/JS function body) or is a Ruby `autoload` — is a **use**, not a load-time
dependency, and the two views now say different things on purpose:

- **Use** — `--impact`'s importer tier (`lazy="1"`), the file's own `<inc t=>` rows, call-resolution
  narrowing, `--expand`'s siblings and `--cochange`'s static-coupling test all keep every edge. "Who uses
  `User`?" is answered by all 197 files that call it.
- **Structure** — `--deps`, `--arch` and `--report` measure the load-time graph: `afferent=`, `instab=`,
  `transitive=`, godfiles, stabledeps, cycles, ccd/acd/nccd and `shape=` leave lazy pairs out
  (`graph.h::resolveStructuralIncludeAdj`; one load-time directive makes the whole pair load-time, the
  parser-72 `recordLazyPair` rule). The cut is disclosed where it is made: `<health lazy_edges=N>` counts the
  distinct pairs left out and a file row carries `lazy_edges=N` for its own, both absent when 0 — so a corpus
  with no lazy directive is byte-identical to before. A lazy edge is not an unresolved one: the unresolved
  row has neither `lazy_edges=` nor an importer; the lazy row has both.

This changes one TS/JS number: a `require()` inside a function body (parser version 72) was already
`lazy="1"` in the importer tier and is now also out of `--deps`' structure. On this repo's own fixtures no
gate pinned it inside the cone. `--deps --limit=100000`, parser version 82 → 83 (`files=` is the listing's
own denominator: files with a row; `<godfiles total=>` the uncapped load-time importee count):

| corpus | files= | ccd | acd | nccd | shape | importees | lazy_edges | `--deps` bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| activesupport 7.2.3.2 `lib/` (282) | 206 → 241 | 10 450 → 15 299 | 37.2 → 54.4 | 5.19 → 7.59 | tangled → tangled | 241 → 201 | 945 | 55 483 → 75 970 |
| activerecord 7.2.3.2 `lib/` (395) | 300 → 368 | 2 714 → 4 088 | 6.9 → 10.4 | 0.90 → 1.36 | horizontal → vertical | 385 → 310 | 1 026 | 71 474 → 114 745 |
| a Rails app, 4683 files / 3532 `.rb` | 2 296 → 3 245 | 12 740 → 13 170 | 3.3 → 3.4 | 0.31 → 0.32 | horizontal → horizontal | 385 → 414 | 5 632 | 378 473 → 750 913 |
| a second Rails app, 1957 files / 1895 `.rb` | 1 072 → 1 455 | 6 289 → 6 382 | 3.3 → 3.4 | 0.33 → 0.34 | horizontal → horizontal | 189 → 197 | 1 830 | 173 606 → 363 733 |

Read the two halves together: on the Rails apps the structure barely moves (class-body receivers are few)
while `lazy_edges` says how large the runtime layer the structure leaves out is — 5 632 pairs on the first
app, where the importer tier now names them all. On the gems the structure grows because a gem does depend at
load time through class-body receivers (`ActiveSupport.on_load`, `Concern`), and importees FALL (241 → 201,
385 → 310): a file whose only importers call it from inside methods is no longer a god file, it is a file
`--impact` lists. The uncapped `<inc t=>` listing on activerecord carries 2 228 rows over 1 188 distinct
targets, the most frequent being `ActiveSupport::Concern` (57, out of tree, shown, no edge).

**Default map.** Byte-identical on a Ruby-free corpus (this repo's `src/`, modulo version stamps). On Ruby
corpora the ranking moves a little (activesupport `est_tokens` 15 745 → 15 688, `pr_iters` 56 → 54) because
include edges narrow ambiguous call resolution and there are more of them; no `id=` row moves — `scope` is
still the immediate enclosing name.

**Record shape unchanged.** A receiver is an `Include` with `isSymbolic` and `byte` (both parser version 82),
so cache format 17 holds and only the extraction identity moved: cached Ruby files re-parse once. Cold and
warm caches agree on activerecord and the 4683-file app (gated on the fixture).

**Round one's gate moved two arms, honestly.** `test/rubyconstfix`'s `dynamic.rb` (`include
Object.const_get(:Trackable)`) now has a row — the `Object` receiver, not the include, and the arm asserts
exactly that; `point.rb` (`Point = Struct.new`) has a `Struct` row with `afferent="0"` — the alias is still
not indexed, the floor note stands.

Gate: `test/rubyrecvcheck.sh` + `test/rubyrecvfix/` (17 files — dedupe across seven receiver sites, two
nestings of one name in one file, four laziness levels, lexical versus absolute, the Object-level fallback
for a module-less script, a self-include, five non-constant receiver shapes, the Struct alias floor, the
argument/rescue floor, a same-basename decoy, the structure-versus-use cut — ccd 20 over 17 files with
`lazy_edges="9"`, App::User with four lazy importers and no `--deps` row, a lazy row told from an unresolved
one — root-spelling parity, determinism, warm == cold, well-formedness). Written red first: 14 arms fail
against the parser-version-82 binary and 7 more against the receiver build before the cut; every mutation
control and floor arm passes there. 558 → 559 gate scripts.

### Added — Ruby constant references are dependencies (parser version 82, cache format 17)

A Zeitwerk application spells almost none of its dependencies with `require`: a controller depends on a
model by **naming the constant**, and a Rails gem declares half its structure with `autoload :Name`. Parser
version 81 gave Ruby `require`/`require_relative`/`load`; this round adds the constant spellings, so the
file graph `--deps`/`--arch`/`--impact`/`--cochange` see is the one Ruby actually has:

| Spelling | Directive | Resolution |
| --- | --- | --- |
| `class X < Base` | the superclass constant | index, lexical rule (below) |
| `include M` / `extend M` / `prepend M` | one directive per constant argument | index, lexical rule |
| `autoload :Name` (ActiveSupport::Autoload) | the constant | index, lexical rule; `isLazy` |
| `autoload :Name, "path"` (Kernel#autoload) | the **path**, as one directive — never the constant beside it | the load-path rule, as a `require`; `isLazy` |

**The rule is Ruby's own, not a convention.** Every `class`/`module` open in the corpus is recorded with its
name as written (`Base`, `App::Audited`, `::Top`) and its byte span (`ConstOpen`, `src/model.h`). An open's
nesting is its enclosing opens by span containment — the same containment that attributes a call to its
def — and its fully-qualified constant follows: `::X` is absolute; a compact `class A::B` inside `module X`
names `X::A::B` when the tree opens `X::A` anywhere, else `::A::B` (Module.nesting first, then Object). A
reference `Name::Sub` at nesting `[A, A::B]` is looked up as `A::B::Name::Sub`, `A::Name::Sub`,
`Name::Sub`; first hit wins. A superclass carries its class's own start byte, so it resolves in the
**enclosing** scope, exactly as Ruby evaluates it. Constant targets are never probed as paths
(`Include::isSymbolic`): `require "Foo"` is legal Ruby, and on a case-insensitive filesystem a path probe for
`Trackable` lands on `lib/trackable.rb` — the fixture's decoy pins it.

**Two kinds of "defined in many files", told apart structurally.** `module App` is opened by every file under
`lib/app/`. An open whose body holds nested opens and **nothing else** is a *namespace wrapper*: it nests,
but it defines nothing of `App` and is not a definer in the index (`ConstOpen::namespaceOnly`, read off the
body's children — comments are extras and are skipped; an EMPTY open defines). A reopening **with** a body — a
monkey patch, a decorator, a `core_ext` — is a real second definer, and a reference then edges to **every**
definer: change any of them and the constant changes, which is what `--deps` measures. That is multiplicity
(every answer is right), deliberately distinct from the specifier ambiguity every other Step-A degrades on
(`require "shared"` answered by two files: exactly one is right, and this tool cannot tell which). Only the
latter resolves to nothing. Measured with a Prism prototype of the same lexical rule on a 3532-file Rails
app: 124 constants were "multiply defined" by opens, **5** by bodies, and treating wrappers as definers was
what made 246 superclass references ambiguous there (0 after).

**Measured** (`--deps --limit=100000 --no-cache`, both binaries from this tree; `importees` is the
uncapped `<godfiles total=>` — files with at least one incoming edge — and `edge-bearing` is `<deps files=>`):

| corpus | ccd | acd | nccd | shape | importees | edge-bearing files |
| --- | --- | --- | --- | --- | --- | --- |
| activesupport 7.2.3.2 `lib/` (282 files) | 3658 → 10450 | 13.0 → 37.2 | 1.82 → 5.19 | vertical → tangled | 194 → 241 | 194 → 206 |
| activerecord 7.2.3.2 `lib/` (395) | 947 → 2714 | 2.4 → 6.9 | 0.31 → 0.90 | horizontal | 214 → 385 | 108 → 300 |
| a Rails app, 4683 files / 3532 `.rb` | 5638 → 12740 | 1.5 → 3.3 | 0.14 → 0.31 | horizontal | 103 → 385 | 1154 → 2296 |
| a second Rails app, 1957 / 1895 `.rb` | 5483 → 6258 | 2.9 → 3.3 | 0.29 → 0.33 | horizontal | 80 → 189 | 619 → 1066 |

ActiveSupport turning `tangled` is `core_ext`: `String` is reopened with a body in 15 files, so every
`< String` and `include`-of-a-patched-module depends on all of them — true, and the point of `core_ext`.
The **default map** is byte-identical to the pre-change binary on four Ruby-free corpora (this repository
and three others) and moves on Ruby ones only through the call graph's same-include tier: ActiveSupport
`edges=` 3729 → 3715, `ambiguous=` 409 → 406; ActiveRecord 8397 → 8298, 1284 → 1105.

**Floors, each pinned by an arm of `test/rubyconstcheck.sh`.** The ancestor half of Ruby's lookup (a
constant inherited from a superclass or an included module) is not walked. `Point = Struct.new(…)` is an
alias, not an open — `queries/ruby/tags.scm` skips CamelCase assignments and so does the index. `include
Object.const_get(:X)`, `autoload :X, some_path`, `require some_variable` capture nothing. Constant
**receivers** (`User.find`) are not this round: they are the bulk of a Zeitwerk app's edges and move every
Ruby denominator again, so they land as their own change with their own table.

**Record shape.** `Include` gains `isSymbolic` and `byte`; the per-file cache record gains the `ConstOpen`
family after `routeUses` — `kCacheVersion` 16 → 17 (a format change; the parser-version bump re-ingests
every cache anyway, so no extra cost). `Symbol::scope` stays the *immediate* enclosing name by design; the
fully-qualified constant lives only where it is needed. `--impact`'s importer tier reports `lazy="1"` for
an `autoload`, as it does for a function-body `require()`.

**Expired floor.** `test/rubyrequirecheck.sh` arm 3(c) pinned "`autoload :Late, "lib/helper"` is not
captured" since parser version 81. It now is (12 directives on that fixture, not 11; `lib/helper.rb`
afferent 2 → 3), and the arm was inverted rather than deleted so the expiry is on the record.

Gate: `test/rubyconstcheck.sh` + `test/rubyconstfix/` (30 files — nesting, compact and absolute names,
lexical shadowing, the three mixin verbs, `autoload` plain / in `eager_autoload do` / in `autoload_under
do` / with a path, a monkey-patched in-tree class, a patched core class, a namespace with 23 wrapper opens
and one real body, a wrapper-only reopen, out-of-tree constants, a same-basename decoy, a same-file
reference, two sites sharing an innermost open but not a nesting chain — `module A; module B` versus the
compact `module A::B`, where only the first can see `A::Helper` — root-spelling parity, determinism,
warm == cold, well-formedness). The chain pair was added after review: the resolver's memo was keyed on
the innermost open alone, so whichever site was visited first fixed the other's answer, and cold and warm
caches visit the sites in different orders — the fixture gave the helper two importers cold and none warm.
The memo is now keyed on the whole chain. Written red first: 24 arms
fail against the parser-version-81 binary, every mutation-control and floor arm passes there. 557 → 558
gate scripts.

Contributed by **@andriytyurnikov** ([#57](https://github.com/redhat-et/ripwire/pull/57)).

## [0.5.0] — 2026-09-07

**The first release carrying outside contributions.** Three people who do not work on this project
wrote fixes that are in this binary — Michael Freeman, PollyBot13 and Andriy Tyurnikov — and three
more found things it got wrong: Cort Fritz, stalep and Jan Mangs. All six are named below, beside
what they found. That is what this number is for.

### Added — Elixir, as a first-class indexed language

A vendored tree-sitter grammar and call-graph extraction, with protocol implementations indexed as
their own definitions. Contributed by **Michael Freeman**
([#43](https://github.com/redhat-et/ripwire/pull/43)), rebased onto main's tip — the extraction
identity is 78, not the 83 the fork carried — and extended with two gaps the fork could not see from
where it sat. The import edges are described in their own section below.

### Added — `<recent>` answers "what changed", not "what churns"

`--rank-by=churn-decay` emits a file-level `<recent>` block ordered by newest commit first rather
than by heaviest weight. A question about what changed recently was being answered with what changes
most often, which is a different question. The MCP instructions carry the deferral hint.

### Added — tests-to-run rows in evidence order

A changed test file comes first, then its stem partner, then graph hops, and each row says *why* it
is there. A test file that is itself in the diff is an obligation on its own evidence. The silent
zero on that surface is fixed: an empty result now says so.

### Fixed — named JavaScript and TypeScript import aliases

`import { a as b }` resolved to the wrong symbol, and the refusal path deleted edges that were
correct. Contributed by **PollyBot13**
([#45](https://github.com/redhat-et/ripwire/pull/45)). The refusal now reports which of the three
things it knew rather than collapsing them into one message.

### Fixed — five languages were invisible to the unanalyzed-language disclosure

`filesByLang` was sized with a hardcoded `16` while the `Lang` enum had grown to 21, so TOML, YAML,
PHP, Lua and Elixir were dropped from the count silently — and two of them were named in
`kUnanalyzedLangs`, meaning the lens promised to declare them and could not. Found by **Cort Fritz**
on his own fork. The array is now sized by `kLangCount`, with a `static_assert` that fails the build
if the enum outgrows it again. **A disclosure surface that under-reports is worse than one that is
absent**, which is why this is the fix in this release that mattered most.

### Fixed — the MCP tool schema a strict client refuses

One tool declared a union type that stricter MCP clients reject outright, taking the whole server
down with it ([#48](https://github.com/redhat-et/ripwire/issues/48), reported by **stalep** against
opencode with `@ai-sdk/google-vertex`). Gated by `test/mcpstrictschemacheck.sh`, written red against
the binary that had the bug.

### Fixed — twenty first-run defects a stranger hits and a maintainer never does

`PATH` not printed on install, a borrowed query in the quickstart, shallow clones mishandled, two
inverted `--doctor` verdicts, lock-file litter, sidecars that did not say what they dropped, an empty
map that read as an answer, and an upgrade path that left a binary which could not run and reported
success. Found by auditing the install as somebody who had never run it.

### Changed — the README leads with the proof

The ten-moments token table and the graphs now sit under the install block: **300 words to the first
piece of evidence instead of 1,009**. Twenty-six prose blocks moved behind `<details>`, each with a
summary carrying its own number, so the page makes the same case whether or not anything is clicked.
Nothing was removed — the full read is longer than before, because the summaries are additive.

### Changed — Graft folded into the lineage ledger as the 42nd repository

A registered head-to-head against Graft 0.17.0 ran, its losses were converted into code, and it was
re-run: 14 of 30, with the placebo arm at 13-12-5. **The stop condition fired, so no ranking claim is
published from that round.** What shipped is the two fixes it produced — tests-to-run in evidence
order, and `<recent>`.

### Changed — CI shards its gate suite across runners

Each release leg's gates split across runner jobs, so the workflow's wall clock is one shard rather
than one suite. Main runs are no longer cancelled by the next push.


### Changed — every skill description rewritten under the client budget, and one skill folded away

Reported and **measured** by [@jmangs](https://github.com/jmangs) in #49: Codex silently shortens skill
descriptions to fit its context budget, keeping the first ~350 characters of each. All eighteen ripwire
descriptions were over that budget — **18,455 characters authored, 6,300 retained, 12,155 discarded**,
fifteen of them cut mid-token. What the truncation removed was the routing boundaries: the "NOT for X,
that's skill Y" clauses, the secondary triggers, the misuse warnings. His diagnosis is the one this round
acted on, and it is worth quoting: the shortened descriptions "do not become literally identical — the
problem is semantic: related skills lose the clauses that distinguish them."

That reframed the task. Eighteen skills whose boundaries need a thousand characters each to explain are
eighteen skills whose boundaries are not carrying their own weight; the budget did not create the routing
problem, it exposed it by deleting the prose that was compensating. So the round asked what set of skills
has boundaries an agent can tell apart *in* 350 characters, rather than how to compress the existing ones.

Pre-registered before any description was touched (`docs/EVALS.md`), with a truncation-aware A/B whose
baseline was today's descriptions **truncated** — the thing users actually have — not today's full text.
The registered set-total ceiling was amended 4,800 → 5,400 and a third blind rater added, both **before**
measurement rather than after. Three LLM raters, sealed held-out set. The result was a **REJECT on the
registered band**, published as such; the parts that stood were kept, including folding
`ripwire-efficient` into `ripwire-orient` — the one boundary all three raters independently could not
distinguish. `test/skilldescbudgetcheck.sh` now pins every description under the budget, with a
binary-backed arm reading the binary's own skill discovery, so this cannot drift back silently.

### Added — Bash, Lua, Ruby and Elixir get import/dependency edges (parser version 81)

Four languages that emitted **no dependency record on any tree** now emit one per directive. Each spells a
real file dependency, and each spells it as an ordinary CALL rather than a reserved statement — which is
why `directiveTargetOf` had no branch for any of them, and why `lintrules.h::dependencyCapable` called all
four incapable. That was a true statement about this extractor and a false one about the languages.

| Language | Directives captured | Resolution rule |
| --- | --- | --- |
| Bash | `source FILE`, `. FILE` | the argument IS the path — no convention to model. A `$VAR`/`$( … )` anchor is reduced to its literal tail and probed against the includer's directory and every ancestor, unique-or-degrade |
| Lua | `require "a.b"` | package.path's dotted convention (`a.b` → `a/b.lua`, or the package form `a/b/init.lua`), probed from the requiring file upward and under the `src/` and `lua/` source roots |
| Ruby | `require_relative`, `require`, `load` | a leading dot means file-relative (the extractor normalizes `require_relative "x"` to `./x`); a bare specifier is searched against the crawl root plus `lib/`, `app/`, `test/`, `spec/` |
| Elixir | `alias`, `import`, `require`, `use` | the corpus's OWN `defmodule` index, not a `MyApp.Foo` → `lib/my_app/foo.ex` path convention — so umbrella layouts and generated paths resolve, and a module two files define resolves to neither |

Every rule is unique-or-degrade: two candidate files answering one specifier resolve to **neither**. There
is no basename fallback anywhere in this, which is the one shortcut that would have made all four look
better on a benchmark and been wrong invisibly.

**Measured on this repository** (`ripwire . --deps`): 29 `source` directives across 28 gate scripts, 26 of
them resolved. The 3 that do not are `. /dev/stdin <<EOF`, an absolute path outside the crawl — shown as a
target row with no edge, never dropped. All 29 specifiers in this tree are `$ROOT/…`, so a literal-only
resolver would have resolved zero of them.

**Disclosed floors.** A shell specifier whose FILENAME is variable (`"$1"`, `"$d/$n.sh"`) cannot be
resolved by anything short of running the script: it is captured, displayed, and produces no edge. Ruby's
`autoload :Foo, "path"` is not captured (its path is argument two). An Elixir `alias A.B.C` also binds the
local name `C`, so a later `C.f()` means `A.B.C.f` — the FILE edge lands, the NAME alias does **not** narrow
call resolution, because the call's receiver is not kept by `queries/elixir/tags.scm`. Quoted Elixir AST
(`quote do … end`) is descended into, so an `alias` inside a macro template is captured: the same
union-over-arms posture the preprocessor tables take, a spurious edge rather than a missing one.

### Changed — the dependency denominator moved, and now says so

Making four languages dependency-capable changes **five denominators and one predicate**: `--deps`'s
`dep_files=`/`ccd`/`acd`/`nccd`, `--arch`'s `propagation_cost`, and `--cochange`'s pair filter. Any number
recorded against an older build on a corpus holding Bash, Ruby, Lua or Elixir has moved. On this repository
`dep_files` went 758 → 1392 and `nccd` 0.68 → 0.39.

`--deps` therefore publishes **`<health dep_langs=>`** — the capable language set, derived from the
predicate itself so it cannot drift from what it documents. A `dep_files=` number is only comparable across
builds when `dep_langs=` matches, and until now the set behind it existed only in a source comment.

**`--cochange`'s `surprising=` is now a PAIR question.** It was "both sides dependency-capable", which
agreed with the truth only while `.sh` was incapable. The moment a shell script became capable, that form
would have declared `test/foo.sh` ↔ `src/bar.h` a pair whose missing static dependency is *evidence* — and
no `source` can name a header. Measured before the change: of 153 `dep_capable="0"` rows in this repo's top
400, the per-file form would have turned 88 capable and **75 of those are cross-dialect** pairs that would
have read as hidden architectural debt. The predicate now also requires a shared dependency dialect, which
additionally fixes 22 pre-existing over-claims of the same shape (`.js`↔`.h`, `.py`↔`.h`, `.py`↔`.cpp`).

**Markdown stays excluded, now on the record.** Markdown *does* mint doc→doc link edges — `[B](b.md)` is a
real edge and the map shows it — so "no import syntax" was never the reason. It is excluded because `--deps`
and `--arch` measure change amplification, and a README linking twelve design docs is not twelve files of
it: docs are read, not compiled. JSON/TOML/YAML have no file-level import at all.

**Fixed while building this:** the root-relative probe every unknown-anchor rule needs was anchored at an
empty base, which is the crawl root only when the root was written as `.`. The same tree scanned as
`ripwire /abs/path` resolved 13 of 29 `source` directives where `ripwire .` resolved 26. Probing the
includer's ancestor chain instead is root-spelling independent, and each new gate asserts the two spellings
produce identical edges.

Five new gates: `test/bashsourcecheck.sh`, `test/luarequirecheck.sh`, `test/rubyrequirecheck.sh`,
`test/eliximportcheck.sh`, `test/deplangscheck.sh` (550 → 555). `test/luacheck.sh` §2 was **inverted** — it
used to assert `<deps files="0">` on a Lua corpus, which is the assertion that would have kept this defect.

### Fixed — Ruby: definitions carry their enclosing class/module, and `def name=` is indexed and called

Landed from PR #47 (Andriy Tyurnikov), rebased onto the Elixir and ES-import work. Two Ruby extraction
defects, plus one resolver defect that turned out not to be Ruby's at all.

**A Ruby `def` had no scope.** `src/ingest_sidecap.h` set a definition's `scope` for C++, Python and Rust
only, so no Ruby row ever carried an `id=`: a `Scope::name` selector (`--expand=B::initialize`,
`--callers=A::helper`) could not address a Ruby method, same-named methods in different classes of one file
folded into a single `overloads=N` row, and `--edit-check=Widget::resize` answered "symbol not found".
(PR #47 also listed `editcheck.h`'s implicit-receiver exemption as a dead branch the scope revives. It does
revive it, and it is still inert: Ruby has no implicit receiver parameter to exempt, and the caller test
short-circuits on `arityExact == 0` — which `cc_paramArityExact` gives every Ruby definition, since its
language gate does not list Ruby. Measured `incompatible="0"` scoped and unscoped, before and after. The
comment there now says so rather than implying a recovered signal.) `rubyEnclosingScopeOf` (`src/ingest_names.h`) records
the nearest enclosing `class`/`module`: it walks THROUGH `class << self`, skips the definition's own node
(a `class Widget` inside `module Outer` scopes to `Outer`, never to itself) and takes the last segment of a
`class Foo::Bar` name, matching the contract C++'s `qualifierOf` already keeps. A top-level `def` still has
no scope and no `id=` — a file is not a scope.

**`def name=(v)` was never indexed, and `obj.name = v` called the getter.** tree-sitter-ruby names a setter
with a `(setter)` node, which `queries/ruby/tags.scm`'s method pattern did not accept. And `obj.name = v`
parses as `(assignment left: (call method: (identifier)))` — the same `(call)` shape as the read
`obj.name` — so the call rule captured a reference to `name` and the resolver handed a WRITE to the getter:
a false edge, not a floor. The setter is now named `name=` on both sides: the definition from the
`(setter)` node's own text, the call site by reading the assignment parent (`rubyCallIsAssignmentTarget`).
`self.name = v` inside the class pins to `Class::name=` through Rule 1, and `--callers=name=` answers.

Three resolver-side changes ride along so the new scope adds precision without losing edges: Ruby call
receivers are classified (`src/ingest_binds.h` — `self.m` is `ThisObj`, `x.m` is `NamedVar`, a receiver-less
`m(args)` stays bare); Rule 1 (`src/resolve.h`) treats a bare Ruby paren call as the implicit-self send it
is, so `helper(2)` inside `class A` pins to `A::helper` as a FACT rather than as a disclosed locality guess
(`lpin=`); and the S6-C locality tie-break (`src/graph.h`) no longer lets the caller's own definition win.

**The tie-break fix is not Ruby's, and is disclosed as such.** A candidate that IS the caller matched itself
on every locality segment, won alone, and was then dropped at emission as a self-loop — the site produced no
edge at all, silently. Ruby's facade idiom surfaced it, but the shape is language-agnostic: the same fixture
in PYTHON goes from `edges=0` to an honest 2-way split with `amb="1"` (`test/lpincheck.sh` arm (I), the
language-agnostic pin — revert that one line and it goes red before any Ruby gate does). Measured across
eight Ruby-FREE corpora (rocksdb, duckdb, ugrep, django, ccxt, mlflow, cpython and one large
ObjC++ tree —
`--no-cache --top-k=100000`, every row and every edge compared): the change is **edge-ADDITIVE, 0 edges lost
anywhere**, `symbols=`, `unresolved=` and `external=` unchanged, `edges=` +0.02% (ccxt) to +0.33% (rocksdb),
and `locality_pinned=` up where an edge that used to vanish is now emitted as a disclosed guess (rocksdb
141 → 587, duckdb 171 → 575, cpython 556 → 709, the ObjC++ tree 100 → 237). A control binary carrying
other change with only that line reverted is BYTE-IDENTICAL to the pre-merge tip on all eleven Ruby-free
corpora — so nothing else in this change moves any other language.

Measured on Ruby 2.6's own stdlib (833 `.rb` files, `--no-cache --top-k=100000`, byte-identical across runs,
`xmllint --noout` clean): `symbols=` 14220 → 14476 (250 setter rows, 253 definitions, where none were
indexed before); rows carrying `id=` 97 → 13191; rows carrying `overloads=` 649 → 194; call edges naming a
setter 0 → 534; `ambiguous=` 5872 → 5544; `edges=` 29077 → 28840 — a NET DROP, because a write against a
setter the tree does not define no longer invents an edge to the getter. **The `id=` attribute is what a
scoped row costs**: the full map's `est_tokens` rose 504107 → 816226 on that corpus and the default 200-row
map's 8796 → 12313 (+40%), the same price Python already pays. Non-Ruby corpora pay ~1% (rocksdb 14652 →
14826).

**Stated floors, each pinned by a gate arm so it stays a decision.** `rubyCallIsAssignmentTarget` reads a
plain `(assignment)` only, so a compound `w.count += 1` and a conditional `w.count ||= 1` (both
`operator_assignment`: they read AND write, and one capture carries one name) and a multiple assignment
`a.count, b.count = 1, 2` (a `left_assignment_list`, one level deeper) all keep the getter edge only.
`attr_accessor` / `attr_writer` / `attr_reader` generate their methods at load time and define nothing in
the source text, so they are not symbols and a write against one resolves to an honest NOTHING — unchanged
by this work, and now asserted. And the tie-break fix is the tie-break only: one layer up, tier 1 admits
same-FILE candidates and stops if any exist, so a caller that is the only same-file candidate is still
selected alone and still dropped to nothing (`def prerelease=; set.prerelease = v; end` in one file with the
real `prerelease=` in another). Widening tier 1 past the caller would mint a cross-file edge the same-file
tier already outranked, so the honest nothing stands.

`kParserVer` 79 → 80 with `quality.h`'s `kIngestParserVerMirror` in the same commit (the fork carried 79,
which the Elixir and ES-import bumps had already taken — re-bumped to the next free number over the merged
tip, per the rule in `src/ingest_cache.h`); `kCacheVersion` stays 16, no record shape moved. Gates:
`test/rubyscopecheck.sh` (scope shapes, the `Scope::name` selector, the overload split, facade delegation,
Rule 1 pins, a hoist mutation, determinism), `test/rubysettercheck.sh` (definitions, write vs read edges,
the explicit `w.name=(4)` and chained `w.inner.name = 5` spellings, four stated floors, `--callers` on both
names, a write-to-read mutation, determinism) and `test/lpincheck.sh` arm (I). Both new gates were run
against the PRE-fix binary and fail there (18 and 12 failing assertions), which is what makes them evidence.


## [0.4.0] — 2026-09-06

**This section spans everything since 0.2.2, not since the last tag.** v0.3.0 through v0.3.8 were cut
and published as release binaries without changelog sections of their own; rather than reconstruct nine
retrospective entries from the log, the work they carried is recorded here, in the release that first
documents it. The tags remain valid — they are what `scripts/install.sh` served while they were latest.

### Added — `--plan-lanes` now recommends a Codex model and reasoning effort per lane

Every lane carries an advisory `execution` object with a current Codex model, reasoning effort, the
deterministic policy rule that selected them, and the complete structural signals used by that rule.
The recommendation labels itself `basis="structural-only"`; partial test evidence, name-based call-graph
resolution, and truncated evidence are disclosed as in-band caveats for the orchestrator to override.
The additive JSON field keeps the top-level schema at `v: 1` and versions its policy independently as
`codex-lane/v1`.

### Changed — `.gitignore` is honoured by default; `--no-ignore` restores the old walk

ripwire is named for ripgrep, whose defining default is that ignored files are not searched. The crawl
walked them. In a git work tree it now consults git's own ignore rules and skips what the repository
already declared uninteresting — `node_modules/`, `.venv/`, `target/`, `build/`, `dist/`, whatever the
repo says — and **`--no-ignore` restores the previous behaviour exactly**.

Measured on this repository's own root with no `--exclude`, three checkouts under a gitignored
`bench/external/`: `files=` 8,674 → **1,522**, cold 2.81 s → **0.52 s**, warm 0.63 s → **0.10 s**, and
the result agrees to the file with the hand-written `--exclude=bench/external` the tool used to need.
The ignore lookup is one `git ls-files ... --directory` per root: 0.020 s (ugrep), 0.030 s (rocksdb),
0.150 s (duckdb), 0.032 s (this root) — `bench/PROFILE.md` carries the ledger.

Nothing is dropped silently. The map header states `ignored_files=` (files the rules covered, exact)
and `ignored_dirs=` (subtrees they pruned — the walk stopped there, so their contents are UNKNOWN, not
zero); both are ABSENT when the rules dropped nothing, so a tree with nothing ignored is byte-identical
to what it produced before. `--skipped` rows the ignored set and names the mode in `ignore_mode=`.
`--exclude` composes on top, and a multi-root run applies the rules per root.

Four situations keep the full walk, and `--skipped`'s `ignore_mode=` says which applied: `git` (rules
consulted), `off` (`--no-ignore`), `unavailable` (no git work tree at this root, or no git binary), and
`root-ignored` — the root is ITSELF inside an ignored subtree (`ripwire build/` in a repo that ignores
`build/`), where honouring the rules literally would hand back an empty map for a directory you pointed
at on purpose. A tracked file that happens to match a `.gitignore` pattern stays indexed, because git
ignores nothing it tracks.

### Changed — one warm cache per tree, and a narrower run no longer throws the wider one's work away

The warm-by-default cache keys on the tree's path and the verb class, and deliberately not on
`--exclude` or `--max-file-size`: one blob per tree, shared by every configuration you run against it.
That sharing had a hole. A run with an `--exclude` deserialised the WHOLE blob — including the records
for the files it had just excluded — and then, if anything had changed, rewrote the blob with only its
own file set. The next run without that `--exclude` found those files missing and re-parsed them from
scratch. Alternating `ripwire .` with `ripwire . --exclude=vendored` therefore paid a cold parse in one
direction and a superset deserialise in the other, every time.

The blob now carries a record offset table, so a run reads only the records for the files it actually
crawled, and a save carries over — byte for byte — the records for files it did not. The cache only ever
grows toward the union of the configurations that share it, so switching between them is free in both
directions.

Measured on a 31,000-file tree (1,000 files kept, 30,000 excluded), comparing `d8fa59c` with this
change. A warm excluded run: **0.06–0.09 s → 0.01 s**, now indistinguishable from that configuration
having its own private `--cache=PATH` blob. The run after a changed excluded run: **30,000 files
re-parsed in 0.96 s → 0 files re-parsed in 0.27 s**. The costs, both real: the table adds **3.3%** to the
blob (32 bytes per file), and a save that has to carry 30,000 records over takes 0.13–0.40 s where the
old truncating save took 0.02 s — which is the trade, because the truncation is what made the next run
cost 0.96 s. Full ledger in `bench/PROFILE.md`; the bands, including the earlier attempt at this that was
measured and reverted, in `docs/EVALS.md` under "The auto-cache key ignores `--exclude`".

Cache blobs from earlier versions are rejected and rebuilt on the next run, as with every format change:
no action needed, one cold parse. `RIPWIRE_CACHE_STATS=1` gains `cached_records=` and `blob_entries=`.
New gate: `test/cacheoffsetcheck.sh`.

### Added — `--slice` reaching definitions are flow-sensitive inside one definition (C-family, Python)

Every use row of `--slice=SYM:VAR` (and the MCP `slice` verb) now carries `rd=` — the lines of the defs
that reach it — computed by one structural pass over the definition's statement tree: a def is killed by
the next unconditional def of its binding on every path, defs join at `if`/`elif`/`else`, `switch` (cases
fall through, no `default` keeps the no-case path), a loop's back-edge (fixpoint), `try` handlers and
`finally`, `for`/`while ... else`, `match` and a build-dependent `#ifdef`; `return`/`break`/`continue`/
`throw`/`raise` end their path. The root says which rule is in force — `reach="cfg"` for C/C++/ObjC and
Python, `reach="linear"` (source order, nothing joins) for JS/TS, Go, Java, Rust until their control
tables are fixture-verified. `--slice-flow` and `--since` read the same reach table, so the rows, the flow
walk and the dependence diff can never disagree about an edge. The unit is the statement (uses read the
entering state, defs apply after); every construct the walk does not branch on — `?:`, short-circuit,
conditional expression/comprehension, lambda/closure/nested def/class bodies, `goto`, `global`/`nonlocal`,
the try handler's entry, aliases — is named in the legend instead of guessed. Registered and measured in
`docs/EVALS.md` ("Flow-sensitive slice in the small"): 0 wrong of 85 hand-written sentinel use rows across
53 functions, and the 57-commit `--since` labelled set unchanged at 35/35 and 22/22. Gate:
`test/sliceflowsenscheck.sh`.
### Fixed — `--expand` no longer takes minutes on a file whose lines are hundreds of kilobytes

Secret redaction (`redactSecrets`, on by default at every body-emission seam) was quadratic in LINE
length. Its low-precision `[A-Za-z0-9+/=_\-]{32,}` rule re-derived three position-independent values at
every cursor: the enclosing line's boundaries, that line's credential-keyword verdict, and — through a
greedy `regex_search` anchored at the cursor — the whole character-class run it sits in. Ordinary source
has ~100-byte lines and never noticed. A minified or vendored bundle is nothing but huge lines, and
`--expand` hands one to this path whole while pricing its whole-file candidate.

Measured on babel's `.yarn/releases/yarn-3.1.0.cjs` (2,196,921 bytes over 768 lines): a single `--expand`
selector burned 196.7 s of CPU without finishing under a manual timeout, and an unattended run was killed
at 1,343.9 s of user CPU with a still-empty output file. It now answers in 0.46 s warm. On a
self-contained 20 KB-single-line fixture, 23.02 s → 0.017 s. Each of the three values is now computed
once per line or per run, which makes the sweep linear.

This is an output no-op — same matches, same gate verdicts, same bytes — verified byte-identical on
stdout, stderr and exit code against the pre-change binary over 24 corpora (20 of them external
multi-language snapshots) × 5 verb shapes. New gate: `test/redactfixcheck.sh`. Ledger row and the
`sample(1)` breakdown in `bench/PROFILE.md`.

## [0.2.2] — 2026-08-09

### Fixed — a local variable that shadows a function name no longer steals that function's use-sites

`--uses` attributed a local's read/write sites to a same-named function (13 false sites on one
measured query). A local binding now claims its own scope, and a `using ns::name;` re-export emits
the `role="import"` row it never produced. Measured against a `scip-clang` oracle on this
repository, site-level precision/recall moved 0.9046/0.9285 → 0.9136/0.9412, with the worst
motivating query going 0.6579 → 0.9615 and three others reaching 1.0000. The suppression took three
refutation rounds to get right, and the third found a **recall loss the first cut introduced**: a
genuine call appearing ABOVE the shadowing local vanished entirely, because the suppression span
started at the enclosing block rather than at the declaration point. It now begins at the end of the
complete declarator, C++ [basic.scope.pdecl]. Fixture corpora, per-round verdicts and the verifier
history: `bench/fixround/RESULTS.md`.

### Fixed — five more shapes that invented or destroyed references

A declared name no longer leaks as a read of the symbol it shadows under a defaulted parameter, a
parameter pack, or an attributed declarator. A bare-identifier assignment (`x = y;`) mints a
function-pointer binding only when the file's own declarations allow it, and a class-typed copy no
longer does — closing a bug that was **losing real call edges**, not merely adding false rows: a
bogus binding tombstoned a genuine same-named file-scope binding corpus-wide. Zero call-edge loss
verified on two corpora (10,742 edges here, 39,741 on a 2,376-file ObjC++ tree, byte-identical
before and after); 59 false `--uses` sites removed with zero sites gained. One deliberate behaviour
change is disclosed in the count-floor legend: a variable whose function-pointer typedef lives in a
HEADER is now missed, because same-file alias evidence cannot distinguish it from a value copy.

### Changed — `--uses` states that a bare type mention is not a use-site

The role list is the whole vocabulary. Naming a symbol as a type in a signature, a declaration or a
template argument contributes no row, so a caller that only names it as a type is absent from the
count. Previously true and unstated; now stated in the legend. A `role="type"` reference class
remains the fix rather than the disclosure, and is recorded as such.

### Added — the oracle-scored reference-precision receipt

`bench/headtohead/r9-2026-08-09/` publishes the round behind the README's silent-miss claim: 68
answers scored against a `scip-clang` index, six imperfect, four self-flagged, and the two unflagged
traced to files the oracle could not see. It reports the comparison in both directions — an
LSP-backed tool is more precise, by ~1.5 points after these fixes, with recall now equal — along
with the protocol asymmetry that inflates one of our own rows and four limits that travel with the
numbers, including that the corpus is this repository.

### Changed — the held-out recall lane now scores a frozen doc corpus

`bench/recalleval/`'s recall lane no longer measures the live repository's docs: it unpacks
`snapshot.mdpack` — every tracked `*.md` at the commit pinned in `snapshot.lock` — into a temp root
and scores that, so its recall/MRR floors trip only on a ranker regression. The change closes a
standing defect: the lane's floor had been ratcheted 85→83→78→69 in five days purely by corpus
composition (documents joining, or even just growing, moved BM25 length normalization), with ranker
neutrality proven at every step — the forensic record is `test/recallevalcheck.sh`'s header. The
live tree keeps its own signal: a `recall_livepol` probe re-runs the same queries against the live
root and reports pollution@5 (ceiling 16% unchanged). Frozen bars: lenient recall@5 76.2% baseline /
floor 71; lenient MRR 0.619 baseline / floor 0.57. Corpus integrity is a content hash verified as
the gate's first check; refreshes happen only in deliberate recalibration commits
(`bench/recalleval/make_snapshot.py --freeze`). Method and bars: `docs/EVALS.md`.

### Fixed — nested JS/TS closures no longer inherit the enclosing function's metrics

Cross-codebase validation on webpack found a systematic extraction bug: a named const-closure
nested inside another function's scope (`const f = (..) => {..}` inside a function body) reported
the ENCLOSING function's loc/cx/ccx/nest/params instead of its own. In webpack's
`lib/html/syntax.js`, all eight closures inside the ~3400-line `tokenize` arrow reported identical
loc=3439 cx=487 params=3; the same happened under anonymous enclosers
(`module.exports = (..) => {..}` in `lib/util/deterministicGrouping.js`). Root cause: the tags-pass
body-climb (built for C++'s `function_declarator` → `function_definition` hop) adopted the first
ancestor owning a `body` field — for a nested closure that ancestor is the *enclosing*
`arrow_function`, whose whole span the closure then stole; `statement_block` was missing from the
climb's scope-stop list, so only nested (not top-level) defs escaped upward. The climb now refuses
any ancestor whose body *contains* the definition — a grammar-agnostic containment stop. Call-edge
attribution rides the same spans, so calls in the encloser's body now attribute to the encloser
instead of the last span-stealing closure. On webpack, unambiguously individually-scoped `nest>=4`
rows went from ~18% to 98% (django's healthy Python baseline: 89%). `kParserVer` 41 → 42 (cached
spans carry the bug). Gate: `test/jsnestedcheck.sh` on `test/jsnestedfix/` — hand-counted
loc/cx/params/nest for both shapes, JS and a byte-identical TS twin.

### Added — `--skipped`: itemize the header's `skipped_oversize=` count

The map header has long disclosed *how many* otherwise-indexable files the crawl dropped for
exceeding a size ceiling (`skipped_oversize=N`, absent when zero) — but nothing anywhere named
*which* files, so a reader could know the corpus was truncated without being able to say what was
absent from it. `--skipped` names them: one `<f p= bytes= limit=/>` row per dropped file, path-sorted,
where `limit=` is the ceiling that dropped the row — `--max-file-size`'s value, or the fixed 256 KB
`.json` config ceiling that flag does not raise; the root element repeats both effective
ceilings so a zero-row report still states its bounds. The accounting invariant is unchanged and now
itemizable: `files=` + `oversize=` = the population the crawl considered, at every `--max-file-size`.
Multi-root workspaces list rows under the same `<label>/./<rel>` spelling every other surface emits.

Scope is deliberate: the parse-time binary-sniff and read-failure skips are *not* listed, because
those files keep their `fileId` and stay inside `files=` (present with zero symbols) — they are not
absent from the accounting this verb itemizes. The default map is byte-identical (G5: purely
additive; the header count was already there). Read-only; exit 0 always. Gate:
`test/skippedcheck.sh`.

### Added — `--dmm`: the Delta Maintainability Model, one comparable number per change

`--quality-delta` reports *which kinds* of debt a change added. It has no scale, so it cannot answer
"was this change better than the last one?" — `--dmm` is that scale: one scalar in `[0,1]` per commit
or per working diff, trendable across commits and comparable across authors.

```
<dmm base="2edbb46cfd9d…" target="working-tree" available="1" combine="pooled"
     size_metric="physical-loc" dmm="0.436" good="462" bad="597"
     base_units="4759" base_volume="86331" target_units="4780" target_volume="86684">
  <p k="size"        dmm="0.184" good="65"  bad="288" d_low="65"  d_high="288"/>
  <p k="complexity"  dmm="0.499" good="176" bad="177" d_low="176" d_high="177"/>
  <p k="interfacing" dmm="0.626" good="221" bad="132" d_low="221" d_high="132"/>
```

A *unit* is a function or method definition with a body; its *volume* is its line span. Per property a
unit is **low risk** iff `loc <= 15` (size), cyclomatic `cx <= 5` (complexity), `params <= 2`
(interfacing). `good` is low-risk volume **added** plus high-risk volume **removed**; `bad` is the
reverse; `dmm = good/(good+bad)`. **Deleting a god function scores 1.000; growing one scores 0.000.**
The three sub-scores ship alongside the combined one because they are separately actionable — a low
`size` with a healthy `interfacing` says *split the function*, not *change the signature*.

Three spellings: bare `--dmm` compares the **working tree** against `git HEAD` (what `--quality-delta`
compares); `--dmm=REV` scores one commit against its **first parent**, the per-commit scalar; and
`--dmm=A..B` scores tree B against tree A. Multi-root workspaces refuse — pooling two histories into
one ratio would mean nothing.

**It is a delta, never a level, and that is the whole design.** A unit you edit without changing its
size, complexity or parameter count sits in the same bin with the same volume on both sides and
contributes exactly zero to both `good` and `bad`. You are not punished for touching pre-existing bad
code, because a gate that punishes touching a mess is a gate people route around. For the same reason
the verb has no threshold, renders no verdict, and always exits 0.

**`dmm="UNAVAILABLE"` is not a score.** When `good + bad` is 0 — a rename, a literal edit, a comment
reflow — the change is outside what the model measures, and the report says so in `reason=` rather
than picking the flattering default. It is never 1.000 and never 0.000. The same token appears per
property: a commit that only adds parameters leaves `size` and `complexity` UNAVAILABLE while
`interfacing` is measured.

**Lineage, and the one deviation.** The model is di Biase, Rastogi, Bruntink & van Deursen, TechDebt
2019 (SIG). The three risk thresholds and the exact good/bad asymmetry are PyDriller's
`deltamaintainability` reference implementation, read out of `pydriller/domain/commit.py` rather than
re-derived from the paper's prose — including the 0/0 case, whose `None` is where UNAVAILABLE comes
from. The deviation is disclosed on every report as `size_metric="physical-loc"`: PyDriller's volume
is lizard's non-comment `nloc`, ripwire's is the definition's physical line span, so a heavily
commented unit crosses the size threshold here earlier. The combined score is labelled
`combine="pooled"` because the paper publishes the three properties separately and no aggregate.

Gate: `test/dmmcheck.sh` — a hand-built git repository whose every commit has a pencil-derivable
answer (delete-only-high-risk → 1.000, grow-a-god-unit → 0.000, a 4-good-vs-4-bad mix → 0.500, a
literal-only edit → UNAVAILABLE), both sides of all three thresholds pinned (15 vs 16 lines, cx 5 vs
6, 2 vs 3 params), plus the root-commit, non-git, refusal, determinism, well-formedness, legend and
additivity arms.

### Added — `--nonlocal-state`: the mutable state a function can reach, reads and writes kept apart

A new lens: for every function and method, the non-local **mutable** state it — or anything in its
transitive callee closure — reads and writes, as two separate sets, with the site or the callee that
explains each one. A *cell* is a file- or namespace-scope variable, a function-local `static` (local
in name only), or a Python module global; a `const`/`constexpr`/`consteval` declaration is not a cell,
so a large `writes=` is genuinely shared mutable state and not a table of constants.

```
<fn p="src/infra/profilePmc.h:288" n="ensure_global_init" writes="2" reads="3"
    direct_writes="1" direct_reads="3" cells_total="3">
  <cell n="g_perf" p="src/infra/profilePmc.h:284" dir="rw" at="src/infra/profilePmc.h:339" at_dir="rw"/>
```

`writes=`/`reads=` fold in the callee closure, `direct_*` is what the body does itself, and each cell
child carries `dir=r|w|rw` plus either `at=` (a use site here, with `at_dir=` for what *this* body does
— it can be narrower than `dir=`) or `via=` (the nearest callee that touches it). Rows are ordered
most writes first; pages with `--limit`/`--offset`.

**Direction is the point, and it is not new.** Henry & Kafura's 1981 information-flow metric already
separated what a procedure reads from what it writes; folding them into one number discards the half
that is a hazard for everyone else. The lineage is recorded in full in
[`docs/LINEAGE.md`](docs/LINEAGE.md) — Fowler's **Global Data** / **Mutable Data** smells (2018), which
name this hazard and ship no metric; **Marinescu's ATFD** (ICSM 2004), the closest existing number and
one-hop, per-class, Java and direction-blind; **QMOOD DAM** and **MOOD AHF/MHF** (Bansiya & Davis, TSE
2002), which count *declared visibility* and therefore score a class with private fields and leaked
mutable internals as perfectly encapsulated; **Potanin, Noble & Biddle 2004**, the only published
*measurement* of externally reachable state, which is dynamic, Java-only and tooled with something
unmaintained; and **Meyers & Binkley** (TOSEM 2007), whose slice-based coupling already puts globals in
its output set, so the delta — per function rather than per variable, over the call graph rather than a
dependence graph — is argued in the source header rather than asserted. **The folklore term "action at
a distance" is deliberately not used**: it has zero academic presence and naming the feature after it
would have been the one indefensible choice available.

**It is unsound, and every count says so.** `counts_floor="1"` is on the root. The analysis cannot see
an indirect call (function pointer, virtual, callback, macro-generated call site), a write through a
pointer or reference that aliases a cell without naming it, a cell named only inside a macro, or
reflection-like dispatch — each of those makes the count too low. In the other direction, a local that
*shadows* a cell's name is charged to the cell unless ingest recorded a type binding for it. The
report's own legend names all of these where the reader meets them.

**Scope, stated rather than implied.** It covers **C++, ObjC and Python** — the languages for which the
index carries read/write use sites at all (`captureUses`, `src/ingest.cpp`). Every other indexed
language is named on the root as `unanalyzed_langs=` with a file count, because a Go or Rust corpus
would otherwise report a confident, wrong zero. Widening the lens means widening `captureUses` first,
with its own gate; adding a declaration rule alone would not do it, and the source header says so.

Gate: `test/nonlocalstatecheck.sh` (12 arms) — a hand-derived golden over a two-language fixture, a
mutation control that turns one cell `const` and must go red, plus determinism, direction, provenance,
paging, additivity and XML well-formedness.

### Added — `--field-affinity[=STRUCT]`, the cache-locality lens (advice only, and validated)

Which fields are **read together but declared far apart**. Every shipping struct-layout tool answers
"where are the holes?" — pahole, clang-analyzer `optin.performance.Padding`, PVS-Studio V802, Go
`fieldalignment`, `-Wpadded`. None answers this one. The verb builds a static field **co-access
affinity graph** (one observation per indexed C-family function body) and diffs it against the declared
field order and 64-byte cache-line geometry, reusing `--layout`'s LP64 offset model rather than
re-deriving it. Bare form ranks every aggregate in the repository by separation cost; `=STRUCT` narrows
the report.

**Almost none of this is new, and the output says so in its own legend.** The affinity graph, the
points-to-free static access enumeration (`<function, struct type>`, an approximation its authors
conceded), the separation weight `wt(fi,fj) = (block − dist)/block` reproduced verbatim, and
hardware-counter validation of layout work are all Chilimbi, Davidson & Larus, *Cache-Conscious
Structure Definition*, **PLDI 1999**. The advice-instead-of-transform posture and per-field counter
attribution are Hundt, Mannarswamy & Chakrabarti, **CGO 2006**. What is new is narrow and is
engineering: a *source-level, no-debug-info, whole-repo-ranking* delivery — pahole needs DWARF, Hundt's
was one proprietary compiler on a dead architecture, `lshaz` is Linux-x86-only and answers the inverse
(false-sharing) question.

**Exactly two findings fire**, both with a direction defensible in one sentence: `split-line` (two
fields co-accessed by ≥2 distinct functions at `wt == 0.00`, so no field order can put them on one line)
and `straddle` (one co-accessed field crossing a line boundary). **Pack-tighter and sort-by-size advice
is deliberately absent** — the Go team excludes its own `fieldalignment` analyzer from `vet` and `gopls`
because the diagnostics "very rarely indicate a significant problem" and tight packing can induce false
sharing. There is no rewrite mode and the verb never exits non-zero: five compiler attempts at automatic
field layout are dead (GCC `-fipa-struct-reorg`, LLVM heap SRA, esan, StructFieldCacheAnalysis,
Qualcomm's AoS→SoA RFC), every one that died on soundness died because a *compiler* must prove a pointer
points at a pool of that struct. Advice cannot miscompile.

Limits, in every header rather than in a footnote: `counts_floor="1"` (`fns=` counts distinct indexed
functions, never dynamic frequency; `w=` is a fan-in reachability *proxy*), `model="lp64-approx"` (a
definition `--layout` marks `modeled="0"` contributes its affinity graph and no geometry finding), only
dot/arrow member syntax is counted, and a field name declared by two aggregates is **refused** and
tallied in `amb_skipped=` rather than guessed.

**The validation half is real, and it refuted the hypothesis in one regime.**
`bench/bench_field_ab.cpp` builds the two layouts the lens compares and measures them through
`prof::pmc` — ripwire's existing counter backend. On an Apple M5 Pro, 64 MB per arm, five repeats per
stride: the flagged layout is 4–41 % **slower** at strides 9/1025/4097, mixed at 129, and ~2× **faster**
under a fully sequential sweep — where the packed arm moves *less* data and still costs more time,
because a single 64 B touch per 256 B element is a sparser stream than two. Hardware counters were
**UNAVAILABLE** in that run (kperf needs root on macOS) and the harness says so rather than implying
confirmation, so the *mechanism* claim remains unconfirmed. `docs/FIELDAFFINITY.md` records all of it,
including the honest reading of the lens's own #1 result on ripwire's source (`MainDispatch` — real
static separation cost, almost certainly nil dynamic cost, which is limit (1) visible in the top row).
Gate: `test/fieldaffinitycheck.sh` over `test/fieldaffinityfix/`, whose every offset is hand-computed in
the fixture's own comments.

### Measured — `--ensemble`'s four families are near-orthogonal; one of them cannot carry a gate

A calibration pass over **nine trees (five independent, 27 889 eligible functions)** spanning C, C++,
ObjC/ObjC++, Metal, Rust, Swift, Python, TypeScript and Bash. No behaviour changed: the new
`bench/ensemblecal/` harness reads `--ensemble`, `--readability` and `--metrics` and computes
nothing of its own. Full numbers, per corpus and pooled, in [`docs/EVALS.md`](docs/EVALS.md) §9.

- **The ensemble premise holds.** Largest cross-family correlation anywhere: **φ = +0.278**; pooled
  over the independent corpora no pair exceeds **+0.168** and the largest overlap between any two
  families is Jaccard 0.119. The four families are not one signal wearing four hats.
- **`historical` is disqualified from gating, on measurement.** Across three commit ladders (148 /
  792 / 1 620 first-parent commits) its flagged set has mean consecutive Jaccard **0.800–0.862** and
  endpoint Jaccard **0.426–0.546**, against 0.920–1.000 for the other three.
- **Three named presets, derived from that**: `lenient` = all four families, `fam ≥ 1` (32.22%
  pooled); `default` = all four, `fam ≥ 2` (4.39%); `strict` = structural + lexical + confusion,
  `fam ≥ 2` (2.34%) — strict is a *selection*, not a higher K, and its output set is both smaller and
  measurably steadier than `fam ≥ 3` over all four.
- **Two honesty defects found and recorded, not fixed here.** The `confusion` family is gated to
  C/C++/ObjC but does not declare itself unavailable on a corpus with no C-family file (it fires 0 of
  4 068 on a Rust tree while still counting inside `of=`); and the "worst decile" ordinal cut is
  capped at 40 rows, so its realized width is **0.23%–8.81%**, not 10%.

### Added — `--cochange` grows the three things the papers behind it already had

`--cochange`'s `surprising="1"` predicate is an independent implementation of published work, now
cited in [`docs/LINEAGE.md`](docs/LINEAGE.md) §2 (Wong/Cai/Kim/Dalton, ICSE 2011 — the Clio tool;
Mo/Cai/Kazman/Xiao, IEEE TSE 2019; Gall/Hajek/Jazayeri, ICSM 1998; Code Maat in §3a). Reading those
against the shipped predicate produced three additions:

- **`recur=` and `sub_windows=` on every row.** Clio does not report a discrepancy the first time it
  appears — it mines frequent patterns over the last five releases and reports only recurring ones.
  ripwire mined one window, in which a one-week refactor sprint and an eighteen-month structural
  defect both score `together=4`. The window is now cut into equal-**commit-count** sub-windows
  (equal time would make the number a function of when the team took holiday) and `recur=` counts how
  many contain a joint commit. `--cochange-recur=K` filters on it and the header publishes
  `min_recur=` so a shortened list is explained. Measured on a 1,648-commit, 2,718-file C++/ObjC++
  corpus: `recur>=2` removes **45%** of the surprising pairs (253 → 140) and `recur>=3` removes
  **81%** (253 → 47).
- **`--cochange-groups`.** Mo's Modularity Violation Group is the minimal set of *groups* covering the
  violating pairs, not a pair list — "X co-changes with {A,B,C}, none of which it depends on" is one
  row that names the file to fix. Same corpus: 253 pair rows collapse to **65 groups** (3.9 pairs per
  group). The cover is greedy and says so (`cover="greedy"`); minimum set cover is NP-hard, so
  `groups=` is an upper bound on the minimum, never the minimum.
- **`conf_ab=` / `conf_ba=` / `driver=`, and `conf_rev=` on the per-file form.** Clio's confidence is
  asymmetric — `conf = frq(x1 ∪ x2)/frq(x1)` — so "A always drags B" is distinguishable from the
  reverse. ripwire's `deg=` divides by the quieter file, which is exactly the *larger* of the two
  directions with the direction discarded; both are now emitted, `deg=` is documented as their max,
  and `driver=` names the antecedent of the stronger rule. A tie emits no `driver=`.

Calibration is published with the feature rather than after it. Clio reports 66% precision on Hadoop
Common and 40% on Eclipse JDT; ripwire's measurable analogue on the corpus above is a **yield** of
59.8% (flagged pairs over dependency-capable candidate pairs), which is not the same quantity — see
[`docs/EVALS.md`](docs/EVALS.md) §7 for what was measured, what was not, and the upper bound on
precision it supports. **Correction, still pre-release:** that 59.8% was measured on an index with a
capture gap (guard-wrapped `#include`/`#import` never seen), fixed in `ba82324` (`kParserVer` 40); the
re-measured yield on the same corpus is 52.2%, with the composition-derived precision ceiling moving
from ≤67.6% to ≤64.3% — now inside Clio's 40–66% band rather than a hair above its top. `docs/EVALS.md`
§7 carries both figures and the full re-derivation; this entry is left as originally written except for
this note, per the project's own rule against silently overwriting a published number.

Gate: `test/cochangecliocheck.sh` (29 arms over a scripted 24-commit fixture repo whose oversized base
commit also proves the 30-file bulk cap still fires).

## [0.2.1] — 2026-08-05

Linux portability patch. The v0.2.0 Linux archives were built on `ubuntu-24.04` and required
`GLIBCXX_3.4.31`, so they died on RHEL 9 and older (verified on ubi9). The Linux release legs now
build inside AlmaLinux-8-based `manylinux_2_28` containers with Red Hat gcc-toolset 14 — newer
libstdc++ symbols link statically (the devtoolset model), so **one binary per arch covers
RHEL/Alma/Rocky 8+, CentOS Stream, Fedora, Ubuntu 20.04+, and Debian 11+** (glibc 2.28 floor;
verified on ubi8, ubi9, ubuntu:22.04, ubuntu:24.04). A new `smoke-rhel` CI job runs the packaged
tarball on a RHEL 9 (ubi9) userland and gates publish. Also: `bench/representative_perfgate.sh`
byte counting is now GNU-portable (`stat -f %z` is BSD-only and zeroed the corpus-shape preflight
on every Linux CI leg). No library or CLI behavior changes.
### Added

- **Optimization-remarks build and triage** — `-DRIPWIRE_OPT_REMARKS=ON` (a separate tree; refused by
  name inside `build/` and `asan/`) collects clang's `-Rpass*` remarks plus a YAML opt-record, and
  `scripts/optremarks.sh` / `scripts/optremarks.py` turn it into a ranked report. `docs/OPTREMARKS.md`
  carries the full triage of the first pass over `src/`, and `skills/ripwire-opt-remarks/` carries the
  remark→fix patterns that survived it. New gate: `test/optremarkscheck.sh`.
- **`-DRIPWIRE_LTO`, now ON by default** — link-time optimization. The first change the remarks pass
  justified: 397 of 636 distinct `inline/NoDefinition` sites in `src/ingest.cpp` name a tree-sitter C
  accessor, inside the two phases that are ~31% of a cold run, and no source edit can reach a
  cross-TU definition. Measured on this repository as corpus (937 files, Apple Silicon) across four
  independent interleaved A/Bs of 9/21/21/31 runs per arm: **cold 1–6% faster, warm 0–3%**, with
  every cold statistic in every run favouring LTO and one run's warm min going the other way — the
  per-run table is in `docs/OPTREMARKS.md` F1, and the range is the claim, not its best row. Output
  is byte-identical and the determinism gate passes on the LTO tree. It costs link time — a rebuild
  after touching `src/main.cpp` goes 34 s → 89 s — which is not a reason to decline a faster binary;
  `-DRIPWIRE_LTO=OFF` restores the fast edit loop. **Note:** `option()` never overwrites an existing
  cache entry, so a build tree configured before this change keeps `RIPWIRE_LTO:BOOL=OFF`; delete the
  tree to pick the new default up.
- **`-DRIPWIRE_PGO=generate|use` and `scripts/pgobuild.sh`** — profile-guided optimization, and the answer to the remark classes LTO cannot touch: `inline/TooCostly` and
  `loop-vectorize/VectorizationNotBeneficial` are the cost model guessing at hotness, and a profile
  replaces the guess with counts. **Cold 14–25% faster than a non-LTO build (6–16% over the shipped
  LTO default), warm 5–10%**, measured on this
  repository *and* on a ~2000-file C++ tree that appears in no training run — six interleaved A/Bs,
  two corpora, two independently built PGO binaries, every statistic favouring PGO. Output is
  byte-identical on both corpora; the determinism gate passes three times on the PGO tree. `pgobuild.sh` runs instrument → train → merge →
  rebuild as one command. Honest G3 tension, stated in `docs/OPTREMARKS.md` F2: this is two configures
  and a training run against a one-build-step guardrail. The `.profdata` is deliberately not committed
  (a stale committed profile is a clang warning, not an error), and `RIPWIRE_PGO=use` **fails the
  configure** when the profile is missing rather than silently producing an ordinary binary.

## [0.2.0] — 2026-08-04

The first binary release: portable archives for macOS arm64/x64 and Linux arm64/x64, each with a
SHA-256 file, built by `.github/workflows/release.yml` on the tag push. Includes everything from the
asset-less `v0.1.0` tag plus the language definition-shape rounds (TypeScript, JavaScript, Python,
Swift, CUDA memory-space capture), the 2026-08-04 audit hardening (cache isolation, honest
lint/doc-drift behavior, transitive test reachability, skill routing, Codex plugin/CLI setup), and
the Codex CLI benchmark harness under `bench/agentloop/`.

### Added — retrieval and ranking

- **`--for=TASK`, the task lens** — ranked signatures + metrics framed for reuse, matching doc
  comments and bodies rather than names alone.
- **Query-shape routing, on by default.** A deterministic, confidence-gated router picks name-exact
  BM25 when the query *names* a symbol (identifier syntax, or every content word is a symbol name)
  and subtoken+body BM25 otherwise, and prints which it chose and why in the header. `--no-route`
  restores the single-ranker behavior.
- **Query-mention anchoring, on by default.** A file, dotted module, or `Type.method` literally named
  in the task text — even inside a URL — is lifted to just below the top hit, and the header names
  what anchored. Byte-identical output when the text names nothing indexed. Disable per run with
  `--no-mention-boost`, or everywhere with `RIPWIRE_NO_MENTION=1`.
- **Doc-mention surfacing on `--for` / `--pack-task`, on by default.** A markdown document that names
  one of the task's top-resolved symbols in backticks is lifted into the bundle, ranked strictly
  below that symbol's own score — closing the case where the design note explains a symbol but shares
  no vocabulary with the query. Bounded (top-8 anchors, 2 docs per anchor, 6 docs total) and
  downweighted (0.55× the anchor's score) so code still dominates a code-shaped query. Byte-identical
  when nothing resolved has a mentioning document. Opt out with `--no-doc-mention` or
  `RIPWIRE_NO_DOC_MENTION=1`. Reuses the existing doc↔code edges `--mentions=SYM` already exposed —
  no new parser, no cache-format change.
- **`--adaptive`** cuts a result set at its relevance cliff (largest relative score gap) instead of a
  fixed *k*, with a floor of 5 and the existing top-K as the ceiling; the header reports what it kept.
- **`--recall=TASK`** returns the most relevant *documents* in full — memory notes, plans, designs,
  READMEs — with the header disclosing the true relevant count, what was shown, and every cut.
- **`--pack-task="TASK"`** — ranking, top bodies, caller signatures, notes and tests-to-run in one
  bundle under one budget.
- **`--exemplar`** returns the repository's best-in-class instance of what you are about to write,
  chosen by *role* (lowest cognitive complexity under a hard ceiling, then tested, then highest
  fan-in) rather than text similarity.
- **`--detail=N`** spends body tokens only on the top-N ranked symbols and emits signatures for the
  rest, in one call.
- **`--pack-signatures`** emits body-elided declaration skeletons. See `docs/EVALS.md` for the
  measured byte reduction, its root-neutralisation methodology, and the honest counterexample.

### Added — navigation and the call graph

- **`--callers` / `--callees` / `--uses` / `--impact` / `--around` / `--path` / `--connect`** — 1-hop
  in-edges, 1-hop out-edges, every statically resolvable use site (call/read/write/import/extends),
  the transitive blast radius, the ego graph, a directed shortest path, and the minimal connecting
  subgraph over 2..16 symbols (which finds the shared-caller join a directed path cannot).
- **`--graph-query=EXPR`** — a small closed expression language over the symbol graph: sources
  (`name("X")`, `all`), filters (`kind`, `cx`, `fanin`, `file`), bounded `callers`/`callees` closure,
  and `and`/`or`/`not` joins.
- **`--grep` / `--regex` / `--match`** — literal search, regex search, and tree-sitter structural
  (shape) queries, each reported with its enclosing symbol.
- **`--from-trace=FILE`** (`-` for stdin) maps a stack trace, sanitizer report, or compiler error onto
  indexed symbols, ranked innermost-first, with the innermost in-corpus symbol's body included.
- **`--external-surface`** lists names referenced but never defined in-corpus. A name called from
  several languages gets one row per language rather than a merged count, because the referencing
  file's language is what the row reports.

### Added — change safety and review

- **`--affected` / `--situ` / `--test-gate`** as one family: plumbing (changed files or a changed
  symbol → the tests that reach them), the mid-task report (blast radius + tests + co-change
  partners + hotspot alert), and the pre-PR gate (tests to run + the untested blast radius, exit 4
  if either obligation is non-empty).
- **`--exercises=TESTFILE`** is the inverse: the non-test symbols a test file transitively calls into.
- **`--edit-check=SYM`** — did this symbol's contract (parameters, publicness) change against HEAD,
  and which callers are now provably incompatible?
- **`--pr-context[=BASEREF]`** — per-file blast radius, tests to run, and hotspot flags for a diff.
- **`--merge-scout=REF1,REF2,…`** — pairwise conflict sites (same-symbol vs same-file) plus a
  suggested landing order.
- **`--quality-delta`** reports only what a change made *worse*, across ten measured failure modes,
  comparing against git HEAD. `--quality-ack` records a reviewed exception; `--ack-only=KIND` scopes
  the acknowledgement.
- **`--plan-lanes=N --task="GOAL"`** predicts, before a line is written, which parallel work lanes
  would collide. Deterministic JSON on stdout: per-lane file and symbol claims, blast radius, the
  tests each lane must run, and a landing order sorted fewest-conflicts-first. Conflict pairs are
  classified `conflicts`, `same_file_risk`, or `contract_touch`.
  - It **exits 0 even when conflicts are predicted** — conflicts are output, not a failure signal.
    Do not wire the exit code as a CI conflict gate.
  - Pre-hoc: no ref to resolve, no second ingest. ~0.1 s warm *(measured on this repository)*.
  - Read-only. The tool never writes the plan; redirecting stdout is the entire write path.
  - Lane claims are keyed on `(path, scope, name)`, not on symbol `id`. Rows still carry `id` for
    addressability, but it is `null` where it would be ambiguous, with `id_addressable` and
    `id_collides_with` stating the residual ambiguity. *(Measured on this repository: 343 `id` values
    name more than one symbol — 29.3% of symbol rows, 1426 colliding across files.)*

### Added — cross-branch archaeology

- **`--stray-content[=SUBSTR]`** — for each local ref, the lines its own divergent work authored that
  the live line does not have, with a `merged` / `superseded` / `unmerged` verdict. **`superseded` is
  the case `git cherry` structurally cannot see**: cherry compares commit ancestry, so a fix the live
  line re-implemented differently stays "unmerged" forever. Evidence is the *deletion site* — both
  sides diff the same base, so "ref R deleted base line L" and "HEAD deleted base line L" compare
  exactly, with no fuzzy matching. A pure-addition file falls back to a high-bar similarity lane, and
  every file row prints its raw `del=` / `redone=` / `sim=` numbers so the verdict is auditable.
- **`--whereis=SYM`** — which ref's tree defines or mentions a symbol, HEAD first, scanning each ref's
  full tree, with `on-head="0"` naming the case the verb exists for.
- **`--eval-stray=FILE`** — labelled verdict-accuracy evaluation (TSV `ref<TAB>verdict`), exit 3 on
  any regressed case. A confusion table rather than a ranked-set metric, because a verdict verb
  classifies. Supersession thresholds were chosen against hand-labelled branches, so changing one is
  an experiment rather than a guess.
- Both cross-branch verbs are keyed by **blob sha**. Branches off one trunk share nearly all blobs,
  and every byte-level fact is a pure function of blob content, so blobs stream through one
  `git cat-file --batch` per run and are reduced to fixed-size facts on arrival — peak memory is
  bounded by the facts, not by the trees. *(Measured on a 35-branch repository: `--whereis` read 4,445
  distinct blobs where HEAD's tree alone holds 2,897 — 35 refs for 1.53× one tree, 1.6 s.
  `--stray-content` is diff-scoped: 443 blobs, 2.2 s.)* Both use only `cat-file`, `diff`, `ls-tree`
  and `merge-base` — read-only by construction.

### Added — dark code and feature flags

- **`--flags[=SUBSTR]`** — one report over what is built but not switched on: `#ifndef`/`#define`
  header gates, CMake `option()`s, and `getenv()` reads, with kind, default, guarded regions and LOC,
  and read sites, dark entries first. *(On the motivating private repository it named 94 dark gates
  of 102.)*
  - When a name is both a header gate and a CMake option, **the CMake default wins** — it is what the
    build actually passes — and the losing definition is shown as an `<also>` row, so the
    contradiction is surfaced rather than silently resolved.
  - Alias chains resolve (`#define F_WALLS F_ALL`): a child inherits its master's default and rolls
    its guarded size up, so a master switch shows its alias count instead of a misleading `loc="0"`.
- **`--flags --flip=NAME`** answers the follow-up: if this one gate flips, what becomes live and what
  covers it? Reports the code that becomes live (`#if` regions **and** C++ branch sites), the hosts,
  downstream and dependent symbols, the tests reaching those hosts, and **`untested`** — the hosts no
  test reaches. Flipping works in both alias directions, and three-level chains resolve correctly.
  - **Value-style gates are followed, not just preprocessor regions.** A gate consumed as
    `inline constexpr bool kWalls = FLAG != 0;` and then guarded with `if constexpr` guards a C++
    *branch*, not an `#if` region; such a gate previously reported `regions="0"` and a naive flip
    analysis would have answered "nothing lights up". *(Measured on the motivating repository: one
    gate family with 11 aliases and 0 regions yields 43 branch sites across 11 host symbols, verified
    row-for-row against an independent whole-word grep.)*
  - Flip semantics are stated per gate kind. A CMake gate becomes a `-DNAME=1` compile definition, so
    its C++ radius matches the compile case — but it also steers the build graph (adding whole
    translation units), and those sites are reported as build rows and **explicitly not followed**.
    An environment gate is marked `runtime="1"`: with no delimited region, its hosts are the symbols
    that consult the variable.

### Added — documentation drift

- **`--doc-drift[=SUBSTR]`** verifies the *checkable* anchors in every markdown file against the live
  index and reports only what no longer holds. Four anchor kinds: `file:line` references (split into
  `missing-file`, `past-eof`, and `line-moved` with `got=` naming the symbol now at that line),
  backticked symbol mentions (`undefined`), `= N` constants (`const-value`), and `[N]` array extents
  (`array-extent`).
  - **Precision is the design constraint and every lane deliberately under-reports.** A name counts as
    stale only if it occurs nowhere in any non-markdown file as an identifier token, and the presence
    corpus is the index *plus* build files, shaders and config — so a shader function or a CMake
    `option()` is never reported missing. A mention must share its line with a name the repository
    does define; a foreign-scoped mention is never treated as ours; a number is compared only against
    a declaration-shaped literal the corpus binds uniquely; fenced code blocks are treated as
    illustrations. *(Measured while tightening on this repository: the naive version emitted 329 rows,
    roughly 90% of the mention lane being library names and hypothetical examples; the shipped rules
    bring it to 110.)*
  - **`checked + unchecked == anchors` always holds**, and every declined check is named and explained.
  - Stated non-goal: prose, status lines and dates are not checked, and the verb never claims otherwise.

### Added — the git-history oracle

- **`--with-history`** (opt-in, off by default) on `--doc-drift` and `--whereis` answers "was this name
  ever in this repository, and when did it leave?"
  - `--doc-drift --with-history` splits its weakest lane three ways instead of blanket-reporting
    `undefined`: `why="deleted"` with the commit, date and file; `unchecked r="never-in-history"`; and
    `unchecked r="history-no-answer"`.
  - `--whereis --with-history` gains a `<fate>` row (`v="never"`, or `v="removed"` with commit, date
    and path) — something a tree scan structurally cannot produce, since a scan can only find content
    some ref still carries.
  - Both emit a row stating exactly what the walk did (`probed=`, `head=`, `commits=`,
    `removed-names=`, and `truncated=` when bounded).
  - **Speed.** `git log -S` has the right semantics but answers one name per process: ~126 s for 247
    candidate names on a 2,965-file application repository (~85 s even rev-range-bounded). The shipped
    probe reproduces those semantics with a single `git log --no-merges -p -U0 --no-renames` walk that
    tokenizes removed lines: **3.0 s** on that repository, **0.83 s** on this one, and O(1) in the
    number of names. `git log -G` was rejected on semantics — it matches diff *text*, so a reindent
    counts — and a `-G` alternation prefilter measured ~183 s, slower than no filter at all.
  - **Precision.** On that 2,965-file repository, 325 `undefined` rows became 80 `deleted` + 243
    `never-in-history` + 2 `history-no-answer` (75% reclassified); total drift 575 → 330, clean docs
    659 → 713. On this repository, 11 → 3 `deleted` + 8 `never-in-history`, drift 119 → 111. Every
    true positive survived, and no other drift lane moved on either repository.
  - **Cost.** Flagless paths are untouched. Under the flag, cold 0.63 s / 3.83 s and warm 0.130 s /
    0.664 s on the two repositories — about +24 ms and +40 ms over default. Results are memoized per
    (repository, HEAD sha); a commit sha is immutable, so the cache cannot go stale. The cached blob
    covers the whole repository, so `--whereis` reuses whatever `--doc-drift` built. Warm output is
    asserted byte-identical to cold.
  - **Stated limits.** It walks HEAD's own history, so a name that only ever lived on an unmerged
    branch reads as *never here* — that is what `--whereis`'s tree scan is for. Merge-only deletions
    are not seen. Evidence is a removed *line*, so a name last removed from a document is cited at
    that document (a code site is preferred when one exists). A repository past the walk bound reports
    `truncated="1"` and answers `unknown`, never `never`; names below the probe's minimum tracked
    length also get `unknown`, enforced at one choke point so absence is never readable as proof.

### Added — languages

- **TypeScript gains three definition shapes that only a real repo produces.** Validated by mapping
  `github.com/openclaw/openclaw` @`1aedd8f3` (24 658 `.ts` files, 261 760 symbols, 2026-08-04) and
  diffing the emitted `n="` set against a ground truth enumerated independently — grep over *blanked*
  source (comments and template literals stripped; that repo embeds Kotlin, Swift and JS fixtures
  inside `String.raw` templates, which otherwise fake thousands of phantom hits), then confirmed at
  AST level with `--match`. Three shapes came back at ~0 % recall, none of them present in any
  fixture: `abstract_method_signature` (76 sites) — an abstract base published its own name and
  nothing a caller could bind to; `public_field_definition` bound to an arrow (287 sites) — the
  bound-method idiom, which is a class's callable surface exactly as `method_definition` is; and a
  declarator whose value is an `as`/`satisfies` cast *wrapping* the arrow (105 sites) — the
  lazy-facade idiom that openclaw's entire public `src/plugin-sdk/` surface is written in, so every
  one of those was an exported API entry point `--for` structurally could not surface. All three now
  extract: +468 symbols and +593 edges on that corpus, **0 removed**, and byte-identical output on
  non-TypeScript trees. Deliberately still out: the object-literal `pair` form of the same syntax
  (>5000 sites there — a `--match` floor — overwhelmingly inline callbacks and mock tables, not a
  navigable surface). Known limits, disclosed in the gate: ambient `declare const/let/var` bindings
  (37 sites) do not extract, and `declare module "x"` / `declare namespace X` *container* names are
  not symbols — their members are, which is what navigation needs. Gate: `test/tsshapecheck.sh`.
- **Known limit, measured and disclosed:** the pinned `tree-sitter-typescript` (v0.23.2) cannot parse
  `typeof import("…")` once it appears in a nested type position — inside a parenthesized type
  (`(typeof import("./m.js").xs)[number]`, 235 sites) or a call's type arguments
  (`importOriginal<typeof import("./m.js")>()`, 2 087 sites, the vitest mock idiom). 1 222 of
  openclaw's 24 658 `.ts` files contain at least one. The *cost* is far smaller than the site count,
  which is the reason this is disclosed rather than paid for with a grammar-pin bump: tree-sitter
  error recovery scopes the loss to the enclosing declaration, so across all 1 222 files the total is
  ~15 definitions out of 261 760 (type-alias recall 1 607/1 614 and function recall 6 805/6 813 *within
  the affected files*). Pinned in both directions by `test/tsshapecheck.sh` §4d — if a future grammar
  bump fixes the parse, that arm fires.
- **CUDA (`.cu`/`.cuh`) is indexed**, parsed with the vendored `tree-sitter-cuda` grammar (v0.21.1,
  a generated superset of tree-sitter-cpp) under the C++ tags — no CUDA-specific query patterns,
  because the grammar aliases `kernel_call_expression` to `call_expression`. *(Measured before
  adopting, 2026-08-04 probe on the fixture now at `test/cudafix/`: under the plain C++ grammar all
  12 definitions survived error recovery, but every `kernel<<<grid, block>>>( … )` launch site
  produced no call reference — `--callers` of a kernel returned 0 — and a `__constant__` module
  table failed to extract. Losing every host→kernel edge is the Metal failure mode over again, which
  is why CUDA gets a real grammar where Metal measurably did not need one.)* `.cu`/`.cuh` map to the
  C++ language, not a language of their own, so dual-compile headers (`#ifdef __CUDACC__`) resolve
  from both the host and device halves. Known limit, disclosed in the gate: a `__constant__ float
  T[64];` module table still does not extract — the shared C++ tags constant pattern keys on
  `const`/`constexpr`, not the `__constant__` qualifier (plain `constexpr` constants in `.cu`/`.cuh`
  do extract). Gate: `test/cudacheck.sh`.
- **Qualified-call resolution across C++, Rust, C#, TypeScript, JavaScript, Java and Objective-C.**
  C++ gained qualified calls of three or more segments and explicit-template calls at any depth (with
  cast exclusion), canonically precise; Rust gained scoped, turbofish and `Self::` calls with a real
  canonical tier and a file-module guard; C# gained the `?.` family; TypeScript, JavaScript and Java
  gained qualified `new`; Objective-C reached field parity. Canonical multi-match now feeds the
  ambiguity accounting rather than being silently resolved, in every language.
- **Go qualified calls are honestly rejected and fenced** rather than half-resolved.
- **Metal Shading Language (`.metal`) is indexed**, parsed with the C++ grammar and C++ tags rather
  than a separate grammar. *(Measured on 45 real shaders, 864 KB, before adopting: ERROR-node byte
  rate 0.811% under the C++ grammar vs 12.3% under the C grammar — 15× worse; real C++ in the same
  repository: 0.000%. All 249 distinct entry points in that corpus are captured: 663 definitions,
  6,283 call references.)* `.metal` maps to the C++ language rather than a language of its own,
  because MSL and its C++/Objective-C++ host share one call namespace through dual-compile headers —
  which is the entire point of indexing shaders. *Known residual, documented rather than hidden:* an
  anonymous `enum : uint { … }` recovers as a named enum, minting 18 junk `t="type"` symbols named
  `uint` across those 45 files, 0.04% of that repository's 47,074-symbol index.
- **Module-level settings constants are first-class ranked `var` symbols in TypeScript, JavaScript,
  Rust, Ruby, Java, C#, C and C++** (the r3 head-to-head's q10 loss — a settings/feature-flag table
  in those languages previously contributed zero rankable symbols, so `--for` structurally could not
  surface it). Scoped to settings-shaped constants, not every literal: module/file/namespace-level
  capture only, gated on SCREAMING_SNAKE names for the convention-based grammars (Rust `const`/
  `static` items are constants by construction and are taken as-is). Python (case-blind module
  assignments, vendored upstream) and Go (CamelCase consts) were already captured and are unchanged
  — the r3 audit's "not extracted at all" reading is corrected in that report's addendum. Gate:
  `test/constcheck.sh`, written red-first against the pre-fix binary (18 red assertions at
  b6068c3).
- The current set: C++, C, Objective-C/Objective-C++, Metal, Python, TypeScript, JavaScript, Java,
  Ruby, Bash, Go, Rust, Swift, C#, plus JSON configuration keys.

### Added — output shaping, honesty and paging

- **`counts_floor="1"`** on `--callers` / `--callees` / `--uses` / `--impact` / `--edit-check` and
  further surfaces. Every such count is a **floor, never a total**: the call graph is extracted from
  source text by name, so dynamic dispatch, callbacks and function pointers, macro-generated call
  sites, and declarations that parse without a call expression contribute no edge. **Read a 0 as
  "none found", never as "none exists".** Each verb's legend also states its counting *unit* — those
  five count distinct (caller, callee) pairs, while `--uses` counts call sites.
- **Generated documents rank last in `--recall` by default.** A document that declares itself
  generated in its first lines, or is both ≥5× the median document's size and mostly fenced quoted
  output, is demoted — a capture that quotes every term otherwise wins every query on lexical match
  alone. It is never dropped: it still wins when nothing else matches, says why on its own line, and
  the header tallies how many were demoted.
- **One paging vocabulary across the verbs that page** — `--limit=N` and `--offset=M`, with the verbs
  that cannot page refusing rather than silently ignoring them.
- **`--token-budget=N` has two documented personalities.** On the default map, `--query` and
  `--recall` it is a CI **gate**: exit 3 if the emitted document's estimated tokens exceed N, with
  nothing of the artifact reaching stdout — only a record naming what was withheld against the budget.
  On `--for`, `--pack-task` and `--from-trace` it **shapes** instead, overriding that lens's own
  default payload budget, always exit 0. The estimate is calibrated against a public tokenizer,
  never exact.
- **`--max-tokens=N` shapes the map to fit** a deliberately conservative byte ceiling and discloses
  both the asked-for N and the honoured byte figure. Because the ceiling and the gate are measured in
  different units, the same N on both flags is not a tautology — and the shaped map says
  `over_ceiling=1` rather than overshooting in silence when even one symbol exceeds the floor.
- **`--order=stable | important-first | important-last`** is the canonical emit-order flag. `stable`
  gives path/ID order for provider KV-cache hits across re-runs; `important-last` puts the
  highest-ranked content at the end for recency-biased readers. Large default maps auto-flip to
  `important-last` past roughly half of a nominal 32K window unless the mode is given explicitly.
- **`--format=columnar` / `--format=candidates` / `--json`** alternate dialects, with an unknown value
  refusing and naming the legal set.
- **Did-you-mean on every selector**, computed as a real edit distance: a `name("X")` literal or a
  `--callers=SYM` that matches no indexed symbol **refuses** with a suggestion. A typo is not a
  `count=0`; a query whose names all resolve but that selects nothing still reports `count="0"`,
  because that is a measurement.
- **`--version` / `-v`** prints the version plus compiler id/version and build type. The version
  string has exactly one source of truth (the CMake project version), and drift between the printed
  and the declared version is gated.
- **`changed="N"` in the `--map-diff` header** — the teleport-seed file count, so a caller can tell a
  real diff run from a clean-tree or no-git degrade without shelling out to git a second time. Reads
  `0` on a clean tree, and is omitted on every other verb so it costs nothing.
- **`est_tokens="N"` on shaped `--for` output** so the delivered bundle's fit is checkable.

### Added — architecture, quality and structure

- **`--metrics`, `--deps`, `--hotspots`, `--clones`, `--cochange`, `--lint`, `--lint-rules=DIR`,
  `--communities`, `--community=ID`, `--zoom`, `--seams`, `--owners`, `--dead-code`, `--report`,
  `--mermaid`, `--tree`, `--html[=FILE]`** — complexity × churn hotspots, duplicate bodies, hidden
  co-change coupling, AST lint with user-supplied rules, call-graph modules and their nested zoom,
  untested cross-module seams, ownership and bus-factor risk, and a self-contained force-directed
  HTML call graph with no CDN.
- **`--color-by=MODE`** sets the initial node-colour lens of the `--html` page — `lang`
  (default), `community` (Louvain module), `cx` (cyclomatic, fixed thresholds), `churn`
  (per-file git commits, 18-month window), or `tested`. The page embeds all five lenses
  and keeps a live selector; when no git history exists the churn legend says so instead
  of painting zeros.
- **`--arch=RULES`** with a committed baseline gates layering violations in CI.
- **Multi-root workspaces**: `ripwire dir1 dir2 [dir3 …]` merges 2..16 checkouts into one labeled
  graph. Cross-root edges are created **only on explicit evidence** — a path-resolved include or
  import, or an FFI binding — so same-name symbols in unrelated repositories stay unlinked. Root order
  on the command line is irrelevant. The single-root verbs (`--quality-delta`, `--test-gate`, the
  eval family, `--arch` baselines, `--pr-context`) stay single-root; run them per root.
- **`--export=cc.json:FILE`** and **`--index-out`** write the index out for reuse; **`--scip=FILE`**
  overlays a precise SCIP index where one exists, and a missing file degrades honestly rather than
  failing.
- **`--batch=FILE`** answers several lookups in one round trip.
- **`--note-add="SYM_or_path: text"`** commits a gotcha to `.ripwire_notes`, auto-surfaced whenever
  `--for` or `--expand` later emits that symbol; `--notes` lists them.
- **`--doctor`** diagnoses a stale binary, a stale cache, or a missing tool.

### Added — MCP server and agent wiring

- **`ripwire wrap <agent>`** prints the recipe to wire the tool into a coding agent as an MCP server.
- **30 MCP verbs**: 15 read verbs, 12 flagship-reflex verbs, and 3 edit verbs. Each is a thin front
  door onto the same computation *and the same renderer* as its CLI sibling — one output shape, two
  surfaces. `find_referencing_symbols` is kept and documented relative to `impact` and `uses` (1-hop
  calls only; `impact` is the full transitive radius, `uses` also catches read/write/import sites).
- **`--scan-skill=FILE` / `--scan-skills=DIR`** scan agent skill files for prompt-injection,
  exfiltration and path-traversal shapes before you install them.

### Added — evaluation instruments

- **A held-out retrieval eval** (`bench/recalleval/`) with a published labeling protocol: every gold
  label was authored by *reading the source*, never by transcribing the ranker's own output, so the
  eval is allowed to say the current ranker is wrong. `--eval`, `--eval-retrieval`, `--eval-stray`
  and `--eval-skills` run the instruments from the binary.
- **A differential argv harness** that replays a large fixed set of command lines against two binaries
  and requires every diff to be provably intended.
- **A Linux hardware-counter backend for the self-profiler** (`-DRIPWIRE_PROFILE=ON` builds only),
  behind the same one-surface contract as the existing Apple Silicon kperf/kpep backend: one
  `perf_event_open` group per thread, **pinned** so the kernel never multiplexes it — a reported delta
  is a raw truth or the column is absent, never a silent scale — read whole in one syscall, and
  `exclude_kernel` so the stock `perf_event_paranoid=2` admits it without root. Where the kernel
  exposes no PMU at all it arms software counters rather than going dark — see the vPMU-less entry
  below — and degrades silently to plain timing only when the kernel offers nothing whatsoever.
  `test/pmccheck.sh` asserts whichever arm (active/inactive) the
  machine can express; see `bench/PROFILE.md` for the availability and validation story.
- See `docs/EVALS.md` for what each instrument measures and every published number's provenance.

### Changed

- **BREAKING (build): the default build is architecture-neutral.** It previously hardcoded
  `-O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only` unconditionally, which was a hard
  configure/compile failure on any non-Apple-Silicon target — Linux x86-64 and aarch64, Intel macOS,
  any cross build — because clang rejects `-mcpu=apple-m1` as an unknown target CPU. `-mcpu=apple-m1`
  is now applied only when configuring on Apple Silicon; elsewhere the default is plain
  `-O2 -ffast-math -fno-finite-math-only`. `RIPWIRE_NATIVE=ON` (`-march=native`, a dev-machine opt-in)
  is unchanged, as is the PageRank no-reassociation contract and the sanitizer target.
- **x86 SIMD kernels, output-identical.** The `dynamic_map` per-node rank scan and `FixedStr`'s
  `operator==` now compile to SSE on x86_64, alongside the NEON kernels that already existed on
  aarch64 — same count-of-true-lanes contract, no node-layout, width or API change, and a portable
  scalar path everywhere else. `test/dynmapsimdcheck.sh` proves SIMD-vs-scalar parity under the full
  sanitizer set and **fails a scalar-only build on a SIMD architecture**, so the gate cannot pass by
  measuring nothing.
- **x86 radix byte-histogram kernels, output-identical.** The radix sort's contiguous-key histogram
  fast paths (uint32/uint64/float, `src/infra/radixSort.inl`) now compile to SSE2 on x86_64 — the
  same one-wide-load-then-byte-spill shape as the NEON kernels that already existed on aarch64, with
  the IEEE sortable-word flip done in SIMD for float. Same histograms bin-for-bin, scalar path
  everywhere else (including big-endian NEON). *Measured (min-of-15 ns/key, x86_64 via Rosetta 2 on
  an M-series host — a translation proxy, not real x86 silicon — `-O2 -DNDEBUG`, 4K/64K/1M random
  keys):* float 1.44–1.52× over scalar; uint32/uint64 within ±10% (a wash — kept for backend
  uniformity, at no measured cost). An AVX2 variant (32-byte load, same spill) measured *slower*
  than SSE2 under the same proxy (0.86–0.94×) and was not shipped; re-evaluate on real x86 hardware
  before adding it. `test/radixsimdcheck.sh` proves SIMD-vs-scalar parity against an
  independently-formulated histogram oracle under the full sanitizer set, **fails a scalar-only
  build on a SIMD architecture**, and on Apple Silicon runs a second cross-compiled pass under
  Rosetta so the SSE2 kernels are gated on the machines this repo is developed on.
- **sparseCsr math kernels join the x86 port.** The CSR `blockReduceDot` / `scaleVec` / `spmvRow`
  float kernels — NEON-only until now, silently falling back to scalar on x86_64 — compile to SSE2
  (mul+add: SSE2 has no FMA, so x86 rounding differs from arm64 while each platform stays
  bit-stable run-to-run, which is what the determinism contract requires). `test/dynmapsimdcheck.sh`
  grew a third parity arm — an exact-integer regime whose sums are exact in every association
  order, so lane and tail bugs surface as bit-exact mismatches with no tolerance band to hide
  behind, plus a tolerance-band random regime and a known-eigenpair check — and its non-vacuity
  banner now covers these kernels, so a scalar-only x86 build fails instead of passing vacuously.
  Found by sweeping `__ARM_NEON` sites rather than porting from the feature list; the radix-sort
  byte-histogram fast paths are the one remaining NEON-only site (identical behavior either way —
  a perf follow-up, bench-gated).
- **BREAKING (output): canonical symbol IDs corrected.** A parse-recovery artifact published a
  function's *return type* as its class scope. *(Measured on one repository: 80 wrong canonical IDs in
  ordinary C++ corrected, plus 5 newly-correct IDs where the real enclosing namespace took over.)*
  Anything scripted against the old IDs will see different values. Valid C++ never triggered the
  guard, so clean parses are unaffected.
- **BREAKING (caches): parser-version bumps invalidate warm caches.** Several extraction changes moved
  the parser version, so an upgrade costs one cold re-parse. The on-disk record *shape* did not
  change, so the cache format version did not move.
- **Graph shape: C-family `#import` now produces an include edge** — the edge that links a shader to
  its headers. `#pragma`, `#error` and `#warning`, which share the same parse node type, are excluded.
  `#include` and `#import` share one path extractor so they cannot drift apart, and a trailing comment
  on the directive line no longer leaks into the resolved path.
- **`--test-gate` obligations are computed per changed *symbol*, not per changed file.** A change that
  owns one symbol inside a 3,000-line file is no longer charged that whole file's test obligations.
- **Ranking: fixture and generated-content paths are de-prioritized.** A measured change, published
  with its held-out numbers in `docs/EVALS.md`, not a hand-tuned weight.
- **`--map-diff` documentation corrected.** The help text and README claimed it filtered to symbols
  changed against git HEAD. It never did: it emits the **full map, re-ranked with a PageRank teleport
  toward git-changed files**, so every file can still appear and a clean tree is byte-identical to the
  default map. `--pr-context` is the actually-filtered only-changed-files report. *(No code changed;
  expectations do.)*
- **`--detail=N` is now accepted with `--flags`, `--stray-content` and `--whereis`**, where it lifts
  the display cap — the same meaning it has on `--for`. It was previously rejected by the
  companion-flag guard.
- **`--query=TERMS` is relabelled "raw BM25 ranking (debug); use `--for`"** — fully functional, no
  longer presented as the primary retrieval entry point.
- **`--order` supersedes `--stable`, `--most-important-last` and `--no-auto-order`**, which remain
  fully functional as hidden aliases and print a one-line stderr deprecation the first time they are
  used. `--no-stable` is unrelated and untouched.
- **`--pack-top-n` and `--pack-budget-bytes`** behave unchanged but now print a stderr line naming
  `--pack-task` and `--detail` as the superseding one-call flags.
- **`--anchor` and `--cochange-boost` are negative-result experiments** — their own records show no
  confirmed recall lift. Both are dropped from `--help` and refuse with an "experimental" message
  unless `RIPWIRE_DEV=1` is set, keeping them reachable for evaluation work without advertising them
  as supported surface.
- **MCP tool count grew to 30**; the `flags` verb gained an optional `symbol` argument for the flip
  view, deliberately an argument on the existing verb rather than a new verb.
- **`install.sh` no longer hardcodes a Homebrew prefix**, which was wrong on Intel macOS and on any
  machine without Homebrew. It detects `brew --prefix` when brew is on `PATH`, honours an explicit
  install-prefix override, and otherwise falls back to `~/.local`. *(Existing installs may land in a
  different prefix than before.)*
- **Corrected performance claims.** A frequently-quoted "75× warm re-runs" was the incremental cache's
  *parse-phase* figure quoted without that qualifier; end-to-end warm command latency measures
  **8.2×** *(large private C++ corpus, 2,340 files; historical private corpus, not publicly
  reproducible; measured 2026-07-22)*. An unlabelled "`--edit-check` ~26 ms" was corpus-specific; the
  labelled figures are **43 ms at 592 files** and **114 ms at 2,340 files**.

### Fixed

- **The self-profiler's Linux counter backend no longer goes dark on vPMU-less machines** — which is
  most cloud VMs and CI boxes (`src/infra/profilePmc.h`; visible only under `-DRIPWIRE_PROFILE=ON`).
  Two defects, found and fixed live on an x86 Xeon VM whose kernel refuses every hardware event with
  `ENOENT`: (1) the documented per-event graceful skip did not apply to the group *leader* — if the
  first event (`cycles`) failed to open, the whole backend went inactive even when later events would
  have opened; leadership now falls to the first event that actually opens. (2) The event table was
  hardware-only, so a PMU-less kernel had nothing to offer; two `PERF_TYPE_SOFTWARE` rows —
  `task-clock` (on-CPU ns) and `page-faults` — now trail the table. They cost no hardware counter
  slot on bare metal and keep per-scope counter columns alive on VMs, under their own names, never as
  a stand-in for hardware counts. The over-budget shrink loop also now drops the last *PMU-consuming*
  event rather than blindly the last row (dropping a software event can never make a pinned group
  fit). Gate: `test/pmccheck.sh`'s inactive arm now additionally proves the kernel offered no counter
  at all — the arm that used to pass vacuously on VMs fails on the old code and exercises the live
  path on the new. *(Measured on the 2-vCPU VM: single-thread scopes' `task-clock` agrees with the
  independent wall column to 0.05–1.6%, and the parse pool's wall-vs-task-clock gap put a number on
  CPU oversubscription — ~36% of the parse phase's wall time was spent off-CPU.)*
- **Rust whole-impl span** — an `impl` block's span covered the whole block, minting phantom clone
  reports.
- **Merge-aware churn.** The churn walks now follow merges, so a history landed through merge commits
  is no longer under-counted.
- **False zeros closed across the count surfaces**: a count that cannot be a total is labelled a
  floor, and a count whose unit differs from its neighbours says so, on every verb that emits one.
- **Host attribution is innermost-wins.** Plain span intersection could credit a 40-line function
  above a 3-line one as the host of the same `#if` region (tree-sitter definition extents over-reach
  in preprocessor-heavy Objective-C++). Hosts are now the definitions wholly inside the region plus
  the *innermost* definition containing its opening line — the same rule `--grep`'s `in=` uses, so a
  flip host and a grep hit can never disagree.
- **Gate shadowing.** A file that declares its own constant of the same name shadows the gate's, as
  normal C++ scoping requires. Without this, short house-style names cross-wired: *measured on one
  repository, a weapons header's `constexpr float kSpeed` / `constexpr int kTurns` contributed six
  phantom branch sites and four phantom hosts to an unrelated gate.* The value lane now also runs on
  C-family source only — an extension denylist had previously let a committed HTML report that merely
  quoted a gate name through.
- **`--flags` no longer reports gates from nested worktrees or build output as the repository's own.**
  The second directory walk that `--flags` needs (CMake files are never ingested) disagreed with the
  crawl about what counts as source. *(Measured: a stale worktree copy inverted a real option's
  reported default.)*
- **Ingest robustness.** Large or degenerately-nested JSON is skipped with a stderr note: the JSON
  lane indexes configuration keys, and a big or `[[[[…`-nested file is data or a test corpus — the
  former explodes the symbol table, the latter drives tree-sitter's error recovery superlinear
  (43 s measured on a 100 KB torture file). Both were found live by benchmarking against real
  upstream repositories.
- **CRLF-encoded files** are handled identically to LF in the flag value lane.
- **Reproducible dependency pinning.** All 15 fetched grammar, tree-sitter and test-framework
  dependencies previously pinned mutable tags, which can be force-moved server-side. Every one is now
  pinned to the commit SHA that tag resolved to, with the human-legible tag kept as a trailing comment.

### Security

- **Credential redaction is on by default** — credential-shaped literals are removed from emitted
  bodies and signatures unless you opt out with **`--no-redact`**. There is no opt-IN spelling,
  because the behaviour is not opt-in. The redaction fixtures that necessarily carry synthetic
  credentials are enumerated in `test/README.md` and enforced by a gate.

### Known limits

These are stated, not hidden, and each is measurable from the output itself:

- **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks, and macro-generated call
  sites produce no edge. A high-ranking symbol with no call edges may be a dispatch hub, not a leaf.
- **`amb="K"`** on a symbol means K of its calls hit a name with multiple definitions and the resolver
  guessed. The header's `ambiguous=N` is the call-graph completeness gauge — read the source when
  which-target matters.
- **Token estimates are calibrated, never exact.** The `--pr-context` estimate in particular is known
  to under-charge relative to a real tokenizer; treat it as a lower bound.
- **Binary-doc extraction (`markitdown` bridge) is uncached and re-runs every ingest.** The doc
  post-pass is deliberately outside the parse cache, so on a machine with `markitdown` installed a
  corpus containing PDF/PPTX/DOCX/XLSX pays the full subprocess extraction on *warm* runs too —
  measured at ~97% of a warm run's wall (2.05 s of 2.11 s) on a 2-vCPU VM against this repository's
  own showcase PDF+PPTX, found by the self-profiler's wall-vs-task-clock gap (child-process CPU is
  invisible to per-thread counters). The extraction is a pure function of the file bytes, so it is a
  clean cache candidate; until then, the cost scales with the corpus's binary docs, not its code.
- **`--for`'s `--token-budget` shaping is not strictly binding at very small budgets** — the header
  floor (envelope, legend, verbatim task echo) is bytes no trim can shrink, and the lens labels the
  result `over_ceiling` rather than claiming a trim it did not perform.
- **Release automation has never been executed end-to-end.** The tag-triggered build-and-attach
  workflow and the release-binary installer are untested until the first real tag push.
- **The x86 64-bit-key rank kernels need SSE4.2.** `_mm_cmpgt_epi64` is not in the SSE2 baseline, so on
  a stock `-march=x86-64` build the `int64`/`uint64` specializations — including the production
  `dynamic_map<std::uint64_t, …>` instantiation — fall back to the scalar template. Build with
  `-march=x86-64-v2` or `RIPWIRE_NATIVE=ON` to light them up. Correctness is identical either way; only
  the scan width changes.
- **The Linux counter backend's *active* path has not been run against real PMU hardware.** It is
  validated for correctness, degrade behavior and the sanitizer set under x86-64 emulation and on
  PMU-less VMs, where `perf_event_open` fails and the backend goes inactive as designed — which
  exercises the inactive arm only. The live counting path awaits a bare-metal box; `bench/PROFILE.md`
  carries the probe that tells you whether a candidate machine qualifies.
