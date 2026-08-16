---
name: react
description: Reference for React 18/19 from react.dev—components, hooks, JSX, DOM APIs, server rendering, and React Compiler. Use when building React apps, using useState/useEffect/useRef, creating components, configuring Vite/Next.js, or when the user mentions React, JSX, hooks, createRoot, or react-dom.
---

# React Reference (react.dev)

Reference material from [React documentation](https://18.react.dev). Use this skill when writing React components, hooks, JSX, or integrating React with build tools and server rendering.

## When to Use

- **Components**: functional components, props, JSX syntax, composition, conditional rendering, lists and `key`.
- **State and effects**: `useState`, `useEffect`, `useRef`, `useReducer`, `useCallback`, `useMemo`, dependency arrays, cleanup.
- **DOM and client**: `createRoot`, `root.render`, `hydrateRoot`, `createPortal`, resource preloading (`preload`, `preinit`).
- **Server**: `renderToReadableStream`, `prerender`, `resume`, Server Components, `use` with Promises.
- **Tooling**: React DevTools, React Compiler (Babel/Vite), ESLint React Hooks, Vite/Next.js/React Router setup.
- **Patterns**: lifting state up, context, forms and `useActionState`, transitions (`useTransition`, `startTransition`), Suspense, View Transitions.

## Quick Reference

### Install and run

```bash
npm install react react-dom
npm install -g react-devtools
react-devtools
```

Connect standalone devtools in HTML: `<script src="http://localhost:8097"></script>` (in `<head>`).

### Root and render

```javascript
import { createRoot } from 'react-dom/client';

const root = createRoot(document.getElementById('root'));
root.render(<App />);
```

Use `hydrateRoot(document.getElementById('root'), <App />)` for server-rendered markup.

### Basic component and state

```jsx
import { useState } from 'react';

function Greeting({ name }) {
  return <h1>Hello, {name}</h1>;
}

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <div>
      <Greeting name="world" />
      <button onClick={() => setCount(c => c + 1)}>Clicked {count} times</button>
    </div>
  );
}
```

### Effect with cleanup

```javascript
useEffect(() => {
  const connection = createConnection(serverUrl, roomId);
  connection.connect();
  return () => connection.disconnect();
}, [serverUrl, roomId]);
```

### Rules to remember

- **Pure components**: No mutating props/state during render; no side effects in render. Use event handlers or `useEffect` for side effects.
- **Rules of hooks**: Call hooks only at the top level of components or custom hooks (no conditionals, loops, or nested functions).
- **Keys**: Use a stable, unique `key` for list items (e.g. `key={item.id}`).
- **Refs**: Don’t read or write `ref.current` during render; use in effects or event handlers.

### Common hooks

| Hook | Purpose |
|------|--------|
| `useState(initial)` | State; returns `[value, setValue]`. Use updater `setValue(v => ...)` when next state depends on previous. |
| `useEffect(fn, deps)` | Run side effect after render; return cleanup. Empty `[]` = mount/unmount only. |
| `useRef(initial)` | Mutable ref (e.g. DOM node); does not trigger re-render. |
| `useCallback(fn, deps)` | Memoized callback. |
| `useMemo(() => value, deps)` | Memoized value. |
| `useReducer(reducer, initial)` | State via reducer; returns `[state, dispatch]`. |
| `useTransition()` | Returns `[isPending, startTransition]` for non-urgent updates. |
| `use( promise )` | Read Promise or Context (can be conditional). Use with Suspense for async. |

### Forms and actions (React 19)

```jsx
import { useActionState } from 'react';

const [state, formAction, isPending] = useActionState(async (prevState, formData) => {
  // server action
  return nextState;
}, null);

<form action={formAction}>...</form>
```

### Context

```javascript
const ThemeContext = createContext('light');

// Provide (React 19: <ThemeContext value="dark">)
<ThemeContext.Provider value={theme}>...</ThemeContext.Provider>

// Consume
const theme = use(ThemeContext);  // or useContext(ThemeContext)
```

### Suspense and lazy

```jsx
import { Suspense, lazy } from 'react';

const MarkdownPreview = lazy(() => import('./MarkdownPreview.js'));

<Suspense fallback={<Loading />}>
  <MarkdownPreview markdown={markdown} />
</Suspense>
```

### React Compiler (optional)

- Install: `npm install -D babel-plugin-react-compiler@latest eslint-plugin-react-hooks@latest`
- Babel: add `'babel-plugin-react-compiler'` first in `plugins`.
- Vite: use `@vitejs/plugin-react` with `babel: { plugins: ['babel-plugin-react-compiler'] }`.
- Directives: `"use memo"` to opt in, `"use no memo"` to opt out (e.g. for debugging).

### Project scaffolding

```bash
npm create vite@latest my-app -- --template react-ts
npx create-next-app@latest
npx create-react-router@latest
npx create-expo-app@latest
```

## Full Reference

For detailed examples, API options, migration notes (React 18/19), server APIs (`prerender`, `resume`, `renderToReadableStream`), resource preloading (`preload`, `preinit`, `prefetchDNS`, `preconnect`), View Transitions, Activity, and React Compiler configuration, see **[reference.md](reference.md)**.
