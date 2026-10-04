# Agent Skills

Puts the same agent skills on every machine. Each skill in `skills.json` is
linked into `~/.claude/skills/<name>` from a checkout of the repo that owns it.

```bash
./workstation/shared/skills/skills.sh            # run it alone
./workstation/shared/skills/skills.sh --status   # survey, change nothing
./workstation/shared/skills/skills.sh -y         # take the defaults
```

It also runs last in the [Mac setup](../../macos/README.md), after
[projects](../projects/README.md). There it is optional: one question, "Set up
the agent skills?". Run alone, it doesn't ask. The
[AI dev setup](../ai-dev/README.md#options) offers it at the end of a
successful run.

## The List

`skills.json` beside the script is committed. Comments and trailing commas are
fine.

```jsonc
{
  "skills": [
    { "name": "library", "repo": "git@github.com:you/skill-catalog.git", "path": "." },
    { "name": "gen-image", "repo": "git@github.com:CGYCGY/gen-image.git", "path": ".claude/skills/gen-image",
      "setup": "setup.sh -y --dir {repo}" }
  ]
}
```

| Key | Meaning |
|-----|---------|
| `name` | The link name under `~/.claude/skills/`. Letters, digits, `.` `_` `-` |
| `repo` | The repo that owns the skill |
| `path` | The skill folder inside the repo. `.` is the whole repo. Relative, no `..` |
| `setup` | Optional. A command run from the skill folder once it is linked |

The list is checked every time it is read: every skill with a name, a repo and
a path, names unique. A problem names the skill.

## Where the Checkout Comes From

The first match wins:

1. **Your projects checkout.** When [`projects.json`](../projects/README.md)
   has a repo or set member with the skill's repo url, and that folder is a
   clone of it, the link points there.
2. **`~/.gylab/repos/<repo name>`.** Cloned there when missing.

Urls match across spellings: `git@github.com:O/R.git`, `git@github.com:O/R`,
`https://github.com/O/R.git` and `https://github.com/O/R` are the same repo.

The rule is checked on every run. If `projects.sh` clones a skill's repo later,
the next run points the link at the projects checkout and says so. The
`~/.gylab/repos` clone stays where it is.

An existing clone is never pulled, fetched or reset. A folder in
`~/.gylab/repos` that isn't a clone of the repo is reported and left alone.

## Links

| Found at `~/.claude/skills/<name>` | Result |
|------------------------------------|--------|
| Nothing | Linked |
| A link to the skill folder | Skipped |
| A link to somewhere else | Replaced, and the old target is named |
| A real folder or file | Warned, left alone. Move it away to let `skills.sh` manage it |

A skill whose folder isn't in the checkout is warned about and not linked.

## Setup Commands

`setup` runs after the link is made or found correct, from the skill folder.
`{repo}` is replaced with the checkout's path. When the first word is a file in
the skill folder, it runs with `bash`, so `setup.sh` needs no `./` and no
executable bit.

It runs on every run, so it must be safe to repeat. A failure is logged and the
rest carry on.

The skills' own setup scripts, and the state folders they create, are a
separate piece of work. This module only runs them.

## Cloning

Repos that need a clone are cloned in the last step, once the GitHub key is on
your account. Each is checked first with `git ls-remote`, the same way
[projects](../projects/README.md#repo-access) does it. If any fail, it waits:
fix the access, or remove the skill from the list, then press Enter to check
again. Type `skip` to go on without them. With `-y` or without a terminal, it
skips them and says so.

## Status

`--status` shows one row per skill:

| State | Meaning |
|-------|---------|
| `present` | Linked to the right folder |
| `partial` | A real folder at the link path, or a link to the wrong place |
| `missing` | Not linked yet: where it will link from, or where it will clone to |

A `skills-list` row shows instead when the list is missing or unreadable.

## Answers Up Front

| Variable | Values |
|----------|--------|
| `SKILLS_SETUP` | `yes` / `no`: set up the skills. Asked only by the Mac setup |
| `SKILLS_FILE` | the list's location (default: `skills.json` beside the script) |
| `PROJECTS_FILE` | the projects list searched for checkouts (default: `../projects/projects.json`) |
