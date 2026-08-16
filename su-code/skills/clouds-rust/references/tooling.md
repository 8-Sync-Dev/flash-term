# Tooling, CI/CD, Observability & Release

The production toolchain, and the judgment for wiring it into a project that a team maintains for years. Baseline: Rust 1.96 (2026-06), edition 2024. Assumes the idioms in `rust-patterns` and the test discipline in `rust-testing`; this file is the layer *around* the code — how it is built, checked, observed, and shipped.

## Cargo is a contract, not just a build tool

Cargo's manifest is a machine-readable statement of intent: what your crate depends on, at what versions, under what feature flags, at what MSRV. Treat every field as load-bearing. The failure mode of Cargo mastery is not "the build breaks" — it is "the build works on your machine, silently pulls a different dependency graph in CI, and ships a binary nobody can reproduce."

### Workspaces

Multi-crate layout, `[workspace.dependencies]` version unification, and the `resolver = "2"`/`"3"` distinction belong to the architecture file — see `references/architecture.md`. The one CI-relevant fact: a workspace shares a single `Cargo.lock` and a single `target/` directory, so `cargo test --workspace --all-features` and one cache key cover the whole tree. Edition 2024 defaults to `resolver = "3"` (MSRV-aware resolution), which changes which versions a `cargo update` picks — pin it explicitly in the root manifest so the resolver choice is not silently coupled to whoever's toolchain ran last.

### Profiles: optimize the axis that hurts

Profiles (`[profile.*]`) are the knobs that trade compile time, runtime speed, and binary size. The defaults are deliberately conservative; a senior engineer changes them only against a measured cost.

| Setting | Default (dev / release) | When to change |
|---|---|---|
| `opt-level` | `0` / `3` | `dev` → `1` if your test suite is CPU-bound and slow; `s`/`z` on `release` only when binary size is a hard product constraint. |
| `lto` | `false` / `false` | `release` → `"thin"` for a cheap 5–15% runtime win; `"fat"` only when you have benchmarks proving it and can absorb minutes of extra link time. |
| `codegen-units` | `256` / `16` | `release` → `1` squeezes the last few % of runtime perf at the cost of losing parallel codegen. Measure first. |
| `debug` | `true` / `false` | `release` → `"line-tables-only"` when you want usable backtraces in production without a 3× binary. |
| `panic` | `"unwind"` / `"unwind"` | `"abort"` shrinks the binary and drops unwinding tables, but you lose `catch_unwind` and any test that asserts a panic still needs `unwind`. |

The highest-leverage, lowest-risk change for iteration speed is a `[profile.dev.package."*"]` block with `opt-level = 3` (or `2`): your dependencies get optimized once and cached, your own crate stays at `opt-level = 0` for fast incremental rebuilds. This is the single profile tweak worth applying almost everywhere. Deviate when your own crate is the hot path under test — then raise `[profile.dev]` too.

`[profile.release.build-override]` and `[profile.dev.build-override]` control how *build scripts and proc-macros* compile. Bumping their `opt-level` speeds up macro-heavy builds (serde, sqlx) without touching your runtime profile.

A companion build-script hygiene rule: always emit `println!("cargo::rerun-if-changed=build.rs")` (plus one line per input the script reads) even in a trivial `build.rs` — with *no* rerun-if-changed directive at all, Cargo re-runs the script whenever *any* file in the package changes, not just `build.rs`, a real compile-time tax in large crates. (Rust 1.71+ fingerprints the compiled build-script binary so a byte-identical one won't re-run, but that does not narrow the trigger set; the explicit instruction does.)

### Features: additive, never mutually exclusive

Cargo features are **unioned** within each dependency-graph partition — if crate A enables `foo/x` and crate B enables `foo/y`, `foo` is compiled once with both. Under resolver 2/3 (the edition-2024 default) the partitions are separate: normal/dev dependencies, build-dependencies and proc-macros, and non-matching target-specific dependencies are resolved independently, so `foo` can legitimately be compiled twice with different feature sets when it appears both as a normal dep and as a build-dep. The hard rule that follows: features must be **purely additive**. A feature that *removes* an API, or two features that conflict, will break some consumer's build the moment the graph unifies them, and the error will surface far from your crate. This is the most common way a well-meaning `no_std` or `minimal` feature poisons an ecosystem.

Practical discipline:
- Test the powerset that matters, not just `--all-features`. At minimum: no features, default features, all features. `cargo hack --feature-powerset --depth 2` (from `cargo-hack`) automates the combinatorial check; run it in CI for library crates.
- Gate optional dependencies with `dep:` syntax (`serde = ["dep:serde"]`) so the feature name and the crate name are decoupled — otherwise enabling the crate implicitly enables a same-named feature you didn't intend to expose.
- Keep `default` small. Every default feature is a cost every downstream user pays and must opt *out* of. `default = ["std"]` is reasonable; `default = ["std", "tokio", "reqwest", "json"]` forces a CLI user to drag in an async runtime.

Trade-off: heavy feature-gating makes the crate flexible but multiplies the CI matrix and the ways a build can differ from what you tested. When in doubt, fewer features and a clean split into sibling crates beats a feature maze.

### The `cargo` subcommand ecosystem

Cargo is extensible: any `cargo-foo` binary on `PATH` becomes `cargo foo`. The subcommands worth institutionalizing (each detailed below where relevant): `cargo-deny`, `cargo-audit`, `cargo-udeps`/`cargo-machete`, `cargo-outdated`, `cargo-hack`, `cargo-nextest` (faster test runner — see `rust-testing`), `cargo-semver-checks`, `cargo-release`/`release-plz`, `cargo-dist`. Install them pinned in CI (`cargo install --locked cargo-deny`) — `--locked` uses the tool's own `Cargo.lock` so a transitive bump in the tool doesn't randomly break your pipeline.

## Formatting and linting: mechanical consistency, then human judgment

### rustfmt — remove the argument entirely

`rustfmt` is not a style *preference*; its value is that it ends every whitespace and layout debate in a diff. Enforce it in CI with `cargo fmt --all --check` (non-zero exit on any deviation, no files touched). Keep a `rustfmt.toml` minimal — the defaults are the community Schelling point, and every override you add is a decision each new contributor must learn. The overrides that occasionally earn their keep: `imports_granularity = "Crate"` and `group_imports = "StdExternalCrate"` (both still nightly-gated as of 1.96, so they only apply under `cargo +nightly fmt` — do not put them in a config a stable CI job runs, or fmt warns and the setting is ignored). Trade-off: nightly-only fmt options mean your formatting depends on a nightly toolchain in CI. Most teams should not pay that; leave imports to the default.

### clippy — a lint is a conversation, `#[allow]` is your reply

Clippy ships hundreds of lints in groups of escalating opinionatedness:

| Group | Default | Posture |
|---|---|---|
| `correctness` | deny | Real bugs. Never allow without an FFI-grade reason. |
| `suspicious` / `style` / `complexity` / `perf` | warn (all in `clippy::all`) | The baseline. Fix them. |
| `pedantic` | allow | Opt in selectively; ~20% are noise for a given codebase. |
| `nursery` | allow | Unstable, may have false positives. Cherry-pick, don't blanket-enable. |
| `cargo` | allow | Manifest hygiene (e.g. `multiple_crate_versions`). Useful in CI for libs. |

The senior stance: enable `clippy::all` everywhere, then opt into `pedantic` and `nursery` at the crate root and **allow back** the handful that don't fit *with a comment stating why*. Configure this in the manifest, not scattered attributes, using the `[lints]` table (stable since 1.74):

```toml
# Cargo.toml — one place, applies to the whole crate/workspace.
[lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
# Allowed back, each with a reason a reviewer can check:
module_name_repetitions = "allow"  # our public paths read fine as `net::NetError`
missing_errors_doc = "allow"       # error types are self-documenting via thiserror
```

The `priority = -1` matters: lint-group entries must have lower priority than individual overrides, or the group re-enables what you tried to allow. This is the single most common `[lints]` mistake.

For a workspace, define `[workspace.lints.clippy]`/`[workspace.lints.rust]` once (the `[lints]` table has been stable since 1.74) and have each member opt in with `[lints] workspace = true` — otherwise lint policy drifts per crate and rots inside source files instead of staying auditable in one place.

**`#[allow]` in code is a claim you must defend.** Every inline allow needs a comment giving the reason, because a bare `#[allow(clippy::too_many_arguments)]` reads to the next maintainer as "clippy is annoying" rather than "this signature mirrors a C header." Compare:

```rust
// Justified allow: this is a 1:1 mirror of the C `blit()` entry point; bundling
// these params into a Rust struct would diverge from the upstream header and add
// a translation layer at every call site.
#[allow(clippy::too_many_arguments)]
pub fn blit(
    dst: *mut u8, src: *const u8, w: u32, h: u32,
    stride: u32, x: u32, y: u32, flags: u32,
) -> i32 {
    // ...
    0
}
```

Prefer `#[expect(lint)]` (stable since 1.81) over `#[allow]` wherever you expect the lint to *actually fire*: `expect` warns if the lint stops triggering, so it self-cleans when a refactor makes the suppression obsolete. Use `allow` only when the lint may or may not fire (e.g. cfg-gated code). This is a genuine upgrade over the old `#[allow]`-everywhere habit.

**`#![deny(warnings)]` belongs in CI, never in source.** Putting it in `lib.rs` means a future compiler that adds a new warning, or a dependency that deprecates an API, turns a green build red for reasons unrelated to your change — and pins every downstream user to your warning policy. Instead, deny at the command line in CI: `cargo clippy --all-targets --all-features -- -D warnings`. This gives you a zero-warning gate on your builds while leaving the source portable across toolchains. `RUSTFLAGS="-D warnings"` does the same for the compiler's own lints. Prefer expressing durable warning policy through the `[lints]`/`[workspace.lints]` table over a blanket `RUSTFLAGS`/`CARGO_ENCODED_RUSTFLAGS` env var: the table is versioned, auditable config Cargo scopes to your own crates, whereas the env var is applied to every rustc invocation Cargo makes. Deviate only for a leaf binary you alone build.

## MSRV, toolchains, and editions

### MSRV is a support promise

`rust-version = "1.82"` in `[package]` (or `[workspace.package]`) declares your Minimum Supported Rust Version. It is not decoration: the edition-2024 resolver *uses* it to avoid selecting dependency versions that require a newer compiler, and `cargo` errors early if the active toolchain is older. The judgment is entirely about your audience:

- **Library crates**: MSRV is an API-surface promise. Bumping it is a semver-minor-at-least event (arguably breaking for conservative consumers) and belongs in the CHANGELOG. Support a window — "latest stable minus N releases" or "what Debian stable ships" — and *test it in CI* (see the MSRV job below), because a dependency bump or a `let-else` you reflexively wrote can raise your real MSRV without touching `rust-version`.
- **Applications / internal services**: MSRV is whatever your build image has. Pin the toolchain instead (below) and don't agonize.

Trade-off: a low MSRV forecloses newer language features (edition 2024, `let-else`, `async fn` in traits since 1.75, `gen` blocks when they stabilize). You are trading ecosystem convenience for reach. Set it as low as your feature needs allow, no lower.

### `rust-toolchain.toml` — pin the toolchain, per repo

```toml
[toolchain]
channel = "1.96.1"
components = ["rustfmt", "clippy"]
targets = ["x86_64-unknown-linux-musl"]
```

This file makes `rustup` auto-select the pinned toolchain the moment anyone runs `cargo` in the directory — CI, contributors, and your laptop all use the identical compiler. Use it for **applications** and CI reproducibility. Do **not** commit a pinned `channel` in a **library** meant to build on many toolchains; there it fights your MSRV promise. The distinction: `rust-version` says "at least this old"; `rust-toolchain.toml` says "exactly this one." Libraries want the former, deployables the latter.

### Editions and migration

Editions (2015/2018/2021/2024) are opt-in language epochs; crates of different editions interoperate freely because the edition is per-crate and the compiled output is uniform. Edition 2024 (stable since 1.85) brought, among others, stricter `unsafe` in `extern` blocks, changes to `impl Trait` capture (`use<>` bounds), and RPIT lifetime capture rules. Migrate with the tool, never by hand:

```
cargo fix --edition          # applies mechanical rewrites for the next edition
# then bump `edition = "2024"` in Cargo.toml and:
cargo test --workspace       # the migration is only done when this is green
```

`cargo fix` handles the deterministic 90%; the remainder are genuine semantic changes the tool flags for you to resolve. (`cargo fix --edition-idioms` is not part of this recipe: the only idiom lint group that exists is `rust_2018_idioms`, so `--edition-idioms` has effect only on a 2015→2018 hop — dropping `extern crate` is a *2018* idiom — and is a silent no-op on an edition-2024 crate.) Trade-off: migrate one crate at a time in a workspace so review stays tractable. Never mix an edition bump with feature work in the same PR — you want the diff to be *only* the migration so a reviewer can trust the mechanical rewrites.

## Dependency hygiene and supply-chain posture

Every dependency is code you now ship, a license you now accept, and an attack surface you now own. The tooling turns "I hope this is fine" into a gate.

**`cargo-deny`** is the policy engine — one tool, four independent checks configured in `deny.toml`:
- `advisories`: fails on any dependency with a RUSTSEC advisory (it reads the same DB as `cargo-audit`). This makes vulnerability scanning a build gate, not a periodic chore.
- `licenses`: allow-list the SPDX licenses legal has cleared (`allow = ["MIT", "Apache-2.0", ...]`); the build fails on anything else, including a transitively pulled GPL crate. This is the only scalable way to keep license compliance honest.
- `bans`: forbid specific crates (`openssl` if you standardized on rustls), and — critically — `multiple-versions = "deny"` to catch the same crate compiled at three incompatible versions, which bloats binaries and fractures type identity.
- `sources`: restrict where crates may come from (crates.io only, or an allow-list of git remotes) — a defense against a typo-squatted or unexpected git dependency.

`cargo-deny` is the one supply-chain tool to run in CI unconditionally; it subsumes `cargo-audit` for the advisory check. Keep `cargo-audit` around for local ad-hoc scans and its `fix` affordances, but you don't need both in the pipeline.

**Unused dependency detection** — two tools, different mechanisms, different trade-offs:
- `cargo-machete` parses source for crate references. Fast, no build, no nightly — but it can false-positive on crates used only via macros or renamed imports. Good default for CI.
- `cargo-udeps` actually asks the compiler which deps produced no code. Accurate, but **requires nightly** and a full build. Use it locally when `machete` is ambiguous, not in a stable CI job.

Unused deps are not cosmetic: they lengthen builds, widen the audit surface, and mislead readers about what the crate actually needs.

**`cargo-outdated`** reports dependencies behind their latest compatible/incompatible release. Run it manually or on a schedule (a weekly Dependabot/Renovate PR is better — it opens the PR and runs your gates on the bump). Never auto-merge; a semver-compatible bump can still change behavior.

**Minimal-version testing** is the underused check that catches a real class of bug: your `Cargo.toml` says `foo = "1.2"` but you actually use an API added in `1.5`. Your build passes because the resolver picks the newest `1.x`, but a consumer who pins `1.2` breaks. Verify with the resolver's minimal selection:

```
cargo +nightly generate-lockfile -Z minimal-versions
cargo +nightly build --all-features   # or: -Z direct-minimal-versions for a laxer, saner check
```

`direct-minimal-versions` (checks only *your* declared minimums, not the whole transitive floor) is the pragmatic variant — the full `minimal-versions` often fails on transitive crates whose own lower bounds are wrong, which you can't fix. Run it periodically for libraries; skip it for applications, where you ship the lockfile anyway.

**Supply-chain posture, in order of leverage:** commit `Cargo.lock` by default, for libraries as well as deployables — `cargo new` now tracks it regardless of crate type, and it does not affect downstream consumers (only your `Cargo.toml` does). Committing it makes CI deterministic (fails on new commits, not on a dependency's surprise release) and makes the MSRV job meaningful, and it is what the `--locked` steps in the CI skeleton below require. To recover the "does it build against the newest graph?" coverage that *not* committing the lockfile used to give libraries, add a scheduled job that runs `cargo update` then tests. Enable `cargo-deny` advisories + licenses in CI. Prefer fewer, well-maintained dependencies over many thin ones — each one is a trust decision. For high-assurance projects, `cargo-vet` or `cargo-crev` let a team record human audits of dependency source and share them; that is real cost for real assurance, appropriate when a compromise is a company-ending event and overkill otherwise.

**Pin `windows-sys`/`windows` to a single minor version.** Unlike most crates, they ship *semver-incompatible* releases (0.48 → 0.52 → 0.59) that remove or rename API bindings, so a lax `^` range can silently break compilation on a routine `cargo update`. Gate them with `[target.'cfg(windows)'.dependencies]` so non-Windows builds never pull them into the graph.

## Observability: `log` facade vs `tracing`, and when logging is the wrong tool

### The decision: `tracing` for anything async or concurrent, `log` for simple synchronous tools

The `log` crate is a **facade**: your code calls `log::info!`, and a chosen backend (`env_logger`, `simplelog`) decides what happens. Its model is a flat stream of independent lines. That model breaks the moment you have concurrency: in an async service handling thousands of interleaved requests, a flat log line `"query failed"` cannot tell you *which request* it belongs to. You end up manually threading a request-id string through every log call — reinventing, badly, what `tracing` gives you for free.

`tracing` replaces the flat stream with **spans** (a period of time with structured context — a request, a transaction) and **events** (a moment within a span). A span attached to an async fn with `#[tracing::instrument]` (or a future wrapped with `.instrument(span)`) is re-entered on every `poll`, so every event and nested span underneath it inherits its context across `.await` points. The counterpart trap: holding a bare `span.enter()` guard across an `.await` is *wrong* — that guard is thread-scoped, not task-scoped, so while your task is suspended it mis-attributes events from other tasks polled on the same executor thread (and loses the span when your task resumes elsewhere); use instrumentation, never a held guard, to cross an await. Structured fields (`tracing::info!(user_id, latency_ms, "request complete")`) are typed key-value pairs, not interpolated strings, so a subscriber can emit them as JSON for ingestion instead of forcing you to regex them back out of a message.

The rule for a service, a library used by services, or anything with `.await`: **use `tracing`.** For a small synchronous CLI or a build script, `log` + `env_logger` is less machinery and perfectly adequate — reach for the simpler tool. A library should depend only on the `tracing` (or `log`) *facade*, never on a subscriber; choosing where logs *go* is the binary's job, not the library's. (`tracing` can even bridge `log`: the `tracing-log` feature captures `log`-crate output from your dependencies into the tracing pipeline.)

### `tracing-subscriber`: where policy lives

The subscriber is the binary-side component that decides filtering, formatting, and destination. The load-bearing pieces:
- `EnvFilter` reads `RUST_LOG` (e.g. `RUST_LOG=info,my_crate::db=debug`) so you tune verbosity per-module at runtime without a recompile — this is the single most useful thing to wire up first.
- The `fmt` layer formats to the console (human-readable in dev) or JSON (`.json()`, for machine ingestion in prod). Choose by environment.
- Layers compose: you can stack a `fmt` layer, an OpenTelemetry export layer (`tracing-opentelemetry`), and an error-reporting layer, and each event flows through all of them.

```rust
// illustrative — needs the `tracing` and `tracing-subscriber` crates
use tracing_subscriber::{fmt, EnvFilter};

fn init_telemetry() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())  // honors RUST_LOG
        .json()                                           // structured for prod ingestion
        .init();
}

#[tracing::instrument(skip(db), fields(user_id = %req.user_id))]
async fn handle(req: Request, db: &Db) -> Result<Response, Error> {
    // Every event below inherits the span's user_id and the fn name automatically.
    tracing::info!("handling request");
    let row = db.fetch(req.user_id).await?;
    Ok(Response::from(row))
}
```

`#[tracing::instrument]` wraps a function in a span named after it; `skip` keeps large/non-`Debug` args out of the span, and `fields(...)` records exactly the context you want. Choosing the log **level** is a real decision, not a formality: `error` = an operator must act; `warn` = degraded but handled; `info` = milestones an operator reads in steady state (keep these sparse — one per request, not per DB call); `debug` = developer diagnostics off by default in prod; `trace` = firehose. Over-logging at `info` is a classic production sin: it costs money in log ingestion and buries the signal.

### When logging is the wrong tool: use metrics

Logs answer "what happened in *this* request?" They are the wrong tool for "how many requests per second, at what p99 latency, over the last hour?" Computing an aggregate by parsing log lines is expensive and lossy. That question wants **metrics** — counters, gauges, histograms exported to Prometheus (via `metrics` + `metrics-exporter-prometheus`, or the OpenTelemetry metrics pipeline) and graphed. The heuristic: if you'd want to *alert* on it or *graph a trend*, it's a metric; if you'd want to *read it while debugging one incident*, it's a log/span. Most production incidents need both — a metric fires the alert, traces explain the specific failures. Emitting a `warn!` for every dropped packet on a saturated link is how you turn an incident into two incidents; a dropped-packet *counter* is the right instrument. Distributed tracing (spans exported via OTLP to Jaeger/Tempo) is the third pillar, and `tracing` + `tracing-opentelemetry` gives it to you from the same span data you already emit.

## CI/CD: the canonical GitHub Actions pipeline

The goal is a pipeline that catches on a machine what you'd otherwise catch in review or production, in parallel, with fast caches. Below is a complete, copy-usable skeleton; the reasoning for each job follows so you can adapt rather than cargo-cult it.

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:

concurrency:                      # cancel superseded runs on the same ref
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  CARGO_TERM_COLOR: always
  RUSTFLAGS: "-D warnings"         # compiler warnings fail the build, in CI only

jobs:
  fmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with: { components: rustfmt }
      - run: cargo fmt --all --check

  clippy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with: { components: clippy }
      - uses: Swatinem/rust-cache@v2
      - run: cargo clippy --all-targets --all-features -- -D warnings

  test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false             # one OS failing shouldn't hide the others
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo test --workspace --all-features --locked

  msrv:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@1.82.0   # your declared rust-version
      - uses: Swatinem/rust-cache@v2
      - run: cargo check --workspace --all-features --locked

  docs:
    runs-on: ubuntu-latest
    env: { RUSTDOCFLAGS: "-D warnings" }       # broken intra-doc links fail
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo doc --workspace --all-features --no-deps

  deny:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: EmbarkStudios/cargo-deny-action@v2   # advisories + licenses + bans + sources
```

**Why this shape:**
- **Separate jobs, not one script.** Each runs in parallel and reports independently, so a formatting nit and a real test failure are distinct red X's, not one opaque failure. `fail-fast: false` on the matrix keeps a Windows-only bug from masking the Linux result.
- **`dtolnay/rust-toolchain`** is the de-facto standard installer — minimal, fast, and it respects `rust-toolchain.toml` if present (so pin the version *there* and use `@stable` here, or pin here for the MSRV job specifically).
- **`Swatinem/rust-cache@v2`** is non-negotiable — it caches `~/.cargo` registry and `target/` keyed on the lockfile and toolchain, turning a 5-minute cold build into a 30-second warm one. It deliberately does *not* cache your own crates' final artifacts (those change every push), only dependencies. Do not hand-roll `actions/cache` for Rust; this action encodes the Rust-specific invalidation rules you'll otherwise get subtly wrong.
- **`--locked`** everywhere that builds: fails if `Cargo.lock` is stale or missing, guaranteeing CI tests the exact graph you committed. Without it, CI can silently resolve a newer patch than your lockfile.
- **The MSRV job runs `cargo check`, not `test`** — you're verifying the code *compiles* on the old compiler; you don't need to re-run the whole suite on it. Pin the toolchain to the literal `rust-version` so a drift between claim and reality turns red here.
- **`RUSTDOCFLAGS: -D warnings`** in the docs job makes a broken `[Type]` intra-doc link a build failure — otherwise doc rot is invisible until a user hits a dead link on docs.rs.
- **`concurrency` with `cancel-in-progress`** stops burning runners on commits you've already superseded — a real cost saver on active branches.

Trade-off: this is six jobs. For a tiny internal tool, collapse fmt+clippy+test into one and drop the matrix — the ceremony should match the stakes. For a published library, this is the floor, and you'd *add* the feature-powerset (`cargo-hack`) and minimal-versions jobs.

### Cross-compilation

`cross` (from cross-rs) runs the build inside a Docker image preloaded with the target's C toolchain and linker, so `cross build --target aarch64-unknown-linux-musl` works from an x86 Linux host without you assembling a sysroot by hand. Use it when you ship binaries for targets you don't develop on — musl for static Linux binaries, ARM for edge/embedded. For pure-Rust crates with no C dependencies, plain `rustup target add <triple>` + `cargo build --target` is enough and skips Docker. The judgment: reach for `cross` only when a `-sys` crate forces a real cross C-toolchain problem; otherwise the native target is simpler. musl targets in particular give you a fully static binary (no glibc version coupling) at the cost of a slower default allocator — worth it for container images `FROM scratch`.

To pin the *glibc floor* rather than just the target architecture, reach for `cargo-zigbuild` over `cross` or a hand-built sysroot: the target suffix `x86_64-unknown-linux-gnu.2.17` tells Zig's bundled linker to link against glibc 2.17 symbol versions, so the binary runs on RHEL/CentOS 7 — plain cross-compilation links the host's glibc and `cross` links its container's, neither of which lets you set the floor, and Zig ships ~40 targets in one ~40 MB download with no Docker. Whichever tool you use, `build.rs` always runs on the *host* during cross-compilation, so it can never execute a target-arch binary or probe the target's runtime — feature-detect through `cfg`/`CARGO_CFG_*` env vars, never by running compiled code.

## Release engineering

### Automate version + changelog + tag as one atomic operation

Manual releases drift: you bump the version, forget the changelog, tag the wrong commit. Two tools remove the drift, with different philosophies:
- **`cargo-release`** is imperative: you run `cargo release minor`, it bumps versions across the workspace (respecting inter-crate dependencies), updates the changelog, commits, tags, and publishes — in one transaction you trigger deliberately. Best when releases are a human decision.
- **`release-plz`** is continuous: a bot watches `main`, and from your Conventional Commits it maintains an always-open "Release PR" with the computed version bump and generated changelog. Merging that PR *is* the release. Best for trunk-based teams that want release to be merge-driven, not a ceremony.

Both depend on **Conventional Commits** (`feat:`, `fix:`, `feat!:`/`BREAKING CHANGE:`) to compute the semver bump and group the changelog. Adopting that commit convention is the prerequisite; without it the automation guesses.

### Semver is a compiler-checkable promise

Rust's semver is stricter than most ecosystems' — adding a variant to a non-`#[non_exhaustive]` public enum, adding a method that shadows a trait method, or tightening a bound are all breaking, and none are obvious in review. **`cargo-semver-checks`** compares your crate's public API against the last published version and *tells you the required bump*, catching the accidental breaking change before you publish it as a patch. Run it in CI for any published library:

```
cargo semver-checks check-release   # fails if the version bump doesn't match the API delta
```

This is the difference between "we think this is a patch" and "the tool verified nothing breaking changed." Trade-off: it only sees the public API, not behavioral changes — a function that keeps its signature but changes its meaning is still your responsibility to flag.

### `cargo publish`, yanking, and reproducibility

`cargo publish` uploads to crates.io **permanently and immutably** — you cannot delete or overwrite a version, only **yank** it (`cargo yank --version 1.2.3`). Yanking doesn't remove the crate; it prevents *new* dependency resolutions from selecting it while leaving existing lockfiles that pin it working. So yank for "this release has a serious bug, stop new adopters," not for "I made a typo" — the version number is spent regardless. Because publishing is irreversible, `cargo publish --dry-run` and the CI semver check are cheap insurance against an embarrassing permanent mistake. For a workspace, publish in dependency order (leaf crates first); `cargo-release` handles this, which is much of why it exists.

**Reproducible builds** — a given source + lockfile + toolchain producing a bit-identical binary — matter when you need to prove a shipped artifact matches audited source. The knobs: commit `Cargo.lock`, pin the toolchain (`rust-toolchain.toml`), set `--remap-path-prefix` to strip absolute build paths, and build in a fixed container. Full bit-reproducibility is achievable but demands care (build timestamps, `$HOME` leakage); pursue it only when the assurance requirement is real, and lean on the lockfile+toolchain pin for the 90% case.

If a `build.rs` bakes in a build time, have it honor `SOURCE_DATE_EPOCH` (falling back to `now()` only when the variable is unset) — embedding `chrono::Utc::now()` directly gives every build a different binary hash, defeating exactly the content-addressed caching and artifact verification that reproducibility buys you.

### Binary distribution

For end-user binaries (a CLI), **`cargo-dist`** generates the whole release apparatus: cross-platform builds, installers (shell script, PowerShell, Homebrew, MSI), and GitHub Release artifacts wired to `cargo-dist init` + a generated workflow. It turns "ship a binary for six platforms" from a bespoke release script into a maintained tool. Use it the moment you have more than one target or want an install one-liner; for a single-platform internal tool, a `cargo build --release` in CI uploading one artifact is enough.

## Documentation is a deliverable, gated like code

`cargo doc --no-deps --open` builds your crate's HTML docs from `///` comments; docs.rs builds them automatically on publish. Three practices raise docs from afterthought to product:

**Gate documentation coverage.** `#![warn(missing_docs)]` at the crate root warns on any undocumented public item; promote to `deny` in CI once you're clean. This is what keeps the *next* public function from shipping undocumented. A fully-documented public surface compiles cleanly under it:

```rust
#![warn(missing_docs)]
//! A tiny crate whose public surface is fully documented.

/// A monotonic sequence generator.
pub struct Counter {
    next: u64,
}

impl Counter {
    /// Creates a counter starting at zero.
    pub fn new() -> Self {
        Self { next: 0 }
    }

    /// Returns the next value, advancing the counter.
    pub fn tick(&mut self) -> u64 {
        let v = self.next;
        self.next += 1;
        v
    }
}

impl Default for Counter {
    fn default() -> Self {
        Self::new()
    }
}
```

**Doc examples are tests.** Code in `///` fences is compiled and run by `cargo test` (doctests). This is uniquely valuable: your documentation *cannot* drift from the API, because a signature change breaks the doctest. Write the example that shows the intended use, not a contrived one — it doubles as the acceptance test for your public API's ergonomics. Mark examples that shouldn't run with ```` ```no_run ```` (compiled, not executed — for network/FS code) or ```` ```ignore ```` (neither — a last resort). Per the Rust API Guidelines, every public item deserves an example; the ones people copy-paste are your most-used docs.

**Configure docs.rs explicitly** for anything non-trivial:

```toml
[package.metadata.docs.rs]
all-features = true                                    # document the full API, not just defaults
rustdoc-args = ["--cfg", "docsrs"]                     # enable feature-gated doc annotations
targets = ["x86_64-unknown-linux-gnu"]                 # or list the platforms that matter
```

Pair `--cfg docsrs` with `#![cfg_attr(docsrs, feature(doc_cfg))]` (nightly-gated `doc_cfg`, but docs.rs builds on nightly so it works there) to render "available on feature X" badges on gated items — without it, users can't tell from the docs which features an API needs. Trade-off: `doc_cfg` is a nightly feature, so it's `cfg_attr`-guarded to keep your stable build clean; it's the one sanctioned nightly-ism in an otherwise-stable crate.

The through-line for the whole toolchain: each of these gates converts a class of "someone will notice in review, or a user will hit it in prod" into "the machine caught it on push." That conversion — from human vigilance to mechanical certainty — is the entire point of investing in tooling, and the judgment is only ever *which* gates are worth their cost for *this* project's stakes.

## Sources

Microsoft RustTraining (github.com/microsoft/RustTraining) chapters mined for the judgment above:

- Logging and Tracing: syslog/printf → log + tracing (`c-cpp-book`) — facade/backend split and span propagation across `.await`: https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch17-4-logging-and-tracing-ecosystem.md
- Build Scripts — build.rs in Depth (`engineering-book`) — `cargo::rerun-if-changed` trigger set and host execution during cross-compilation: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch01-build-scripts-buildrs-in-depth.md
- Cross-Compilation — One Source, Many Targets (`engineering-book`) — `cargo-zigbuild` glibc-floor pinning: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch02-cross-compilation-one-source-many-target.md
- Compile-Time and Developer Tools (`engineering-book`) — centralizing lint policy in `[workspace.lints]`: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch08-compile-time-and-developer-tools.md
- Windows and Conditional Compilation (`engineering-book`) — pinning `windows-sys`/`windows` and `cfg(windows)` dependency gating: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch10-windows-and-conditional-compilation.md
- Tricks from the Trenches (`engineering-book`) — `RUSTFLAGS` vs `[lints]` scope and `SOURCE_DATE_EPOCH` in build scripts: https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch12-tricks-from-the-trenches.md
