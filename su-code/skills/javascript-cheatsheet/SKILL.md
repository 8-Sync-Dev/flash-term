---
name: javascript-cheatsheet
description: Quick reference for JavaScript syntax, arrays, objects, functions, regex, Set/Map, Node.js fs, and debugging. Use when writing or looking up JavaScript/Node.js syntax, setting up pnpm, or when the user asks about JS APIs, array methods, or the javascript-cheatsheet.
---

# JavaScript Cheatsheet

Quick reference from [javascript-cheatsheet](https://github.com/wilfredinni/javascript-cheatsheet). For full code snippets, see [reference.md](reference.md).

## Setup (pnpm & git)

**Install pnpm**
- Linux/macOS: `curl -fsSL https://get.pnpm.io/install.sh | sh -`
- Windows (PowerShell): `iwr https://get.pnpm.io/install.ps1 -useb | iex`

**Clone and install**
```shell
git clone https://github.com/wilfredinni/javascript-cheatsheet.git
cd javascript-cheatsheet
pnpm install
```

**Branch and push**
```shell
git branch fix_bug
git checkout fix_bug
# ... make changes ...
git add .
git commit -m 'succinct explanation of what changed'
git push origin fix_bug
```

## Basics

- **Variables:** `let`, `var` (function-scoped), `const` (block-scoped, no reassign).
- **Comments:** `//` single-line; `/* ... */` multi-line.
- **Operators:** `+ - * / % **`, `+= -= *= /= %= **=`, `++ --`, `== === != !==`, `> < >= <=`, `&& || !`.
- **Console:** `console.log(x)`, `console.error`, `console.warn`, `console.info`, `console.table(arr)`, `console.time('label')` / `console.timeEnd('label')`, `console.group` / `console.groupEnd`, `console.assert(cond, msg)`, `console.trace()`.

## Control flow

- **if/else:** `if (cond) { } else if (cond) { } else { }`
- **Ternary:** `condition ? valueIfTrue : valueIfFalse`
- **switch:** `switch (expr) { case value: ... break; default: ... }`
- **Loops:** `for (let i = 0; i < n; i++)`, `while (cond)`, `do { } while (cond)`; `break`, `continue`.
- **For vs map:** `for` mutates in place; `arr.map(fn)` returns new array, original unchanged.

## Arrays

- **Declare:** `[]`, `new Array()`, `Array.of()`, `Array.from(iterable)`.
- **Length:** `arr.length` (get/set to truncate or extend).
- **Access/assign:** `arr[i]`.
- **Add/remove:** `push(...items)`, `unshift(...items)`, `pop()`, `shift()`, `splice(start, deleteCount, ...items)`.
- **Copy/slice:** `slice(start, end)` (new array); `concat(...arrs)`; spread `[...arr]`.
- **Transform:** `map(fn)`, `filter(fn)`, `reduce((acc, cur) => ..., init)`, `flatMap(fn)`, `flat(depth)`.
- **Search:** `indexOf(val)`, `findIndex(fn)`, `find(fn)`, `includes(val)`.
- **Other:** `join(sep)`, `reverse()`, `sort([compareFn])`, `fill(val, start, end)`.
- **Iterators:** `entries()`, `keys()`, `values()` (use with `for...of`).
- **Check:** `Array.isArray(x)`.

## Objects

- **Literal:** `{ key: value, method() { } }`.
- **Access:** dot `obj.key` or bracket `obj['key']` (for dynamic keys).
- **Add/update/delete:** `obj.key = value`, `delete obj.key`.
- **Property check:** `'key' in obj`, `obj.hasOwnProperty('key')`; `obj.key !== undefined` (can miss explicit `undefined`).
- **Iterate:** `for (let key in obj) { if (obj.hasOwnProperty(key)) ... }`.

## Functions

- **Declaration (hoisted):** `function name(a, b) { return a + b; }`
- **Expression (not hoisted):** `let fn = function(a, b) { return a + b; };`
- **Arrow:** `(a, b) => a + b`, `x => x * 2`, `() => { }`; single param can omit `()`.
- **this:** Arrow functions use lexical `this`; regular functions use call-site `this`.
- **Parameters/arguments:** Pass args at call; use default params `p = default` (not `||` for falsy).

## Strings

- **Methods:** `slice(start, end)`, `split(sep)`, `replace(pattern, replacement)`, `concat(...)`, `trim()`, `trimLeft()`, `trimRight()`, `toUpperCase()`, `toLowerCase()`, `indexOf(sub)`, `includes(sub)`, `charAt(i)`.
- **Template literals:** `` `Hello, ${name}` ``.

## Set & Map

- **Set:** `new Set()`, `new Set([...])`, `add(v)`, `delete(v)`, `has(v)`, `clear()`, `size`; iterate with `for...of` or `forEach`.
- **Set operations:** Union `new Set([...setA, ...setB])`; intersection `new Set([...setA].filter(x => setB.has(x)))`; difference `new Set([...setA].filter(x => !setB.has(x)))`.
- **Map:** `new Map()`, `new Map([['k','v']])`, `set(k,v)`, `get(k)`, `has(k)`, `delete(k)`, `clear()`, `size`; iterate `entries()`, `keys()`, `values()`, or `for (const [k,v] of map)`.

## Regular expressions

- **Anchors:** `^` start, `$` end.
- **Quantifiers:** `*` (0+), `+` (1+), `?` (0 or 1), `{n}`, `{n,m}`, `{n,}`.
- **Groups:** `(abc)` capturing, `(?:abc)` non-capturing.
- **Lookahead:** `(?=...)` positive, `(?!...)` negative.
- **Classes:** `[abc]`, `[^abc]`, `.`, `\d` `\D`, `\w` `\W`, `\s` `\S`.
- **Alternation:** `abc|def`.
- **Usage:** `regex.test(str)`, `str.match(regex)`.

## Error handling

- **Sync:** `try { } catch (err) { } finally { }`; `throw new Error('msg')`.
- **Async:** Prefer `async/await` with try/catch; or `.catch()` on Promises; or callback `(err, data)`.
- **Custom error:** `class MyError extends Error { constructor() { super('msg'); this.name = 'MyError'; } }`.

## Node.js fs (promises)

- **File:** `fs.readFile(path, 'utf8')`, `fs.writeFile(path, content)`, `fs.appendFile(path, content)`, `fs.unlink(path)`, `fs.rename(old, new)`.
- **Dir:** `fs.mkdir(path, { recursive: true })`, `fs.readdir(path)`, `fs.rmdir(path)` (empty only); for recursive delete use custom loop (unlink files, then rmdir).
- **Exists:** `fs.access(path)` in try/catch (reject if missing).
- **Watch:** `fs.watch(path, (eventType, filename) => { })` (platform-dependent; consider `chokidar` for robustness).

## Testing (Jest)

```javascript
const sum = require('./sum');
test('adds 1 + 2 to equal 3', () => {
  expect(sum(1, 2)).toBe(3);
});
```

## Debugging

- **Timing:** `console.time('label')` … `console.timeEnd('label')`.
- **Group:** `console.group('title')` … `console.groupEnd()`.
- **Table:** `console.table(arrayOrObjects)`.
- **Assert:** `console.assert(condition, 'message')` (logs only if false).
- **Stack trace:** `console.trace()`.
- **Breakpoint:** `debugger;` (pauses when devtools open).

## Additional reference

Full snippets for each topic (control flow, array methods, regex, Set/Map, fs, etc.) are in [reference.md](reference.md).
