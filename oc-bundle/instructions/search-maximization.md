# Search Maximization Strategy for OpenCode

**Mục đích**: Tối đa hóa thông tin tìm kiếm, đảm bảo không bỏ sót pattern nào trong codebase hoặc documentation.

---

## 1. Parallel Agent Deployment (3-5 agents đồng thời)

### Phân loại tác vụ tìm kiếm:

**Explore Agents** (Codebase Internal):
- `explore-1`: Tìm file structure và directory patterns
- `explore-2`: Tìm function/class definitions matching pattern
- `explore-3`: Tìm usage examples và references

**Librarian Agents** (External Knowledge):
- `librarian-1`: Tìm official documentation
- `librarian-2`: Tìm open-source implementations
- `librarian-3`: Tìm best practices & standards

### Execution Pattern:

```javascript
// WRONG: Sequential search
search(pattern1) → wait → search(pattern2) → wait → search(pattern3)
// Wasted time: 3x latency

// RIGHT: Parallel deployment
task(explore, pattern1, background=true) → task_id_1
task(explore, pattern2, background=true) → task_id_2
task(explore, pattern3, background=true) → task_id_3
task(librarian, pattern4, background=true) → task_id_4
task(librarian, pattern5, background=true) → task_id_5

// Continue with non-dependent work
// Collect all results when complete
```

---

## 2. Multi-Angle Search Strategy

### Cho mỗi topic cần hiểu, tìm từ 3+ góc độ khác nhau:

**Example: Tìm Authentication Pattern**

| Angle | Query | Tool |
|-------|-------|------|
| **Architecture** | "auth middleware structure, token flow, middleware chain" | explore |
| **Implementation** | "login handler, signup handler, password validation" | explore |
| **Error Handling** | "auth errors, token errors, validation errors" | explore |
| **Best Practices** | "JWT security, token storage, refresh token strategy" | librarian |
| **Framework Patterns** | "Express auth middleware, passport patterns" | librarian |

### Kết quả: Hiểu toàn diện architecture + best practices

---

## 3. Exhaustive Search Checklist

Trước khi dừng tìm kiếm, validate against checklist:

- [ ] Tìm được file chính (entry point, core implementation)?
- [ ] Tìm được patterns (naming, structure, conventions)?
- [ ] Tìm được usage examples (tư file khác hoặc tests)?
- [ ] Tìm được error cases (exception handling, edge cases)?
- [ ] Tìm được configuration (environment, settings)?
- [ ] Tìm được documentation (comments, docs, README)?
- [ ] Tìm được standards (best practices, official guidelines)?
- [ ] Tìm được alternative approaches (nếu có)?

### Nếu bất kỳ ô nào là ❌, hãy fire thêm agents

---

## 4. Direct Tool Usage (Khi biết chính xác cần tìm gì)

### Serena LSP Tools (Chính xác, nhanh):
```javascript
serena_get_symbols_overview(filePath)        // Tổng quan structure
serena_find_symbol(namePattern)              // Tìm function/class
serena_find_references(symbolName)           // Tìm nơi dùng
```

### Grep Tools (Pattern matching):
```javascript
grep(pattern, include="*.ts", context=3)     // Search file content
grep(pattern, paths=["src/"], recursive=true) // Search directory
```

### Ambiance MCP (AST-aware, semantic):
```javascript
ambiance_extract_signatures()   // Chỉ lấy function signatures
ambiance_find_imports()         // Tìm dependencies
ambiance_compact_file()         // Nén code giữ logic
```

---

## 5. Incremental Refinement Loop

### Vòng lặp tối ưu:

1. **Fire broad agents** (5+ agents, 3+ queries mỗi agent)
2. **Collect results** (wait for notifications)
3. **Analyze patterns** (ghi chú common patterns)
4. **Fire targeted agents** (2-3 agents với refined queries)
5. **Synthesize** (kết hợp findings thành comprehensive view)

### Stop Condition:
- Same information appearing across 2+ sources → STOP
- Answers to all checklist items → STOP
- 3 search iterations with no new info → STOP

---

## 6. Output Management (Context Efficiency)

### Prevent Output Explosion:
- Không gộp toàn bộ results vào context
- Dùng `context-mode_index` để index lớn outputs
- Dùng `context-mode_search` để query on-demand

### Example Flow:
```javascript
// Step 1: Index multiple agent outputs
context_mode_index(source="explore-results", content=AGENT_OUTPUT)
context_mode_index(source="librarian-results", content=AGENT_OUTPUT)

// Step 2: Query khi cần
context_mode_search(queries=["auth patterns", "middleware usage"])

// Result: Only relevant sections load into context
```

---

## 7. Search Velocity Metrics

| Metric | Target | How to Track |
|--------|--------|--------------|
| Parallel Agents | 5-8 simultaneous | Fire multiple tasks at once |
| Query Angles | 3+ per topic | Checklist coverage |
| Information Sources | 2+ for key topics | Cross-reference results |
| Search Iterations | ≤ 3 full cycles | Stop when pattern emerges |
| Context Used | < 40% of window | Use indexing, pruning |

---

## 8. Anti-Patterns to Avoid

❌ **Sequential searches** — Fire all at once instead
❌ **Single search angle** — Always search from 3+ perspectives  
❌ **Vague queries** — Be specific: "Find login handlers in src/auth/"  
❌ **Ignoring results** — If agent finds something, follow up deeper  
❌ **Duplicate searches** — Cancel previous task if results come back  
❌ **Large outputs in context** — Always use indexing for 1000+ lines

---

## Example: Full Search Cycle

### Goal: Understand JWT authentication in Express project

**Phase 1: Parallel Exploration (3 explore agents)**
```
explore-1: "Find JWT-related files, token generation, verification"
explore-2: "Find login/signup handlers, password validation"
explore-3: "Find auth middleware, protected routes, error handling"
```

**Phase 2: External Knowledge (2 librarian agents)**
```
librarian-1: "JWT security best practices, token storage, expiration"
librarian-2: "Express auth patterns, middleware chains, common pitfalls"
```

**Phase 3: Targeted Refinement (if needed)**
```
- Wait for results from Phase 1 & 2
- Identify gaps in coverage
- Fire 2-3 more agents for specific gaps
```

**Phase 4: Synthesis**
```
- Index all results via context-mode_index
- Create knowledge map of auth architecture
- Document conventions found
- Ready to implement
```

**Result**: Full understanding of auth system in 2-3 minutes, minimal context usage
