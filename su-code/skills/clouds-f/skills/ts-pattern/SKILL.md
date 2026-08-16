---
name: ts-pattern
description: Reference for TS-Pattern exhaustive pattern matching in TypeScript—match(), .with(), .exhaustive(), .otherwise(), P patterns (select, union, intersection, when, optional, instanceOf), isMatching(), P.infer. Use when writing or refactoring conditional logic, handling discriminated unions, validating unknown data, or when the user mentions ts-pattern, pattern matching, exhaustive matching, or isMatching.
---

# TS-Pattern Reference

TS-Pattern is an exhaustive pattern matching library for TypeScript (~2kB). It replaces complex conditionals with declarative pattern-based branching and provides compile-time exhaustiveness checking.

## When to Use

- **Discriminated unions**: API responses, state machines, event payloads.
- **Validation**: Unknown data from APIs, forms, or config—use `isMatching` + `P.infer`.
- **Exhaustive branching**: Replace long if/else or switch with `match().exhaustive()` so missing cases are caught at compile time.
- **Type narrowing**: Handlers receive narrowed types from the matched pattern.

## Core API

### match(value) and .with() / .exhaustive() / .otherwise()

```typescript
import { match, P } from 'ts-pattern';

type Response =
  | { type: 'success'; data: string }
  | { type: 'error'; error: Error }
  | { type: 'loading' };

const message = match(response)
  .with({ type: 'success' }, (res) => `Data: ${res.data}`)
  .with({ type: 'error' }, (res) => `Error: ${res.error.message}`)
  .with({ type: 'loading' }, () => 'Loading...')
  .exhaustive();  // compile-time check: all cases covered

// Default fallback (no exhaustiveness guarantee)
const short = match(response)
  .with({ type: 'success' }, () => 'OK')
  .otherwise(() => 'Not OK');
```

- Chain `.with(pattern, handler)`; multiple patterns in one `.with()` match any of them.
- End with `.exhaustive()` for type-safe exhaustive matching or `.otherwise(handler)` for default.
- Optional guard: `.with(pattern, guardFn, handler)` — handler runs only when guard returns true.

### .returnType\<T\>()

Enforce a single return type for all branches:

```typescript
match(input)
  .returnType<string>()
  .with({ status: 'active' }, () => 'Active')
  .with({ status: 'inactive' }, () => 'Inactive')
  .exhaustive();
```

## Pattern Builders (P)

### Wildcards

- `P._` / `P.any`: match anything.
- `P.nullish`: null or undefined.
- `P.nonNullable`: exclude null/undefined.

### P.select() – extract values into handler

- Anonymous: `P.select()` → single value as first handler argument.
- Named: `P.select('key')` → object of selections as argument.

```typescript
.with({ profile: { city: P.select() } }, (city) => city)
.with(
  { name: P.select('userName'), profile: { age: P.select('userAge') } },
  ({ userName, userAge }) => `${userName} is ${userAge}`
)
```

### P.union() and P.intersection()

- `P.union(...patterns)`: match if any pattern matches.
- `P.intersection(...patterns)`: match only if all match.

```typescript
.with({ type: P.union('square', 'rectangle') }, () => 'Has corners')
.with(
  P.intersection(P.instanceOf(Tagged), { value: P.number }),
  (item) => `Tagged ${item.tag} with value ${item.value}`
)
```

### P.not(pattern)

Matches when the value does **not** match the pattern.

### P.when(predicate)

Matches when predicate returns true. Use a type guard to narrow types in the handler.

```typescript
.with(P.when((x): x is string => typeof x === 'string'), (s) => s.toUpperCase())
.with({ price: P.when((p) => p > 100) }, () => 'Premium')
```

### P.optional(subpattern)

Property is undefined or matches subpattern.

### P.instanceOf(Constructor)

Matches class instances (e.g. `NetworkError`, `ValidationError`).

### P.string / P.number – chainable predicates

- **P.string**: `.startsWith()`, `.endsWith()`, `.includes()`, `.regex()`, `.minLength()`, `.maxLength()`, `.length()`.
- **P.number**: `.between()`, `.lt()`, `.gt()`, `.lte()`, `.gte()`, `.int()`, `.finite()`, `.positive()`, `.negative()`.

```typescript
.with(P.string.startsWith('SELECT'), () => 'Read query')
.with(P.number.between(80, 89), () => 'B')
```

### P.array(subpattern)

Matches arrays where elements match; supports tuple patterns with spread.

```typescript
.with(P.array({ id: P.number, name: P.select() }), (names) => names.join(', '))
.with([P.select('first'), P.select('second'), ...P.array()], ({ first, second }) => first + second)
```

### P.map(keyPattern, valuePattern) / P.set(subpattern)

Match Map/Set structures.

### P.record(keyPattern?, valuePattern)

Match record/dictionary objects; single-arg form assumes string keys.

## isMatching(pattern) and P.infer

- **isMatching(pattern)**: returns a type guard; use to validate unknown data.
- **isMatching(pattern, value)**: one-shot check.
- **P.infer\<typeof pattern\>**: derive TypeScript type from a pattern (keep runtime and types in sync).

```typescript
const UserPattern = {
  id: P.number,
  name: P.string,
  email: P.string.includes('@'),
  role: P.union('admin', 'user', 'guest'),
  metadata: P.optional({ lastLogin: P.string })
} as const;

type User = P.infer<typeof UserPattern>;
const isUser = isMatching(UserPattern);

if (isUser(data)) {
  // data is User
  return data;
}
```

## Integration Tips

1. Use **strict TypeScript** so exhaustiveness and inference are reliable.
2. Define reusable patterns with `P.infer` for types and `isMatching` for validation.
3. Prefer `match().exhaustive()` for discriminated unions so new variants cause compile errors.
4. Combine with state machines, API response types, and form/config validation.

## Additional Reference

For detailed examples (P.record, P.map/P.set, optional/instanceOf, string/number chains, guards), see [reference.md](reference.md).
