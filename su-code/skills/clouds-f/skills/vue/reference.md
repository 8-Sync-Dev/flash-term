# Vue.js Reference (vuejs.org)

Organized reference for Vue 3.5 from the official documentation. Source: https://vuejs.org

---

## 1. Creating a Vue Application

Initialize and mount a Vue 3 app; register globals before `mount()`.

```js
import { createApp } from 'vue'
import App from './App.vue'

const app = createApp(App)

app.component('GlobalButton', { template: '<button><slot /></button>' })
app.directive('focus', {
  mounted(el) { el.focus() }
})
app.provide('apiUrl', 'https://api.example.com')
app.config.errorHandler = (err) => console.error('App error:', err)

app.mount('#app')
```

---

## 2. Reactive State: ref() and reactive()

**ref()** – primitives or any value; access via `.value` in script; auto-unwraps in template.

```vue
<script setup>
import { ref } from 'vue'

const count = ref(0)
const message = ref('Hello Vue!')

function increment() {
  count.value++
}

function reset() {
  count.value = 0
  message.value = 'Reset!'
}
</script>

<template>
  <p>{{ message }}</p>
  <p>Count: {{ count }}</p>
  <button @click="increment">Increment</button>
  <button @click="reset">Reset</button>
</template>
```

**reactive()** – deeply reactive object; nested properties are reactive. Use **toRefs()** to destructure while keeping reactivity.

```js
import { reactive, toRefs } from 'vue'

const state = reactive({
  user: { name: 'John', preferences: { theme: 'dark' } },
  loading: false,
  error: null
})

function updateTheme(newTheme) {
  state.user.preferences.theme = newTheme
}

const { user, loading } = toRefs(state)
```

---

## 3. Computed Properties

Cached derived state; re-evaluates only when dependencies change.

```vue
<script setup>
import { ref, computed } from 'vue'

const items = ref([...])

const totalItems = computed(() =>
  items.value.reduce((sum, item) => sum + item.quantity, 0)
)

const subtotal = computed(() =>
  items.value.reduce((sum, item) => sum + item.price * item.quantity, 0)
)

// Writable computed
const discountCode = ref('')
const finalTotal = computed({
  get() {
    return discountCode.value === 'SAVE10' ? total.value * 0.9 : total.value
  },
  set(value) { /* custom setter */ }
})
</script>
```

---

## 4. Component Props

Define with types, defaults, and optional validator.

```vue
<script setup>
const props = defineProps({
  title: { type: String, required: true },
  content: { type: String, default: '' },
  author: { type: Object, default: () => ({ name: 'Anonymous' }) },
  tags: { type: Array, default: () => [] },
  likes: { type: Number, default: 0, validator: (value) => value >= 0 },
  published: { type: Boolean, default: false }
})

const isPopular = computed(() => props.likes > 100)
</script>

<template>
  <article>
    <h2>{{ title }}</h2>
    <p>By {{ author.name }}</p>
    <span v-for="tag in tags" :key="tag">{{ tag }}</span>
    <p>Likes: {{ likes }} <span v-if="isPopular">🔥</span></p>
  </article>
</template>
```

Parent: `<BlogPost :title="t" :content="c" :author="{ name: 'Jane' }" :tags="['vue']" :likes="150" />`

---

## 5. Component Events (defineEmits)

Emit with optional validation.

```vue
<script setup>
const emit = defineEmits({
  change: null,
  update: (value) => typeof value === 'string',
  submit: (value, isValid) => typeof value === 'string' && typeof isValid === 'boolean'
})

const inputValue = ref('')

function handleInput(e) {
  inputValue.value = e.target.value
  emit('update', inputValue.value)
}

function handleSubmit() {
  emit('submit', inputValue.value, inputValue.value.length > 0)
}
</script>

<template>
  <input :value="inputValue" @input="handleInput" />
  <button @click="handleSubmit">Submit</button>
</template>
```

Parent: `<CustomInput @update="handleUpdate" @submit="handleSubmit" />`

---

## 6. v-model on Components

Default: prop `modelValue`, event `update:modelValue`. Use computed getter/setter.

```vue
<script setup>
const props = defineProps({
  modelValue: { type: Number, default: 0 },
  max: { type: Number, default: 5 }
})
const emit = defineEmits(['update:modelValue'])

const rating = computed({
  get: () => props.modelValue,
  set: (value) => emit('update:modelValue', value)
})

function setRating(value) { rating.value = value }
</script>

<template>
  <div class="rating">
    <button v-for="n in max" :key="n" :class="{ active: n <= rating }" @click="setRating(n)">⭐</button>
  </div>
</template>
```

Parent: `<RatingInput v-model="userRating" :max="5" />`

**Multiple v-models:** `v-model:first-name="user.first"` and `v-model:last-name="user.last"` — props `firstName`/`lastName`, events `update:firstName`/`update:lastName`.

---

## 7. Watchers

**watch** – explicit source(s) and options.

```js
watch(searchQuery, async (newQuery) => {
  loading.value = true
  const res = await fetch(`/api/search?q=${newQuery}`)
  searchResults.value = await res.json()
  loading.value = false
}, { immediate: false })

watch([firstName, lastName], ([newFirst, newLast]) => { ... })

watch(() => user.value.age, (newAge) => { ... })

watch(state, (newState) => { ... }, { deep: true })
```

**watchEffect** – auto-tracks reactive dependencies; optional cleanup.

```js
watchEffect(() => {
  document.title = `Search: ${searchQuery.value}`
})

const stop = watchEffect((onCleanup) => {
  const timer = setTimeout(() => { ... }, 1000)
  onCleanup(() => clearTimeout(timer))
})
// stop() to stop
```

---

## 8. Lifecycle Hooks

Use in Composition API / `<script setup>`:

```js
import {
  onBeforeMount, onMounted,
  onBeforeUpdate, onUpdated,
  onBeforeUnmount, onUnmounted,
  onErrorCaptured
} from 'vue'

onBeforeMount(() => { ... })
onMounted(async () => {
  const res = await fetch('/api/data')
  data.value = await res.json()
  intervalId = setInterval(() => { ... }, 5000)
})
onBeforeUpdate(() => { ... })
onUpdated(() => { ... })
onBeforeUnmount(() => { ... })
onUnmounted(() => {
  if (intervalId) clearInterval(intervalId)
  window.removeEventListener('resize', handleResize)
})
onErrorCaptured((err, instance, info) => {
  console.error(err, info)
  return false  // prevent propagation
})
```

---

## 9. Provide / Inject

**Ancestor:**

```js
import { provide, ref, readonly } from 'vue'

const theme = ref('dark')
const user = ref({ id: 1, name: 'John', role: 'admin' })

provide('theme', readonly(theme))
provide('user', {
  data: readonly(user),
  updateName: (newName) => { user.value.name = newName },
  logout: () => { user.value = null }
})
provide('apiUrl', 'https://api.example.com')
```

**Descendant:**

```js
import { inject } from 'vue'

const theme = inject('theme', 'light')
const userContext = inject('user')
const apiUrl = inject('apiUrl')

userContext.updateName('Jane')
userContext.logout()
```

**Symbol keys** (e.g. for plugins): `const userKey = Symbol('user')` then `provide(userKey, user)` and `inject(userKey)`.

---

## 10. Composables

Reusable stateful logic; return refs/computed and optionally functions.

```js
// composables/useFetch.js
import { ref, watch, toValue } from 'vue'

export function useFetch(url) {
  const data = ref(null)
  const error = ref(null)
  const loading = ref(false)

  async function fetchData() {
    loading.value = true
    error.value = null
    try {
      const response = await fetch(toValue(url))
      data.value = await response.json()
    } catch (err) {
      error.value = err
    } finally {
      loading.value = false
    }
  }

  watch(() => toValue(url), fetchData, { immediate: true })
  return { data, error, loading, refetch: fetchData }
}
```

```js
// composables/useMouse.js
export function useMouse() {
  const x = ref(0)
  const y = ref(0)
  function update(e) { x.value = e.pageX; y.value = e.pageY }
  onMounted(() => window.addEventListener('mousemove', update))
  onUnmounted(() => window.removeEventListener('mousemove', update))
  return { x, y }
}
```

```js
// composables/useLocalStorage.js
export function useLocalStorage(key, defaultValue) {
  const value = ref(JSON.parse(localStorage.getItem(key)) ?? defaultValue)
  watch(value, (v) => localStorage.setItem(key, JSON.stringify(v)), { deep: true })
  function remove() { localStorage.removeItem(key); value.value = defaultValue }
  return { value, remove }
}
```

In component: `const { data, loading, refetch } = useFetch(computed(() => `/api/users/${userId.value}`))`.

---

## 11. Template Directives (summary)

| Directive | Usage |
|-----------|--------|
| `v-if` / `v-else-if` / `v-else` | Conditional render |
| `v-show` | Toggle visibility (display) |
| `v-for` | `(item, index) in items` with `:key="item.id"`; object: `(value, key, index) in obj` |
| `v-on` / `@` | `@click`, `@click.prevent`, `@keyup.enter`, `@[eventName]` |
| `v-bind` / `:` | `:id="id"`, `:class="{ active }"`, `:style="{}"`, `v-bind="objectOfAttrs"` |
| `v-model` | Two-way; `.number`, `.trim`; on components: `modelValue` + `update:modelValue` |
| `v-slot` / `#` | `#default`, `#footer="{ message }"` |
| `v-once` | Render once |
| `v-pre` | Skip compilation |
| `v-cloak` | Hide until compiled (use with CSS) |
| `v-memo` | `v-memo="[a, b]"` — skip re-render unless a or b change |
| `v-html` | Raw HTML (sanitize to avoid XSS) |
| `v-text` | Set textContent |

---

## 12. Async Components

**Basic:**

```js
const AsyncModal = defineAsyncComponent(() => import('./components/Modal.vue'))
```

**With loading/error and timeout:**

```js
const AsyncChart = defineAsyncComponent({
  loader: () => import('./components/Chart.vue'),
  loadingComponent: { template: '<div>Loading chart...</div>' },
  errorComponent: { template: '<div>Failed to load chart</div>' },
  delay: 200,
  timeout: 3000
})
```

**Suspense** for components with top-level `await` in setup:

```vue
<Suspense>
  <template #default>
    <AsyncDashboard />
  </template>
  <template #fallback>
    <div>Loading dashboard...</div>
  </template>
</Suspense>
```

AsyncDashboard.vue can use `const data = await fetch(...).then(r => r.json())` at top level in `<script setup>`.

---

## 13. Build and Development (docs repo)

**Requirements:** Node.js 18+ (22 recommended for production), pnpm 9.12.1.

```bash
corepack enable
pnpm install
pnpm run dev       # http://localhost:5173
pnpm run build     # .vitepress/dist
pnpm run preview
pnpm run type      # vue-tsc
```

**Deployment (example):**

- Netlify: `NODE_VERSION = "22"`, `publish = ".vitepress/dist"`, `command = "pnpm run build"`.
- Vercel: cache headers for `/assets/(.*)`, rewrites for SPA.

---

## 14. Integration Overview

- **Composition API** with `<script setup>` is the primary style; Options API remains supported.
- **TypeScript:** vue-tsc, InjectionKey for typed provide/inject.
- **Routing:** Vue Router; **State:** Pinia.
- **SSR, testing, production, performance, accessibility, security** are covered in the full docs.
- **VitePress** is used for the docs site (VitePress 1.6.4, Vite, Vue 3.5.12); config includes nav, sidebar, Algolia search, markdown and Vite plugins.
