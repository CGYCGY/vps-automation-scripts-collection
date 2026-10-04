# Projects

Puts your projects in the same place on every machine. It clones the repos in
your projects list, creates the plain folders, and registers each name with
`cdp`, so `cdp vps` jumps to that project. An entry can [pick another shortcut
or none](#the-list).

```bash
./workstation/shared/projects/projects.sh            # run it alone
./workstation/shared/projects/projects.sh --status   # survey, change nothing
./workstation/shared/projects/projects.sh -y         # take the defaults
```

It also runs last in the [Mac setup](../../macos/README.md), after the GitHub
key is on your account. There it is optional: one question, "Set up your
projects?". Run alone, it doesn't ask.

It never touches anything inside a folder that is already there. An existing
clone is not pulled, fetched or reset. A folder in the way is left alone with a
warning, never deleted.

## The List

`projects.json` beside the script is your list. It is gitignored, so each
machine keeps its own. Comments and trailing commas are fine, so you can comment
an entry out. `projects.example.json` shows the format.

```jsonc
{
  "root": "~/projects",
  "projects": [
    { "name": "projects", "path": "." },
    { "name": "temp", "path": "lab/temp" },
    { "name": "vps", "path": "tools/vps-automation-scripts-collection",
      "url": "git@github.com:CGYCGY/vps-automation-scripts-collection.git" },
    { "name": "pi", "path": "tools/pi", "repos": [
        { "path": "pi-deployment-manager", "url": "git@github.com:CGYCGY/pi-deployment-manager.git" }
    ]}
  ]
}
```

The keys decide the kind:

| Kind | Keys | What happens |
|------|------|--------------|
| Folder | `name`, `path` | The folder is created |
| Repo | `name`, `path`, `url` | Cloned to `path` |
| Set | `name`, `path`, `repos` | Each member is cloned into `path`. Members have a `path` (inside the set) and a `url`, no name |

Paths are relative to `root`, with no leading `/` and no `..`. `root` is per
machine; `~` in it is kept as written and expanded when the list is read.

An optional `cdp` key sets the shortcut:

| Where | `cdp` | Shortcut |
|-------|-------|----------|
| Entry (any kind) | absent | `name` |
| Entry (any kind) | `"sh"` | `sh` instead of `name`, same folder |
| Entry (any kind) | `false` | none; still cloned or created |
| Set member | `"pdm"` | `pdm`, to the member's folder |
| Set member | absent or `false` | none |

```jsonc
{ "name": "pi", "path": "tools/pi", "cdp": false, "repos": [
    { "path": "pi-deployment-manager", "url": "git@github.com:CGYCGY/pi-deployment-manager.git", "cdp": "pdm" }
]}
```

The list is checked every time it is read: names unique, every entry with a
name and a path, repos with a url, set members with a path and a url, nothing
with both `url` and `repos`, `cdp` either `false` or a name (letters, digits,
`.` `_` `-`; `true` is an error), and every shortcut unique across entries and
set members. A problem names the entry.

## Getting the List onto a Machine

When `projects.json` is missing, the setup asks where it is. Give it any of:

- a URL: host the JSON anywhere, e.g. a private gist's raw link
- a file path
- the JSON itself, pasted

Comments are stripped and the list is checked before it is saved. If it has no
`root`, the setup asks where your projects live (default `~/projects`) and
writes it in.

To write a list from a machine that already has your projects:

```bash
./workstation/shared/projects/projects.sh scan > list.json   # or: scan ~/code
```

`scan` changes nothing. A folder directly under the root is a category, not an
entry. Inside a category, a git repo becomes a repo entry, a folder holding git
repos becomes a set, and any other folder a plain folder. Names are the folder
names; shorten them to what you want to type after `cdp`.

## Repo Access

Before cloning, every url is checked with `git ls-remote`, without prompts and
with a time limit. Each repo gets a row:

| Result | Meaning |
|--------|---------|
| `ok` | Reachable |
| key not on the git host | Your SSH key isn't on the account. `../../macos/ssh.sh` makes one |
| no access, or a typo | GitHub says "not found" for a private repo you can't see |
| unreachable | Anything else, with the first line of git's error |

If any fail, it waits: fix the access, or remove them from the list, then press
Enter to check again. Type `skip` to clone the rest without them. With `-y` or
without a terminal, it skips them and says so.

```bash
./workstation/shared/projects/projects.sh check   # the table only; exits 1 if any fail
```

## Clones

| Found at the repo's path | Result |
|--------------------------|--------|
| Nothing, or an empty folder | Cloned |
| A clone of the same url | Skipped |
| A clone of another url | Warned, left alone |
| A folder with files and no `.git` | Warned, left alone |

A failed clone is logged and the rest carry on. The end shows the counts.

## `cdp`

The navigator comes from [CGYCGY/shell-utils](https://github.com/CGYCGY/shell-utils)
(`~/.zsh/project-navigator.zsh` on macOS, `~/.project-navigator.sh` on Linux).
It is installed if missing, the same way the AI dev setup does it. All shortcuts
are written in one pass: a name with a new path is updated, names that aren't in the
list stay, and the previous file is kept as `.bak`. Open a new shell to use them.

## Status

`--status` shows three rows:

| Row | Shows |
|-----|-------|
| `projects-list` | Where the list is and its root, or that it is missing |
| `projects-repos` | How many repos are cloned |
| `projects-cdp` | How many of the list's shortcuts are registered with the right path |

## Answers Up Front

| Variable | Values |
|----------|--------|
| `PROJECTS_SETUP` | `yes` / `no`: set up projects. Asked only by the Mac setup |
| `PROJECTS_SOURCE` | URL, file path or JSON, when there is no list yet |
| `PROJECTS_ROOT` | where projects live, when the list has no root (default `~/projects`) |
| `PROJECTS_FILE` | the list's location (default: `projects.json` beside the script) |
