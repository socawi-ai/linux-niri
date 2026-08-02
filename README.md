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
to pacman/AUR. It never installs or configures the bootloader itself
(whatever it is — Limine, rEFInd, GRUB, etc.), Plymouth, `mkinitcpio` HOOKS,
or kernel-cmdline settings; all of that is assumed already installed and
preconfigured (e.g. via `archinstall`):

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
- The [rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils) visual theme, if
  rEFInd is in use: `refind.conf` is located by searching `/boot`,
  `/boot/efi`, `/efi`, and any mounted vfat filesystem (or `REFIND_CONF_PATH`
  if set explicitly), the theme is cloned into `themes/rEFInd-nils` next to
  it, and a matching `include` line is appended to `refind.conf` if not
  already present. If not on UKI, it also copies the theme's
  `icons/os_arch.png` to `/boot/.VolumeIcon.png` — the file rEFInd looks for
  to show a proper Arch icon on loose-kernel (non-UKI) boot entries, rather
  than a generic Linux icon. Skipped gracefully if `refind.conf` can't be
  found (e.g. a different bootloader is in use) — set `INSTALL_REFIND_THEME=0`
  to disable it outright.
- `nowatchdog` added to every boot option line in `/boot/refind_linux.conf`
  (non-UKI rEFInd only), suppressing the harmless but noisy "watchdog did not
  stop" shutdown warning some hardware watchdog chips produce. This is a
  hardware-specific tweak, not a universal need — set
  `DISABLE_HARDWARE_WATCHDOG=0` if your machine doesn't hit it.

An AUR helper (`paru` by default; `yay` also supported via `AUR_HELPER=yay`)
is bootstrapped automatically from the AUR itself if not already installed.

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
