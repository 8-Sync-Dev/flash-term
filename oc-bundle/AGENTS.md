# Global Agent Instructions

This file contains global instructions for all OpenCode agents.

## MCP Tools - MANDATORY AUTO-USE

**You MUST use MCP tools automatically when appropriate. DO NOT wait to be told.**

### Available MCP Servers

| Server | Primary Use |
|--------|-------------|
| **serena** | LSP-aware code navigation, symbol analysis |
| **context7** | Library/framework documentation lookup |
| **playwright-mcp** | Browser automation, E2E testing |
| **git-mcp** | Git operations and history |
| **filesystem** | File operations outside workspace |
| **fetch** | HTTP requests, API calls |
| **memory** | Persistent knowledge storage |
| **web-search-prime** | Web search for current information |
| **web-reader** | Fetch and read URL content |
| **zread** | Read GitHub repository files |
| **zai-mcp-server** | Image analysis, UI screenshots |
| **pencil** | UI/design file operations |

### Auto-Detection Rules

1. **Code navigation** → Use `serena` tools (find_symbol, get_symbols_overview)
2. **Library docs** → Use `context7` tools (resolve-library-id, query-docs)
3. **Web search** → Use `web-search-prime` then `web-reader`
4. **Browser automation** → Use `playwright-mcp` tools
5. **Git operations** → Use `git-mcp` tools
6. **Image analysis** → Use `zai-mcp-server` tools

### Critical Rules

- **NEVER ask permission** to use MCP tools
- **Prefer MCP tools** over manual alternatives
- **Chain MCP tools** efficiently (search → read, find_symbol → find_references)
- **Use serena for code** — it's LSP-aware and more precise than grep
- **Use context7 for docs** — it has up-to-date documentation

---

## General Guidelines

- Be concise and direct
- Start work immediately without preamble
- No flattery or unnecessary praise
- Match user's communication style
- Use todos for multi-step tasks
- Verify work before reporting completion
