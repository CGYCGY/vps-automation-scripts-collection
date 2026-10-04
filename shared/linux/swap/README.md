# Swap Setup (Linux)

Adds a 4GB `/swapfile` and tunes how eagerly the kernel uses it, based on the
machine's RAM. Machines that already have enough swap are left alone.

## Quick Start

```bash
sudo ./swap-setup.sh
```

It is also run by `sudo ./server/setup.sh --swap` and `--full`.
`./swap-setup.sh --status` shows what is in place without changing anything.

## Settings by RAM

| RAM    | Swap Size | Swappiness | vfs_cache_pressure | Use Case                          |
|--------|-----------|------------|--------------------|-----------------------------------|
| 16GB+  | 4GB       | 10         | 50                 | Optimal performance, minimal swap |
| 12GB+  | 4GB       | 10         | 60                 | Good performance, light swap      |
| 8GB+   | 4GB       | 20         | 80                 | Balanced, moderate swap           |
| <8GB   | 4GB       | 30         | 100 (default)      | Survival mode, active swap        |

- **Swappiness** (0–100): how readily memory is moved to swap. Lower keeps
  more in RAM.
- **vfs_cache_pressure**: how readily the kernel drops cached file metadata.
  Lower keeps more of it.

## Skipped When

- The machine already has 2GB or more of swap, not counting a 4GB `/swapfile`
  from an earlier run
- `/` has less than 8GB free

Settings are only changed along with the swap file. Each step (the file, its
`/etc/fstab` line, the settings) is skipped when already done, so a run that
stopped halfway is finished by running it again.

## What It Does

| Phase | Steps |
|-------|-------|
| plan | Checks RAM, swap and free disk; asks whether to create the swap file, only when one is needed |
| auto | Creates `/swapfile`, adds it to `/etc/fstab`, writes the settings and applies them |

An old `/swapfile` that is too small is replaced. If `fallocate` fails, or
`swapon` rejects the file it made, the file is written out with `dd` instead.

### Files Changed

- `/swapfile`: the swap file, mode 600
- `/etc/fstab`: keeps it on after a reboot
- `/etc/sysctl.d/99-swap.conf`: the two settings

`/etc/sysctl.conf` is applied after `sysctl.d`, so any `vm.swappiness` or
`vm.vfs_cache_pressure` lines already in it would override the new values. The
script comments those lines out and marks them `# moved to 99-swap.conf`.

## Unattended Runs

```bash
sudo SWAP_CREATE=yes ./swap-setup.sh -y
```

| Variable | Values |
|----------|--------|
| `SWAP_CREATE` | `yes` / `no`: create the swap file when one is needed |

## Checking It

```bash
swapon --show
sysctl vm.swappiness vm.vfs_cache_pressure
grep swapfile /etc/fstab
```

## Changing the Settings Later

Edit `/etc/sysctl.d/99-swap.conf`, then apply it:

```bash
sudo sysctl --system
```
