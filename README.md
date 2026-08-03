# Linux Niri Setup

Personal setup scripts for a Niri desktop on Fedora and Arch Linux.

This is in testing. Read the script before running it, and only run it on a system you
are prepared to repair.

Run as your normal user, not with `sudo`. The scripts ask for sudo when needed.

Works the same over SSH/bare TTY as in a desktop terminal: download, `chmod +x`, run.

## Fedora

`fedora-niri-setup.sh` installs and configures:

- Niri, greetd, Noctalia v5 + Noctalia Greeter
- Alacritty, Nautilus, Fish, Firefox
- PipeWire, pavucontrol, desktop portals, GTK/Qt Wayland support
- McMojave cursors, Nautilus Open Any Terminal (set to Alacritty)
- LACT (`lactd` service), for AMD/Nvidia/Intel GPU control
- VS Code, Steam, Polaris (host setup + autostart), Plymouth spinner

It also deploys this repo's configs and wallpapers to `~/.config`,
`~/.local/state`, and the user's pictures folder.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/fedora-niri-setup.sh -o fedora-niri-setup.sh
chmod +x fedora-niri-setup.sh
./fedora-niri-setup.sh
```

Unattended: `env TARGET_USER=your-user ASSUME_YES=1 ./fedora-niri-setup.sh`

## Fedora rEFInd boot theme (optional)

`fedora-refind-setup.sh` gives a UEFI Fedora machine a themed
[rEFInd](https://www.rodsbooks.com/refind/) boot screen
([rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils)). Additive and
standalone: installs rEFInd as a new firmware boot entry alongside Fedora's
existing one, chainloads into Fedora's own shim/GRUB/kernel chain, and hides
GRUB's menu so rEFInd is the only one you see.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/fedora-refind-setup.sh -o fedora-refind-setup.sh
chmod +x fedora-refind-setup.sh
./fedora-refind-setup.sh
```

## Arch Linux

`arch-niri-setup.sh` installs the same desktop, adapted to pacman/AUR. It
assumes the bootloader is already installed and preconfigured (e.g. via
`archinstall`) and never touches it — except rEFInd, which it themes if
present (skipped gracefully otherwise).

- Niri, greetd, Alacritty, Nautilus, Fish, Firefox, PipeWire, pavucontrol,
  desktop portals, GTK/Qt Wayland support — official repos
- Flatpak + Flathub; Proton Mail, LocalSend, ProtonUp-Qt from Flathub
- [arch-update](https://github.com/Antiz96/arch-update) with its update
  timer, from the AUR
- Noctalia v5 + Greeter (stable, AUR), McMojave cursors (AUR), Nautilus Open
  Any Terminal (AUR), LACT (official repo), VS Code (AUR)
- Steam (via `multilib`), Polaris (host setup + autostart)
- [rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils) theme, if rEFInd is
  detected — plus a hardware-watchdog module blacklist to silence a common
  "watchdog did not stop" shutdown warning

An AUR helper (`paru` by default, `yay` supported) is bootstrapped
automatically if missing. Most behaviors above are toggleable via env vars —
see the script header for the full list.

It downloads the same repo configs and wallpapers as the Fedora script.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/arch-niri-setup.sh -o arch-niri-setup.sh
chmod +x arch-niri-setup.sh
./arch-niri-setup.sh
```

Unattended: `env TARGET_USER=your-user ASSUME_YES=1 ./arch-niri-setup.sh`

## Backups

Each script backs up replaced files before touching them, and writes a
timestamped log to the user's home directory.

- Fedora: `~/.local/share/fedora-niri-setup/backups/` (user),
  `/var/backups/fedora-niri-setup/` (system)
- Arch: `~/.local/share/arch-niri-setup/backups/` (user),
  `/var/backups/arch-niri-setup/` (system)
- rEFInd setup: `/var/backups/fedora-refind-setup/` (system only)
