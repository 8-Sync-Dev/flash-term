# React Reference (react.dev)

Organized reference for React 18/19 from the official docs. Source: https://18.react.dev

---

## 1. Installation and setup

**Install React and React DOM**

```bash
npm install react react-dom
yarn add react react-dom
```

**React 19**

```bash
npm install --save-exact react@^19.0.0 react-dom@^19.0.0
yarn add --exact react@^19.0.0 react-dom@^19.0.0
```

**React DevTools (standalone)**

```bash
yarn global add react-devtools
npm install -g react-devtools
react-devtools
```

Connect app to standalone devtools: add in `<head>`:

```html
<script src="http://localhost:8097"></script>
```

**TypeScript types**

```bash
npm install --save-dev @types/react @types/react-dom
# React 19:
npm install --save-exact @types/react@^19.0.0 @types/react-dom@^19.0.0
```

**Scaffolding**

```bash
npm create vite@latest my-app -- --template react-ts
npx create-next-app@latest
npx create-react-router@latest
npx create-expo-app@latest
npx create-rsbuild --template react
```

---

## 2. Components and JSX

**Basic component**

```jsx
function Greeting({ name }) {
  return <h1>Hello, {name}</h1>;
}

export default function App() {
  return <Greeting name="world" />;
}
```

**JSX rules**

- Close all tags (e.g. `<br />`).
- Multiple siblings need one parent: `<div>` or `<>...</>` (Fragment).
- Use `className` instead of `class`; `style` is an object.
- Embed expressions with `{}`.

**Composition**

```jsx
<PageLayout>
  <NavigationHeader />
  <Sidebar />
  <PageContent>
    <TableOfContents />
    <DocumentationText />
  </PageContent>
</PageLayout>
```

**Conditional rendering**

```jsx
{isLoggedIn ? <AdminPanel /> : <LoginForm />}
{isLoggedIn && <AdminPanel />}
```

**Lists and keys**

```jsx
const listItems = products.map(product =>
  <li key={product.id}>{product.title}</li>
);
return <ul>{listItems}</ul>;
```

Use a stable, unique `key` (e.g. `id`). Don’t use array index as key if list can reorder.

**Pure components**

- Same props/state → same output.
- No mutating props or external state during render.
- No side effects during render; use event handlers or `useEffect`.

---

## 3. State (useState, useReducer)

**useState**

```javascript
const [count, setCount] = useState(0);
const [text, setText] = useState('');
```

- Updater when next state depends on previous: `setCount(c => c + 1)`.
- Lazy initial state: `useState(() => createInitialTodos())`.
- Resetting state: give component a new `key` (e.g. `key={version}`).

**useReducer**

```javascript
const [state, dispatch] = useReducer(reducer, initialArg, init?);

function reducer(state, action) {
  switch (action.type) {
    case 'added':
      return [...state, { id: action.id, text: action.text }];
    case 'deleted':
      return state.filter(t => t.id !== action.id);
    default:
      throw new Error('Unknown action');
  }
}
```

Reducer must be pure (no mutation; return new state).

---

## 4. Effects (useEffect, useLayoutEffect)

**useEffect**

```javascript
useEffect(() => {
  const connection = createConnection(serverUrl, roomId);
  connection.connect();
  return () => connection.disconnect();
}, [serverUrl, roomId]);
```

- Dependencies: list every reactive value used inside the effect.
- Empty `[]`: run once on mount; cleanup on unmount.
- No dependency array: runs after every commit (usually avoid).

**useLayoutEffect**

Runs after DOM updates, before paint. Use for measuring DOM or synchronous DOM updates to avoid flicker.

```javascript
useLayoutEffect(() => {
  const { height } = ref.current.getBoundingClientRect();
  setTooltipHeight(height);
}, []);
```

**Patterns**

- Don’t put one-off user actions (e.g. “buy”) in effects; use event handlers.
- Use an `ignore` flag in async effects to avoid updating state after unmount or when deps change.

---

## 5. Refs (useRef, forwardRef, useImperativeHandle)

**useRef**

```javascript
const inputRef = useRef(null);
<input ref={inputRef} />
// In handler or effect:
inputRef.current.focus();
```

- Don’t read or write `ref.current` during render.
- Use refs for DOM nodes or values that shouldn’t trigger re-renders.

**forwardRef**

```javascript
const MyInput = forwardRef(function MyInput(props, ref) {
  return <input {...props} ref={ref} />;
});
```

**useImperativeHandle**

Expose a custom handle to the parent instead of the DOM node:

```javascript
useImperativeHandle(ref, () => ({
  focus() { inputRef.current.focus(); },
  scrollIntoView() { inputRef.current.scrollIntoView(); }
}), []);
```

---

## 6. Context and use

**createContext and provide**

```javascript
const ThemeContext = createContext('light');

// React 19: <ThemeContext value="dark">
<ThemeContext.Provider value={theme}>
  <Page />
</ThemeContext.Provider>
```

**Consume**

```javascript
const theme = useContext(ThemeContext);
// or with use (React 19, can be conditional):
const theme = use(ThemeContext);
```

**use(resource)**

- `use(promise)`: suspends until resolved; use with Suspense.
- `use(context)`: read context; can be called conditionally (unlike `useContext`).

---

## 7. Memoization (useMemo, useCallback, memo)

**useMemo**

```javascript
const visibleTodos = useMemo(
  () => filterTodos(todos, tab),
  [todos, tab]
);
```

**useCallback**

```javascript
const handleSubmit = useCallback((orderDetails) => {
  post('/product/' + productId + '/buy', { referrer, orderDetails });
}, [productId, referrer]);
```

**memo**

```javascript
const Chart = memo(function Chart({ dataPoints }) { ... });
```

Use when re-renders are expensive and props are stable. React Compiler can automate many of these optimizations.

---

## 8. Transitions (useTransition, startTransition)

**useTransition**

```javascript
const [isPending, startTransition] = useTransition();

function selectTab(nextTab) {
  startTransition(() => {
    setTab(nextTab);
  });
}
```

**startTransition (standalone)**

```javascript
import { startTransition } from 'react';
startTransition(() => setSearchResults(input));
```

Mark non-urgent state updates so React can keep the UI responsive (e.g. keep input responsive while results update).

---

## 9. Forms and useActionState (React 19)

**useActionState**

```javascript
const [state, formAction, isPending] = useActionState(async (prevState, formData) => {
  const error = await updateName(formData.get('name'));
  if (error) return error;
  return null;
}, null);

<form action={formAction}>
  <input name="name" />
  <button type="submit" disabled={isPending}>Update</button>
  {state && <p>{state}</p>}
</form>
```

**useFormStatus** (in a child of the form)

```javascript
const { pending, data, method, action } = useFormStatus();
```

---

## 10. Suspense and lazy

**lazy**

```javascript
const MarkdownPreview = lazy(() => import('./MarkdownPreview.js'));

<Suspense fallback={<Loading />}>
  <MarkdownPreview markdown={markdown} />
</Suspense>
```

**use with Promises**

```javascript
function Message({ messagePromise }) {
  const message = use(messagePromise);
  return <p>{message}</p>;
}

<Suspense fallback={<p>Loading...</p>}>
  <Message messagePromise={fetchMessage()} />
</Suspense>
```

---

## 11. React DOM client (createRoot, hydrateRoot)

**createRoot**

```javascript
import { createRoot } from 'react-dom/client';

const root = createRoot(document.getElementById('root'));
root.render(<App />);
```

- First `render` clears the container.
- Options (e.g. `onUncaughtError`, `onRecoverableError`, `identifierPrefix`) go on `createRoot(container, options)`.

**hydrateRoot**

For server-rendered or pre-rendered HTML:

```javascript
import { hydrateRoot } from 'react-dom/client';

hydrateRoot(document.getElementById('root'), <App />);
```

**Unmount**

```javascript
root.unmount();
```

**Migration from legacy API**

- Replace `ReactDOM.render(<App />, node)` with `createRoot(node).render(<App />)`.
- Replace `ReactDOM.hydrate(...)` with `hydrateRoot(...)`.
- Replace `unmountComponentAtNode(node)` with `root.unmount()`.

---

## 12. React DOM server

**renderToReadableStream** (streaming)

```javascript
import { renderToReadableStream } from 'react-dom/server';

const stream = await renderToReadableStream(<App />, {
  bootstrapScripts: ['/main.js'],
  onError(error) { console.error(error); }
});
return new Response(stream, { headers: { 'content-type': 'text/html' } });
```

**prerender** (static / SSG)

```javascript
import { prerender } from 'react-dom/static';

const { prelude, postponed } = await prerender(<App />, {
  bootstrapScripts: ['/main.js'],
  signal: controller.signal
});
```

**resume** (continue after postpone)

```javascript
import { resume } from 'react-dom/server';
const stream = await resume(reactNode, postponedState, options);
```

**Node streams**

- `renderToPipeableStream` (Node).
- `prerenderToNodeStream`, `resumeAndPrerenderToNodeStream` from `react-dom/static`.

---

## 13. Resource preloading (React 19)

From `react-dom`:

- **prefetchDNS**(href)
- **preconnect**(href)
- **preload**(href, { as: 'font' | 'script' | 'style' | ... })
- **preinit**(href, { as: 'script' | 'style', precedence? })

Call during render or in event handlers (e.g. before navigation) so the browser can fetch resources earlier.

---

## 14. Portals (createPortal)

```javascript
import { createPortal } from 'react-dom';

createPortal(
  <Modal><p>Rendered into document.body</p></Modal>,
  document.body
);
```

Use for modals, tooltips, or any UI that should render outside the parent DOM hierarchy. React still treats it as part of the component tree (context, events).

---

## 15. React Compiler

**Install**

```bash
npm install -D babel-plugin-react-compiler@latest eslint-plugin-react-hooks@latest
```

**Babel**

```javascript
module.exports = {
  plugins: [
    'babel-plugin-react-compiler', // must run first
    // ...
  ]
};
```

**Vite (@vitejs/plugin-react)**

```javascript
react({
  babel: {
    plugins: ['babel-plugin-react-compiler']
  }
})
```

**Directives**

- `"use memo"`: opt this component/hook into compilation.
- `"use no memo"`: opt out (e.g. temporary workaround).

**Modes**

- `compilationMode: 'annotation'` – only compile with `"use memo"`.
- `compilationMode: 'infer'` – infer components/hooks; use `"use no memo"` to exclude.
- `compilationMode: 'all'` – compile all.

---

## 16. View Transitions and Activity (React 19)

**ViewTransition**

```jsx
import { ViewTransition } from 'react';

<ViewTransition key={url}>
  {url === '/' ? <Home /> : <Details />}
</ViewTransition>
```

Use `default`, `enter`, `exit` (and related) for custom animation classes.

**Activity** (preserve state when hiding)

```jsx
<Activity mode={url === '/' ? 'visible' : 'hidden'}>
  <Home />
</Activity>
```

---

## 17. Rules of Hooks

- Call hooks only at the **top level** of a component or custom hook (not inside conditions, loops, or nested functions).
- Call hooks only from **React function components** or **custom hooks** (not from class components or plain functions).
- `use` can be used in conditionals; other hooks cannot.

---

## 18. Styling and DOM components

- **className**: for CSS classes.
- **style**: object, e.g. `style={{ color: 'red', fontSize: 14 }}`.
- **dangerouslySetInnerHTML**: `dangerouslySetInnerHTML={{ __html: sanitized }}` (sanitize to avoid XSS).

Built-in components (e.g. `<div>`, `<input>`, `<form>`) support standard DOM props and events. Use React’s `on*` handlers (e.g. `onClick`, `onChange`).

---

## 19. Error boundaries and StrictMode

**Error boundary** (class component)

Catches errors in tree and shows fallback; wrap risky subtrees.

**StrictMode**

```jsx
import { StrictMode } from 'react';

<StrictMode>
  <App />
</StrictMode>
```

Development-only: double-invokes some logic to surface side effects. Use for root during development.

---

## 20. Migration (React 18 → 19)

- **Root**: `createRoot` / `hydrateRoot` (already required in 18).
- **act**: import from `'react'` instead of `'react-dom/test-utils'`.
- **ref as prop**: function components can take `ref` as a normal prop in React 19 (no `forwardRef` needed for simple cases).
- **Context**: `<Context value={...}>` instead of `<Context.Provider value={...}>`.
- **useActionState**: new hook for form actions and pending state.
- **Removed/deprecated**: `propTypes`, `defaultProps` (use TypeScript or default params), string refs, `ReactDOM.render`, `findDOMNode`, legacy context, etc.

Codemods: `npx codemod@latest react/19/migration-recipe`, `react/19/replace-reactdom-render`, `react/19/replace-act-import`.
