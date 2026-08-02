# Linux Niri Setup

Personal setup scripts for a Niri desktop on Fedora and Arch Linux.

This is in testing. Read the script before running it, and only run it on a system you
are prepared to repair.

Run as your normal user, not with `sudo`. The scripts ask for sudo when needed.

All scripts below work the same on a terminal-only machine (SSH session,
bare TTY console — no browser needed) as they do in a desktop terminal:
download the script, mark it executable, then run it. This works the same in
fish, zsh, or bash as your login shell, and the scripts read their yes/no
prompts from `/dev/tty` directly rather than stdin, so it's safe to run over
SSH.

## Fedora

`fedora-niri-setup.sh` installs and configures:

- Niri
- Noctalia v5
- Noctalia Greeter
- greetd
- Alacritty
- Nautilus
- Fish
- Firefox
- PipeWire
- pavucontrol
- desktop portals
- GTK/Qt Wayland support
- McMojave cursors
- Nautilus Open Any Terminal, set to Alacritty
- LACT, with the `lactd` service enabled, for AMD/Nvidia/Intel GPU control
- VS Code
- Steam from RPM Fusion, not Flatpak
- Polaris with host setup and user-service autostart
- Plymouth spinner
- GRUB timeout

It also downloads this repo's configs and wallpapers:

- `alacritty/` -> `~/.config/alacritty`
- `niri/` -> `~/.config/niri`
- `polaris/` -> `~/.config/polaris`
- `noctalia/` -> `~/.local/state/noctalia`
- `wallpapers/` -> the user's localized pictures folder

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/fedora-niri-setup.sh -o fedora-niri-setup.sh
chmod +x fedora-niri-setup.sh
./fedora-niri-setup.sh
```

Unattended run:

```bash
env TARGET_USER=your-user ASSUME_YES=1 ./fedora-niri-setup.sh
```

## Arch Linux

`arch-niri-setup.sh` installs the same desktop as the Fedora script, adapted
to pacman/AUR and an already-installed Limine bootloader:

- Niri, greetd, Alacritty, Nautilus, Fish, Firefox, PipeWire, pavucontrol,
  desktop portals, GTK/Qt Wayland support — all from the official repos
- Noctalia v5 and Noctalia Greeter, from the AUR (`noctalia-git` /
  `noctalia-greeter-git`, the bleeding-edge variants, matching the Fedora
  script's COPR choice)
- McMojave cursors
- Nautilus Open Any Terminal (AUR), set to Alacritty
- LACT, with the `lactd` service enabled, for AMD/Nvidia/Intel GPU control
  (official repo — no AUR needed)
- VS Code (AUR, `visual-studio-code-bin`)
- Steam, via the `multilib` repo (enabled automatically if needed)
- Polaris with host setup and user-service autostart
- Automatic pre/post Snapper snapshots on every pacman transaction
  (`snap-pac`), and Snapper snapshots exposed as bootable Limine menu
  entries (`limine-snapper-sync`) — both optional, and both skipped
  gracefully if Snapper + btrfs aren't already set up. If `limine.conf` is
  missing the `/Snapshots` placeholder `limine-snapper-sync` needs, the
  script backs it up and appends a top-level `/Snapshots` block (safe —
  doesn't touch any existing entry) rather than leaving it broken.

An AUR helper (`paru` by default; `yay` also supported via `AUR_HELPER=yay`)
is bootstrapped automatically from the AUR itself if not already installed.

Limine itself is otherwise assumed already installed and preconfigured (e.g.
via `archinstall`), which is also assumed to already own boot splash —
Plymouth, `mkinitcpio` HOOKS, and kernel-cmdline changes are all out of
scope for the same reason.

It downloads the same repo configs and wallpapers as the Fedora script (see
above).

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/arch-niri-setup.sh -o arch-niri-setup.sh
chmod +x arch-niri-setup.sh
./arch-niri-setup.sh
```

Unattended run:

```bash
env TARGET_USER=your-user ASSUME_YES=1 ./arch-niri-setup.sh
```

## Backups

The scripts back up most replaced files.

- Fedora: `~/.local/share/fedora-niri-setup/backups/` (user),
  `/var/backups/fedora-niri-setup/` (system)
- Arch: `~/.local/share/arch-niri-setup/backups/` (user),
  `/var/backups/arch-niri-setup/` (system)

Each run also writes a timestamped log file in the user's home directory.
