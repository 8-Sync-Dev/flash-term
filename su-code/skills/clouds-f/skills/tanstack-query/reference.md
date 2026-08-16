# TanStack Query – Full Reference

Source: [TanStack Query docs](https://tanstack.com/query/latest). Covers React, Vue, Solid, Svelte, and Angular.

---

## 1. Installation

**React**
```bash
npm i @tanstack/react-query
npm i @tanstack/react-query-devtools
# pnpm add / yarn add / bun add
```

**Vue** – `@tanstack/vue-query`  
**Solid** – `@tanstack/solid-query`  
**Svelte** – `@tanstack/svelte-query`  
**Angular** – `@tanstack/angular-query-experimental`

**Persistence (React)**  
```bash
npm install @tanstack/query-async-storage-persister @tanstack/react-query-persist-client
# or @tanstack/query-sync-storage-persister for sync (e.g. localStorage)
```

**ESLint**
```bash
npm i -D @tanstack/eslint-plugin-query
```

---

## 2. React – Setup and Provider

**QueryClient + QueryClientProvider**
```tsx
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query'
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'

const queryClient = new QueryClient()

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ReactQueryDevtools />
      <Example />
    </QueryClientProvider>
  )
}
```

**Root render (React 18+)**
```tsx
import ReactDOM from 'react-dom/client'
const root = document.getElementById('root') as HTMLElement
ReactDOM.createRoot(root).render(<App />)
```

**Default options (e.g. staleTime, retry)**
```tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000,
      retry: 2,
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
    },
  },
})
```

**Next.js _app (per-request client)**
```tsx
export default function MyApp({ Component, pageProps }) {
  const [queryClient] = React.useState(
    () =>
      new QueryClient({
        defaultOptions: { queries: { staleTime: 60 * 1000 } },
      }),
  )
  return (
    <QueryClientProvider client={queryClient}>
      <Component {...pageProps} />
    </QueryClientProvider>
  )
}
```

---

## 3. React – useQuery

**Minimal**
```tsx
const { isPending, error, data, isFetching } = useQuery({
  queryKey: ['todos'],
  queryFn: fetchTodoList,
})
```

**With states**
```tsx
if (isPending) return 'Loading...'
if (error) return 'An error has occurred: ' + error.message
return (
  <div>
    <h1>{data.full_name}</h1>
    <p>{data.description}</p>
    <div>{isFetching ? 'Updating...' : ''}</div>
  </div>
)
```

**enabled (conditional / lazy)**
```tsx
useQuery({
  queryKey: [`/posts/${postId}`],
  queryFn: () => fetchPost(postId),
  enabled: !!postId,
})
```

**Disabled query (manual refetch)**
```tsx
const { refetch, data, isFetching } = useQuery({
  queryKey: ['todos'],
  queryFn: fetchTodoList,
  enabled: false,
})
// <button onClick={() => refetch()}>Fetch Todos</button>
```

**Dynamic key (e.g. filter)**
```tsx
const [filter, setFilter] = useState('')
const { data } = useQuery({
  queryKey: ['todos', { filter }],
  queryFn: () => fetchTodos(filter),
  enabled: !!filter,
})
```

---

## 4. React – Default query function

**Define once on QueryClient**
```tsx
const defaultQueryFn = async ({ queryKey }: { queryKey: QueryKey }) => {
  const res = await fetch(`https://jsonplaceholder.typicode.com${queryKey[0]}`)
  return res.json()
}
const queryClient = new QueryClient({
  defaultOptions: { queries: { queryFn: defaultQueryFn } },
})
```

**Use with key only**
```tsx
useQuery({ queryKey: ['/posts'] })
useQuery({ queryKey: [`/posts/${postId}`], enabled: !!postId })
```

---

## 5. React – useMutation and invalidation

**Mutation + invalidate**
```tsx
const queryClient = useQueryClient()
const mutation = useMutation({
  mutationFn: postTodo,
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['todos'] })
  },
})
// mutation.mutate({ id: Date.now(), title: 'Do Laundry' })
```

**Cache update from mutation response**
```tsx
const mutation = useMutation({
  mutationFn: editTodo,
  onSuccess: (data, variables) => {
    queryClient.setQueryData(['todo', { id: variables.id }], data)
    queryClient.invalidateQueries({ queryKey: ['todos'] })
  },
})
```

**Optimistic update (onMutate / onError / onSettled)**
```tsx
const addTodoMutation = useMutation({
  mutationFn: async (newTodo: string) => { /* POST */ },
  onMutate: async (newTodo, context) => {
    await context.client.cancelQueries(todoListOptions)
    const previousTodos = context.client.getQueryData(todoListOptions.queryKey)
    context.client.setQueryData(todoListOptions.queryKey, (old) => ({
      ...old,
      items: [...old.items, { id: crypto.randomUUID(), text: newTodo }],
    }))
    return { previousTodos }
  },
  onError: (err, variables, onMutateResult, context) => {
    if (onMutateResult?.previousTodos)
      context.client.setQueryData(['todos'], onMutateResult.previousTodos)
  },
  onSettled: (data, error, variables, onMutateResult, context) =>
    context.client.invalidateQueries({ queryKey: ['todos'] }),
})
```

---

## 6. React – useInfiniteQuery

**Basic**
```tsx
const {
  data,
  fetchNextPage,
  hasNextPage,
  isFetchingNextPage,
  status,
  error,
} = useInfiniteQuery({
  queryKey: ['projects'],
  queryFn: async ({ pageParam }) => {
    const res = await fetch(`/api/projects?cursor=${pageParam}`)
    return res.json()
  },
  initialPageParam: 0,
  getNextPageParam: (lastPage) => lastPage.nextId ?? undefined,
  getPreviousPageParam: (firstPage) => firstPage.previousId ?? undefined,
  maxPages: 3, // optional
})
```

**Render**
```tsx
{data.pages.map((page) => (
  <React.Fragment key={page.nextId}>
    {page.data.map((project) => <p key={project.id}>{project.name}</p>)}
  </React.Fragment>
))}
<button
  onClick={() => fetchNextPage()}
  disabled={!hasNextPage || isFetchingNextPage}
>
  {isFetchingNextPage ? 'Loading more...' : hasNextPage ? 'Load More' : 'Nothing more'}
</button>
```

---

## 7. React – Prefetching

**On event (e.g. hover)**
```tsx
const queryClient = useQueryClient()
await queryClient.prefetchQuery({
  queryKey: ['character', id],
  queryFn: () => getCharacter(id),
  staleTime: 10_000,
})
```

**Prefetch infinite (multiple pages)**
```tsx
await queryClient.prefetchInfiniteQuery({
  queryKey: ['projects'],
  queryFn: fetchProjects,
  initialPageParam: 0,
  getNextPageParam: (lastPage) => lastPage.nextCursor,
  pages: 3,
})
```

**usePrefetchQuery (Suspense)**
```tsx
usePrefetchQuery({
  queryKey: ['article-comments', id],
  queryFn: getArticleCommentsById,
})
```

---

## 8. React – SSR and hydration

**Prefetch + dehydrate (e.g. getStaticProps)**
```tsx
export async function getStaticProps() {
  const queryClient = new QueryClient()
  await queryClient.prefetchQuery({ queryKey: ['posts'], queryFn: getPosts })
  return { props: { dehydratedState: dehydrate(queryClient) } }
}
```

**HydrationBoundary**
```tsx
import { HydrationBoundary, dehydrate, QueryClient, useQuery } from '@tanstack/react-query'

export default function PostsRoute({ dehydratedState }) {
  return (
    <HydrationBoundary state={dehydratedState}>
      <Posts />
    </HydrationBoundary>
  )
}
function Posts() {
  const { data } = useQuery({ queryKey: ['posts'], queryFn: getPosts })
  // ...
}
```

**Remix loader**
```tsx
export async function loader() {
  const queryClient = new QueryClient()
  await queryClient.prefetchQuery({ queryKey: ['posts'], queryFn: getPosts })
  return json({ dehydratedState: dehydrate(queryClient) })
}
```

**initialData (no full hydration)**
```tsx
export async function getServerSideProps() {
  const posts = await getPosts()
  return { props: { posts } }
}
function Posts(props) {
  const { data } = useQuery({
    queryKey: ['posts'],
    queryFn: getPosts,
    initialData: props.posts,
  })
}
```

---

## 9. React – Persistence

**PersistQueryClientProvider + sync persister**
```tsx
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client'
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister'

const queryClient = new QueryClient({
  defaultOptions: { queries: { gcTime: 1000 * 60 * 60 * 24 } },
})
const persister = createSyncStoragePersister({ storage: window.localStorage })

ReactDOM.createRoot(root).render(
  <PersistQueryClientProvider client={queryClient} persistOptions={{ persister }}>
    <App />
  </PersistQueryClientProvider>,
)
```

**Async persister (e.g. React Native)**
```tsx
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister'
const persister = createAsyncStoragePersister({ storage: AsyncStorage })
```

---

## 10. React – Suspense and errors

**useSuspenseQuery**
```tsx
const { data } = useSuspenseQuery({ queryKey: ['todos'], queryFn: fetchTodos })
```

**QueryErrorResetBoundary + ErrorBoundary**
```tsx
<QueryErrorResetBoundary>
  {({ reset }) => (
    <ErrorBoundary onReset={reset} fallbackRender={({ error, resetErrorBoundary }) => (
      <div>Error! <button onClick={() => resetErrorBoundary()}>Try again</button></div>
    )}>
      <Suspense fallback={<h1>Loading...</h1>}>
        <Project />
      </Suspense>
    </ErrorBoundary>
  )}
</QueryErrorResetBoundary>
```

**useQuery().promise + React.use()**
```tsx
const query = useQuery({ queryKey: ['todos'], queryFn: fetchTodos })
const data = React.use(query.promise)
```

---

## 11. React – Devtools

**Floating**
```tsx
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'
<QueryClientProvider client={queryClient}>
  <App />
  <ReactQueryDevtools initialIsOpen />
</QueryClientProvider>
```

**Embedded panel**
```tsx
import { ReactQueryDevtoolsPanel } from '@tanstack/react-query-devtools'
const [isOpen, setIsOpen] = useState(false)
{isOpen && <ReactQueryDevtoolsPanel onClose={() => setIsOpen(false)} />}
```

**Lazy (production)**
```tsx
const ReactQueryDevtoolsProduction = React.lazy(() =>
  import('@tanstack/react-query-devtools/build/modern/production.js').then((d) => ({ default: d.ReactQueryDevtools })),
)
{showDevtools && <Suspense fallback={null}><ReactQueryDevtoolsProduction /></Suspense>}
```

---

## 12. Vue – Setup and useQuery

**Plugin**
```tsx
import { VueQueryPlugin } from '@tanstack/vue-query'
app.use(VueQueryPlugin)
```

**useQuery**
```vue
<script setup>
import { useQuery } from '@tanstack/vue-query'
const { isPending, isError, data, error } = useQuery({
  queryKey: ['todos'],
  queryFn: getTodos,
})
</script>
<template>
  <span v-if="isPending">Loading...</span>
  <span v-else-if="isError">Error: {{ error.message }}</span>
  <ul v-else><li v-for="todo in data" :key="todo.id">{{ todo.title }}</li></ul>
</template>
```

**Reactivity**: use a getter for keys (e.g. `() => props.userId`), not raw `props.userId`.

**useMutation + invalidation**
```vue
<script setup>
import { useQueryClient, useQuery, useMutation } from '@tanstack/vue-query'
const queryClient = useQueryClient()
const mutation = useMutation({
  mutationFn: postTodo,
  onSuccess: () => queryClient.invalidateQueries({ queryKey: ['todos'] }),
})
</script>
```

**Suspense (useQuery + suspense())**
```vue
<script>
export default defineComponent({
  async setup() {
    const { data, suspense } = useQuery({ queryKey: ['todos'], queryFn: todoFetcher })
    await suspense()
    return { data }
  },
})
</script>
```

**Nuxt 3 plugin (SSR hydration)**
```ts
const queryClient = new QueryClient({ defaultOptions: { queries: { staleTime: 5000 } } })
nuxt.vueApp.use(VueQueryPlugin, { queryClient })
if (import.meta.server) {
  nuxt.hooks.hook('app:rendered', () => { vueQueryState.value = dehydrate(queryClient) })
}
if (import.meta.client) {
  nuxt.hooks.hook('app:created', () => hydrate(queryClient, vueQueryState.value))
}
```

---

## 13. Solid – Setup and useQuery

**Provider**
```tsx
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/solid-query'
import { SolidQueryDevtools } from '@tanstack/solid-query-devtools'

const queryClient = new QueryClient()
export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <SolidQueryDevtools />
      <Example />
    </QueryClientProvider>
  )
}
```

**useQuery: pass options as a function; don’t destructure outside reactive scope**
```tsx
const query = useQuery(() => ({
  queryKey: ['todos'],
  queryFn: fetchTodos,
}))
// In JSX: query.isPending, query.data, query.error
return (
  <Switch>
    <Match when={query.isPending}>Loading...</Match>
    <Match when={query.isError}>Error: {query.error.message}</Match>
    <Match when={query.isSuccess}><For each={query.data}>{(todo) => <div>{todo.title}</div>}</For></Match>
  </Switch>
)
```

**Signals in options**
```tsx
const [todo, setTodo] = createSignal(0)
const todoDetailsQuery = useQuery(() => ({
  queryKey: ['todo', todo()],
  queryFn: fetchTodo,
  enabled: todo() > 0,
}))
```

**Suspense**
```tsx
<Suspense fallback="Loading...">
  <For each={query.data}>{(todo) => <div>{todo.title}</div>}</For>
</Suspense>
```

**Default query function**
```tsx
const defaultQueryFn: QueryFunction<unknown> = async ({ queryKey }) => {
  const res = await fetch(`https://jsonplaceholder.typicode.com${queryKey[0]}`)
  return res.json()
}
const queryClient = new QueryClient({
  defaultOptions: { queries: { queryFn: defaultQueryFn } },
})
```

---

## 14. Svelte – Setup and createQuery

**Provider**
```svelte
<script lang="ts">
  import { QueryClientProvider, QueryClient } from '@tanstack/svelte-query'
  import { SvelteQueryDevtools } from '@tanstack/svelte-query-devtools'
  import Simple from './lib/Simple.svelte'
  const queryClient = new QueryClient()
</script>
<QueryClientProvider client={queryClient}>
  <main><Simple /></main>
  <SvelteQueryDevtools />
</QueryClientProvider>
```

**createQuery**
```svelte
<script lang="ts">
  import { createQuery } from '@tanstack/svelte-query'
  const query = createQuery(() => ({
    queryKey: ['todos'],
    queryFn: () => fetchTodos(),
  }))
</script>
{#if query.isPending}<p>Loading...</p>
{:else if query.isError}<p>Error: {query.error.message}</p>
{:else if query.isSuccess}
  {#each query.data as todo}<p>{todo.title}</p>{/each}
{/if}
```

**Dev server**
```bash
npm run dev
npm run dev -- --open
```

**SvelteKit layout (QueryClient per request)**
```ts
// +layout.ts
import { browser } from '$app/environment'
import { QueryClient } from '@tanstack/svelte-query'
export async function load() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { enabled: browser } },
  })
  return { queryClient }
}
```

**Page load prefetch**
```ts
// +page.ts
export async function load({ parent, fetch }) {
  const { queryClient } = await parent()
  await queryClient.prefetchQuery({
    queryKey: ['posts'],
    queryFn: async () => (await fetch('/api/posts')).json(),
  })
}
```

---

## 15. Angular – Setup and injectQuery

**Standalone**
```ts
import { provideHttpClient } from '@angular/common/http'
import { provideTanStackQuery, QueryClient } from '@tanstack/angular-query-experimental'

bootstrapApplication(AppComponent, {
  providers: [provideHttpClient(), provideTanStackQuery(new QueryClient())],
})
```

**NgModule**
```ts
@NgModule({
  providers: [provideTanStackQuery(new QueryClient())],
  // ...
})
export class AppModule {}
```

**injectQuery**
```ts
query = injectQuery(() => ({
  queryKey: ['todos'],
  queryFn: () => this.todoService.getTodos(),
}))
```

**injectMutation + invalidation**
```ts
queryClient = inject(QueryClient)
mutation = injectMutation(() => ({
  mutationFn: (todo: Todo) => this.todoService.addTodo(todo),
  onSuccess: () => this.queryClient.invalidateQueries({ queryKey: ['todos'] }),
}))
```

**Devtools**
```ts
import { withDevtools } from '@tanstack/angular-query-experimental/devtools'
providers: [provideTanStackQuery(new QueryClient(), withDevtools())],
```

---

## 16. Query options (shared)

- **queryKey** – Array, unique; include all variables (e.g. `['todos', { filter }]`).
- **queryFn** – `(context) => Promise<TData>`; context has `queryKey`, `signal` (AbortSignal).
- **enabled** – Boolean or (query) => boolean; when false, query does not run automatically.
- **staleTime** – ms until data is stale (default 0).
- **gcTime** – ms before inactive cache is garbage-collected (default 5 min).
- **retry** – number, boolean, or (failureCount, error) => boolean.
- **retryDelay** – (attemptIndex) => number (e.g. exponential: `Math.min(1000 * 2 ** attemptIndex, 30000)`).
- **initialData** – initial cache value (considered stale unless staleTime set).
- **placeholderData** – show while pending (not cached); e.g. `keepPreviousData` for pagination.
- **select** – (data) => TSelected; subscribe to derived value.
- **refetchInterval** – ms or false.
- **refetchOnWindowFocus**, **refetchOnMount**, **refetchOnReconnect** – boolean or 'stale'.

---

## 17. Invalidation and cache

**Invalidate by prefix**
```tsx
queryClient.invalidateQueries() // all
queryClient.invalidateQueries({ queryKey: ['todos'] })
queryClient.invalidateQueries({ queryKey: ['todos', { type: 'done' }] }) // exact match
```

**Read/update cache**
```tsx
const data = queryClient.getQueryData(['posts'])
queryClient.setQueryData(['todo', id], newTodo)
```

**Prefetch**
```tsx
await queryClient.prefetchQuery({ queryKey: ['posts'], queryFn: getPosts })
```

---

## 18. useQueries, useIsFetching, useMutationState

**useQueries**
```tsx
const results = useQueries({
  queries: ids.map((id) => ({
    queryKey: ['post', id],
    queryFn: () => fetchPost(id),
    staleTime: Infinity,
  })),
})
```

**useIsFetching**
```tsx
const isFetching = useIsFetching()
const isFetchingPosts = useIsFetching({ queryKey: ['posts'] })
```

**useMutationState**
```tsx
const variables = useMutationState({
  filters: { status: 'pending' },
  select: (mutation) => mutation.state.variables,
})
```

---

## 19. Query options helper (queryOptions)

**Type-safe options**
```tsx
import { queryOptions } from '@tanstack/react-query'
function groupOptions(id: number) {
  return queryOptions({
    queryKey: ['groups', id],
    queryFn: () => fetchGroups(id),
    staleTime: 5 * 1000,
  })
}
useQuery(groupOptions(1))
queryClient.prefetchQuery(groupOptions(23))
queryClient.setQueryData(groupOptions(42).queryKey, newGroups)
```

---

## 20. ESLint and migration

**Flat config**
```js
import pluginQuery from '@tanstack/eslint-plugin-query'
export default [...pluginQuery.configs['flat/recommended']]
```

**Legacy**
```json
{ "extends": ["plugin:@tanstack/query/recommended"] }
```

**React Query v4**
```bash
npm uninstall react-query
npm install @tanstack/react-query @tanstack/react-query-devtools
```

**v5**: useQuery/useMutation use single options object; `cacheTime` → `gcTime`; `isLoading` vs `isPending` / `isInitialLoading` for disabled queries.

---

## 21. Testing and React Native

**React**: wrap with `QueryClientProvider` and a fresh `QueryClient`; use `@testing-library/react` (React 18+ has `renderHook`).

**Angular**: `TestBed.runInInjectionContext(() => injectQuery(...))`, then `TestBed.tick()`, `await appRef.whenStable()`.

**React Native**: use `focusManager.setFocused(status === 'active')` with AppState; optionally `PersistQueryClientProvider` + `createAsyncStoragePersister({ storage: AsyncStorage })`.
