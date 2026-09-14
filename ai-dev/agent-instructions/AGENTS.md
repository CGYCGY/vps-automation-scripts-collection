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
- Do not add agent/session metadata lines
- Author all commits as me

## Subagents

- Use `model: "gpt-5.6-sol"` when spawning subagents, unless I override for a specific task.
- A model override requires `fork_turns: "none"` or a bounded turn count; full-history forks inherit the parent model.

## Comments

- A comment must carry what the code can't — the non-obvious *why*, an external fact or gotcha, a constraint an edit could break. Cut the rest (narration, banners, JSDoc echoing the signature). Code is LLM-read, so this overrides match-surrounding-style.
- When delegating, put this in the subagent's spec — don't say "match the existing comment style."
