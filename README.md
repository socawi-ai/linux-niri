# Linux Niri Setup

Personal setup scripts for a Niri desktop on Arch Linux and Fedora.

This is in testing. Read the script before running it, and run it only on a system you
are prepared to repair if a package name, service, or display-manager setup is wrong.

Run scripts as your normal user, not with `sudo`. The scripts ask for sudo when they
need to install packages or change system files.

## Scripts

### Arch

`arch-niri-setup.sh` is the fuller setup script.

It installs and configures:

- Niri
- greetd
- Noctalia v5
- Noctalia Greeter
- Alacritty
- Fish
- Firefox
- Nautilus
- PipeWire
- desktop portals
- GTK/Qt Wayland support
- Avahi and `.local` name resolution
- optional Steam support
- optional Polaris support
- optional Snapper hooks
- optional Plymouth/Limine boot splash setup

It also copies this repo's Niri, Alacritty, Noctalia, and wallpaper configs into the
target user's home directory.

Run:

```bash
chmod +x arch-niri-setup.sh
./arch-niri-setup.sh
```

For an unattended run:

```bash
TARGET_USER=your-user ASSUME_YES=1 ./arch-niri-setup.sh
```

### Fedora

`fedora-niri-setup.sh` is newer and more minimal.

It currently installs and configures the core desktop pieces:

- Niri
- greetd
- Noctalia v5
- Noctalia Greeter
- Alacritty
- Fish
- Firefox
- Nautilus
- PipeWire
- desktop portals
- GTK/Qt Wayland support
- basic GTK dark-mode settings

It enables the configured COPR for Noctalia packages, installs Noctalia v5 and the
Noctalia Greeter, configures Niri to autostart Noctalia, and configures greetd to launch
the Noctalia Greeter with Niri as the default session.

It also clones or updates this repo, installs the Alacritty, Niri, and Noctalia configs,
and copies the `wallpapers` folder into the target user's localized pictures directory.
Noctalia v5 settings are installed under `~/.config/noctalia/settings.toml`.

Run:

```bash
chmod +x fedora-niri-setup.sh
./fedora-niri-setup.sh
```

For an unattended run:

```bash
TARGET_USER=your-user ASSUME_YES=1 ./fedora-niri-setup.sh
```

## Backups

The scripts back up files before replacing most existing user or system config.

Arch backups:

- user files: `~/.local/share/arch-niri-setup/backups/`
- system files: `/var/backups/arch-niri-setup/`

Fedora backups:

- user files: `~/.local/share/fedora-niri-setup/backups/`
- system files: `/var/backups/fedora-niri-setup/`

Each run also writes a timestamped log file in the user's home directory.

## Notes

- The Fedora script is especially early testing.
- The Fedora script does not yet include the full Arch feature set.
- Package names may need adjustment as Fedora, COPR, AUR, and upstream packages change.
- Existing display managers can conflict with greetd. The scripts may offer to disable
  them when configuring greetd.
