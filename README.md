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
- VS Code, Steam, Plymouth spinner

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
`archinstall`) and never touches it, **except rEFInd, which it requires**:
the script checks for an existing `refind.conf` right at the start and
refuses to run if it can't find one (set `INSTALL_REFIND_THEME=0` to run
without rEFInd at all). It only ever themes an existing rEFInd install —
never installs rEFInd itself or touches its existing menu entries/scan
config, beyond adding the theme and setting an explicit `resolution` (fixes
distorted banner/icons under the theme; set
`REFIND_RESOLUTION_WIDTH`/`HEIGHT=""` to leave your existing setting alone).

- Niri, greetd, Alacritty, Nautilus, Fish, Firefox, PipeWire, pavucontrol,
  desktop portals, GTK/Qt Wayland support — official repos
- Flatpak + Flathub; Proton Mail, LocalSend, ProtonUp-Qt from Flathub
- [arch-update](https://github.com/Antiz96/arch-update) with its update
  timer, from the AUR
- Noctalia v5 + Greeter (stable, AUR), McMojave cursors (AUR), Nautilus Open
  Any Terminal (AUR), LACT (official repo), VS Code (AUR)
- Steam (via `multilib`)
- [rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils) theme (required, see
  above) — plus a hardware-watchdog module blacklist to silence a common
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

## archinstall profile (optional)

`archinstall/user_configuration.json` reproduces this machine's base-system
choices in [archinstall](https://github.com/archlinux/archinstall) (v4.4+):
disk layout (btrfs on a single NVMe drive, `@`/`@home`/`@log`/`@pkg`
subvolumes, zstd compression), rEFInd as the bootloader (archinstall installs
and configures it directly — no UKI, Plymouth's `spinner` theme), zram swap,
Swedish locale/timezone, and NetworkManager. It does **not** cover the
desktop — that's still `arch-niri-setup.sh` above, run after first boot.

**This wipes `/dev/nvme0n1`.** Check `lsblk` on the target machine first and
edit `disk_config.device_modifications[0].device` in the JSON if the disk
differs from this one.

On the Arch ISO (`git` is preinstalled there):

```bash
git clone https://github.com/socawi-ai/linux-niri.git
cd linux-niri
lsblk                                          # confirm the disk target above
archinstall --config archinstall/user_configuration.json
```

Deliberately not `--silent`, and no credentials file: every guided screen is
pre-filled from the config but still shown for review before anything is
written, and you type the username/password directly when archinstall asks
for them — nothing sensitive ever needs to live in this repo.

The live ISO's filesystem doesn't survive the reboot into the new install, so
clone the repo again afterwards to run `arch-niri-setup.sh` for the desktop
layer:

```bash
git clone https://github.com/socawi-ai/linux-niri.git
cd linux-niri
./arch-niri-setup.sh
```

## Polaris game streaming (optional)

`install-polaris.sh` installs [Polaris](https://github.com/papi-ux/polaris)
(a self-hosted GameStream host for Nova and Moonlight-compatible clients)
from the latest GitHub release, verifying each downloaded package against
the sha256 digest GitHub publishes for it before installing. Not called by
the setup scripts above and doesn't require them — just assumes Steam is
already installed if you plan to stream it. Fedora gets the
`Polaris-fedoraNN-x86_64.rpm` asset matching your Fedora version (falling
back to whatever build is published, with a warning, if Polaris hasn't cut
one for your exact release yet); Arch gets `Polaris-arch-x86_64.pkg.tar.zst`
via `pacman -U`. Both run `sudo -H polaris --setup-host` and enable the
`polaris` user service to start on login:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/install-polaris.sh -o install-polaris.sh
chmod +x install-polaris.sh
./install-polaris.sh
```

Afterwards, open `https://localhost:47990` once in a browser to create the
web account and pair a client (Nova or Moonlight) — this one-time step
can't be scripted. Steam games don't need a separate sync script: add them
from the web UI's Applications tab (built-in library scan, optional
SteamGridDB cover art), or launch Steam Big Picture directly. If capture
doesn't work out of the box, see
[the Polaris configuration docs](https://papi-ux.com/docs/configuration/)
about `POLARIS_ENABLE_KMS=1` (re-run the script) or
`sudo -H polaris --setup-host --enable-kms` manually — off by default since
it's explicitly situational, not a universal requirement.

## Backups

Each script backs up replaced files before touching them, and writes a
timestamped log to the user's home directory.

- Fedora: `~/.local/share/fedora-niri-setup/backups/` (user),
  `/var/backups/fedora-niri-setup/` (system)
- Arch: `~/.local/share/arch-niri-setup/backups/` (user),
  `/var/backups/arch-niri-setup/` (system)
- rEFInd setup: `/var/backups/fedora-refind-setup/` (system only)
