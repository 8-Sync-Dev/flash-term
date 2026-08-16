---
name: tanstack-query
description: Reference for TanStack Query (React Query, Vue Query, Solid Query, Svelte Query, Angular Query)—QueryClient, QueryClientProvider, useQuery, useMutation, invalidation, devtools, prefetching, SSR, persistence. Use when building data-fetching with TanStack Query, setting up useQuery/useMutation/injectQuery, or when the user mentions TanStack Query, React Query, Vue Query, queryKey, queryFn, QueryClientProvider.
---

# TanStack Query Reference

Reference material from [TanStack Query docs](https://tanstack.com/query/latest). Use this skill when wiring up TanStack Query for React, Vue, Solid, Svelte, or Angular—queries, mutations, caching, devtools, and SSR.

## When to Use

- **Setup**: QueryClient, QueryClientProvider, framework-specific install and provider (React, Vue, Solid, Svelte, Angular).
- **Queries**: useQuery / createQuery / injectQuery, queryKey, queryFn, loading/error/success states, enabled, default query function.
- **Mutations**: useMutation / injectMutation, mutationFn, onSuccess/onError/onSettled, invalidateQueries, cache updates.
- **Advanced**: useInfiniteQuery, prefetching, SSR/hydration (HydrationBoundary, dehydrate), persistence, Suspense.
- **Tooling**: React/Vue/Solid/Svelte/Angular Query Devtools, ESLint plugin, TypeScript.

## Quick Reference

### Install (React)

```bash
npm i @tanstack/react-query
npm i @tanstack/react-query-devtools
```

Vue: `@tanstack/vue-query`. Solid: `@tanstack/solid-query`. Svelte: `@tanstack/svelte-query`. Angular: `@tanstack/angular-query-experimental`.

### React – Provider and root

```tsx
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query'
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'

const queryClient = new QueryClient()

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Example />
      <ReactQueryDevtools />
    </QueryClientProvider>
  )
}
```

### Basic query (React)

```tsx
const { isPending, error, data, isFetching } = useQuery({
  queryKey: ['todos'],
  queryFn: getTodos,
})

if (isPending) return 'Loading...'
if (error) return 'Error: ' + error.message
return <ul>{data?.map(todo => <li key={todo.id}>{todo.title}</li>)}</ul>
```

### Mutation and invalidation (React)

```tsx
const queryClient = useQueryClient()
const mutation = useMutation({
  mutationFn: postTodo,
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['todos'] })
  },
})
mutation.mutate({ id: Date.now(), title: 'Do Laundry' })
```

### Vue – Plugin and useQuery

```ts
import { VueQueryPlugin } from '@tanstack/vue-query'
app.use(VueQueryPlugin)
```

```vue
<script setup>
import { useQuery } from '@tanstack/vue-query'
const { isPending, isError, data, error } = useQuery({
  queryKey: ['todos'],
  queryFn: getTodos,
})
</script>
```

### Solid – useQuery (options in getter)

```tsx
const query = useQuery(() => ({
  queryKey: ['todos'],
  queryFn: fetchTodos,
}))
// Use query.isPending, query.data, query.error in JSX (no destructuring outside reactive scope)
```

### Svelte – createQuery

```svelte
<script>
  import { createQuery } from '@tanstack/svelte-query'
  const query = createQuery(() => ({
    queryKey: ['todos'],
    queryFn: () => fetchTodos(),
  }))
</script>
{#if query.isPending}...{:else if query.isError}...{:else if query.isSuccess}...
```

### Svelte dev server

```bash
npm run dev
# or open in browser
npm run dev -- --open
```

### Angular – provideTanStackQuery and injectQuery

```ts
import { provideTanStackQuery, QueryClient } from '@tanstack/angular-query-experimental'
bootstrapApplication(AppComponent, {
  providers: [provideHttpClient(), provideTanStackQuery(new QueryClient())],
})
```

```ts
query = injectQuery(() => ({
  queryKey: ['todos'],
  queryFn: () => this.todoService.getTodos(),
}))
```

### Default query function (shared queryFn from key)

```ts
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      queryFn: async ({ queryKey }) => {
        const res = await fetch(`https://jsonplaceholder.typicode.com${queryKey[0]}`)
        return res.json()
      },
    },
  },
})
// Then: useQuery({ queryKey: ['/posts'] }) or useQuery({ queryKey: [`/posts/${postId}`], enabled: !!postId })
```

### Infinite query (React)

```tsx
const {
  data, fetchNextPage, hasNextPage, isFetchingNextPage, status, error,
} = useInfiniteQuery({
  queryKey: ['projects'],
  queryFn: async ({ pageParam }) => {
    const res = await fetch(`/api/projects?cursor=${pageParam}`)
    return res.json()
  },
  initialPageParam: 0,
  getNextPageParam: (lastPage) => lastPage.nextId ?? undefined,
})
```

### Prefetch (e.g. on hover)

```tsx
const queryClient = useQueryClient()
queryClient.prefetchQuery({
  queryKey: ['character', id],
  queryFn: () => getCharacter(id),
  staleTime: 10_000,
})
```

### SSR (Next.js) – dehydrate / HydrationBoundary

```tsx
// getStaticProps or getServerSideProps
const queryClient = new QueryClient()
await queryClient.prefetchQuery({ queryKey: ['posts'], queryFn: getPosts })
return { props: { dehydratedState: dehydrate(queryClient) } }

// Page
export default function PostsRoute({ dehydratedState }) {
  return (
    <HydrationBoundary state={dehydratedState}>
      <Posts />
    </HydrationBoundary>
  )
}
```

### Persist client (e.g. localStorage)

```tsx
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client'
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister'

const persister = createSyncStoragePersister({ storage: window.localStorage })
<PersistQueryClientProvider client={queryClient} persistOptions={{ persister }}>
  <App />
</PersistQueryClientProvider>
```

### ESLint (flat config)

```js
import pluginQuery from '@tanstack/eslint-plugin-query'
export default [...pluginQuery.configs['flat/recommended']]
```

### Rules to remember

- **queryKey**: Array, unique per request shape; include variables (e.g. `['todos', { filter }]`).
- **Solid**: Pass options as a function to useQuery; don’t destructure query result outside reactive scope.
- **Vue**: Use getters/computed for reactive query keys (e.g. `() => props.userId`), not raw props.
- **Invalidation**: Use `queryClient.invalidateQueries({ queryKey: ['todos'] })` after mutations to refetch.

## Full Reference

For framework-specific setup, useQueries, useMutationState, useIsFetching, optimistic updates, query options (staleTime, gcTime, retry, retryDelay), persistence, SSR patterns (Remix, Nuxt, SvelteKit), and migration notes, see **[reference.md](reference.md)**.
