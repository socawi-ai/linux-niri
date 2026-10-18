# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal Niri desktop setup for Fedora: one Bash installer (`fedora-niri-setup.sh`), the dotfiles it deploys (`niri/`, `alacritty/`, `noctalia/`, `wallpapers/`), and `steam-sunshine-sync.sh`, which is run separately once Steam is logged in with games installed. README.md is the user documentation; keep it in step with behavior changes.

It's tuned for one machine: DP-1 is the main 3440x1440 monitor, DP-2 a 1920x1080 output used for Sunshine streaming, the keyboard layout is `se`, and GRUB/rEFInd resolutions assume the ultrawide.

## Commands

There's no build. Check scripts with:

```bash
bash -n fedora-niri-setup.sh steam-sunshine-sync.sh
shellcheck -S warning fedora-niri-setup.sh steam-sunshine-sync.sh
niri validate -c niri/config.kdl          # needs niri installed
./fedora-niri-setup.sh --help             # options: --configs-only, --no-menu, --verbose
./steam-sunshine-sync.sh --dry-run --verbose
```

The installer only runs on Fedora as a normal (non-root) user with sudo, so it can't run end to end on other machines. To exercise parts of it elsewhere, source it without its last line (`main "$@"`) and stub the system-facing helpers:

```bash
head -n -1 fedora-niri-setup.sh > /tmp/lib.sh
# in a test script: source /tmp/lib.sh; then override
#   require_fedora() { DNF_BIN=dnf; }   run_as_user() { "$@"; }   run_sudo() { "$@"; }  (or make it fail loudly)
# and point TARGET_HOME, USER_BACKUP_ROOT, SYSTEM_BACKUP_ROOT, CONFIG_SOURCE_DIR (e.g. the repo), LOG_FILE at a temp dir,
# then call single functions or `main --configs-only`.
```

The whiptail menu and progress gauge need a terminal: run under `TERM=xterm-256color script -qec "bash test.sh" typescript`, since a `dumb` TERM makes whiptail exit immediately.

## Installer architecture (`fedora-niri-setup.sh`)

**Configuration**: every setting is an environment variable with a default at the top of the script, documented in comments there. Defaults that live in the target user's home are filled in `resolve_target_user`, since the script may set up a `TARGET_USER` other than the one running it. Always use `run_as_user` for files in their home and `run_sudo` for system changes. The script refuses to run as root.

**Menu and modes**:
- `SETUP_MODE` is `full` (everything) or `configs` (`--configs-only`: only fetch the repo and deploy configs, with no sudo and no packages).
- Optional features are the `SETUP_FEATURES` entries (`"tag|VARIABLE|label"`). The whiptail checklist sets each `VARIABLE` to 1 or 0, and the step function checks it. To add a feature, add its variable, a `SETUP_FEATURES` entry and a function that checks the variable.
- `main` runs the steps in `section`s. `TOTAL_SECTIONS` must equal the number of `section` calls in each mode (10 full, 3 configs), so update it when adding or removing sections.

**Error model**: `set -Eeuo pipefail` with an ERR trap that calls `die`.
- Core steps stop the script on failure.
- rEFInd, lsfg-vk and Sunshine (`install_extras`) instead `warn` and `return 1`, so one failing doesn't stop the others. They're called as `install_x || warn …`, so errexit is off inside them, and every command that matters must be checked explicitly (`cmd || { warn "…"; return 1; }`).
- `dnf_install` fails on error, `dnf_install_optional` warns, and `dnf_install_best_effort` retries packages one at a time.

**Re-runs must be safe**. Everything is meant to converge when the script runs again.
- Replaced files are first copied to timestamped backup roots (`backup_user_path`, `backup_system_path`, or via `write_user_file` / `write_system_file`).
- Generated sections inside user-editable files are delimited by `BEGIN`/`END` marker comments and rewritten in place: the Noctalia wallpaper block in `settings.toml`, and the rEFInd block in `refind.conf`. Keep the rEFInd marker text as it is; it's named after the former `fedora-refind-setup.sh` so older installs are still recognized.
- `backup_system_path` checks paths through sudo, because the ESP is root-only.

**Output**:
- `log`, `warn` and `record_change` feed the final summary; `print_next_steps` lists manual follow-ups.
- With a terminal and `ASSUME_YES=1`, a whiptail progress gauge replaces the scrolling output (`start_progress`/`stop_progress`). `section`, `log` and `warn` update it, and all command output goes only to the log file.
- Nothing may prompt on the terminal while the gauge is shown. For that reason, sudo's timestamp is kept fresh by a background loop, `GIT_TERMINAL_PROMPT=0` is exported, and interactive helpers (`ask_yes_no`, `ask_value`, prompting commands) only prompt when `ASSUME_YES` isn't 1, in which case the gauge is off.
- The gauge's `NEWT_COLORS` theme is shared with `steam-sunshine-sync.sh`.

**Configs are deployed from GitHub, not the working tree**: the installer clones `CONFIG_REPO_URL` at `CONFIG_REPO_BRANCH` (default `main`) into `~/.cache/fedora-niri-setup/linux-niri`. Set `CONFIG_SOURCE_DIR` to a local checkout to deploy uncommitted changes. Deployment replaces whole directories:

| Repo | Deployed to |
| --- | --- |
| `niri/` | `~/.config/niri` |
| `alacritty/` | `~/.config/alacritty` |
| `noctalia/` | `~/.local/state/noctalia` (then the wallpaper block is regenerated) |
| `wallpapers/wallpapers.tar.xz` | the XDG Pictures folder, under `wallpapers/` |

`verify_config_source` requires all four to exist.

**Boot**: Plymouth and GRUB look are set early. When rEFInd is enabled (UEFI only) it becomes the visible boot menu: it's installed as an extra firmware entry next to Fedora's, which is never touched, and GRUB is set to `timeout 0` / `hidden`. `configure_plymouth_and_grub` therefore leaves GRUB's timeout alone when rEFInd is enabled or already set up (`refind_setup_installed`). For Secure Boot, rEFInd is installed with `--shim --localkeys`, but `refind-install --yes` never enrolls its key with shim (that needs a password prompt). Instead, `check_refind_mok_key` checks whether the key is already enrolled, and `print_next_steps` gives the `mokutil --import` steps when it isn't.

## niri config

- `niri/config.kdl` only includes `niri/cfg/*.kdl`.
- In `rules.kdl`, niri applies matching window rules in order and later ones win, so the general appearance rule (opacity, blur, rounded corners) is first and app-specific rules override it.
- Named workspaces (`misc.kdl`): Web and Dev on DP-1, Stream on DP-2.
- Names shared across files must stay in sync:
  - Steam Big Picture opens on Stream (`rules.kdl`).
  - `steam-sunshine-sync.sh` switches to `NIRI_STREAM_WORKSPACE=Stream` when a stream starts and to `NIRI_NATIVE_WORKSPACE=Web` when it ends.
  - The installer sets Sunshine's capture output to `SUNSHINE_CAPTURE_OUTPUT=DP-2`.

## steam-sunshine-sync.sh

Standalone and safe to re-run.
- Finds Steam libraries (native or Flatpak) via `libraryfolders.vdf` and games via `appmanifest_*.acf`.
- Lets the user pick games in a whiptail/dialog checklist (with a plain fallback) and saves the selection under `~/.config/steam-sunshine-sync/`.
- Rewrites only its own slice of Sunshine's `apps.json`: entries whose `detached` command contains `steam://rungameid/`. Hand-added apps are never touched.
- Entries get niri workspace switching (`prep-cmd`), optional Steam quit on stream end, and cover art from Steam's CDN.
- Installs its own dependencies (`jq`, whiptail) via dnf.
