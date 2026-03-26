# MCP Tool Auto-Detection & Usage Rules

**CRITICAL: You MUST use MCP tools automatically when appropriate. DO NOT wait to be told.**

## Available MCP Servers & Tools

| Server | Tools | Primary Use Case |
|--------|-------|------------------|
| **serena** | `get_symbols_overview`, `find_symbol`, `find_references`, `rename_symbol`, `execute_command` | LSP-aware code navigation, symbol analysis |
| **context7** | `resolve-library-id`, `query-docs` | Library/framework documentation lookup |
| **playwright-mcp** | `playwright_navigate`, `playwright_screenshot`, `playwright_click`, etc. | Browser automation, E2E testing |
| **git-mcp** | `git_status`, `git_log`, `git_diff`, `git_blame`, etc. | Git operations and history |
| **filesystem** | `read_file`, `write_file`, `list_directory`, etc. | File operations outside workspace |
| **fetch** | `fetch_url`, etc. | HTTP requests, API calls |
| **memory** | `memory_store`, `memory_retrieve`, etc. | Persistent knowledge storage |
| **web-search-prime** | `web_search_prime` | Web search for current information |
| **web-reader** | `webReader` | Fetch and read URL content |
| **zread** | `read_file` (GitHub) | Read GitHub repository files |
| **zai-mcp-server** | `ui_to_artifact`, `extract_text_from_screenshot`, `diagnose_error_screenshot`, etc. | Image analysis, UI conversion |
| **pencil** | Design tools | UI/design file operations |
| **sequential-thinking** | `sequentialthinking` | Complex multi-step reasoning |

---

## Auto-Detection Rules (MANDATORY)

### Code Analysis Tasks
```
IF task involves: reading code, finding functions/classes, understanding structure
THEN: Use serena tools FIRST
  - get_symbols_overview → for file/project structure
  - find_symbol → for specific function/class
  - find_references → for usage discovery
```

### Documentation Tasks
```
IF task involves: library usage, framework features, API reference
THEN: Use context7 tools FIRST
  - resolve-library-id → to find the library
  - query-docs → to get documentation
```

### Web Information Tasks
```
IF task involves: current information, news, latest versions
THEN: Use web-search-prime FIRST
  - web_search_prime → search the web
  - THEN web-reader → to read specific URLs
```

### Browser/UI Tasks
```
IF task involves: E2E testing, browser automation, screenshots
THEN: Use playwright-mcp tools FIRST
  - playwright_navigate → go to URL
  - playwright_screenshot → capture page
  - playwright_click/type → interact
```

### Git Tasks
```
IF task involves: git history, blame, diff, branch info
THEN: Use git-mcp tools FIRST
  - git_log → see history
  - git_diff → see changes
  - git_blame → see who changed what
```

### Image/Multimodal Tasks
```
IF task involves: screenshots, UI images, diagrams
THEN: Use zai-mcp-server tools
  - ui_to_artifact → convert UI to code
  - extract_text_from_screenshot → OCR
  - diagnose_error_screenshot → analyze errors
  - analyze_data_visualization → charts/graphs
```

---

## Priority Order by Task Type

### Reading/Navigating Code
1. **serena** (LSP-aware, precise symbol navigation)
2. **git-mcp** (for history context)
3. Built-in read/grep tools (fallback)

### Finding Documentation
1. **context7** (official docs lookup)
2. **web-search-prime** (web search)
3. **web-reader** (read specific URLs)

### Web & Browser
1. **web-search-prime** (search)
2. **web-reader** (read content)
3. **playwright-mcp** (browser automation)

### GitHub/Repos
1. **zread** (read GitHub files)
2. **git-mcp** (local git operations)

### Testing
1. **playwright-mcp** (E2E/UI tests)
2. **serena** (find test files)
3. Built-in bash (run tests)

---

## Tool Naming Patterns

MCP tools follow these naming conventions:
- `serena_*` — Serena LSP tools
- `context7_*` — Context7 documentation tools
- `mcp-filesystem_*` — Filesystem operations
- `playwright_*` — Browser automation
- `git-mcp_*` or `git_*` — Git operations
- `web-search-prime_*` — Web search
- `zai-mcp-server_*` — Image/multimodal tools

---

## Critical Rules

1. **NEVER ask permission** to use MCP tools — they are enabled by default
2. **Prefer MCP tools** over manual alternatives when available
3. **Chain MCP tools** efficiently:
   - web-search → web-reader (for web info)
   - serena find_symbol → find_references (for code analysis)
   - context7 resolve-library-id → query-docs (for docs)
4. **Use serena for code navigation** — it's LSP-aware and more precise than grep
5. **Use context7 for library docs** — it has up-to-date documentation
6. **Use playwright for browser tasks** — don't give manual browser instructions

---

## Quick Reference Card

| I Need To... | Use This MCP |
|--------------|--------------|
| Find a function in code | `serena.find_symbol` |
| Understand file structure | `serena.get_symbols_overview` |
| Find where something is used | `serena.find_references` |
| Get library documentation | `context7.resolve-library-id` + `context7.query-docs` |
| Search the web | `web-search-prime.web_search_prime` |
| Read a web page | `web-reader.webReader` |
| Automate browser | `playwright-mcp.*` |
| Check git history | `git-mcp.git_log` |
| See what changed | `git-mcp.git_diff` |
| Analyze a screenshot | `zai-mcp-server.analyze_image` |
| Convert UI to code | `zai-mcp-server.ui_to_artifact` |
| Store knowledge | `memory.*` |

---

## Examples

### Example 1: Finding React useEffect Documentation
```
WRONG: grep for "useEffect" or search web manually
RIGHT: 
1. context7.resolve-library-id("react hooks useEffect")
2. context7.query-docs(libraryId, "useEffect cleanup best practices")
```

### Example 2: Understanding Codebase Structure
```
WRONG: ls -la and grep for patterns
RIGHT:
1. serena.get_symbols_overview(filePath)
2. serena.find_symbol(symbolName)
3. serena.find_references(symbolName)
```

### Example 3: E2E Testing
```
WRONG: Tell user to "open browser and click..."
RIGHT:
1. playwright_navigate(url)
2. playwright_click(selector)
3. playwright_screenshot()
```

### Example 4: Getting Current Library Version
```
WRONG: Assume version or check old docs
RIGHT:
1. web-search-prime.web_search_prime("react latest version 2024")
2. web-reader.webReader(official_url)
```
