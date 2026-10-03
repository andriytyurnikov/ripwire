# falseedgefix — calls that must not bind to a same-named in-repo definition (test/falseedgecheck.sh)

Each directory is its own root (the gate indexes one at a time). Every root holds a call that the language
resolves OUTSIDE the tree, or to exactly one in-repo function, beside an in-repo definition spelled the same way,
plus near-miss calls whose edges are real and must stay.

- `go/` — builtins `append max copy delete len close` beside a method, a function-local variable and another
  package's function of those names; `cells.NewScreen()` / `c.NewScreen()` / `strings.Split()` into packages
  outside the module beside in-repo `NewScreen`/`Split`. Kept: a same-package `min` that shadows the builtin, a
  same-package `copy`, `h.append()`, a package-level function variable called bare, `own.Pick()` inside the module.
- `js/` — `JSON.stringify`, `new URL()`, `Buffer.from`, `console/Math/Object/Array/Promise` members,
  `require('destroy')`, `require('supertest')`, `require('qs').stringify`, `{ parse } = require('cookie')` beside an
  object property, a getter, a static method, a test double and helpers of those names. Kept: relative requires
  (destructured and as a receiver), a file-local `const JSON` shadow, a same-file `function fetch`, a const arrow.
- `ts/`, `tsimport/` — the global `fetch` beside a class field and beside another file's exported `fetch`;
  `JSON.parse`, `crypto.subtle.verify`, `import * as qs from 'qs'` beside exported `parse`/`verify`/`stringify`.
  Kept: named imports of the in-repo `parse` and `fetch`, `new App()` and `app.dispatch()`.
- `py/` (src layout) — `from ui.css.match import match` beside two methods named `match`; a bare `process()` that
  only a method defines. Kept: an imported `append`, a same-module helper, a class-body call.
- `c/` — the function `opts_parse()` beside `struct opts_parse`; `find_type()` (an outside library) beside
  `enum find_type`. `cpp/` is the control: `Point( v )` constructs a struct in C++ and keeps its rows.
- `rs/` — `use termkit::render; render( n )` beside the method `History::render`. Kept: a same-module function
  and `h.render()`.

The names are paraphrases of graded false rows; the code is minimal and is never built.
