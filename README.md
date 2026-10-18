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
- Hardware-watchdog module blacklist, to silence a common "watchdog did not
  stop" shutdown warning

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
config, beyond adding the theme, setting an explicit `resolution` (fixes
distorted banner/icons under the theme; set
`REFIND_RESOLUTION_WIDTH`/`HEIGHT=""` to leave your existing setting alone),
and setting `use_graphics_for osx,linux` (keeps the graphical theme on
screen through the Linux boot handoff instead of dropping to a text console;
set `REFIND_USE_GRAPHICS_FOR=""` to leave your existing setting alone).

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

## Sunshine game streaming (optional, standalone)

`install-sunshine.sh` installs [Sunshine](https://github.com/LizardByte/Sunshine)
(a self-hosted Moonlight streaming host) from each distro's stable channel and
enables it to start on login:

- Fedora: LizardByte's own COPR, stable channel
- Arch: the AUR's stable `sunshine` package, via an AUR helper (`paru` by
  default, `yay` supported) — bootstrapped from the AUR if missing

Installs the native package rather than Flatpak: Flatpak's Sunshine sandbox
doesn't support the KMS screen capture this repo's bare-Wayland/niri sessions
need. Also sets the capture output (`output_name`) to `DP-2` by default —
override with `SUNSHINE_CAPTURE_OUTPUT` if that's not the right connector on
your machine (`niri msg outputs` lists them).

Fully standalone: not called by `fedora-niri-setup.sh`/`arch-niri-setup.sh`,
and doesn't require either to have run first.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/install-sunshine.sh -o install-sunshine.sh
chmod +x install-sunshine.sh
./install-sunshine.sh
```

One manual step Sunshine itself requires: open https://localhost:47990 and
set the initial admin username/password — it won't accept streaming
connections until that's done.

## Steam library → Sunshine sync (optional, standalone)

`steam-sunshine-sync.sh` scans your installed Steam games and syncs a chosen
subset into Sunshine's `apps.json` as `steam://rungameid/<appid>` launchers,
with cover art pulled from Steam's public CDN. Safe to re-run any time — it
only touches its own slice of `apps.json` (entries whose "detached" command
contains `steam://rungameid/`), so hand-added Sunshine apps are left alone,
and uninstalled games silently drop out on the next sync.

Also switches niri to a dedicated streaming workspace (`Stream` by default)
via Sunshine's `prep-cmd` when a stream starts, and back to your native
workspace (`Games` by default) when it ends.

Requires Steam and Sunshine already installed. Doesn't require
`install-sunshine.sh` or either setup script to have run first.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/steam-sunshine-sync.sh -o steam-sunshine-sync.sh
chmod +x steam-sunshine-sync.sh
./steam-sunshine-sync.sh
```

## lsfg-vk frame generation (optional, standalone, Fedora only)

`install-lsfg-vk.sh` builds and installs [lsfg-vk](https://lsfg-vk.dev) from
source: a Vulkan layer that runs Lossless Scaling's frame-generation
algorithm on Linux, following the official Fedora build-from-source guide.
It also registers the installed library with `ldconfig` if Fedora's default
library search path doesn't already cover it — `/usr/local/lib64` isn't
scanned by default, which otherwise silently breaks the layer for every
Vulkan app, not just one game — and functionally verifies the fix with a
`vkcube` test run rather than trusting a file-presence check alone.

Requires [Lossless Scaling](https://store.steampowered.com/app/993090)
purchased and installed through Steam, switched to its `lsfg-vk` beta branch:
lsfg-vk is a re-implementation of its Vulkan layer, not a replacement for the
app, and needs the `lsfg-vk.dll` file that ships inside it. That Steam-side
step can't be scripted.

Arch has its own AUR packages (`lsfg-vk` / `lsfg-vk-bin` / `lsfg-vk-git`) and
doesn't need this script.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/install-lsfg-vk.sh -o install-lsfg-vk.sh
chmod +x install-lsfg-vk.sh
./install-lsfg-vk.sh
```

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

## Backups

Each script backs up replaced files before touching them, and writes a
timestamped log to the user's home directory.

- Fedora: `~/.local/share/fedora-niri-setup/backups/` (user),
  `/var/backups/fedora-niri-setup/` (system)
- Arch: `~/.local/share/arch-niri-setup/backups/` (user),
  `/var/backups/arch-niri-setup/` (system)
- rEFInd setup: `/var/backups/fedora-refind-setup/` (system only)

## License

Licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). You may use, change and share it; if you share a changed version, or run one as a network service for others, you must make its source available under the same license.

Third-party files keep their own licenses.
