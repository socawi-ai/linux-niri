# Linux Niri Setup

Personal setup scripts for a Niri desktop.

This is in testing. Read the script before running it, and only run it on a system you
are prepared to repair.

Run scripts as your normal user, not with `sudo`. The scripts ask for sudo when needed.

## Fedora

`fedora-niri-setup.sh` is the current focus.

It installs and configures:

- Niri
- Noctalia v5
- Noctalia Greeter
- greetd
- Alacritty
- Nautilus
- Fish
- Firefox
- PipeWire
- desktop portals
- GTK/Qt Wayland support
- McMojave cursors
- Nautilus Open Any Terminal, set to Alacritty
- VS Code
- Steam from RPM Fusion, not Flatpak
- LSFG-VK
- Polaris with host setup and user-service autostart
- Plymouth spinner
- GRUB timeout and the forked dark Sleek GRUB theme in `grub/sleek-dark/`

It also downloads this repo's configs and wallpapers:

- `alacritty/` -> `~/.config/alacritty`
- `niri/` -> `~/.config/niri`
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
TARGET_USER=your-user ASSUME_YES=1 ./fedora-niri-setup.sh
```

## Steam Drive

`mount-steam-drive.sh` is a separate helper for mounting a Steam library drive at
`/mnt/steam`.

It lists available partitions and lets you choose which one to add. The fstab entry
will look like this:

```fstab
UUID=your-selected-uuid /mnt/steam ext4 defaults,noatime 0 2
```

Run:

```bash
chmod +x mount-steam-drive.sh
./mount-steam-drive.sh
```

Unattended run:

```bash
STEAM_DRIVE_UUID=your-uuid ./mount-steam-drive.sh
```

## Arch

`arch-niri-setup.sh` is older and fuller, but Fedora is the current script being worked on.

Run:

```bash
chmod +x arch-niri-setup.sh
./arch-niri-setup.sh
```

## Backups

The scripts back up most replaced files.

Fedora:

- user backups: `~/.local/share/fedora-niri-setup/backups/`
- system backups: `/var/backups/fedora-niri-setup/`

Arch:

- user backups: `~/.local/share/arch-niri-setup/backups/`
- system backups: `/var/backups/arch-niri-setup/`

Each run also writes a timestamped log file in the user's home directory.

## Vendored Theme

`grub/sleek-dark/` is a local copy of the dark Sleek GRUB theme from
`sandesh236/sleek--themes`. Its MIT license is kept with the theme files.
