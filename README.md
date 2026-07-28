# Linux Niri Setup

Personal setup script for a Niri desktop on Fedora.

This is in testing. Read the script before running it, and only run it on a system you
are prepared to repair.

Run as your normal user, not with `sudo`. The script asks for sudo when needed.

Both scripts below work the same on a terminal-only machine (SSH session,
bare TTY console — no browser needed) as they do in a desktop terminal:
download the script, mark it executable, then run it. This works the same in
fish, zsh, or bash as your login shell, and both scripts read their yes/no
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

## rEFInd boot manager

`refind-migrate.sh` is a separate, standalone script — run it independently of
`fedora-niri-setup.sh`, and re-run it on its own if something needs fixing.
Bootloader changes are riskier than desktop setup, so they're kept out of the
main script entirely.

It installs [rEFInd](https://www.rodsbooks.com/refind/) as the primary UEFI
boot manager. This does **not** replace GRUB or touch how Linux boots: GRUB
stays installed exactly as it is, and rEFInd simply chainloads into it (its
normal boot-loader scan finds the existing GRUB EFI binary and offers it as a
menu entry). GRUB itself is reconfigured for an instant, silent boot
(`GRUB_TIMEOUT=0`, hidden menu), so in practice: firmware -> rEFInd -> GRUB ->
Linux, with no visible menus unless you interact with rEFInd's own timeout.

It also installs the [rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils)
visual theme by default, since rEFInd's menu is the only boot menu you'll
actually see.

Have a Fedora live USB ready before running this, in case of boot failure.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/refind-migrate.sh -o refind-migrate.sh
chmod +x refind-migrate.sh
./refind-migrate.sh
```

Unattended run:

```bash
env ASSUME_YES=1 ./refind-migrate.sh
```

Skip the theme:

```bash
env INSTALL_REFIND_THEME=0 ./refind-migrate.sh
```

If Secure Boot is enabled, rEFInd is self-signed with a locally generated key
(Fedora's rEFInd package isn't signed with the Fedora Secure Boot key), and
the script prints the exact `mokutil --import` command to enroll it after the
run finishes.

Recovery: GRUB is never modified or removed beyond its timeout, so if rEFInd
fails to start, use your firmware's boot menu (usually F12, F11, Esc, or Del
at power-on) to select the original GRUB boot entry directly — no live media
needed.

## Backups

The scripts back up most replaced files.

- user backups: `~/.local/share/fedora-niri-setup/backups/`
- system backups: `/var/backups/fedora-niri-setup/`

Each run also writes a timestamped log file in the user's home directory.
