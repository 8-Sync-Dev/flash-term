# TS-Pattern – Detailed Examples

Use this file when you need full code examples for a specific pattern. The main skill is in [SKILL.md](SKILL.md).

---

## match() – Basic and multiple patterns

```typescript
import { match, P } from 'ts-pattern';

type Response =
  | { type: 'success'; data: string }
  | { type: 'error'; error: Error }
  | { type: 'loading' };

const response: Response = { type: 'success', data: 'Hello!' };

const message = match(response)
  .with({ type: 'success' }, (res) => `Data: ${res.data}`)
  .with({ type: 'error' }, (res) => `Error: ${res.error.message}`)
  .with({ type: 'loading' }, () => 'Loading...')
  .exhaustive();

const shortMessage = match(response)
  .with({ type: 'success' }, () => 'OK')
  .otherwise(() => 'Not OK');

// Multiple patterns in one .with()
const status = match(response)
  .with({ type: 'success' }, { type: 'loading' }, () => 'In progress or done')
  .with({ type: 'error' }, () => 'Failed')
  .exhaustive();
```

---

## .with() with guard function

```typescript
const guardedResult = match({ value: 42 })
  .with(
    { value: P.number },
    (obj) => obj.value > 10,
    (obj) => `Large number: ${obj.value}`
  )
  .with({ value: P.number }, (obj) => `Small number: ${obj.value}`)
  .exhaustive();
```

---

## P.select() – anonymous and named

```typescript
type User = { name: string; profile: { age: number; city: string } };
const user: User = { name: 'Alice', profile: { age: 30, city: 'NYC' } };

const city = match(user)
  .with({ profile: { city: P.select() } }, (selectedCity) => selectedCity)
  .exhaustive();

const info = match(user)
  .with(
    { name: P.select('userName'), profile: { age: P.select('userAge') } },
    ({ userName, userAge }) => `${userName} is ${userAge} years old`
  )
  .exhaustive();

// Select with sub-pattern
const adultCity = match(user)
  .with(
    { profile: { age: P.select(P.number.gte(18)), city: P.select('loc') } },
    (age, { loc }) => `Adult (${age}) in ${loc}`
  )
  .otherwise(() => 'Minor');
```

---

## P.union / P.intersection

```typescript
type Shape =
  | { type: 'circle'; radius: number }
  | { type: 'square'; side: number }
  | { type: 'rectangle'; width: number; height: number };

const isRound = match(shape)
  .with({ type: P.union('square', 'rectangle') }, () => 'Has corners')
  .with({ type: 'circle' }, () => 'Round')
  .exhaustive();

class Tagged {
  constructor(public tag: string) {}
}
const obj = Object.assign(new Tagged('important'), { value: 42 });
const result = match<unknown>(obj)
  .with(
    P.intersection(P.instanceOf(Tagged), { value: P.number }),
    (item) => `Tagged ${item.tag} with value ${item.value}`
  )
  .otherwise(() => 'Unknown');
```

---

## P.not() and P.when()

```typescript
const result = match(status)
  .with(P.not('error'), (s) => `Not an error: ${s}`)
  .with('error', () => 'Error occurred')
  .exhaustive();

const discount = match(item)
  .with(
    { price: P.when((p) => p > 100) },
    () => 'Premium discount'
  )
  .with(
    { price: P.when((p) => p > 20), quantity: P.when((q) => q >= 3) },
    () => 'Bulk discount'
  )
  .otherwise(() => 'No discount');

const isString = (x: unknown): x is string => typeof x === 'string';
const narrowed = match(mixed)
  .with(P.when(isString), (s) => s.toUpperCase())
  .with(P.number, (n) => n.toFixed(2))
  .exhaustive();
```

---

## P.array() – variadic tuples

```typescript
const names = match(items)
  .with(P.array({ id: P.number, name: P.select() }), (selectedNames) => selectedNames.join(', '))
  .otherwise(() => 'No items');

const firstTwo = match(numbers)
  .with([P.select('first'), P.select('second'), ...P.array()], ({ first, second }) => first + second)
  .otherwise(() => 0);

const lastArg = match(commands)
  .with([...P.array(), P.select()], (last) => `Last: ${last}`)
  .otherwise(() => 'Empty');
```

---

## P.string and P.number chains

```typescript
const queryType = match(query)
  .with(P.string.startsWith('SELECT'), () => 'Read query')
  .with(P.string.startsWith('INSERT'), () => 'Insert query')
  .otherwise(() => 'Unknown query');

const validation = match(email)
  .with(
    P.string.includes('@').includes('.').minLength(5),
    () => 'Valid email format'
  )
  .otherwise(() => 'Invalid email');

const grade = match(score)
  .with(P.number.between(90, 100), () => 'A')
  .with(P.number.between(80, 89), () => 'B')
  .with(P.number.lt(60), () => 'F')
  .otherwise(() => 'Invalid');

const category = match(amount)
  .with(P.number.positive().gte(1000), () => 'Large credit')
  .with(P.number.negative().lte(-1000), () => 'Large debit')
  .with(0, () => 'Zero balance')
  .exhaustive();
```

---

## P.optional()

```typescript
type Config = { host: string; port?: number; ssl?: { cert: string; key: string } };
const connectionString = match(config)
  .with(
    { host: P.select('h'), port: P.optional(P.number).select('p'), ssl: P.optional({ cert: P.string }) },
    ({ h, p }) => (p ? `${h}:${p}` : h)
  )
  .exhaustive();
```

---

## P.instanceOf()

```typescript
class NetworkError extends Error {
  constructor(public statusCode: number, message: string) { super(message); }
}
const errorMessage = match(error)
  .with(P.instanceOf(NetworkError), (e) => `HTTP ${e.statusCode}: ${e.message}`)
  .with(P.instanceOf(ValidationError), (e) => `Invalid ${e.field}: ${e.message}`)
  .with(P.instanceOf(Error), (e) => `Error: ${e.message}`)
  .exhaustive();
```

---

## isMatching() and P.infer – validation pattern

```typescript
const UserPattern = {
  id: P.number,
  name: P.string,
  email: P.string.includes('@'),
  role: P.union('admin', 'user', 'guest'),
  metadata: P.optional({
    lastLogin: P.string,
    preferences: P.record(P.string)
  })
} as const;

type User = P.infer<typeof UserPattern>;
const isUser = isMatching(UserPattern);

async function fetchUser(id: number): Promise<User | null> {
  const data: unknown = await response.json();
  if (isUser(data)) return data;
  return null;
}

if (isMatching(UserPattern, maybeUser)) {
  console.log(maybeUser.email);
}
```

---

## P.map() and P.set()

```typescript
const hasAdmin = match(userRoles)
  .with(P.map(P.string, 'admin'), () => 'Has admin users')
  .with(P.map(P.string, P.union('admin', 'user')), () => 'Mixed roles')
  .otherwise(() => 'No users');

const category = match(tags)
  .with(P.set(P.string.startsWith('type')), () => 'All TypeScript related')
  .with(P.set(P.string), () => 'String tags')
  .otherwise(() => 'Unknown tags');
```

---

## P.record()

```typescript
const result = match(scores)
  .with(P.record(P.string, P.number.gte(90)), () => 'All high scores')
  .with(P.record(P.string, P.number.gte(80)), () => 'All passing scores')
  .otherwise(() => 'Mixed scores');

const keys = match(data)
  .with(P.record(P.string.select(), P.number), (keys) => keys)
  .otherwise(() => []);
```

---

## Wildcards – P._, P.nullish, P.nonNullable

```typescript
const simplified = match(response)
  .with({ status: 'success', data: P._ }, () => 'Got data')
  .with({ status: P._ }, () => 'Other status')
  .exhaustive();

const greeting = match(user)
  .with({ name: P.nullish }, () => 'Hello, Guest')
  .with({ name: P.string }, (u) => `Hello, ${u.name}`)
  .exhaustive();

const processed = match(maybeValue)
  .with(P.nonNullable, (v) => `Value: ${v}`)
  .with(P.nullish, () => 'No value')
  .exhaustive();
```
