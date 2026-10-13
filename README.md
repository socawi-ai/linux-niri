# Linux Niri Setup

Personal setup scripts for a Niri desktop on Fedora.

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
- VS Code, Steam (RPM Fusion), gamescope, Plymouth spinner
- Flatpak + Flathub; Proton Mail, LocalSend, ProtonUp-Qt from Flathub
- Hardware-watchdog module blacklist, to silence a common "watchdog did not
  stop" shutdown warning

It also deploys this repo's configs and wallpapers to `~/.config`,
`~/.local/state`, and the user's pictures folder.

At the end it runs this repo's other setup scripts (each also works on its
own, see below). Turn any of them off with its variable:

- `INSTALL_REFIND=0`: the themed rEFInd boot menu (`fedora-refind-setup.sh`)
- `INSTALL_LSFG_VK=0`: lsfg-vk frame generation (`install-lsfg-vk.sh`)
- `INSTALL_SUNSHINE=0`: the Sunshine streaming host (`install-sunshine.sh`)
- `INSTALL_STEAM_SUNSHINE_SYNC=0`: the game picker that adds installed Steam
  games to Sunshine (`steam-sunshine-sync.sh`). It shows on the terminal and
  isn't in the log. Right after a fresh install there are no games yet, so
  it just notes that; run the installer again, or the script on its own,
  once games are installed.

If one of them fails, the setup warns and finishes the rest; fix the problem
and run that script on its own.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/fedora-niri-setup.sh -o fedora-niri-setup.sh
chmod +x fedora-niri-setup.sh
./fedora-niri-setup.sh
```

Run from a terminal, it first opens a menu (same look as the Steam game
picker) where you tick the optional features: Steam, gamescope, LACT, VS Code,
Flatpak and the Flatpak apps, cursors, the login screen, Plymouth, the
watchdog fix, rEFInd, lsfg-vk, Sunshine and the Steam game sync. Niri,
Noctalia, the base packages and the configs are always installed. A
confirmation screen shows what will and won't be installed before anything
changes; Quit leaves the machine untouched.

Each feature also has an environment variable (see the top of the script).
They set what's pre-ticked in the menu, and are used as they are with
`--no-menu` (or `SETUP_MENU=0`), or when there's no terminal.

Unattended: `env TARGET_USER=your-user ASSUME_YES=1 ./fedora-niri-setup.sh --no-menu`

## Fedora rEFInd boot theme (optional)

`fedora-refind-setup.sh` gives a UEFI Fedora machine a themed
[rEFInd](https://www.rodsbooks.com/refind/) boot screen
([rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils)). Additive and
standalone: installs rEFInd as a new firmware boot entry alongside Fedora's
existing one, chainloads into Fedora's own shim/GRUB/kernel chain, and hides
GRUB's menu so rEFInd is the only one you see. `fedora-niri-setup.sh` runs
it by default; once it has run, re-running `fedora-niri-setup.sh` leaves
GRUB's timeout alone.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/fedora-refind-setup.sh -o fedora-refind-setup.sh
chmod +x fedora-refind-setup.sh
./fedora-refind-setup.sh
```

## Frame generation and streaming

- `install-lsfg-vk.sh` builds and installs
  [lsfg-vk](https://lsfg-vk.dev) (Lossless Scaling frame generation for
  Vulkan games). Needs Lossless Scaling bought and installed on Steam.
- `install-sunshine.sh` installs [Sunshine](https://github.com/LizardByte/Sunshine)
  from LizardByte's COPR, sets the capture output (`DP-2` by default, override
  with `SUNSHINE_CAPTURE_OUTPUT`) and starts it on login. Open
  https://localhost:47990 once afterwards to create Sunshine's admin login.
- `steam-sunshine-sync.sh` adds installed Steam games (native or Flatpak) to
  Sunshine, with cover art. Run it again whenever games change; `--select`
  opens the game picker, `--help` shows the rest.

## Backups

Each script backs up replaced files before touching them, and writes a
timestamped log to the user's home directory.

- Fedora: `~/.local/share/fedora-niri-setup/backups/` (user),
  `/var/backups/fedora-niri-setup/` (system)
- rEFInd setup: `/var/backups/fedora-refind-setup/` (system only)
