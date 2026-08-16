# Rust Fundamentals — Memory Model & Control

How a senior engineer reasons about ownership, borrowing, lifetimes, matching, error
mechanics, and modules — the decisions the Book won't make for you. Baseline: Rust 1.96,
edition 2024. Deep error *design* lives in `best-practices/error-design`; here we cover
language mechanics only.

## The one mental model everything else follows from

Rust's memory safety is not a runtime feature — it is a *compile-time proof* built on two
rules the borrow checker enforces on every reference:

1. **Shared XOR mutable.** At any point, a value has either any number of shared references
   (`&T`) or exactly one mutable reference (`&mut T`) — never both. Aliasing and mutation
   are mutually exclusive.
2. **No reference outlives its referent.** Every borrow's lifetime is contained within the
   validity of the thing it points at.

Everything — moves, lifetimes, `Send`/`Sync`, `Cell`/`RefCell` — is a consequence of, or a
controlled escape hatch from, these two rules. When a design fights the borrow checker, the
fix is almost always to restructure so that "shared XOR mutable" is *locally obvious*, not
to reach for `.clone()` or `Rc<RefCell<_>>`.

**Why this eliminates whole bug classes at compile time.** Rust types are *affine*: a value
can be used at most once by-value. Moving a `String` into a function invalidates the source
binding, so there is no second owner to free it — **double-free is unrepresentable**.
Because a reference can't outlive its referent, a pointer to freed or moved-out memory can't
be named — **use-after-free is unrepresentable**. Shared-XOR-mutable additionally forbids
iterator invalidation and data races (a data race *is* concurrent aliased mutation). These
are not lints you can suppress; they are the type system refusing to compile the bug.

**NLL (Non-Lexical Lifetimes) is stable** and is the model in effect. A borrow ends at its
*last use*, not at the end of its lexical scope. This is why the code below compiles: `r`'s
borrow is dead before the mutation.

```rust
// illustrative
let mut v = vec![1, 2, 3];
let r = &v[0];
println!("{r}");   // last use of r — borrow ends HERE
v.push(4);         // OK: no live shared borrow
```

Do **not** write pre-NLL workarounds (extra scopes `{ }` just to end a borrow, temporary
rebinding to drop a reference). For plain `&`/`&mut` borrows these are historical noise —
delete them. But keep explicit scopes around values whose *drop* matters: lock guards
(`MutexGuard`, `RwLock*Guard`), `Ref`/`RefMut` from `RefCell`, and anything held across an
`.await`. NLL ends borrows early; it does not drop `Drop` types early.

## Ownership & moves

Every value has exactly one owner; when the owner goes out of scope the value is dropped
(deterministic, no GC). This makes `Drop` the `IDisposable` you can't forget — cleanup runs
exactly once at scope exit with no `using`/opt-in, so *any* resource-holding type (file,
socket, lock guard, temp file) should implement `Drop` rather than expose a manual `close()`.
A binding without `mut` is *transitively* immutable: it freezes the entire value tree,
including nested `Vec`/`String`, so there is no shallow "const" for callers to leak past and
no team discipline to opt into — mutation requires an explicit `mut` on the owner. Assignment
and passing by value **move** ownership for non-`Copy` types; `Copy` types (integers, `bool`,
`char`, shared refs, and `Copy` structs) are duplicated bitwise instead.

```rust
fn consume(s: String) -> usize { s.len() }

fn owns() -> usize {
    let s = String::from("hi");
    consume(s) // s MOVED here; a later use of `s` would fail to compile
}
```

**The decision that matters:** *by-value vs by-reference in an API signature.* Take by value
(`String`, `Vec<T>`, `T`) when the function needs to **own or consume** the input — store it,
transform it into the return, or drop it. Take `&T` when you only need to read, `&mut T` when
you need to mutate in place. The cost of getting this wrong: a by-value parameter forces every
caller to give up or clone their value; a by-reference parameter that then needs ownership
forces an internal clone. Prefer to **push the clone to the boundary where it's actually
needed**, and let the caller decide — a caller who owns a throwaway value moves it in for free;
a caller who needs to keep it clones explicitly and *visibly*.

Taking `self` **by value** goes further — it *consumes* the receiver, so a non-`Copy`,
non-`Clone` type is proven usable exactly once at compile time with no runtime check. This is
the mechanism behind single-use crypto types like `ring`'s `Nonce`, where reuse is a compile
error rather than `memset`-and-pray: the value is simply gone from memory after the call.

For flexible read-only string/slice APIs, accept `impl AsRef<str>` or `&str`/`&[T]` rather
than `&String`/`&Vec<T>` — a `&String` needlessly rejects `&str` literals and forces an
allocation upstream. (See `api-and-interface-design` for the full argument-type playbook.)

## Borrowing

### Shared vs mutable

`&T` grants read access and is freely copyable; `&mut T` grants exclusive read/write. The
exclusivity of `&mut` is *the* invariant that makes safe mutation sound — it is what lets the
compiler assume no aliasing and optimize accordingly (this is also why `&mut T` is invariant,
below).

### Reborrows

Passing a `&mut T` to a function does **not** move it — the compiler inserts an implicit
*reborrow* (`&mut *v`), a fresh mutable borrow tied to the current scope. This is why you can
call through a `&mut` parameter repeatedly:

```rust
fn takes(v: &mut Vec<i32>) { v.push(1); }

fn reborrow(v: &mut Vec<i32>) {
    takes(v); // implicit reborrow &mut *v — NOT a move
    takes(v); // v still usable afterwards
}
```

Knowing reborrows exist stops the reflexive "the mutable ref got moved, better clone" panic.
Explicit `&mut *v` is only needed when you must force a shorter reborrow than inference picks
(rare; e.g. ending a borrow before another use).

### Split borrows — the idiomatic escape from "already borrowed"

The single most common borrow-checker fight is wanting two `&mut` into *disjoint parts* of one
value. The compiler tracks borrows per-**place**, so borrowing two distinct struct fields
mutably is fine, but it can't prove disjointness through a method call or an index. Idiomatic
fixes, in preference order:

- **Borrow fields directly**, not through a `&mut self` method — the compiler sees the fields
  are distinct places:

```rust
struct Parser { input: String, pos: usize }

impl Parser {
    fn advance(&mut self) {
        let input = &self.input;  // shared borrow of ONE field
        let pos = &mut self.pos;  // mutable borrow of a DIFFERENT field
        *pos += input.len();      // both live simultaneously — legal
    }
}
```

- **Slices:** `split_at_mut`, `split_first_mut`, `chunks_mut`, or `iter_mut` hand you provably
  disjoint `&mut` pieces. These are the safe, blessed way to get multiple mutable references
  into one collection:

```rust
fn split_borrow(buf: &mut [i32]) {
    let (head, tail) = buf.split_at_mut(1); // two disjoint &mut [i32]
    head[0] += tail[0];
}
```

- **Index/id indirection:** store indices instead of references (an "arena"/`SlotMap` shape).
  Trades pointer-chasing safety proofs for a bounds check — usually the right call for graphs
  and any self-referential structure.

Reach for `Cell`/`RefCell` (below) only after these fail. `.clone()` to dodge a split borrow
is a code smell: it hides an ownership-structure problem behind an allocation.

### When interior mutability is actually justified

`Cell<T>` and `RefCell<T>` move the shared-XOR-mutable check from compile time to runtime,
letting you mutate through a `&T`. Legitimate uses: mutation behind an otherwise-shared API
(caches, memoization, `&self` methods that update internal bookkeeping), single-threaded
shared graph state, and breaking a borrow cycle you genuinely can't restructure away.

```rust
use std::cell::RefCell;

struct Graph { visited: RefCell<Vec<bool>> }

impl Graph {
    fn mark(&self, i: usize) {            // &self, yet mutates
        self.visited.borrow_mut()[i] = true;
    }
}
```

**Trade-off:** `RefCell` panics on a runtime borrow-rule violation (`already borrowed`) — you
have traded a compile error for a potential runtime crash, and you pay a borrow-flag check on
every access. `Cell<T>` avoids the panic and the flag but only supports whole-value get/set
(and `T: Copy` for `get`), no interior references. **When to deviate / not reach for it:** if
the mutation could just be `&mut self` threaded through, do that instead — `RefCell` in a
data model is often a sign the ownership graph wasn't designed. For cross-thread sharing you
need `Mutex`/`RwLock`/atomics, never `RefCell` (it's `!Sync`); see `concurrency`.

## Lifetimes

Lifetimes are **descriptive, not prescriptive** — an annotation `'a` does not change how long
anything lives; it *names a constraint* the borrow checker already needs to verify. Most code
needs none because of elision.

### Elision rules (stable, apply to `fn` and `impl` method signatures)

1. Each elided input reference gets its own distinct lifetime.
2. If there is exactly **one** input lifetime, it is assigned to **all** elided output
   lifetimes.
3. In a method, if there is a `&self`/`&mut self`, **`self`'s lifetime** is assigned to all
   elided outputs.

```rust
fn first_word<'a>(s: &'a str) -> &'a str {  // rule 2 makes the <'a> optional here
    s.split_whitespace().next().unwrap_or("")
}
```

### When annotations are genuinely required

Only when elision cannot pick a single unambiguous answer — the classic case is **multiple
input references where the output could borrow from more than one**:

```rust
fn longest<'a>(a: &'a str, b: &'a str) -> &'a str {
    if a.len() >= b.len() { a } else { b }
}
```

Here you are asserting "the result is valid as long as *both* inputs are" — the compiler can't
guess that. Structs that hold references also require explicit lifetimes (`struct S<'a> { x:
&'a str }`), which is a design signal: a borrowing struct is a *view* whose owner must outlive
it. If a self-referential or long-lived struct fights you here, the answer is usually to
**own the data** (`String` not `&str`) or use indices — not ever-more-elaborate lifetime
gymnastics.

### Lifetime bounds and `'static`

`T: 'a` means "every reference inside `T` outlives `'a`". `T: 'static` means `T` contains **no
non-`'static` references** — i.e. it could live forever *if you kept it*. This is the most
misread bound in Rust: `'static` on a generic **does not mean "lives for the whole program"**;
an owned `String` is `'static` because it borrows nothing, even though you drop it immediately.
`thread::spawn` and many async runtimes require `'static` closures precisely because they can't
prove any borrowed data will outlive the spawned work — owning the data (move it in) satisfies
the bound. `&'static T` (a reference that truly lasts the whole program, e.g. from a string
literal or `Box::leak`) is the *narrower* thing people usually confuse it with.

### Variance — the intuition you need

You don't write variance, but it explains otherwise-baffling errors:
- `&'a T` is **covariant** in `'a` and `T` — a longer-lived / more-general reference can be
  used where a shorter one is expected.
- `&'a mut T` is covariant in `'a` but **invariant** in `T` — you cannot substitute a
  different `T` lifetime through a mutable reference, because writing through it could smuggle
  a shorter-lived value into a longer-lived slot (a soundness hole). This invariance is the
  direct consequence of `&mut`'s exclusivity/write capability.

The practical takeaway: if a `&mut` of a generic/lifetime-parameterized type refuses a
seemingly-compatible substitution, invariance is why — restructure to pass by shared ref or
by value rather than trying to defeat it.

## Pattern matching

### Exhaustiveness as a design tool

`match` must cover every case, checked at compile time. This is not a chore — it is
**refactoring insurance**: add a variant to an `enum` and every non-wildcard `match` becomes a
compile error pointing at the code that must handle it. **Therefore: avoid a catch-all `_` arm
on enums you own and expect to evolve** — a wildcard silently absorbs new variants and defeats
the exhaustiveness check. Use `_` only for genuinely open domains (integers, external enums
marked `#[non_exhaustive]`). This is a real code-review line: a `_ => {}` on a domain enum is a
latent bug waiting for the next variant.

### Binding modes / "match ergonomics" (stable)

When you match a reference against a non-reference pattern, bindings are inferred as references
automatically — `match &opt { Some(x) => .. }` binds `x: &T`, not `T`, with no explicit `ref`.
This is why `ref`/`ref mut` are rarely written in modern Rust; if you see them, they're usually
legacy. Know the mechanism so you understand why a bound variable is `&T` when you didn't write
`&` — that surprise is the #1 pattern-matching confusion.

### `if let`, `let else`, `while let`

- `if let` — handle one pattern, ignore the rest. Use when a full `match` would be one arm
  plus a noise `_`.
- `let ... else` (stable since 1.65) — bind in the *happy path* and **diverge** (return,
  break, panic) in the else. This is the idiomatic early-return-on-`None`/`Err`, and it keeps
  the bound value in the enclosing scope instead of nesting:

```rust
fn parse_first(line: &str) -> Option<i32> {
    let Some(tok) = line.split_whitespace().next() else {
        return None;          // else block MUST diverge
    };
    tok.parse().ok()          // `tok` is in scope here, un-nested
}
```

Prefer `let else` over `if let ... { ... } else { return }` when the else always bails — it
reads top-to-bottom with no rightward drift. Keep `match`/`if let` when the else branch does
real work with the value.

- `let`-chains (stable **1.88**, **edition 2024 only**) — `&&`-chain several `let` patterns
  with boolean tests in one `if`/`while` condition; bindings from earlier links are in scope in
  later links and in the body:

```rust
// edition 2024 only — will not compile on 2021
fn parse_pair(a: Option<&str>, b: Option<&str>) -> Option<(i32, i32)> {
    if let Some(x) = a
        && let Some(y) = b
        && let (Ok(x), Ok(y)) = (x.parse::<i32>(), y.parse::<i32>())
        && x < y
    {
        return Some((x, y));
    }
    None
}
```

This flattens the `if let { if let { if cond { } } }` pyramid that `let else` cannot help with —
you are *guarding one branch*, not diverging. **Trade-off / when to deviate:** it is
**edition-2024-gated** (it depends on the 2024 `if let` temporary-scope change for a consistent
drop order; earlier all-edition attempts hit drop-order edge cases), so a crate on edition 2021
cannot use it — check the edition before reaching for it. Keep `let else` when the failure path
diverges, and `match` when arms do real work. (Rust 1.88 release notes:
https://blog.rust-lang.org/2025/06/26/Rust-1.88.0/)

### Guards, `@` bindings, or-patterns, ranges

Guards (`if cond`) add a boolean test to an arm — but note **guards are not counted by the
exhaustiveness checker**, so a guarded arm still needs a fallback. `@` binds the whole matched
value while also testing its shape. Or-patterns (`A | B`) and ranges (`0..=9`) compress arms:

```rust
fn classify(n: i32) -> String {
    match n {
        big @ 100.. => format!("large: {big}"), // @ binds while range-testing
        z @ (0 | 1) => format!("bit: {z}"),     // @ over an or-pattern
        neg if neg < 0 => "negative".into(),    // guard
        _ => "small".into(),
    }
}
```

Combine them to keep logic in the pattern (where the compiler reasons about it) rather than in
arm bodies (where it can't):

```rust
enum Event { Key(u8), Resize { w: u32, h: u32 }, Quit }

fn handle(ev: Event) -> &'static str {
    match ev {
        Event::Key(b'a'..=b'z') => "lowercase",
        Event::Key(0 | 27)      => "control",
        Event::Key(_)           => "other",
        Event::Resize { w, h } if w == h => "square",
        Event::Resize { .. }    => "resize",
        Event::Quit             => "quit",
    }
}
```

## Error handling — the language mechanics

(Design questions — error *types*, when to use `thiserror`/`anyhow`, layering — are in
`best-practices/error-design`. This section is the boundary and the plumbing only.)

### `Option<T>` vs `Result<T, E>`

`Option` models **absence with no story** — "not found", "empty", "not yet set". `Result`
models **failure with a reason** you want to propagate or inspect. The decision: if a caller
would reasonably ask *"why did it fail?"*, use `Result`; if the only fact is presence/absence,
use `Option`. Bridge them explicitly — `opt.ok_or(err)` / `ok_or_else(|| ..)` turns absence
into a typed failure; `result.ok()` discards the reason.

### `?` and `From` conversions — the mechanism

`?` on a `Result` is: if `Ok(v)` evaluate to `v`; if `Err(e)` **`return Err(From::from(e))`**.
That `From::from` is the whole trick — `?` auto-converts the error into the function's declared
error type via a `From` impl. This is why you define `From<SourceError> for MyError` once and
then `?` composes cleanly across layers without manual `map_err` at every call site:

```rust
use std::num::ParseIntError;

#[derive(Debug)]
enum ConfigError { Missing, Bad(ParseIntError) }

impl From<ParseIntError> for ConfigError {
    fn from(e: ParseIntError) -> Self { ConfigError::Bad(e) }
}

fn read_port(raw: Option<&str>) -> Result<u16, ConfigError> {
    let raw = raw.ok_or(ConfigError::Missing)?; // Option -> Result, then ?
    let port: u16 = raw.parse()?;               // ParseIntError -> ConfigError via From
    Ok(port)
}
```

**When to deviate:** if you need to *add context* rather than mechanically convert, `?` alone
isn't enough — use `.map_err(|e| ..)` at the call site or an error type that carries context
(the domain of `error-design`). `?` also works on `Option` (returns `None` early) and in `main`
returning `Result<(), E>`.

### Panic vs recoverable — the boundary (the actual judgment call)

- **`Result`/`Option` = the caller can and should decide.** I/O failure, bad user input,
  parse failure, resource exhaustion, anything driven by the outside world. These are *expected*
  and must be typed into the signature.
- **`panic!`/`unwrap`/`expect`/`assert!` = a bug or broken invariant, unwinding is the only
  sane response.** Indexing past the end, a "impossible" `None`, a violated precondition the
  type system couldn't encode. Panicking says *"the program is now in a state it was written to
  never reach."*

The rule that keeps libraries usable: **library code returns `Result` for anything a caller
could plausibly handle; it panics only on genuine contract violations.** `unwrap()`/`expect()`
in library logic (not tests, not `main`, not examples) is a review red flag — replace with `?`
or a typed error. `expect("reason")` is strictly better than `unwrap()` where a panic is truly
correct, because the message documents the invariant being asserted. In `main`, prototypes, and
tests, `unwrap`/`expect` are fine — the "caller" is a human reading a crash.

Panics unwind and run destructors by default. Since 1.81 an unwind escaping an `extern "C"`
function aborts the process (use `extern "C-unwind"` if unwinding must cross the boundary). A
panic inside a `Drop` impl unwinds normally, but if that drop is running during an existing
unwind the double panic aborts — so `Drop` impls should be panic-free (see `unsafe-rust`).

## Modules, visibility & paths

Rust's module tree is **decoupled from the filesystem by declaration**: `mod foo;` tells the
compiler to pull in `foo.rs` or `foo/mod.rs`; without the `mod` declaration a file is not part
of the crate at all. This trips up newcomers constantly — adding a file does nothing until it's
declared in a parent module.

**Everything is private by default**, including struct fields. Visibility is a deliberate API
decision, not boilerplate:

| Visibility        | Meaning                                    | Use for |
|-------------------|--------------------------------------------|---------|
| (none)            | private to the defining module + children  | default; implementation detail |
| `pub`             | public to whoever can see the item's path  | the actual API surface |
| `pub(crate)`      | public within this crate only              | cross-module internals, not for downstream users |
| `pub(super)`      | public to the parent module                | sibling collaboration |
| `pub(in path)`    | public within a specific ancestor module   | rare, fine-grained control |

The judgment: **default to private and widen only on demand.** `pub(crate)` is the workhorse
for splitting a crate into modules that cooperate without leaking internals into the public
API — once something is `pub`, it's a semver commitment. Struct fields being private by default
is a feature: it lets you enforce invariants via constructors/methods and change the
representation without breaking callers. Make a field `pub` only when the struct is a plain
data bag with no invariant to protect.

Privacy is per-**module**, not per-type as in C++: a private field is visible to every item
in its enclosing module, so a colocated helper type can read and write another struct's
private fields freely. That is why Rust has no `friend` keyword — you grant access by choosing
module topology (with `pub(crate)`/`pub(super)`/`pub(in path)` for finer reach than C++'s
public/protected/private), not by access specifiers on the type.

**Paths & re-exports:** `use` brings a path into scope; it does not change visibility. `pub use`
(a re-export) *does* — it's how you build a clean public API (a "facade"): implement in nested
private modules, then `pub use` the handful of types you want at the crate root so users write
`mycrate::Widget` instead of `mycrate::internal::widgets::Widget`. Prefer `pub use` re-exports
over deep public module trees; the flatter the public path, the more freedom you keep to
reorganize internals. Note `extern crate` is **historical** (pre-2018) — in edition 2024 crates
are referenced directly by name; never add `extern crate`.

## The recurring borrow-checker fights → idiomatic fix

| Fight | Idiomatic resolution (not `.clone()`) |
|-------|----------------------------------------|
| "cannot borrow `x` as mutable, already borrowed as immutable" | NLL: the shared borrow is still *live* at the mutation — shorten it (use the value earlier) or restructure so uses don't overlap. |
| Two `&mut` into one collection/struct | `split_at_mut`/`split_first_mut`/`iter_mut`; borrow distinct fields directly; or index-based indirection. |
| "returns a value referencing data owned by the current function" | You're trying to return a borrow of a local — return the **owned** value, or take the buffer as a `&mut` out-param from the caller. |
| Storing references in a long-lived struct → lifetime spiral | Own the data (`String`/`Vec`), or store indices/IDs into an arena. |
| Need `&mut` through a shared `&self` | `Cell`/`RefCell` **only if** the mutation can't be threaded as `&mut self`; document why. |
| Closure "may outlive borrowed value" (thread/async spawn) | `move` the owned data into the closure to satisfy `'static`; don't try to extend the borrow. |
| Borrow conflict inside a loop | Bind the needed data before the loop, or collect indices in one pass and mutate in a second. |

The meta-rule: a borrow-checker error is the compiler pointing at an **ownership design
question you haven't answered yet**. Answer it by deciding who owns the data and who merely
looks at it — cloning to silence the error just defers the question and adds an allocation.

## Sources
- The Rust Programming Language (ch. 4 Ownership, ch. 10 Lifetimes, ch. 6 & 18 Pattern
  matching, ch. 9 Error handling, ch. 7 Modules) — https://doc.rust-lang.org/book/
- Comprehensive Rust (Google) — ownership/borrowing, pattern matching modules —
  https://google.github.io/comprehensive-rust/
- Rust Reference — Non-Lexical Lifetimes, variance, `?` desugaring, visibility & paths —
  https://doc.rust-lang.org/reference/
- Rust API Guidelines (argument types, error types) — https://rust-lang.github.io/api-guidelines/
- std docs — `Cell`/`RefCell`, `slice::split_at_mut`, `Result`/`Option` combinators
- Microsoft RustTraining — per-module privacy & no `friend` (c-cpp-book ch. 18) and lifetime
  elision / `'static` bounds (c-cpp-book ch. 7.1) —
  https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch18-cpp-rust-semantic-deep-dives.md ,
  https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch07-1-lifetimes-and-borrowing-deep-dive.md
- Microsoft RustTraining (csharp-book) — deep immutability vs record illusions (ch. 3.1),
  `Drop`/RAII vs `IDisposable` (ch. 7.3) —
  https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch03-1-true-immutability-vs-record-illusions.md ,
  https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch07-3-smart-pointers-beyond-single-ownership.md
- Microsoft RustTraining — single-use types as cryptographic guarantees
  (type-driven-correctness-book ch. 3) —
  https://github.com/microsoft/RustTraining/blob/main/type-driven-correctness-book/src/ch03-single-use-types-cryptographic-guarantee.md
