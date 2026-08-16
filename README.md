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

## Sunshine game streaming (optional)

Two standalone scripts add [Sunshine](https://app.lizardbyte.dev/Sunshine/)
game streaming for your Steam library. Neither is called by the setup
scripts above and neither requires them — both just assume Steam is
already installed.

`install-sunshine-beta.sh` installs Sunshine from each distro's **beta**
channel (LizardByte's `lizardbyte/beta` COPR on Fedora, the `sunshine-git`
AUR package on Arch — not the Flatpak build, since Flatpak's Sunshine
sandbox doesn't support KMS screen capture) and enables it to start on
login:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/install-sunshine-beta.sh -o install-sunshine-beta.sh
chmod +x install-sunshine-beta.sh
./install-sunshine-beta.sh
```

Afterwards, open `https://localhost:47990` once in a browser to set
Sunshine's admin username/password — this one-time step can't be scripted
and Sunshine won't accept connections until it's done.

`steam-sunshine-sync.sh` scans your installed Steam games (including
libraries on other drives, and Flatpak Steam) and syncs a chosen subset
into Sunshine's `apps.json` as `steam://rungameid/<appid>` launchers, with
cover art pulled from Steam's CDN:

```bash
curl -fsSL https://raw.githubusercontent.com/socawi-ai/linux-niri/main/steam-sunshine-sync.sh -o steam-sunshine-sync.sh
chmod +x steam-sunshine-sync.sh
./steam-sunshine-sync.sh
```

The first run (or any run with `--select`) opens a checklist (`whiptail`,
falling back to `dialog`, or a plain numbered prompt if neither is
installed) pre-checked with your current selection, so you choose which
games to sync — nothing is added unconditionally. Use `--list` to print the
current selection without opening the picker. Re-run after installing new
games to add them, or with `--select` to change your selection; it only
ever touches the entries it created, so anything you added to Sunshine by
hand is left alone. See `--help` for all options.

### Streaming at a different resolution than your desktop

If your desktop monitor and streaming target (e.g. a TV) have different
resolutions/aspect ratios (ultrawide desktop, 16:9 TV), run
`./steam-sunshine-sync.sh --settings` to open a settings dialog (same
`whiptail`/`dialog`/plain-prompt picker as game selection) and turn on
resolution switching. Once enabled, **every** synced game switches a given
niri output to a streaming-friendly mode for the duration of the stream and
restores it afterwards — via a `prep-cmd` calling
`niri msg output <name> mode ...`, the same idea as Sunshine's own bundled
"Low Res Desktop" `xrandr` example, adapted for niri. The dialog asks for
the output's connector name (find it with `niri msg outputs`) and the two
modes to switch between; it's persisted to
`~/.config/steam-sunshine-sync/settings.conf` and applied automatically on
every future run — no flag needed after that first `--settings` run.
`NIRI_RESOLUTION_SWITCH`/`NIRI_OUTPUT_NAME`/`NIRI_STREAM_MODE`/`NIRI_NATIVE_MODE`
env vars are also available for scripting and always override whatever's
in the settings file.

## Backups

Each script backs up replaced files before touching them, and writes a
timestamped log to the user's home directory.

- Fedora: `~/.local/share/fedora-niri-setup/backups/` (user),
  `/var/backups/fedora-niri-setup/` (system)
- Arch: `~/.local/share/arch-niri-setup/backups/` (user),
  `/var/backups/arch-niri-setup/` (system)
- rEFInd setup: `/var/backups/fedora-refind-setup/` (system only)
