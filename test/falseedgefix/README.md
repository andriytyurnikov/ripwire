# falseedgefix — calls that must not bind to a same-named in-repo definition (test/falseedgecheck.sh)

Each directory is its own root (the gate indexes one at a time). Every root holds a call that the language
resolves OUTSIDE the tree, or to exactly one in-repo function, beside an in-repo definition spelled the same way,
plus near-miss calls whose edges are real and must stay.

- `go/` — builtins `append max copy delete len close` beside a method, a function-local variable and another
  package's function of those names; `cells.NewScreen()` / `c.NewScreen()` / `strings.Split()` into packages
  outside the module beside in-repo `NewScreen`/`Split`. Kept: a same-package `min` that shadows the builtin, a
  same-package `copy` (and `min`/`score`/`hook` from another file of the package), `h.append()`, a package-level
  function variable called bare, `own.Pick()` inside the module, a dot-import's bare `Pick()`, a nested module's
  `lib.Helper()` (`sub/go.mod`). `gonomod/` has no go.mod at all: its full-path import of an in-tree package keeps
  its edge.
- `js/` — `JSON.stringify`, `new URL()`, `Buffer.from`, `console/Math/Object/Array/Promise` members,
  `const { stringify } = JSON`, `globalThis.fetch`, `require('destroy')`, `require('supertest')`, `require('qs').stringify`, `{ parse } = require('cookie')` beside an
  object property, a getter, a static method, a test double and helpers of those names. Kept: relative requires
  (destructured and as a receiver), relative ES namespace/default imports (`esm/`), a file-local `const JSON` shadow,
  a same-file `function fetch`, a const arrow.
- `ts/`, `tsimport/` — the global `fetch` beside a class field and beside another file's exported `fetch`;
  `JSON.parse`, `crypto.subtle.verify`, `import * as qs from 'qs'` beside exported `parse`/`verify`/`stringify`.
  Kept: named and relative namespace imports of the in-repo `parse`/`stringify`/`verify`/`fetch`, `new App()` and
  `app.dispatch()`, an ambient `declare function track` called from a file that imports nothing.
- `py/` (src layout) — `from ui.css.match import match` and `import *` beside two methods named `match`; a bare
  `process()` that only a method defines. Kept: imported `append`/`format`, a same-module helper, a module-level
  callable variable, a bare `Worker()` construction, a class-body call.
- `c/` — the functions `opts_parse()` and `region()` beside same-named structs; the macro `CLAMP` is kept; `find_type()` (an outside library) beside
  `enum find_type`. `cpp/` is the control: `Point( v )` constructs a struct in C++ and keeps its rows.
- `rs/` — `use termkit::render; render( n )` beside the method `History::render`. Kept: a same-module function,
  `h.render()`, `History::new()`, `History::render( &h )`, `Self::width()`.

The names are paraphrases of graded false rows; the code is minimal and is never built.
