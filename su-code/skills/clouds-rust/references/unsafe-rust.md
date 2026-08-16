# Unsafe Rust, FFI, Pin & no_std

Judgment for the parts of Rust where the compiler stops proving things for you and you take over the proof obligation. Baseline: Rust 1.96, edition 2024. Cross-references `async.md` (futures/Pin), `performance.md`, `architecture.md`; does not restate them.

## The mental model: unsafe is a proof obligation, not an escape hatch

`unsafe` does **not** disable the borrow checker, turn off lifetimes, or make aliasing rules go away. It unlocks exactly five *superpowers* (Rustonomicon):

1. Dereference a raw pointer (`*const T` / `*mut T`).
2. Call an `unsafe fn` (including FFI).
3. Access or modify a `static mut` (avoid; see below).
4. Implement an `unsafe trait` (`Send`, `Sync`, and others).
5. Access fields of a `union`.

Everything else — moves, borrows, lifetime rules, `Drop` — still applies inside `unsafe`. The keyword means "I, the author, have discharged an invariant the compiler cannot check." It is a promise, not a permission slip.

**Why this framing matters:** the compiler's soundness guarantee is a contract between *your unsafe code* and *the rest of the program*. If your `unsafe` block violates an invariant, the miscompilation can surface arbitrarily far away, in safe code you never touched. So the unit of reasoning is never the line — it is the *module boundary* that upholds an invariant.

### unsafe vs unsound — the distinction that governs everything

- **`unsafe`** is a keyword: a block/fn where superpowers are available.
- **Sound** means: no safe caller can ever trigger UB, no matter what inputs they pass. This is the only bar that matters.
- **Unsound** means: some safe usage *can* cause UB. An unsound API is a bug even if it "works" in every test, because the compiler is licensed to assume UB never happens and optimize accordingly.

A public safe function that wraps `unsafe` internals is **your** responsibility to make sound. If a caller can pass values that break your `// SAFETY` reasoning, the API is unsound and must either validate at the boundary or be marked `unsafe fn` (pushing the obligation to the caller). Marking a function `unsafe fn` is not a fix — it is a decision about *where the proof lives*.

## Undefined behavior catalog — and why each is UB

UB is not "crashes" or "wrong answer." It is "the compiler assumed this never happens, so all bets are off": time travel, deleted bounds checks, `match` arms that both run. The stable list you must never trigger (Rust Reference, *Behavior considered undefined*):

| UB | Why it is UB (what the optimizer assumes) |
|----|-------------------------------------------|
| **Data race** — two threads, one writes, no sync | The memory model gives no defined value; LLVM assumes race-free and reorders freely. |
| **Dangling / out-of-bounds deref** | Pointer must be to a live allocation of the right size; else reads/writes hit reused or unmapped memory. |
| **Misaligned reference/deref** | `&T`/`*T` must be aligned to `align_of::<T>()`; hardware and LLVM assume it. |
| **Producing an invalid value** | e.g. `bool` other than 0/1, `char` > 0x10FFFF, a null/dangling `&`/`&mut`, an uninhabited type, a `NonNull`/`NonZero*` holding the forbidden value. The type's *validity invariant* is assumed by every consumer. |
| **Aliasing a `&mut`** | `&mut T` is assumed unique; two live `&mut` to the same place (or `&mut` + `&`) lets the optimizer cache/reorder as if no other access exists. |
| **Breaking a library safety invariant** | e.g. `str` non-UTF-8, `Vec` len > capacity. Safe code trusts these unconditionally. |
| **Unwind-ABI mismatch across an `extern "C"` frame** | A Rust-defined `extern "C" fn` aborts the process on an escaping panic (compiler guard, since 1.81) — a hard kill, not UB. Genuine UB is a mismatched unwind ABI: unwinding *into* Rust from a C frame compiled with no unwind tables. |

The subtle one is **`&mut` aliasing**: this is why `split_at_mut` *must* be `unsafe` internally — the borrow checker cannot prove two subslices are disjoint, so you prove it and expose a sound safe API. Note the *validity* vs *safety* invariant split: violating a validity invariant (bad `bool`) is instant UB even if you never read it; violating a safety invariant (non-UTF-8 `str`) is UB only once safe code relies on it — but you must uphold both.

## The safe-abstraction discipline

The senior pattern is not "avoid unsafe" — it is **encapsulate unsafe behind a sound safe API, with the smallest possible unsafe surface**.

1. **Minimal blocks.** Wrap only the operations that truly need the superpower. A giant `unsafe { ... }` around 40 lines hides which line carries the obligation. In edition 2024, `unsafe_op_in_unsafe_fn` is warn-by-default: even inside an `unsafe fn` you must write explicit inner `unsafe {}` blocks, which forces per-operation SAFETY reasoning. Keep it that way; do not `#[allow]` it.
2. **`// SAFETY:` on every block.** Clippy's `undocumented_unsafe_blocks` should be on. The comment states *which invariant holds and why* — not what the code does. A block without a defensible SAFETY comment is a code-review reject.
3. **`# Safety` on every `unsafe fn`.** The doc section states the *preconditions the caller must uphold*. If you can't enumerate them, the function should not be `unsafe fn` (it should validate) or shouldn't exist.
4. **Prove disjointness/uniqueness explicitly**, usually via `assert!` that a later SAFETY comment cites.

```rust
use std::slice;

/// Splits `slice` into two disjoint mutable halves at `mid`.
pub fn split_at_mut<T>(slice: &mut [T], mid: usize) -> (&mut [T], &mut [T]) {
    let len = slice.len();
    let ptr = slice.as_mut_ptr();
    assert!(mid <= len);
    // SAFETY: mid <= len. Ranges [0,mid) and [mid,len) are disjoint, so the two
    // returned &mut slices never alias. Both lie within the one allocation `ptr`
    // is valid for; `ptr.add(mid)` stays in bounds.
    unsafe {
        (
            slice::from_raw_parts_mut(ptr, mid),
            slice::from_raw_parts_mut(ptr.add(mid), len - mid),
        )
    }
}
```

The public fn is safe: no input can make it unsound (the `assert!` handles `mid > len`), so callers get a checked, UB-free primitive. That is the whole game — one `unsafe` block, one invariant, proven, wrapped.

**Trade-off:** encapsulation costs a wrapper type/fn and discipline. **When to deviate:** essentially never for a public API. Internal-only helpers may skip the wrapper if the module is small and every caller is audited — but the SAFETY comment stays.

## Raw pointers, provenance, NonNull

`*const T` / `*mut T` carry no borrow-checker meaning: creating and moving them is safe; only *dereferencing* is unsafe. They can dangle, be null, be misaligned, be aliased — the compiler tracks none of it.

**Provenance intuition (stable; Miri enforces it under `-Zmiri-strict-provenance`):** a pointer is not just an address — it carries the *right to access* a specific allocation, derived from the reference/allocation it came from. An integer→pointer cast can only recover provenance that was previously *exposed* (via a `ptr as usize` cast / `.expose_provenance()`); fabricating an address that was never exposed and dereferencing it is UB. Miri flags this only with `-Zmiri-strict-provenance` (int→ptr round-trips are accepted by default), so enable that flag when auditing provenance. Practical rule: derive pointers by `.add()`/`.offset()`/field projection *from a pointer you legitimately have*, never by integer arithmetic through `usize`. When you must round-trip through an integer, the strict-provenance / exposed-provenance APIs (`ptr.addr()`, `.expose_provenance()`, `ptr::with_exposed_provenance`) are stable since 1.84 and usable directly on the pinned baseline; only the `fuzzy_provenance_casts` / `lossy_provenance_casts` *lints* remain nightly. `.offset_from`, `.add`, `.wrapping_add` differ in whether they assume in-bounds — `.add` assumes it (UB if not), `.wrapping_add` does not.

**`NonNull<T>`** over `*mut T` when the pointer is a known-non-null owning/interior pointer: it enables the null-pointer niche so `Option<NonNull<T>>` is pointer-sized, and it is covariant (unlike `*mut T`). It is the right building block for custom smart pointers, allocator-backed structures, and FFI handles.

```rust
use std::ptr::NonNull;

/// Niche-optimized handle: `Option<Handle>` is the same size as `Handle`.
pub struct Handle {
    ptr: NonNull<u8>,
}

impl Handle {
    /// # Safety
    /// `raw` must be non-null and valid for the lifetime of the `Handle`.
    pub unsafe fn from_raw(raw: *mut u8) -> Self {
        // SAFETY: caller guarantees `raw` is non-null (contract above).
        Handle { ptr: unsafe { NonNull::new_unchecked(raw) } }
    }
    pub fn as_ptr(&self) -> *mut u8 { self.ptr.as_ptr() }
}

const _: () = assert!(size_of::<Option<Handle>>() == size_of::<Handle>());
```

Prefer `NonNull::new(raw)` (returns `Option`) at trust boundaries; reserve `new_unchecked` for when non-null is already proven.

**`PhantomData<T>` when wrapping raw pointers** silently sets both variance *and* drop-check, and the wrong marker is unsound, not cosmetic. `PhantomData<T>` means "I own a `T`" — covariant, and dropck then requires `T` to outlive the struct; `PhantomData<*const T>` means "I only point at a `T`" — no dropck obligation; `PhantomData<&'a mut T>` is *invariant* over `T`, which is exactly what blocks an unsound lifetime-shortening. (`fn(T)` is contravariant over `T`, `fn() -> T` covariant, `fn(T) -> T` invariant.) Decision rule: a container that *owns* its pointees carries `PhantomData<T>`; a view/reference type carries `PhantomData<&'a T>` or `PhantomData<*const T>`.

**`static mut`:** effectively deprecated in practice. In edition 2024 taking a reference to a `static mut` is a hard error (`static_mut_refs`), because any two references race trivially. Use a real interior-mutability type instead — `static COUNTER: AtomicUsize = AtomicUsize::new(0);` or `static CFG: OnceLock<Config> = OnceLock::new();` (or a `Mutex` for larger state). If you truly need mutable global raw memory, use `&raw mut` / `&raw const` (stable raw-reference operators, 1.82+) to get a pointer without ever forming a reference.

## MaybeUninit — the only correct way to touch uninitialized memory

`std::mem::uninitialized()` and `zeroed()` for non-zeroable types are **UB and effectively removed** — `uninitialized` produces an invalid value the instant it exists (violates the validity invariant, and `Drop` may run on garbage). Historical; never use it.

`MaybeUninit<T>` is the replacement: it is *always* a valid value (it means "no assumptions"), so holding it uninitialized is fine. You write into it, then call `.assume_init()` *after* actually initializing — and that call is where the obligation lives.

```rust
use std::mem::MaybeUninit;

/// Build a fully-initialized array without a dummy default value.
pub fn make() -> [u32; 4] {
    let mut arr: [MaybeUninit<u32>; 4] = [const { MaybeUninit::uninit() }; 4];
    for (i, slot) in arr.iter_mut().enumerate() {
        slot.write(i as u32);
    }
    // SAFETY: all 4 elements written exactly once; [MaybeUninit<u32>;4] and
    // [u32;4] share layout, so this reinterpret is sound.
    unsafe { std::mem::transmute::<[MaybeUninit<u32>; 4], [u32; 4]>(arr) }
}
```

**Why:** it separates "memory exists" from "value is valid," which is exactly the gap raw allocation, FFI out-params, and partial array init need. **Trade-off:** verbose, and *you* must guarantee every field/element is written before `assume_init` — forget one and you fabricate an invalid value. **When to deviate:** if a cheap `Default` exists and the code is not hot, just initialize normally; `MaybeUninit` is for genuinely-can't-default or measured-hot paths.

**`transmute`** is the last resort — a reinterpret with zero checks beyond size-equality. Prefer, in order: a `From`/`as` cast, `f32::from_bits`/`to_bits`, `bytemuck`/`zerocopy` (checked, safe, derive-based) for POD reinterpretation, pointer casts + `read`/`write`. Reach for `transmute` only when none apply, and never to change lifetimes (use it and you've probably created an unsound lifetime extension). It cannot even transmute between types whose sizes aren't statically equal (as the const-generic array case shows — hence the fixed size above).

## Pin & self-referential types

**The problem Pin solves:** Rust values are freely movable (a move is a `memcpy`), so a struct that holds a pointer *into itself* breaks the instant it moves — the internal pointer now dangles. Async futures generated by `async fn` are exactly this: a borrow across an `.await` becomes a self-reference in the state machine. Pin is the type-system tool that lets such a type exist without unsafe at the *use* site.

**The mechanism (stable):**
- `Pin<P>` (where `P` is a pointer like `&mut T` or `Box<T>`) is a wrapper whose contract is: *the pointee will never be moved again* until it is dropped.
- `Unpin` is an auto-trait meaning "moving me is fine even when pinned" — i.e., Pin is a no-op for me. Almost every type is `Unpin`; the exceptions are self-referential generated futures and types that opt out with `PhantomPinned`.
- For `T: Unpin`, `Pin<&mut T>` gives you `&mut T` freely (`Pin::get_mut`) — Pin buys nothing and costs nothing.
- For `!Unpin` types, you can only get `&mut T` via `unsafe { Pin::get_unchecked_mut }`, and *you* promise not to move out. This is why `Future::poll` takes `Pin<&mut Self>`: once polled, the future may be self-referential and must not move.

**`pin!` macro (stable since 1.68):** pins a value to the current stack frame with no heap allocation — the ergonomic way to get a `Pin<&mut T>` for a local.

```rust
use std::pin::pin;
use std::future::Future;

async fn use_pinned<F: Future<Output = u8>>(fut: F) -> u8 {
    let mut fut = pin!(fut);            // Pin<&mut F>, no Box
    std::future::poll_fn(|cx| fut.as_mut().poll(cx)).await
}
```

**Structural pinning** is the design decision when you build a `!Unpin` type: for each field you choose whether `Pin<&mut Self>` projects to `Pin<&mut Field>` (structural — the field is also pinned) or `&mut Field` (not structural). Getting this wrong is a classic soundness bug; use the `pin-project`/`pin-project-lite` crates rather than hand-writing projections. **When you actually need this:** almost never in application code — you consume `Pin` (via `.await`, or `Box::pin`) far more than you implement it. Hand-rolling a `Future` or an intrusive linked list is the real trigger. See `async.md` for the futures side.

## FFI — crossing the C boundary

The boundary is where Rust's guarantees end and a manual contract begins. Rules that keep it sound:

- **`unsafe extern "C" { ... }`** (edition 2024 requires the `unsafe` on the block) declares foreign functions. Calls are `unsafe` — the signature is an unchecked promise about the other side.
- **`#[unsafe(no_mangle)]`** (edition 2024 wraps `no_mangle`/`export_name`/`link_section` in `unsafe(...)`, because a chosen symbol name can collide and cause UB at link) plus `pub extern "C" fn` exports a Rust fn with the C ABI.
- **`#[repr(C)]`** is required only for *transparent* structs/enums whose fields C reads or writes directly: `repr(Rust)` layout is unspecified and unstable across compiles, so a field-by-field-shared struct without it is UB waiting to happen. It is *not* needed for an opaque handle C only holds and hands back (the pattern PyO3 uses for `#[pyclass]`) — Rust's default layout is fine there and forcing `#[repr(C)]` is cargo-culting. Use `#[repr(transparent)]` for single-field newtypes that must ABI-match their inner type.

```rust
use core::ffi::c_int;

unsafe extern "C" {
    fn abs(input: c_int) -> c_int;
}

#[unsafe(no_mangle)]
pub extern "C" fn add_one(x: c_int) -> c_int {
    // SAFETY: libc `abs` is pure and has no preconditions.
    let a = unsafe { abs(x) };
    a + 1
}
```

**Strings:** C strings are NUL-terminated and unsized; Rust's are length-prefixed and UTF-8. Convert explicitly. `CString` owns a NUL-terminated buffer (construction *fails* on an interior NUL — do not `unwrap` blindly on untrusted input); `CStr` borrows one. Never hand C a `&str`'s pointer and expect NUL termination.

```rust
use std::ffi::{CStr, CString};
use core::ffi::c_char;

pub fn to_c(s: &str) -> Result<CString, std::ffi::NulError> {
    CString::new(s) // Err if `s` has an interior NUL byte
}

/// # Safety
/// `ptr` must point to a valid, NUL-terminated C string that outlives the borrow.
pub unsafe fn from_c<'a>(ptr: *const c_char) -> &'a str {
    // SAFETY: caller upholds validity + NUL termination.
    unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("")
}
```

**Ownership across the boundary** is a manual protocol you must document per-function: who allocates, who frees, with which allocator. Memory allocated by Rust must be freed by Rust (expose a `free_*` fn) and vice versa — mixing allocators is UB. `Box::into_raw`/`from_raw` hand ownership out and take it back; `mem::forget`/`ManuallyDrop` suppress the Rust-side drop when C now owns the value.

**Null and validity:** every incoming pointer is untrusted — check for null (`ptr.is_null()` or `NonNull::new`) and document the alignment/validity precondition in `# Safety`. An incoming `bool`/`char`/enum from C that Rust would consider invalid is instant UB; take an integer and validate.

**Panics must not escape across the boundary** — for a Rust-defined `extern "C" fn` the compiler inserts an abort guard (since 1.81), so an escaping panic is a hard process kill (`panic in a function that cannot unwind` → `thread caused non-unwinding panic. aborting.`), not UB. Aborting the process is still unacceptable at an FFI boundary (genuine UB is reserved for a mismatched unwind ABI — unwinding *into* Rust from a C frame with no unwind tables). Wrap the Rust body of every `extern "C"` export in `catch_unwind`:

```rust
use std::panic::{catch_unwind, AssertUnwindSafe};

#[unsafe(no_mangle)]
pub extern "C" fn ffi_entry(n: i32) -> i32 {
    let out = catch_unwind(AssertUnwindSafe(|| {
        assert!(n >= 0, "n must be non-negative");
        n * 2
    }));
    out.unwrap_or(-1) // turn a panic into an error code, never let it escape
}
```

(`AssertUnwindSafe` is needed only when the closure captures state that could be observed in a broken condition after the catch — e.g. `&mut` data shared with the caller. For plain `Copy` inputs like `n` here it is unnecessary and `catch_unwind(|| { ... })` compiles bare.) Setting `panic = "abort"` in the profile (not the default — Cargo defaults to `unwind` for both `dev` and `release`) turns any panic into an immediate abort, but `catch_unwind` lets you convert to an error code and keep the process alive; choose per use case.

**Callbacks:** a Rust fn pointer passed to C must be `extern "C" fn`, and if C invokes it on another thread you inherit `Send`/`Sync` obligations on any captured state. Prefer passing a plain `extern "C" fn` + a `*mut c_void` user-data pointer over trying to pass a closure.

**Binding generation:** `bindgen` generates Rust `extern` declarations from C headers (build-time, in `build.rs`); `cbindgen` generates a C header from your Rust FFI surface. Use them rather than hand-transcribing signatures — a single wrong type is silent UB. They encode the ABI contract mechanically; the trade-off is a build-time dependency and generated code you should still review at the boundary.

## no_std — programming without the standard library

`#![no_std]` opts out of `std`, linking only `core` (and `alloc` if you add it). **What you lose:** the OS abstraction layer — no `std::fs`, `std::net`, `std::thread`, `std::io`, no default heap allocator, no `println!`, and no default panic handler. Most of `std::collections` (`Vec`, `VecDeque`, `BTreeMap`/`BTreeSet`, `BinaryHeap`, `LinkedList`) lives in `alloc`; `HashMap`/`HashSet` do **not** — they need `RandomState` (OS entropy), so use `hashbrown` on `no_std`. **What you keep in `core`:** everything allocation-free and OS-free — `Option`/`Result`, iterators, slices, `Ordering`, formatting traits, atomics, `Future`.

Layering:
- **`core` only:** truly bare metal / tight embedded. No heap at all; use fixed arrays, `heapless`, stack buffers.
- **`core` + `alloc`:** add `extern crate alloc;` to get `Box`, `Vec`, `String`, `Rc`/`Arc`, `BTreeMap` — but you must register a `#[global_allocator]`. This is the common embedded-with-heap and much of the wasm story.

You must provide what `std` normally would:

```rust
// illustrative — needs a bare-metal target and a real allocator to link
#![no_std]
extern crate alloc;

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {} // real firmware: log + reset; hosted: abort
}
```

**Why it matters as judgment:** embedded (`cortex-m`, RISC-V) and some wasm targets have no OS, so `std` cannot exist; libraries meant for those contexts should be `#![no_std]` with an optional `std` feature (`#![cfg_attr(not(feature = "std"), no_std)]`) so they compose in both worlds. **Trade-off:** every dependency must also be `no_std`, and error handling gets harder (no `std::error::Error` object safety historically — though `core::error::Error` is now stable, 1.81+). **When to deviate:** application code targeting an OS should just use `std`; reach for `no_std` only for libraries that must run bare-metal, or to shrink a wasm binary.

**Hardware registers and shared ISR state:** Rust has no `volatile` keyword, and C's two uses of it split into two distinct mechanisms — conflating them is the classic port bug. Memory-mapped registers use `ptr::read_volatile`/`ptr::write_volatile` in `unsafe`; better, an svd2rust-generated PAC makes a wrong register field or width a *compile* error instead of silent UB. Cross-thread signaling uses atomics (`AtomicBool`, …) — C's `volatile` was never correct there (a data race under C++11+), and Rust makes the atomic requirement compiler-enforced. Write drivers against `embedded-hal` traits (`I2c`, `Spi`) generic over the peripheral so a `Tmp102<I2C: I2c>` runs unchanged on STM32/nRF/ESP32/RP2040 where a vendor-HAL binding needs a rewrite to port, and reach for critical-section tokens (`interrupt::free(|cs| …)`) so shared ISR access is *proven* exclusive rather than guarded by a manual `__disable_irq`.

## Cross-platform portability

`#[cfg(...)]` is compile-time conditional compilation; `cfg!(...)` is a runtime-evaluated boolean of the same predicate. Provide one definition per platform and a fallback so an unlisted target still builds.

```rust
#[cfg(target_os = "linux")]
pub fn tmp_root() -> &'static str { "/tmp" }

#[cfg(target_os = "windows")]
pub fn tmp_root() -> &'static str { r"C:\Temp" }

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
pub fn tmp_root() -> &'static str { "/tmp" }

pub const IS_64: bool = cfg!(target_pointer_width = "64");
pub fn to_wire(x: u32) -> [u8; 4] { x.to_le_bytes() } // explicit endianness
```

Portability rules that bite:
- **Endianness:** never `transmute`/cast integers to bytes and assume order — use `to_le_bytes`/`to_be_bytes`/`from_*_bytes` with an *explicit* choice for any wire/file format.
- **Pointer width:** `usize`/`isize` are 16/32/64-bit depending on target; do not assume `usize == u64`. Serialize sizes as a fixed width.
- **Paths:** use `std::path::Path`/`PathBuf` and never hardcode `/`; separators and case-sensitivity differ.
- **Prefer feature detection over OS detection** where possible (`cfg(target_has_atomic = "64")`, `cfg(target_feature = "avx2")`) — it survives new targets that a hardcoded OS list does not.

`#[cfg]` is checked at compile time only for the *active* target, so untested `cfg` branches rot silently — CI must actually build every target you claim to support (`cargo check --target ...`).

## Verification tooling — because tests don't find UB

UB is invisible to normal testing: a program with UB can pass every test and miscompile after a compiler upgrade. You need tools that *model* the rules:

| Tool (cost) | What it catches | When |
|------|-----------------|------|
| **`cargo careful`** (~1.5×) | Uninitialized-memory/invalid-value/unaligned reads the release build hides, at near-native speed. | Cheap first pass alongside normal tests. |
| **Miri** (`cargo +nightly miri test`, 10–100×) | A MIR *interpreter*, not a linter: executes step-by-step tracking every pointer's provenance and enforcing Stacked/Tree Borrows — aliasing violations, use-after-free/realloc, uninitialized reads, misalignment, invalid values, data races, provenance breaks — on the paths your tests reach. Cannot interpret C (no FFI), needs `-Zmiri-disable-isolation` for real syscalls. | Any crate with `unsafe`. Run per-push in CI. |
| **AddressSanitizer / ThreadSanitizer** (~2×) | Real hardware-level memory errors and data races, including *through* FFI into C where Miri can't follow. | FFI-heavy crates, C interop, native deps. Schedule nightly. |
| **Valgrind** (10–50×) | Whole-binary FFI memory errors + leaks across all machine code — but oblivious to Stacked Borrows. | When the bug may span Rust *and* linked C. Schedule nightly. |

**The judgment:** Miri only checks paths your tests hit, so unsafe code needs *tests that exercise the unsafe path* to be meaningful — writing unsafe without a Miri-run test is shipping unverified proofs. Miri and Valgrind are complementary, not redundant: Miri knows Rust's borrow rules but can't see C; Valgrind checks all machine code but is oblivious to Stacked Borrows. Gate an `unsafe` fast-path behind a Cargo feature with a fully-safe default beside it, so the default build ships safe and CI verifies the unsafe path in isolation (`cargo +nightly miri test --features direct-ipmi`) — a small, opt-in surface, continuously checked. See `testing.md` for the harness side.

## When unsafe is unjustified — push back

Most `unsafe` in application code is premature optimization or an avoidable shortcut. Before accepting it, demand:

1. **A measured reason.** "It's faster" without a benchmark is not a reason — `unsafe` frequently is *not* faster (bounds checks are cheap and often elided; `Vec` indexing in a loop with a known length usually optimizes to the same code as `get_unchecked`). Profile first; the safe version is very often equal.
2. **No safe alternative.** `get_unchecked` → iterate or `chunks`; `MaybeUninit` array → `array::from_fn` or `collect`; manual pointer juggling → `split_at_mut`/`iter_mut`/`Cell`/`RefCell`; POD reinterpret → `bytemuck`/`zerocopy`; global mutable state → `OnceLock`/atomics. The ecosystem has *safe* answers for most classic unsafe use cases.
3. **A proof it's sound.** If the author can't write the `// SAFETY:` comment and defend it against adversarial inputs, the code is not ready regardless of how it performs.

Legitimate unsafe: FFI, implementing a genuinely-new data structure or allocator, hand-rolled `Future`s, a *measured* hot path where the safe form provably can't elide a check, and platform intrinsics. Everything else should be pushed back on. The cost of unsafe is not the keyword — it is that every future maintainer must re-verify the proof, and one wrong edit is UB with no compiler backstop. That maintenance tax is why "can this be safe?" is the first review question.

## Sources

- The Rustonomicon — https://doc.rust-lang.org/nomicon/ (meaning of unsafe, working with unsafe, UB, provenance, FFI, transmute)
- Rust Reference — *Behavior considered undefined* & *Unsafety* — https://doc.rust-lang.org/reference/behavior-considered-undefined.html
- `std` docs: `MaybeUninit`, `ptr` (provenance), `NonNull`, `pin` module, `panic::catch_unwind`, `ffi::{CStr, CString}` — https://doc.rust-lang.org/std/
- The Book, ch. 20 (Advanced Features: unsafe, FFI) & ch. 17 (async/Pin) — https://doc.rust-lang.org/book/
- Rust API Guidelines (naming/soundness of `unsafe fn`, `# Safety` docs) — https://rust-lang.github.io/api-guidelines/
- Edition Guide — 2024 changes (`unsafe extern`, `unsafe(no_mangle)`, `static_mut_refs`, `unsafe_op_in_unsafe_fn`) — https://doc.rust-lang.org/edition-guide/
- The Embedded Rust Book (no_std, panic handlers, targets) — https://docs.rust-embedded.org/book/
- Miri — https://github.com/rust-lang/miri ; Rust Performance Book (when unsafe is/ isn't worth it) — https://nnethercote.github.io/perf-book/
- Microsoft RustTraining — *(C)-Rust FFI: opaque vs transparent structs, ownership handoff, panic hardening* (c-cpp-book & csharp-book & python-book ch. 14) — https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch14-unsafe-rust-and-ffi.md , https://github.com/microsoft/RustTraining/blob/main/python-book/src/ch14-unsafe-rust-and-ffi.md
- Microsoft RustTraining — *volatile → atomics / `read_volatile`* (c-cpp-book ch. 18) & *embedded-hal drivers, svd2rust type-safe registers* (ch. 15-1) — https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch18-cpp-rust-semantic-deep-dives.md , https://github.com/microsoft/RustTraining/blob/main/c-cpp-book/src/ch15-1-embedded-deep-dive.md
- Microsoft RustTraining — *PhantomData: variance & drop-check* (rust-patterns-book ch. 04) — https://github.com/microsoft/RustTraining/blob/main/rust-patterns-book/src/ch04-phantomdata-types-that-carry-no-data.md
- Microsoft RustTraining — *Miri, Valgrind & Sanitizers: verifying unsafe code* (engineering-book ch. 05) — https://github.com/microsoft/RustTraining/blob/main/engineering-book/src/ch05-miri-valgrind-and-sanitizers-verifying-u.md
