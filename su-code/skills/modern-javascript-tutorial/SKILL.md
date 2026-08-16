---
name: modern-javascript-tutorial
description: Reference for Modern JavaScript (javascript.info): variables, data types, arrays, objects, classes, promises, async/await, Fetch API, DOM manipulation, event handling, localStorage, regular expressions. Use when writing vanilla JavaScript, DOM code, or when the user mentions JavaScript fundamentals, fetch, events, or javascript.info.
---

# Modern JavaScript Tutorial

Reference for JavaScript from fundamentals to advanced topics (javascript.info). Use for vanilla JS, browser APIs, and web development patterns.

## Variables and Data Types

- Prefer `let` and `const`; avoid `var`.
- Template literals: `` `Hello, ${name}` ``.
- Type conversion: `Number(str)`, `JSON.stringify(obj)`, `JSON.parse(str)`.

## Array Methods

- `arr.map(x => ...)` — transform each element.
- `arr.filter(x => ...)` — select matching elements.
- `arr.reduce((acc, curr) => ..., initial)` — accumulate.
- `arr.slice(start, end)` — copy; `arr.splice(index, deleteCount, ...items)` — mutate.
- `arr.find(predicate)` — first match.

## Object Basics

- Access: `obj.key` or `obj["key"]`.
- Iterate: `for (let key in obj)`, `Object.keys(obj)`, `Object.values(obj)`, `Object.entries(obj)`.
- Check: `"key" in obj`.

## Classes

- `class Name { constructor(...) { } method() { } }`.
- Inheritance: `class Child extends Parent { constructor(...) { super(...); } }`.
- Getters/setters: `get prop() { }`, `set prop(value) { }`.

## Promises and Async/Await

- Create: `new Promise((resolve, reject) => { ... })`.
- Chain: `.then(...).catch(...)`.
- Async: `async function f() { const x = await promise; return x; }`.
- Parallel: `await Promise.all(promises)`.

## Fetch API

- GET: `const res = await fetch(url); const data = await res.json();` — check `res.ok` or `res.status`.
- POST: `fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })`.
- Timeout: use `AbortController` with `signal` and `setTimeout(() => controller.abort(), ms)`.

## DOM Manipulation

- Create: `document.createElement('tag')`, set `className`, `innerHTML`, `textContent`.
- Append: `parent.append(node)`.
- Select: `getElementById`, `querySelector(selector)`, `querySelectorAll(selector)`.
- Modify: `element.style.*`, `classList.add/remove/toggle`, `setAttribute`/`getAttribute`.

## Event Handling

- Add: `element.addEventListener('click', handler)`.
- Prevent default: `event.preventDefault()`.
- Delegation: attach to parent, use `event.target` and `event.target.closest(selector)`.
- Remove: `removeEventListener` with same function reference.

## Local Storage

- `localStorage.setItem(key, value)` — values are strings; use `JSON.stringify` for objects.
- `localStorage.getItem(key)`, `localStorage.removeItem(key)`, `localStorage.clear()`.
- `sessionStorage` — same API; cleared when tab closes.

## Regular Expressions

- Create: `/pattern/` or `new RegExp('pattern', 'gi')`.
- Test: `regex.test(str)`.
- Match: `str.match(regex)`; replace: `str.replace(regex, replacement)`.
- Groups: `(...)` in pattern; capture in match `[1]`, `[2]`, etc.

## Additional Resources

- For full code examples and longer snippets, see [reference.md](reference.md).
