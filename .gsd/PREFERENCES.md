---
version: 1
mode: solo
always_use_skills: []
prefer_skills: []
avoid_skills: []
skill_rules: []
custom_instructions: []
models:
  planning:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex
  research:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex
  discuss:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex
  execution:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.4
  execution_simple:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.1-codex-mini
  completion:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.4
  validation:
    model: openai-codex/gpt-5.4
    fallbacks:
      - openai-codex/gpt-5.3-codex
  subagent:
    model: openai-codex/gpt-5.3-codex
    fallbacks:
      - openai-codex/gpt-5.1-codex-mini
skill_discovery:
skill_staleness_days:
auto_supervisor: {}
git:
  auto_push: true
  push_branches:
  remote:
  snapshots:
  pre_merge_check:
  commit_type:
  main_branch: main
  merge_strategy:
  isolation: worktree
  manage_gitignore:
  worktree_post_create:
unique_milestone_ids:
budget_ceiling:
budget_enforcement:
context_pause_threshold:
token_profile:
phases:
  skip_research:
  skip_reassess:
  reassess_after_slice:
  skip_slice_research:
dynamic_routing:
  enabled:
  tier_models: {}
  escalate_on_failure:
  budget_pressure:
  cross_provider:
  hooks:
auto_visualize:
auto_report:
parallel:
  enabled:
  max_workers:
  budget_ceiling:
  merge_strategy:
  auto_merge:
verification_commands: []
verification_auto_fix:
verification_max_retries:
notifications:
  enabled:
  on_complete:
  on_error:
  on_budget:
  on_milestone:
  on_attention:
cmux:
  enabled:
  notifications:
  sidebar:
  splits:
  browser:
remote_questions:
  channel:
  channel_id:
  timeout_minutes:
  poll_interval_seconds:
uat_dispatch:
post_unit_hooks: []
pre_dispatch_hooks: []
# experimental:
#   rtk: false
---

# GSD Skill Preferences

Project-level preferences for this repository.

See `~/.gsd/agent/extensions/gsd/docs/preferences-reference.md` for full field documentation and examples.
