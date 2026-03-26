/**
 * smart-compact.mjs
 * Super Auto Compact Smart — OpenCode plugin
 *
 * Uses the real `experimental.session.compacting` hook to inject rich,
 * structured context into every compaction summary. This prevents OpenCode
 * from losing critical task state when the context window fills up.
 *
 * Hook API (verified from sst/opencode source):
 *   experimental.session.compacting(input, output) => Promise<void>
 *     - input.sessionID: string
 *     - output.context: string[]  → push extra context strings here
 *     - output.prompt?: string    → override the entire compaction prompt
 */

export default async function SmartCompactPlugin(ctx) {
  return {
    "experimental.session.compacting": async (input, output) => {
      const { sessionID } = input;

      // ── 1. Fetch current session messages to extract task state
      let sessionSummary = "";
      try {
        const res = await ctx.client.GET("/session/{id}/messages", {
          params: { path: { id: sessionID } },
        });

        if (res.data) {
          const messages = res.data;
          sessionSummary = extractTaskState(messages);
        }
      } catch (_) {
        // Non-fatal — compaction still works without this
      }

      // ── 2. Inject structured context that the compaction agent MUST preserve
      output.context.push(`
<smart-compact-context>
  <instructions>
    CRITICAL: You are performing an intelligent context compaction.
    The following information MUST be preserved verbatim in your summary.
    Never omit or abbreviate these sections.
  </instructions>

  <preservation-rules>
    1. ALWAYS keep: current goal, active task, open todos, architecture decisions
    2. ALWAYS keep: file paths being edited, error messages encountered, bugs being fixed
    3. ALWAYS keep: tech stack, framework, language, key constraints
    4. ALWAYS keep: the user's original request / requirements
    5. ALWAYS keep: last 2-3 tool call results that are still relevant
    6. COMPRESS: completed tasks (keep 1-line summary only)
    7. COMPRESS: exploration/search results already synthesized
    8. DROP: duplicate information, verbose tool outputs no longer needed
  </preservation-rules>

  <required-summary-format>
    Your compaction summary MUST start with this block:

    ## 📋 Session Summary (Auto-Compact)
    **Goal**: [What the user is trying to achieve]
    **Status**: [% complete or current phase]
    **Active Task**: [What was being worked on right now]

    ## 📁 Key Context
    **Tech Stack**: [language/framework/tools]
    **Files Modified**: [list of files changed this session]
    **Important Decisions**: [architecture/design choices made]

    ## ✅ Completed
    [brief bullet list of done items]

    ## 🔄 Next Actions
    [ordered list of remaining tasks]

    ## ⚠️ Active Issues
    [any errors, bugs, blockers being worked on]
  </required-summary-format>

  ${sessionSummary ? `<extracted-task-state>\n${sessionSummary}\n</extracted-task-state>` : ""}
</smart-compact-context>
`);
    },
  };
}

/**
 * Extract key task state from recent messages for injection into compaction.
 * Focuses on: todos, file patches, recent errors, active goal.
 */
function extractTaskState(messages) {
  const lines = [];
  let todoCount = 0;
  let patchCount = 0;
  const modifiedFiles = new Set();
  const recentErrors = [];

  // Walk messages from newest to oldest, cap at last 20
  const recent = messages.slice(-20);

  for (const msg of recent) {
    if (!msg.parts) continue;

    for (const part of msg.parts) {
      // Collect modified files from patches
      if (part.type === "patch" && part.files) {
        for (const f of part.files) {
          modifiedFiles.add(f.path || f);
          patchCount++;
        }
      }

      // Collect todo state
      if (
        part.type === "tool" &&
        part.tool === "todowrite" &&
        part.state?.status === "completed"
      ) {
        todoCount++;
      }

      // Collect recent errors
      if (
        part.type === "tool" &&
        part.state?.status === "error" &&
        part.state?.error
      ) {
        recentErrors.push(part.state.error.substring(0, 200));
      }
    }
  }

  if (modifiedFiles.size > 0) {
    lines.push(`Files touched this session: ${[...modifiedFiles].join(", ")}`);
  }
  if (patchCount > 0) {
    lines.push(`Total file edits: ${patchCount}`);
  }
  if (recentErrors.length > 0) {
    lines.push(`Recent errors:\n${recentErrors.map((e) => `  - ${e}`).join("\n")}`);
  }

  return lines.join("\n");
}
