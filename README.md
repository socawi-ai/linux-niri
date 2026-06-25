# Arch Niri Setup

`arch-niri-setup.sh` configures an already-installed Arch Linux system as a Niri desktop. It is written for an existing Btrfs/Snapper/Limine install and is intentionally conservative: it backs up files before editing them, logs its work, and keeps package names and machine-specific paths overrideable.

Run it as your normal user, not with `sudo`. The script asks for sudo only when it needs to change system files, install packages, or enable services.

By default, the script starts as a guided installer. It asks which existing local user should receive the desktop configs, then asks about optional pieces like Steam/multilib, greetd, Plymouth, Polaris, Snapper hooks, and conflicting display-manager handling. It still lets `pacman`, `paru`, and `makepkg` ask about package conflicts, providers, replacements, and optional selections.

Current release note: `v1.1` adds Nautilus SMB share browsing support and `.local` mDNS name resolution through Avahi and `nss-mdns`.

## What It Does

- Enables `multilib` when needed for Steam.
- Installs official Arch packages for Niri, greetd, Alacritty, JetBrains Mono, Fish, Firefox, GitHub CLI, Steam, GPU-matched Steam Vulkan providers, Xwayland Satellite, Nautilus, Nautilus SMB browsing support, GNOME Software, Bitwarden, Plymouth, Snapper support, GNOME utilities, portals, Avahi `.local` discovery, and PipeWire audio support.
- Bootstraps Paru from the AUR if Paru is missing.
- Installs configurable AUR packages for Noctalia v5, Noctalia Greeter, McMojave cursors, Visual Studio Code, `nautilus-open-any-terminal`, and `lsfg-vk-git`.
- Installs Polaris from the upstream Arch release package, runs `sudo polaris --setup-host`, writes recommended Headless Stream defaults, and tries to enable the Polaris user service.
- Clones or updates `https://github.com/socawi-ai/linux-niri`.
- Installs Alacritty, Niri, and optional Noctalia config from the repo's `noctalia` directory into the selected target user's home directory.
- Installs wallpapers into the localized XDG pictures directory.
- Appends generated Noctalia v5 wallpaper settings to the installed config using the target user's local paths.
- Configures greetd to launch the Noctalia Greeter and enables `greetd.service`.
- Creates a dedicated greetd greeter user if the configured user is missing.
- Disables common conflicting display managers by default when greetd is enabled.
- Configures `/etc/nsswitch.conf` and enables Avahi for `.local` mDNS name resolution.
- Configures Swedish locale and keyboard defaults.
- Configures GTK dark-mode preferences for GTK3, GTK4/libadwaita, and gsettings-aware apps where available.
- Configures Fish as the selected target user's login shell without changing root's shell.
- Installs `snap-pac` only when an existing Snapper config is detected.
- Configures Plymouth spinner boot splash, updates `mkinitcpio`, and adds `splash` plus optional `quiet` to matching Limine Arch entries.
- Configures McMojave cursor defaults system-wide and for the user.

## Run

Download the latest script from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/arch-niri-setup.sh -o arch-niri-setup.sh
chmod +x arch-niri-setup.sh
./arch-niri-setup.sh
```

Or, from a local clone:

```bash
chmod +x arch-niri-setup.sh
./arch-niri-setup.sh
```

The script is designed to be safe to re-run after fixing a package name, service issue, or warning. It prints a final summary with changes, warnings, log location, and backup locations.

Status output is colored in interactive terminals. Set `NO_COLOR=1` before running the script if you prefer plain output.

For an unattended run, set `ASSUME_YES=1`. This accepts the script defaults for prompts, so prompts with a default of no still resolve to no:

```bash
TARGET_USER=user ASSUME_YES=1 ./arch-niri-setup.sh
```

If multiple Limine entries match, `ASSUME_YES=1` will not guess. Set `LIMINE_DEFAULT_ENTRY` explicitly for that run.

## Important Overrides

Set overrides before the command:

```bash
AUR_PACKAGE_NOCTALIA=noctalia-git \
AUR_PACKAGE_NOCTALIA_GREETER=noctalia-greeter-git \
NOCTALIA_GREETER_COMMAND='/usr/bin/noctalia-greeter-session -- --session niri' \
LIMINE_DEFAULT_ENTRY='Arch Linux' \
./arch-niri-setup.sh
```

Common variables:

- `CONFIG_REPO_URL`: defaults to `https://github.com/socawi-ai/linux-niri`
- `CONFIG_REPO_DIR`: defaults to the selected target user's `~/.cache/arch-niri-setup/linux-niri`
- `TARGET_USER`: defaults to `SUDO_USER` or the current user; guided mode asks for this
- `AUR_PACKAGE_PARU`: defaults to `paru`
- `AUR_PACKAGE_NOCTALIA`: defaults to `noctalia-git`
- `AUR_PACKAGE_NOCTALIA_GREETER`: defaults to `noctalia-greeter-git`
- `AUR_PACKAGE_NAUTILUS_OPEN_ANY_TERMINAL`: defaults to `nautilus-open-any-terminal-git`
- `AUR_PACKAGE_MCMOJAVE_CURSORS`: defaults to `mcmojave-cursors`
- `AUR_PACKAGE_VSCODE`: defaults to `visual-studio-code-bin`
- `AUR_PACKAGE_LSFG_VK`: defaults to `lsfg-vk-git`
- `NOCTALIA_GREETER_SESSION_BIN`: defaults to `/usr/bin/noctalia-greeter-session`
- `NOCTALIA_GREETER_COMMAND`: defaults to `/usr/bin/noctalia-greeter-session -- --session niri`
- `GREETD_USER`: defaults to `greeter`
- `PLYMOUTH_THEME`: defaults to `spinner`
- `LIMINE_CONFIG`: defaults to `/boot/limine/limine.conf`
- `LIMINE_ARCH_ENTRY_MATCH`: defaults to `Arch Linux`
- `LIMINE_DEFAULT_ENTRY`: empty by default; set it when multiple Limine entries match
- `POLARIS_PACKAGE_URL`: defaults to the latest upstream Arch release package
- `POLARIS_ENCODER`: defaults to `nvenc`; set to `vaapi` or `software` for other hardware
- `POLARIS_TRUSTED_SUBNETS`: defaults to `["10.0.0.0/24"]`
- `POLARIS_MAX_SESSIONS`: defaults to `2`
- `ENABLE_QUIET_KERNEL_ARG`: defaults to `1`
- `ENABLE_GREETD`, `ENABLE_PLYMOUTH`, `ENABLE_SNAPSHOTS`, `ENABLE_POLARIS`: default to `1`
- `ENABLE_POLARIS_USER_SERVICE`: defaults to `1`
- `INSTALL_STEAM`: defaults to `1`; if multilib is declined, Steam is skipped for that run
- `ASSUME_YES`: defaults to `0`; set to `1` for unattended defaults
- `DISABLE_CONFLICTING_DISPLAY_MANAGERS`: defaults to `1`
- `SWEDISH_LOCALE`: defaults to `sv_SE.UTF-8`
- `CONSOLE_KEYMAP`: defaults to `sv-latin1`
- `XKB_LAYOUT`: defaults to `se`
- `CURSOR_THEME`: defaults to `McMojave-cursors`
- `WALLPAPER_PARENT_DIR`: empty by default; derived from the locale, with Swedish using `~/Bilder`
- `WALLPAPER_SUBDIR`: defaults to `wallpapers`
- `NOCTALIA_WALLPAPER_FILE`: defaults to `10.jpg`
- `GTK_COLOR_SCHEME`: defaults to `prefer-dark`
- `GTK_THEME_NAME`: defaults to `Adwaita-dark`
- `GTK_APPLICATION_PREFER_DARK`: defaults to `1`
- `EXTRA_OFFICIAL_PACKAGES` and `EXTRA_AUR_PACKAGES`: optional space-separated package lists

## Backups And Logs

The log file is written to:

```bash
~/arch-niri-setup-YYYYMMDD-HHMMSS.log
```

User file backups are stored under:

```bash
~/.local/share/arch-niri-setup/backups/YYYYMMDD-HHMMSS/
```

System file backups are stored under:

```bash
/var/backups/arch-niri-setup/YYYYMMDD-HHMMSS/
```

To recover manually, inspect the final summary or log, then copy the backed-up file or directory back to its original path. Use `sudo cp -a` for files under `/etc`, `/usr`, `/boot`, or `/var`.

## Limine Notes

The script edits `cmdline:`/`kernel_cmdline:` entries in modern Limine configs and `CMDLINE=`/`KERNEL_CMDLINE=` entries in older-style configs. It adds missing `splash` and, by default, `quiet`.

If more than one entry matches `LIMINE_ARCH_ENTRY_MATCH` and `LIMINE_DEFAULT_ENTRY` is not set, the script lists the matches and asks which exact entry to configure. If you leave the answer blank, it skips the Limine edit. For unattended runs, set `LIMINE_DEFAULT_ENTRY` explicitly.

If no Limine entries match but the config contains `cmdline`/`CMDLINE` lines, the script asks whether to update all of those command lines. If the config contains no editable command line at all, it warns and skips the Limine edit.

## What It Intentionally Does Not Do

- It does not install Arch Linux.
- It does not repartition disks.
- It does not format filesystems.
- It does not create or recreate Btrfs subvolumes.
- It does not recreate or overwrite Snapper configs.
