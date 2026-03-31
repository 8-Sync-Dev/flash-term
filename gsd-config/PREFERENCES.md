---
version: 1
mode: solo
models:
  planning:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - zai/glm-5.1
      - zai/glm-5-turbo
  research:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - zai/glm-5.1
  execution:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
  execution_simple:
    model: zai/glm-4.7
    fallbacks:
      - zai/glm-4.7-flash
      - zai/glm-4.6
  completion:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
  subagent:
    model: zai/glm-5.1
    fallbacks:
      - zai/glm-5-turbo
      - zai/glm-5
      - zai/glm-4.7
      - zai/glm-4.7-flash
skill_staleness_days: 0
uat_dispatch: false
unique_milestone_ids: true
cmux:
  enabled: false
  notifications: false
  sidebar: false
  splits: false
  browser: false
token_profile: balanced
phases:
  skip_research: false
  skip_reassess: false
  skip_slice_research: false
  reassess_after_slice: false
---

# GSD Skill Preferences

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.
