---
name: clean-code-javascript
description: Reference for writing clean JavaScript following SOLID, naming, functions, async, and testing practices from clean-code-javascript. Use when writing or refactoring JavaScript/TypeScript, reviewing code, or when the user asks about clean code, DIP, SRP, naming, or async patterns.
---

# Clean Code JavaScript

Quick reference for patterns from [clean-code-javascript](https://github.com/ryanmcdermott/clean-code-javascript). Prefer good patterns; avoid bad ones.

## SOLID

### DIP – Inject dependencies
**Good:** High-level module receives the requester; easy to swap (e.g. HTTP vs WS).
```javascript
class InventoryTracker {
  constructor(items, requester) {
    this.items = items;
    this.requester = requester;
  }
  requestItems() {
    this.items.forEach(item => this.requester.requestItem(item));
  }
}
const tracker = new InventoryTracker(["apples"], new InventoryRequesterV2());
```
**Bad:** High-level module instantiates low-level module → tight coupling.
```javascript
constructor(items) {
  this.requester = new InventoryRequester(); // BAD
}
```

### SRP – One reason to change
**Good:** Separate auth into `UserAuth`; `UserSettings` only handles settings and uses it.
**Bad:** `UserSettings` with both `changeSettings` and `verifyCredentials`.

### OCP – Extend without modifying
**Good:** Adapters with common `request`; `HttpRequester` takes adapter, no `if (adapter.name === ...)`.
**Bad:** `HttpRequester.fetch` with `if (ajaxAdapter) ... else if (nodeAdapter) ...`.

### LSP – Substitutability
**Good:** `Rectangle` and `Square` extend `Shape`, each with `getArea()`; use `shape.getArea()`.
**Bad:** `Square extends Rectangle` and overrides `setWidth`/`setHeight` so area breaks when used as rectangle.

### ISP – Minimal interface
**Good:** Settings with optional nested `options`; clients pass only what they need.
**Bad:** Fat settings object requiring unused options (e.g. `animationModule` for simple traversal).

## Functions

- **Arguments:** Prefer object destructuring over many positional params; use default parameters (`name = "Foo"`) not `name || "Foo"` (falsy).
- **Single responsibility:** One level of abstraction per function; extract helpers (e.g. `tokenize`, `parse`).
- **No flag parameters:** Split into two functions (e.g. `createFile` and `createTempFile`) instead of `createFile(name, temp)`.
- **Return new data:** `return [...cart, { item, date: Date.now() }]` instead of `cart.push(...)`.
- **Pure when possible:** Don’t mutate globals or input; return new values.

## Naming & style

- **Meaningful names:** `currentDate` not `yyyymmdstr`; `location` not `l` in callbacks.
- **One term per concept:** Use `getUser()` everywhere, not mix of `getUserInfo`, `getClientData`, `getCustomerRecord`.
- **Searchable constants:** `MILLISECONDS_PER_DAY` not `86400000`.
- **Consistent capitalization:** e.g. constants UPPER_SNAKE; classes PascalCase; functions camelCase.
- **No redundant context:** Inside `Car`, use `make`, `model`, `color` not `carMake`, `carModel`, `carColor`.

## Async

- Prefer **async/await** over raw Promises over callbacks.
- In **catch**: do something useful (e.g. `console.error`, notify user, report to service), not only `console.log`.
- Same for **.catch()** on Promises.

## Testing

- **One concept per test:** Separate `it` blocks for 30-day months, leap year, non-leap year.
- **Bad:** One `it("handles date boundaries")` with multiple assertions for different scenarios.

## Classes & OOP

- **ES6 class:** Use `class`/`extends`/`super`; avoid ES5 prototype boilerplate.
- **Composition over inheritance for “has-a”:** e.g. `Employee` has `EmployeeTaxData`, not `EmployeeTaxData extends Employee`.
- **Method chaining:** Return `this` from setters so `car.setColor("pink").save()` works.
- **Private data:** Use getters/setters or closure (e.g. `makeEmployee(name)` returning `{ getName() { return name; } }`); avoid public `balance` with no accessors.
- **Extend built-ins via class:** `class SuperArray extends Array { diff(...) {} }` instead of `Array.prototype.diff = ...`.

## Conditionals & polymorphism

- **Positive conditionals:** `if (isDOMNodePresent(node))` not `if (!isDOMNodeNotPresent(node))`.
- **Encapsulate conditions:** `if (shouldShowSpinner(fsm, listNode))` instead of raw `fsm.state === "fetching" && isEmpty(listNode)`.
- **Polymorphism over switch/type checks:** Subclasses override one method (e.g. `getCruisingAltitude`) instead of one method with `switch (this.type)` or `instanceof` branches.

## Comments & dead code

- Comment only **non-obvious / complex logic**; avoid journal comments; remove commented-out code (use version control).
- **Remove dead code**; don’t leave unused functions “just in case”.

## Other

- **Default object props:** `Object.assign({ title: "Foo", body: "Bar", cancellable: true }, config)` instead of manual `config.x = config.x || default`.
- **Don’t over-optimize:** e.g. avoid caching `list.length` in loops for “readability” unless profiling shows need.
- **Avoid positional markers:** No `//// Scope Model` comment blocks; use structure and names.

## Additional reference

For full good/bad code pairs (DIP, testing, ES5/ES6, getters/setters, async, LSP/ISP, etc.), see [reference.md](reference.md).
