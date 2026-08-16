# Macros

Senior judgment on Rust metaprogramming: when a macro earns its cost, how `macro_rules!`
and procedural macros actually work, and how to keep both from wrecking readability,
IDE support, and error messages. Baseline: Rust 1.96, edition 2024.

## The decision: reach for a macro last

A macro is the tool of last resort. Everything a macro touches becomes harder to read,
harder for rust-analyzer to complete/rename/jump into, and harder to produce a good
compiler error for — because the code the user wrote is not the code the compiler sees.
Before writing one, prove the ordinary abstractions cannot do the job:

| Need | Prefer | Macro only when |
|------|--------|-----------------|
| Same logic over one type | function | never |
| Same logic over many types, shared bound | generic `fn<T: Trait>` | never |
| Same behaviour, per-type customization | trait + impls | impls are pure mechanical boilerplate across *many* types |
| A compile-time constant | `const` / `const fn` | value needs syntax `const fn` can't express |
| Compile-time chosen impl | trait dispatch / `const` generics | you need *new syntax*, not new values |

Macros are justified by **syntax that no function signature can express**, not by logic
you'd rather not repeat. The three legitimate drivers:

1. **Variadic / DSL syntax** — `vec![1, 2, 3]`, `println!("{x}")`, a mini query language.
   Functions can't take a variable number of heterogeneous arguments or custom grammar.
2. **Compile-time codegen across many types** — `#[derive(Debug)]` writing an impl for
   every field shape. A generic can't *emit an impl block*.
3. **Genuinely irreducible boilerplate** — code where a trait/generic would still leave
   a mechanical, error-prone stamp (e.g. registering many enum variants).

The cost, stated plainly: worse errors (they point at expanded code or the macro def, not
the user's line), degraded IDE navigation, opaque control flow, and — for proc macros —
real compile-time overhead. If a reviewer reading the call site can't predict what it does,
the macro has failed regardless of how clever it is. When in doubt, write the function.

## Declarative macros: `macro_rules!`

Pattern-matching over token trees. Each rule is `(matcher) => { transcription }`; the first
matcher that matches the invocation's tokens wins, so order rules from most to least
specific. `macro_rules!` is stable and covers the vast majority of real needs — prefer it
over a proc macro whenever the transformation is a syntactic rewrite rather than
type-directed codegen.

The right mental model: this is the only sound replacement for the C preprocessor, because
it rewrites the *parsed token tree* rather than raw text — an `expr` capture is one AST node,
so C's `SQUARE(a+b)` precedence corruption cannot happen, and hygiene makes name-capture bugs
structurally impossible. Double-evaluation is the one C hazard that survives (see pitfalls):
substituting an `expr` twice still runs it twice, so bind it to a `let` first.

### Fragment specifiers — pick the narrowest that fits

A `$name:frag` capture binds a chunk of the input as a specific grammar fragment. The choice
is a real decision because the fragment determines both what matches *and* how the captured
tokens may be re-used downstream (a captured `expr` is an opaque single node — you cannot
peel tokens off it later).

| Specifier | Matches | Use it for | The trap |
|-----------|---------|-----------|----------|
| `expr` | one expression | values, arguments | can't be followed by anything except `=> , ;` in the matcher; opaque afterwards |
| `ty` | one type | type positions | needs `ty`, not `expr`, or `Vec<i32>` won't parse where a value is expected |
| `ident` | one identifier | names you declare (`let $x`, `fn $x`) | `expr` can't be used to *name* a binding |
| `path` | `a::b::C` | trait/type paths, `use`-like args | `ty` accepts paths but also `&T`, `[T]`, etc. — `path` is stricter |
| `pat` | a pattern | `match`/`let` LHS | `pat` vs `pat_param`: since edition 2021 `pat` matches top-level or-patterns, so `|` leaves its follow set and a following `|` matcher becomes illegal; `pat_param` keeps the pre-2021 `PatternNoTopAlt` behaviour and still permits a following `|`. The governing edition is that of the `macro_rules!` *definition* |
| `tt` | one token tree | recursion, forwarding, munchers | matches *anything* balanced — powerful but gives zero structure/validation |
| `literal` | a literal expression, optional leading `-` | numeric, string, byte, char, and bool literals | opaque once captured — you cannot re-match its inner tokens literally in a downstream macro (only `ident`/`lifetime`/`tt` can be re-matched by literal tokens) |
| `block`, `stmt`, `item`, `meta`, `lifetime`, `vis` | as named | blocks, statements, whole items, attr contents | `stmt` doesn't consume its trailing `;` |

Rule of thumb: capture with the **most specific** fragment that admits every valid input.
Over-broad `tt` disables the parser's own error messages (bad input becomes a confusing
"no rule matched" instead of "expected type"); over-narrow forces callers into awkward
syntax. Once captured as a non-`tt` fragment the tokens are sealed — if you need to inspect
or recurse over them, capture `tt`/`$($t:tt)*` instead.

### Repetition

`$( ... )sep rep` replays the body once per match. `rep` is `*` (zero+), `+` (one+), or `?`
(zero or one, no separator). `sep` is an optional single token between iterations.

```rust
macro_rules! hashmap {
    // `$(,)?` = optional trailing comma; the classic ergonomic touch
    ($($key:expr => $val:expr),* $(,)?) => {{
        let mut m = ::std::collections::HashMap::new();
        $( m.insert($key, $val); )*
        m
    }};
}
```

Every repetition in the transcription must be driven by a metavariable captured under a
matching repetition, and nested repetitions must nest consistently — the compiler ties
iteration counts together, so `$($a),*` and `$($b),*` used in one output repetition must
have matched the same number of times. Always offer the `$(,)?` trailing comma: it is what
callers expect from `vec!`/`println!` and its absence is a papercut.

### Hygiene — what it protects, and where it stops

Identifiers *introduced by the macro* live in the macro's own syntax context, so they can't
capture or be captured by names at the call site. This is why a macro can freely declare a
temporary without fear of shadowing the caller's variable of the same name:

```rust
macro_rules! swap_via_tmp {
    ($a:expr, $b:expr) => {{
        let tmp = $a;   // this `tmp` is a *different* `tmp` than any caller's
        $a = $b;
        $b = tmp;
    }};
}
// caller may have its own `tmp` in scope — no collision
```

Hygiene's limits, which bite in practice:
- **It is per-identifier, not per-path.** Local variable bindings are hygienic. Paths to
  *items* (functions, types, traits) are resolved from where the tokens appear, so a macro
  that names `HashMap::new()` breaks if the caller hasn't imported `HashMap`.
- **Type and trait names are effectively unhygienic** for resolution — you must qualify them.
  Use fully-qualified paths (`::std::collections::HashMap`, `::core::default::Default`) or
  `$crate` (below), never bare names that assume the caller's imports.
- **Labels and lifetimes** follow their own hygiene rules; passing a lifetime *in* works,
  but inventing one inside is limited.

### `$crate` — call-site-independent paths

`$crate` expands to a path referring to the crate that *defined* the macro, whatever alias
the caller imported it under. It is mandatory in any exported macro that references its own
crate's items — without it the expansion assumes the caller has your crate in scope under a
specific name, which is fragile and often just wrong. The alias case is concrete: a
downstream user can rename your crate via `package = "..."` in their `Cargo.toml`, and only
`$crate::your_item` (never the literal crate name) survives that rename.

```rust
#[macro_export]
macro_rules! log_error {
    ($msg:expr) => { $crate::inner::record($msg) };
}
pub mod inner { pub fn record(_m: &str) {} }
```

### Scope and export — order matters, unlike items

`macro_rules!` macros are **textually scoped**: a macro must be defined (or brought into
scope) *before* the line that invokes it. This is unlike normal items, which are visible
regardless of source order, and is the usual cause of "cannot find macro" in a fresh file —
move the definition up, or the `mod` that defines it. `#[macro_export]` lifts a macro to the
crate root and makes it available to downstream crates (they reach it via `use your_crate::mac`
in edition 2018+, no `#[macro_use]` needed). Prefer explicit `use` over the legacy
`#[macro_use] extern crate` pattern, which is historical and pollutes scope.

### Recursion and the `tt`-muncher

A macro can call itself, peeling tokens off the front and recursing on the rest — the
"tt-muncher" pattern. It's how you process a token sequence the parser has no fragment for.

```rust
macro_rules! count {
    () => { 0usize };
    ($head:tt $($tail:tt)*) => { 1usize + count!($($tail)*) };
}
const N: usize = count!(a b c d); // == 4
```

Munchers are the escape hatch for real DSLs, but they compile in O(n²) token work and hit
the recursion limit (`#![recursion_limit = "256"]` to raise it). If a muncher is growing
past a dozen rules, that is the signal to move to a proc macro, where you have a real parser
instead of hand-rolled token recursion.

### Common `macro_rules!` pitfalls

- **`$e:expr` re-evaluation.** Substituting an `expr` capture more than once evaluates it
  more than once. Bind it to a `let` first — every argument exactly once, like a function
  would:
  ```rust
  macro_rules! max_ok {
      ($a:expr, $b:expr) => {{ let a = $a; let b = $b; if a > b { a } else { b } }};
  }
  ```
  The naive `if $a > $b { $a } else { $b }` evaluates the winner twice and any side effect
  in the loser once — a silent correctness bug.
- **Ambiguity / follow-set errors.** After an `expr` or `stmt` fragment the grammar only
  permits `=>`, `,`, or `;`, so `$x:expr $y:expr` is illegal. Separate captures with a real
  token, or capture `tt`.
- **`;` vs `,` and block vs expression.** `{{ ... }}` (a block returning a value) versus
  `{ ...; }` (statements) changes whether the macro is usable in expression position. Decide
  which position the macro must work in and wrap accordingly.
- **Matching order.** Put specific matchers before general ones; a leading `$($t:tt)*` rule
  will greedily win and mask the others.

## Procedural macros

When the transformation is *type-directed* — inspect a struct's fields, generate an `impl`,
parse a custom grammar into an AST — you need a proc macro. Unlike `macro_rules!`, a proc
macro is a compiled Rust function that receives and returns `proc_macro::TokenStream` and
runs *inside the compiler* at build time.

In practice these are Rust's *source generators*: you lean on `#[derive(...)]`,
`#[tokio::main]`, and `sqlx::query!` constantly, yet almost never author one — the bar in
"When a derive earns its keep" below is why.

Structural facts that drive the architecture:
- **Separate crate.** Proc macros must live in their own crate with `proc-macro = true` in
  `Cargo.toml`. That crate can export *only* proc macros. The near-universal pattern is a
  facade crate (`foo`) that re-exports from an internal proc-macro crate (`foo-macros`), so
  users depend on one thing.
- **Compile-time execution.** The macro is compiled first, then run against your code. This
  is why a proc-macro crate with heavy dependencies (a full `syn` with all features, plus
  transitive deps) taxes *every* downstream build.

### The three kinds

| Kind | Invoked as | Signature (conceptually) | Use for |
|------|-----------|--------------------------|---------|
| Derive | `#[derive(MyTrait)]` | `TokenStream -> TokenStream` (item in, *new items* out; original untouched) | auto-implementing a trait over a type's shape |
| Attribute | `#[my_attr(args)]` | `(attr: TokenStream, item: TokenStream) -> TokenStream` (may *replace* the item) | rewriting/wrapping an item: routes, instrumentation |
| Function-like | `my_macro!(...)` | `TokenStream -> TokenStream` | a `macro_rules!`-shaped call needing real parsing (e.g. `sqlx::query!`) |

Derive is additive and safest (it can't corrupt the annotated item, only add alongside it);
attribute macros are the most powerful and the most dangerous, because they can silently
rewrite the code the user wrote.

### The `syn` + `quote` + `proc-macro2` toolchain (ecosystem, not std)

`proc_macro::TokenStream` is a bare, compiler-tied token sequence with almost no parsing.
Nobody hand-parses it. The de-facto stack:
- **`syn`** — parses a `TokenStream` into a typed AST (`syn::DeriveInput`, `syn::ItemFn`,
  and `syn::parse_macro_input!`). Enable only the features you use; the default heavy build
  is a real compile-time cost.
- **`quote`** — the `quote! { ... }` interpolation macro builds output tokens with `#var`
  substitution and `#(...)*` repetition. It is the transcription half, analogous to a
  `macro_rules!` body but as a normal library.
- **`proc-macro2`** — a wrapper over `proc_macro` that works *outside* the compiler (in unit
  tests and shared logic). `syn`/`quote` speak `proc-macro2`; you convert at the boundary
  with `.into()`. This is what lets you unit-test macro logic without a compiler harness.

```rust
// illustrative — needs syn, quote, proc-macro2 in a `proc-macro = true` crate
use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput};

#[proc_macro_derive(Hello)]
pub fn derive_hello(input: TokenStream) -> TokenStream {
    let ast = parse_macro_input!(input as DeriveInput);
    let name = &ast.ident;
    // split_for_impl preserves the type's own generics/where-clause
    let (impl_g, ty_g, where_c) = ast.generics.split_for_impl();
    quote! {
        impl #impl_g Hello for #name #ty_g #where_c {
            fn hello(&self) -> &'static str { stringify!(#name) }
        }
    }
    .into()
}
```

The generics dance (`split_for_impl`) is not optional trivia: a derive that ignores the
target's generics generates code that fails to compile on any generic type, which is the
single most common derive bug.

### Spans and hygiene intuition

Every token carries a `Span` — a pointer back to source location *and* a hygiene context.
Spans are the entire reason proc-macro diagnostics can be good or terrible:
- **Call-site span** (`Span::call_site()`) resolves names as if written at the invocation
  and points errors at the user's code. Use it for identifiers that should see the caller's
  scope and for error messages the user must act on.
- **Def-site span** (mixed/def-site, `Span::mixed_site()` from `proc-macro2`) hides helper
  identifiers the macro invents so they can't collide with or leak to the caller — the proc-
  macro analog of `macro_rules!` hygiene, which you otherwise *don't get for free*.

Getting spans wrong produces the notorious "error points at the derive, not the field that
caused it" experience. Attach the span of the *relevant input token* to generated tokens so
the compiler underlines the user's actual mistake.

### Error handling — emit diagnostics, don't panic

A proc macro that `panic!`s aborts compilation with an opaque "custom attribute panicked"
and no useful location. Instead, turn errors into tokens the compiler reports at a real span:
`syn::Error::new_spanned(&offending, "message").to_compile_error()` produces a
`compile_error!` invocation carrying the right span. Return it as tokens on the error path:

```rust
// illustrative
match syn::parse2::<syn::DeriveInput>(input) {
    Ok(ast) => expand(ast),
    Err(e) => e.to_compile_error().into(), // underlines the offending tokens
}
```

For accumulating *multiple* errors (report every bad field in one pass, not one-at-a-time),
combine `syn::Error`s with `Error::combine`. The `proc-macro-error2` crate offers
`abort!`/`emit_error!` ergonomics if you're writing many diagnostics; plain `syn::Error`
is enough for most and adds no dependency.

### When a derive earns its keep

A custom derive pays for itself when: (a) the impl is a pure mechanical function of the
type's shape, (b) it must be generated for *many* types, and (c) the alternative is humans
hand-writing (and drifting) that impl. `serde`'s `Serialize`/`Deserialize` is the archetype —
correct, exhaustive field handling no human should transcribe. If only two or three types
need the impl, write them by hand: a proc-macro crate is a permanent compile-time tax and a
maintenance surface that a handful of explicit impls never incur.

## Debugging macros

- **`cargo expand`** (cargo-expand, an external subcommand) — prints the fully expanded
  source. This is the first and best tool for both `macro_rules!` and proc macros: you see
  exactly what the compiler sees. Install once; reach for it before guessing.
- **`trace_macros!(true)`** — *nightly only.* Logs each `macro_rules!` expansion as it
  happens; useful for runaway recursion.
- **`log_syntax!(...)`** — *nightly only.* Prints its token arguments at compile time, for
  peeking at what a matcher captured.
- For proc macros, `panic!`/`dbg!` inside the macro prints during compilation, and unit-
  testing the `proc-macro2`-level logic (input `TokenStream` → expected output) catches most
  bugs without a full compile cycle.

## Anti-patterns

- **A macro where a generic `fn` works.** If the body doesn't need new syntax and every
  argument has a nameable type, it's a function. Macros here only cost you errors and tooling.
- **Over-DSL-ing.** A bespoke mini-language inside `macro_rules!` that a plain builder or
  typed API would express more clearly. Novel syntax is a liability every reader must learn.
- **Unhygienic captures.** Emitting bare item names (`HashMap`, `Result`) that assume the
  caller's imports, instead of `$crate::…` / fully-qualified paths. Works in your tests,
  breaks in someone else's module.
- **Un-IDE-able output.** Macros that generate identifiers by concatenation (e.g. `paste!`
  gluing `get_` + field) defeat go-to-definition and rename. Sometimes necessary — but each
  invisible name is a tax on everyone who later reads the code.
- **Heavy proc-macro dependencies.** Pulling large or many crates into a `proc-macro = true`
  crate slows every downstream build. Trim `syn` features to what you parse; avoid dragging
  runtime-only deps into compile time.
- **`expr` captures re-substituted.** Covered above — silent double-evaluation. Bind to a
  `let` once.

## Cross-references

- **The Little Book of Rust Macros** — the definitive `macro_rules!` deep dive (fragments,
  hygiene, muncher patterns): https://veykril.github.io/tlborm/
- **The Rust Reference, Macros chapter** — normative grammar for matchers, repetition,
  hygiene, and proc-macro kinds: https://doc.rust-lang.org/reference/macros.html
- **`syn` / `quote` / `proc-macro2` docs** on docs.rs — the proc-macro toolchain API.
- **The Book, ch. 20 "Macros"** — https://doc.rust-lang.org/book/ch20-06-macros.html
- Composition: this file assumes the idioms in the `rust-patterns` skill; it does not restate
  generics/traits, which are the *alternatives* a macro must justify itself against.

## Sources

- Microsoft RustTraining, c-cpp-book ch.19 "Rust Macros: From Preprocessor to
  Metaprogramming / Hygiene" — https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch19-macros.md
- Microsoft RustTraining, csharp-book ch.12.1 "Macros: Code That Writes Code" —
  https://github.com/microsoft/RustTraining/blob/main/csharp-book/src/ch12-1-macros-primer.md
- Microsoft RustTraining, rust-patterns-book ch.13 "Macros — Code That Writes Code" —
  https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch13-macros-code-that-writes-code.md
