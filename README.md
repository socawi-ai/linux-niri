# Linux Niri Setup

Personal setup for a Niri desktop on Fedora: one installer,
`fedora-niri-setup.sh`, plus `steam-sunshine-sync.sh` to run once Steam is set
up.

This is in testing. Read the script before running it, and only run it on a system you
are prepared to repair.

Run as your normal user, not with `sudo`. The scripts ask for sudo when needed.

Works the same over SSH/bare TTY as in a desktop terminal: download, `chmod +x`, run.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/fedora-niri-setup.sh -o fedora-niri-setup.sh
chmod +x fedora-niri-setup.sh
./fedora-niri-setup.sh
```

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
- A themed [rEFInd](https://www.rodsbooks.com/refind/) boot menu
  ([rEFInd-nils](https://github.com/NilsPvR/rEFInd-nils)) that boots the
  kernels directly, with GRUB kept as a fallback. UEFI with Secure Boot off only
- [lsfg-vk](https://lsfg-vk.dev) frame generation, built from source
- The [Sunshine](https://github.com/LizardByte/Sunshine) streaming host

It also deploys this repo's configs and wallpapers to `~/.config`,
`~/.local/state`, and the user's pictures folder.

Run from a terminal, it first opens a menu that asks for a full install or a config update (see below). For a
full install you then tick the optional features: Steam, gamescope, LACT, VS Code,
Flatpak and the Flatpak apps, cursors, the login screen, Plymouth, the
watchdog fix, rEFInd, lsfg-vk and Sunshine. Niri, Noctalia, the base packages
and the configs are always installed. A confirmation screen shows what will
and won't be installed before anything changes; Quit leaves the machine
untouched.

Each feature also has an environment variable (see the top of the script).
They set what's pre-ticked in the menu, and are used as they are with
`--no-menu` (or `SETUP_MENU=0`), or when there's no terminal.

While it installs, a progress gauge shows the current step instead of every
command's output, which goes to the log (the gauge shows its path; follow it
with `tail -f`). The summary prints on the terminal at the end. Use
`--verbose` (or `PROGRESS_UI=0`) to see the full output instead. The gauge
is skipped with `ASSUME_YES=0`, since the script then asks questions on the
terminal.

Unattended: `env TARGET_USER=your-user ASSUME_YES=1 ./fedora-niri-setup.sh --no-menu`

### Update configs only

Pick "Update configs only" in the menu, or run:

```bash
./fedora-niri-setup.sh --configs-only
```

It fetches this repo and replaces the local niri, Alacritty and Noctalia
configs and the wallpapers with the repo's (the old ones are backed up
first), then re-applies the Noctalia wallpaper settings. Nothing else:
no packages, no system changes, no sudo.

rEFInd, lsfg-vk and Sunshine are set up last. If one of them fails, the
installer warns and finishes the rest; fix the problem and run it again. The
summary at the end lists the manual steps each one leaves.

### rEFInd boot menu

rEFInd becomes the first firmware boot entry and boots the kernels in
`/boot` directly, with no GRUB in between. The newest kernel is the Fedora
entry, and older ones are under F2/Tab. Windows shows up too if it's
installed. Each kernel gets the theme's Fedora icon, and a `kernel-install`
hook in `/etc/kernel/install.d/` does the same for new kernels.

rEFInd doesn't read Fedora's boot entries, so the kernel options are kept in
`/boot/refind_linux.conf`, copied from GRUB's default entry on every run. If
you change kernel options with `grubby`, re-run the installer to copy them
over.

GRUB stays installed as the fallback, and shows its menu when it's used. If
rEFInd ever fails, pick "Fedora" in the firmware boot menu (F12/F2 at POST),
which is Fedora's own shim and GRUB, left untouched. To undo, remove the
rEFInd entry with the `efibootmgr` command shown in the summary.

Requirements:
- **Secure Boot off.** This rEFInd is unsigned. Fedora's shim also can't load
  rEFInd 0.14.2, because of a misaligned section in rEFInd's binary
  ([rhboot/shim#803](https://github.com/rhboot/shim/issues/803)). With
  Secure Boot on, the installer skips rEFInd, removes any old rEFInd boot
  entries, and GRUB stays the boot menu.
- **`/boot` on its own ext4 partition**, which is Fedora's default layout.

Running it again on a machine set up by an earlier version (rEFInd through
shim) converts it. The leftover rEFInd boot entries and files are removed.

### lsfg-vk

Needs Lossless Scaling bought and installed on Steam, switched to its
`lsfg-vk` beta branch. Re-running the installer updates and rebuilds lsfg-vk.
Fedora doesn't search `/usr/local/lib64` for libraries, so the installer
registers the layer's library directory in `/etc/ld.so.conf.d/lsfg-vk.conf`
and then runs `vkcube` briefly to check that the Vulkan loader loads the layer.

### Sunshine

Installed from LizardByte's COPR, with the capture output set (`DP-2` by
default, override with `SUNSHINE_CAPTURE_OUTPUT`), and started on login.
Open https://localhost:47990 once afterwards to create Sunshine's admin login.

## Add Steam games to Sunshine

`steam-sunshine-sync.sh` adds installed Steam games (native or Flatpak) to
Sunshine, with cover art. The installer doesn't run it, because it needs you
logged in to Steam with games installed. Run it then, and again whenever your
games change:

```bash
bash ~/.cache/fedora-niri-setup/linux-niri/steam-sunshine-sync.sh --select
```

`--select` opens the game picker, `--help` shows the rest.

## Backups

The installer backs up replaced files before touching them, and writes a
timestamped log to the user's home directory.

- User files: `~/.local/share/fedora-niri-setup/backups/`
- System files: `/var/backups/fedora-niri-setup/`
- Machines set up with the former `fedora-refind-setup.sh` also have
  `/var/backups/fedora-refind-setup/`

## License

Licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). You may use, change and share it; if you share a changed version, or run one as a network service for others, you must make its source available under the same license.

Third-party files keep their own licenses.
