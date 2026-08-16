---
name: vue
description: Reference for Vue.js 3 (Composition API, Options API) from official docs—createApp, ref/reactive, computed, watchers, components, props, emit, v-model, provide/inject, composables, template directives. Use when building Vue apps, writing SFCs, or when the user mentions Vue 3, Composition API, script setup, ref(), reactive(), or Vue Router/Pinia.
---

# Vue.js Reference (vuejs.org)

Reference material from the [Vue.js 3 documentation](https://vuejs.org). Use this skill when writing Vue 3 applications, Single File Components (SFCs), or integrating Vue with build tools.

## When to Use

- **Application setup**: `createApp`, `app.mount`, global components/directives, `app.provide`, `app.config`.
- **Reactivity**: `ref()`, `reactive()`, `computed()`, `watch()`, `watchEffect()`, `toRefs()`.
- **Components**: props (with validation), `defineEmits`, events, slots.
- **Two-way binding**: `v-model`, custom `v-model` and `v-model:propName`.
- **Lifecycle**: `onMounted`, `onUnmounted`, `onBeforeMount`, etc.
- **Dependency injection**: `provide()` / `inject()`.
- **Composables**: reusable logic with refs and lifecycle.
- **Template**: `v-if`, `v-for`, `v-show`, `@click`, `:class`, `v-bind`, `v-memo`, etc.
- **Async**: `defineAsyncComponent`, `Suspense`, top-level `await` in setup.

## Quick Reference

### Create and mount app

```js
import { createApp } from 'vue'
import App from './App.vue'

const app = createApp(App)
app.component('GlobalButton', { template: '<button><slot /></button>' })
app.directive('focus', { mounted(el) { el.focus() } })
app.provide('apiUrl', 'https://api.example.com')
app.config.errorHandler = (err) => console.error(err)
app.mount('#app')
```

### Reactive state (Composition API, `<script setup>`)

```vue
<script setup>
import { ref, computed, reactive, toRefs } from 'vue'

const count = ref(0)
const message = ref('Hello')
count.value++   // in script; in template use count

const state = reactive({ user: { name: 'John' }, loading: false })
const { user, loading } = toRefs(state)

const double = computed(() => count.value * 2)
</script>

<template>
  <p>{{ message }}</p>
  <p>{{ count }}</p>
  <p>{{ double }}</p>
</template>
```

### Props and events

```vue
<script setup>
const props = defineProps({
  title: { type: String, required: true },
  likes: { type: Number, default: 0, validator: (v) => v >= 0 }
})

const emit = defineEmits({
  update: (value) => typeof value === 'string',
  submit: null
})

emit('update', newValue)
emit('submit', value, isValid)
</script>

<template>
  <h2>{{ title }}</h2>
</template>
```

### v-model (custom component)

```vue
<script setup>
const props = defineProps({ modelValue: Number, max: { type: Number, default: 5 } })
const emit = defineEmits(['update:modelValue'])

const rating = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v)
})
</script>

<template>
  <button v-for="n in max" :key="n" @click="rating = n">⭐</button>
</template>
```

Parent: `<RatingInput v-model="userRating" />`. Multiple: `v-model:first-name`, `v-model:last-name`.

### Watchers

```js
watch(source, (newVal, oldVal) => { ... }, { immediate: true, deep: true })
watch([a, b], ([newA, newB]) => { ... })
watchEffect(() => { /* auto-tracks deps */ })
```

### Lifecycle hooks

```js
import { onMounted, onUnmounted, onBeforeMount, onUpdated, onErrorCaptured } from 'vue'

onBeforeMount(() => { ... })
onMounted(() => { ... })
onUpdated(() => { ... })
onBeforeUnmount(() => { ... })
onUnmounted(() => { ... })
onErrorCaptured((err, instance, info) => { ... })
```

### Provide / inject

```js
// Ancestor
provide('theme', readonly(theme))
provide('user', { data: readonly(user), updateName: (n) => { user.value.name = n } })

// Descendant
const theme = inject('theme', 'light')
const userContext = inject('user')
```

### Composables

```js
// composables/useFetch.js
export function useFetch(url) {
  const data = ref(null)
  const error = ref(null)
  const loading = ref(false)
  async function fetchData() { ... }
  watch(() => toValue(url), fetchData, { immediate: true })
  return { data, error, loading, refetch: fetchData }
}

// In component
const { data, loading, refetch } = useFetch(computed(() => `/api/users/${userId.value}`))
```

### Template directives (essentials)

| Directive   | Example |
|------------|---------|
| `v-if` / `v-else-if` / `v-else` | Conditional render |
| `v-show`   | Toggle visibility (CSS) |
| `v-for`    | `v-for="(item, i) in items" :key="item.id"` |
| `v-model`  | Two-way binding; `.number`, `.trim` |
| `@event`   | `@click`, `@click.prevent`, `@keyup.enter` |
| `:attr`    | `:id="id"`, `:class="{ active }"`, `:style="{}"` |
| `v-bind`   | `v-bind="objectOfAttrs"` |
| `v-slot` / `#` | Slots: `#default`, `#footer="{ message }"` |
| `v-once`   | Render once |
| `v-memo`   | `v-memo="[a, b]"` — re-render only when a/b change |
| `v-html`   | Raw HTML (sanitize to avoid XSS) |

### Async components

```js
const AsyncModal = defineAsyncComponent(() => import('./Modal.vue'))

const AsyncChart = defineAsyncComponent({
  loader: () => import('./Chart.vue'),
  loadingComponent: { template: '<div>Loading...</div>' },
  errorComponent: { template: '<div>Error</div>' },
  delay: 200,
  timeout: 3000
})
```

Use with `<Suspense>` for components with top-level `await` in setup.

### Build and dev (project from docs)

```bash
pnpm install
pnpm run dev      # http://localhost:5173
pnpm run build    # .vitepress/dist
pnpm run preview
```

Requires Node.js 18+ and pnpm (e.g. 9.12.1). Use `corepack enable` for pnpm.

## Full Reference

For detailed examples (props validation, emit validation, writable computed, deep watchers, provide/inject with Symbols, full composable patterns, all template directives, VitePress config), see **[reference.md](reference.md)**.
