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
      "setup": "setup.sh -y" }
  ]
}
```

| Key | Meaning |
|-----|---------|
| `name` | The link name under `~/.claude/skills/`. Letters, digits, `.` `_` `-` |
| `repo` | The repo that owns the skill |
| `path` | The skill folder inside the repo. `.` is the whole repo. Relative, no `..` |
| `setup` | Optional. A command run from the checkout root (see [Setup Commands](#setup-commands)) |

The list is checked every time it is read: every skill with a name, a repo and
a path, names unique. A problem names the skill.

## Where the Checkout Comes From

The first match wins:

1. **Your projects checkout.** When [`projects.json`](../projects/README.md)
   has a repo or set member with the skill's repo url, and that folder is a
   clone of it, the link points there.
2. **`~/.gylab/<repo>`**, where `<repo>` is the repo's name from its url
   (`gen-image` for `git@github.com:CGYCGY/gen-image.git`). Cloned there when
   missing.

Urls match across spellings: `git@github.com:O/R.git`, `git@github.com:O/R`,
`https://github.com/O/R.git` and `https://github.com/O/R` are the same repo.

The rule is checked on every run. If `projects.sh` clones a skill's repo later,
the next run points the link at the projects checkout and says so. The
`~/.gylab/<repo>` clone stays where it is.

An existing clone is never pulled, fetched or reset. A non-empty
`~/.gylab/<repo>` that isn't a clone of the repo is reported and left alone.
That includes one holding only the tool's `config.json` and `state/`, left
from a projects checkout that has since gone.

## Links

| Found at `~/.claude/skills/<name>` | Result |
|------------------------------------|--------|
| Nothing | Linked |
| A link to the skill folder | Skipped |
| A link to somewhere else | Replaced, and the old target is named |
| A real folder or file | Warned, left alone. Move it away to let `skills.sh` manage it |

A skill whose folder isn't in the checkout is warned about and not linked.

## Setup Commands

Each skill repo keeps its user data in `~/.gylab/<repo>/`: `config.json` and
`state/`. It has two setup scripts: a `setup.sh` at the repo root that makes a
checkout work and writes `config.json`, and a thin one in the skill folder for
installing the skill alone, which clones and then calls the root one. This
module has its own checkout, so it runs only the root one.

`setup` runs from the checkout root when the link was just made (or moved to
another checkout), or when `~/.gylab/<repo>/config.json` is missing. That file
is the sign the setup finished, so a failed or interrupted setup is retried on
the next run and a working one is left alone. Nothing is recorded by this
module. When the first word is a file in the checkout root, it runs with
`bash`, so `setup.sh` needs no `./` and no executable bit.

A failure is logged and the rest carry on.

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
| `present` | Linked to the right folder, and set up when the skill has a `setup` |
| `partial` | Linked, setup pending: `~/.gylab/<repo>/config.json` is missing. Or a real folder at the link path, or a link to the wrong place |
| `missing` | Not linked yet: where it will link from, or where it will clone to |

A `skills-list` row shows instead when the list is missing or unreadable.

## Answers Up Front

| Variable | Values |
|----------|--------|
| `SKILLS_SETUP` | `yes` / `no`: set up the skills. Asked only by the Mac setup |
| `SKILLS_FILE` | the list's location (default: `skills.json` beside the script) |
| `PROJECTS_FILE` | the projects list searched for checkouts (default: `../projects/projects.json`) |
