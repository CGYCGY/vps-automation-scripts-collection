## Commit Style

- Title: `<emoji> <type>(<scope optional>): <description>`, under 70 characters
- Emoji is required; use the mapping below (lobe-commit gitmoji set):
  - ✨ feat — introduce new features
  - 🐛 fix — fix a bug
  - ♻️ refactor — refactor code that neither fixes a bug nor adds a feature
  - ⚡ perf — code change that improves performance
  - 💄 style — add or update style files that do not affect the meaning of the code
  - ✅ test — add missing tests or correct existing tests
  - 📝 docs — documentation only changes
  - 👷 ci — changes to CI configuration files and scripts
  - 🔧 chore — other changes that don't modify src or test files
  - 📦 build — make architectural changes
- Body in point form, not the title
- Body: flat bullets; group under `<section>:` headers when multi-area
- Do not add Co-Authored-By, Claude-Session lines
- Author all commits as me

## Subagents

- Always pass `model: "opus"` when spawning subagents (Agent tool calls and Workflow `agent()` opts), unless I override for a specific task.

## Comments

- A comment must carry what the code can't — the non-obvious *why*, an external fact or gotcha, a constraint an edit could break. Cut the rest (narration, banners, JSDoc echoing the signature). Code is LLM-read, so this overrides match-surrounding-style.
- When delegating, put this in the subagent's spec — don't say "match the existing comment style."
