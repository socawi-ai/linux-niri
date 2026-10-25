#!/usr/bin/env bash
set -Eeuo pipefail

# Scans installed Steam games and syncs a user-chosen subset into Sunshine's
# apps.json as detached "steam://rungameid/<appid>" launchers, with cover
# art pulled from Steam's public CDN (no SteamGridDB account needed).
#
# Fully standalone -- does not require fedora-niri-setup.sh to have been
# run first. Steam and Sunshine are just expected to already be installed
# by the time this runs.
#
# Safe to re-run at any time (e.g. after installing/uninstalling games): it
# only ever touches its own slice of apps.json -- entries whose "detached"
# command contains "steam://rungameid/" -- so hand-added Sunshine apps
# (Desktop, Steam Big Picture, anything else you configured yourself) are
# never modified. Every run fully replaces that slice from the current
# selection + currently-installed games, so an uninstalled game silently
# drops out on the next sync with no separate cleanup step needed.

AUTO_INSTALL_DEPENDENCIES="${AUTO_INSTALL_DEPENDENCIES:-1}"

SUNSHINE_CONFIG_DIR="${SUNSHINE_CONFIG_DIR:-$HOME/.config/sunshine}"
SUNSHINE_APPS_JSON="${SUNSHINE_APPS_JSON:-$SUNSHINE_CONFIG_DIR/apps.json}"
SUNSHINE_COVERS_DIR="${SUNSHINE_COVERS_DIR:-$SUNSHINE_CONFIG_DIR/covers}"
FETCH_COVER_ART="${FETCH_COVER_ART:-1}"
SELECTION_DIR="${SELECTION_DIR:-$HOME/.config/steam-sunshine-sync}"
SELECTION_FILE="${SELECTION_FILE:-$SELECTION_DIR/selected-games.txt}"

# Always on: every synced game switches niri to the streaming workspace via
# prep-cmd when the stream starts, and back to the native workspace when it
# ends -- so Moonlight always lands on the right screen/workspace regardless
# of what was focused beforehand.
NIRI_STREAM_WORKSPACE="${NIRI_STREAM_WORKSPACE:-Stream}"
NIRI_NATIVE_WORKSPACE="${NIRI_NATIVE_WORKSPACE:-Web}"

# Always on: quits Steam via prep-cmd's undo when the stream ends (nothing
# runs on start -- Steam is already up, since it owns the game being
# streamed). Set QUIT_STEAM_ON_STREAM_END=0 to leave Steam running instead.
QUIT_STEAM_ON_STREAM_END="${QUIT_STEAM_ON_STREAM_END:-1}"

# How a synced game is launched. Empty = auto: native Steam ("steam") if it's
# installed, otherwise Flatpak Steam (see resolve_steam_launch_command).
STEAM_LAUNCH_COMMAND="${STEAM_LAUNCH_COMMAND:-}"

# Every write of apps.json keeps a timestamped backup next to it; only the
# newest ones are kept.
APPS_JSON_BACKUPS_TO_KEEP="${APPS_JSON_BACKUPS_TO_KEEP:-5}"

# Native and Flatpak Steam both keep their own separate data directories on
# Linux; check both so it doesn't matter which one games are installed
# through. libraryfolders.vdf inside each then points at any additional
# library folders on other drives/mounts.
STEAM_DATA_DIRS=(
  "$HOME/.local/share/Steam"
  "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

DRY_RUN=0
FORCE_SELECT=0
VERBOSE=0
LIST_ONLY=0
SKIP_IF_NO_GAMES=0

# whiptail's default theme is light text on a blue window, which reads
# poorly in a lot of terminal color schemes -- explicit light theme
# instead: white dialog, black text (readable regardless of terminal
# palette). Buttons/checkboxes and their focused ("act*") counterparts
# previously used shades of gray/blue that were too close in hue to tell
# apart in some terminals; green vs. red gives unambiguous contrast for
# "this is a button" vs. "this is the focused one" regardless of palette.
# Leaves things alone entirely if the user (or their shell rc) already set
# NEWT_COLORS.
NEWT_COLORS="${NEWT_COLORS:-root=,black
window=black,white
border=black,white
title=black,white
label=black,white
listbox=black,white
actlistbox=white,red
checkbox=black,white
actcheckbox=white,red
button=black,green
actbutton=white,red
entry=black,white
textbox=black,white
acttextbox=white,red
helpline=white,black
roottext=white,black}"
export NEWT_COLORS

declare -A GAME_NAME=()
declare -A SELECTED=()
declare -A SELECTED_NAME=()
declare -a CHANGES=()
declare -a WARNINGS=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_DIM=$'\033[2m'
else
  COLOR_RESET=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_DIM=""
fi

log() {
  printf '  %s✓%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

warn() {
  WARNINGS+=("$*")
  printf '  %s⚠%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

die() {
  printf '\n  %s✗  ERROR:%s %s\n\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
  exit 1
}

record_change() {
  CHANGES+=("$*")
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

vlog() {
  [[ "$VERBOSE" == "1" ]] && printf '  %s·%s  %s\n' "$COLOR_DIM" "$COLOR_RESET" "$*" >&2
  return 0
}

usage() {
  cat <<EOF
Usage: steam-sunshine-sync.sh [options]

Scans installed Steam games and syncs a chosen subset into Sunshine's
apps.json as "steam://rungameid/<appid>" launchers, with cover art from
Steam's CDN. Safe to re-run at any time.

The picker is a checklist dialog (whiptail, or dialog if that's what's
installed) -- pre-checked with your current selection, space to toggle,
Enter to confirm. Falls back to a plain numbered prompt if neither is
installed.

Options:
  --select      Open the game picker even if a selection already exists
  --list        Print the current selection and exit (no picker, no sync)
  --no-art      Skip downloading cover art
  --dry-run     Show what would change without writing anything
  --verbose     Print extra diagnostic detail
  --skip-if-no-games
                Exit successfully (with a note) instead of failing when Steam
                or installed games aren't found, e.g. right after a fresh
                install
  -h, --help    Show this help and exit

Config is overridable via environment variables; see the top of this
script for the full list (SUNSHINE_APPS_JSON, SUNSHINE_COVERS_DIR,
SELECTION_FILE, STEAM_LAUNCH_COMMAND, NIRI_STREAM_WORKSPACE,
NIRI_NATIVE_WORKSPACE, QUIT_STEAM_ON_STREAM_END, ...).
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --select) FORCE_SELECT=1 ;;
      --list) LIST_ONLY=1 ;;
      --no-art) FETCH_COVER_ART=0 ;;
      --dry-run) DRY_RUN=1 ;;
      --verbose) VERBOSE=1 ;;
      --skip-if-no-games) SKIP_IF_NO_GAMES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (see --help)." ;;
    esac
    shift
  done
}

suggest_install_cmd() {
  printf 'sudo dnf install %s' "$1"
}

# Maps a generic dependency name to the Fedora package that provides it --
# the package name differs from the command for a couple of these.
package_name_for() {
  local tool="$1"
  case "$tool" in
    imagemagick) printf 'ImageMagick' ;;
    whiptail) printf 'newt' ;;
    *) printf '%s' "$tool" ;;
  esac
}

install_packages() {
  local -a pkgs=("$@")
  ((${#pkgs[@]})) || return 0

  have_command dnf || { warn "dnf was not found; cannot auto-install: ${pkgs[*]}."; return 1; }
  sudo dnf install -y "${pkgs[@]}" || { warn "Could not install: ${pkgs[*]}."; return 1; }

  record_change "Installed: ${pkgs[*]}."
  return 0
}

# Installs the package providing $cmd if it's missing and auto-install is
# enabled. Returns success iff $cmd is available by the time it returns
# (whether it already was, or installing it worked).
ensure_command() {
  local cmd="$1" pkgkey="${2:-$1}"
  have_command "$cmd" && return 0
  [[ "$AUTO_INSTALL_DEPENDENCIES" == "1" ]] || return 1

  log "Installing missing dependency: $cmd."
  install_packages "$(package_name_for "$pkgkey")"
  have_command "$cmd"
}

check_dependencies() {
  local -a still_missing=()
  ensure_command jq || still_missing+=(jq)
  ensure_command curl || still_missing+=(curl)
  ((${#still_missing[@]} == 0)) || die "Missing required command(s): ${still_missing[*]}. Install with: $(suggest_install_cmd "${still_missing[*]}")"

  if [[ "$FETCH_COVER_ART" == "1" ]] && ! have_command magick && ! have_command convert && ! have_command ffmpeg; then
    if [[ "$AUTO_INSTALL_DEPENDENCIES" == "1" ]]; then
      log "Installing missing dependency: ImageMagick (Sunshine needs PNG cover art, Steam's CDN only serves JPG)."
      install_packages "$(package_name_for imagemagick)"
    fi
    if ! have_command magick && ! have_command convert && ! have_command ffmpeg; then
      warn "No image converter available (ImageMagick's magick/convert, or ffmpeg). Cover art will be skipped. Install with: $(suggest_install_cmd "$(package_name_for imagemagick)")"
      FETCH_COVER_ART=0
    fi
  fi
}

# The command a synced game is launched with (followed by
# steam://rungameid/<appid>). Native Steam if installed, otherwise Flatpak
# Steam: games found in the Flatpak data directory can't be started with a
# "steam" command that doesn't exist.
resolve_steam_launch_command() {
  if [[ -n "$STEAM_LAUNCH_COMMAND" ]]; then
    return 0
  fi
  if have_command steam; then
    STEAM_LAUNCH_COMMAND="setsid steam"
  elif have_command flatpak && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
    STEAM_LAUNCH_COMMAND="setsid flatpak run com.valvesoftware.Steam"
  else
    STEAM_LAUNCH_COMMAND="setsid steam"
    warn "Neither native Steam (steam) nor Flatpak Steam was found; games are synced with \"steam\" as the launcher. Set STEAM_LAUNCH_COMMAND if that's wrong."
  fi
  vlog "Steam launch command: $STEAM_LAUNCH_COMMAND"
}

discover_steam_libraries() {
  local -a roots=() libraries=()
  local d
  for d in "${STEAM_DATA_DIRS[@]}"; do
    [[ -d "$d/steamapps" ]] && roots+=("$d")
  done
  # Runs inside < <(...), where die would only end that subshell; with no
  # Steam data at all, discover_installed_games reports it instead.
  ((${#roots[@]})) || return 0

  local root vdf path
  for root in "${roots[@]}"; do
    libraries+=("$root")
    vdf="$root/steamapps/libraryfolders.vdf"
    if [[ -f "$vdf" ]]; then
      while IFS= read -r path; do
        [[ -n "$path" ]] && libraries+=("$path")
      done < <(grep -oP '"path"\s+"\K[^"]+' "$vdf" || true)
    fi
  done

  printf '%s\n' "${libraries[@]}" | sort -u
}

discover_installed_games() {
  local lib manifest appid name installdir
  while IFS= read -r lib; do
    [[ -d "$lib/steamapps" ]] || continue
    for manifest in "$lib"/steamapps/appmanifest_*.acf; do
      [[ -e "$manifest" ]] || continue

      appid="$(basename "$manifest")"
      appid="${appid#appmanifest_}"
      appid="${appid%.acf}"
      [[ "$appid" =~ ^[0-9]+$ ]] || continue

      name="$(grep -m1 -oP '"name"\s+"\K[^"]+' "$manifest" || true)"
      [[ -n "$name" ]] || continue

      installdir="$(grep -m1 -oP '"installdir"\s+"\K[^"]+' "$manifest" || true)"
      if [[ -n "$installdir" && ! -d "$lib/steamapps/common/$installdir" ]]; then
        vlog "Skipping $name ($appid): installdir '$installdir' not found under $lib/steamapps/common (mid-install/uninstall?)."
        continue
      fi

      GAME_NAME["$appid"]="$name"
    done
  done < <(discover_steam_libraries)

  if ((${#GAME_NAME[@]} == 0)); then
    local message="No installed Steam games were found under: ${STEAM_DATA_DIRS[*]} (or the library folders they list)."
    if [[ "$SKIP_IF_NO_GAMES" == "1" ]]; then
      log "$message Nothing to sync yet; run steam-sunshine-sync.sh again after installing games."
      exit 0
    fi
    die "$message"
  fi
  vlog "Discovered ${#GAME_NAME[@]} installed game(s)."
}

load_selection() {
  [[ -f "$SELECTION_FILE" ]] || return 0
  local appid name
  while IFS=$'\t' read -r appid name; do
    [[ -n "$appid" ]] || continue
    SELECTED["$appid"]=1
    SELECTED_NAME["$appid"]="$name"
  done < "$SELECTION_FILE"
}

list_selection() {
  load_selection
  if ((${#SELECTED[@]} == 0)); then
    log "No games selected yet. Run with --select to choose some."
    return 0
  fi

  printf '\n  Selected games (%s), from %s:\n\n' "${#SELECTED[@]}" "$SELECTION_FILE"
  local appid
  while IFS= read -r appid; do
    printf '  - %s (%s)\n' "${SELECTED_NAME[$appid]:-?}" "$appid"
  done < <(printf '%s\n' "${!SELECTED[@]}" | sort -n)
  printf '\n'
}

save_selection() {
  mkdir -p "$SELECTION_DIR"
  local appid
  : > "$SELECTION_FILE.tmp"
  for appid in "${!SELECTED[@]}"; do
    printf '%s\t%s\n' "$appid" "${GAME_NAME[$appid]:-}" >> "$SELECTION_FILE.tmp"
  done
  sort -n -o "$SELECTION_FILE.tmp" "$SELECTION_FILE.tmp"
  mv "$SELECTION_FILE.tmp" "$SELECTION_FILE"
}

# Prints whiptail or dialog, whichever is installed, or nothing. Only
# detects: it's called inside $(...), where anything an install printed
# would end up in the result.
dialog_tool() {
  if have_command whiptail; then
    printf 'whiptail'
  elif have_command dialog; then
    printf 'dialog'
  fi
}

run_picker() {
  local -a appids
  mapfile -t appids < <(printf '%s\n' "${!GAME_NAME[@]}" | sort -n)
  ((${#appids[@]})) || die "No installed Steam games were found."

  # Install whiptail first if neither picker is available (and auto-install
  # is on) -- outside the $(...) below.
  have_command whiptail || have_command dialog || ensure_command whiptail || true

  local tool
  tool="$(dialog_tool)"

  if [[ -z "$tool" ]]; then
    warn "Neither whiptail nor dialog is installed; falling back to a plain numbered picker. Install one with: $(suggest_install_cmd "$(package_name_for whiptail)")"
    run_picker_plain "${appids[@]}"
    return 0
  fi

  run_picker_checklist "$tool" "${appids[@]}"
}

# Checkbox dialog: every game is pre-checked/unchecked to match the current
# selection, so opening it doubles as "see what's currently selected".
# Space toggles, Enter confirms, Esc/Cancel leaves the selection untouched.
run_picker_checklist() {
  local tool="$1"
  shift
  local -a appids=("$@")

  local -a menu_args=()
  local appid status
  for appid in "${appids[@]}"; do
    status="off"
    [[ "${SELECTED[$appid]:-}" == "1" ]] && status="on"
    menu_args+=("$appid" "${GAME_NAME[$appid]}" "$status")
  done

  local list_height=${#appids[@]}
  ((list_height > 15)) && list_height=15
  local box_height=$((list_height + 8))

  local selection
  if ! selection="$("$tool" --title "Steam -> Sunshine sync" --separate-output --checklist \
      "Space to toggle, Enter to confirm, Esc to cancel:" "$box_height" 70 "$list_height" \
      "${menu_args[@]}" 3>&1 1>&2 2>&3)"; then
    warn "Picker cancelled; selection left unchanged."
    return 0
  fi

  SELECTED=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && SELECTED["$line"]=1
  done <<< "$selection"

  save_selection
  log "Selection saved to $SELECTION_FILE (${#SELECTED[@]} game(s))."
}

run_picker_plain() {
  local -a appids=("$@")

  printf '\n  Installed Steam games:\n\n'
  local i appid mark
  for i in "${!appids[@]}"; do
    appid="${appids[$i]}"
    mark=" "
    [[ "${SELECTED[$appid]:-}" == "1" ]] && mark="x"
    printf '  %3d) [%s] %s (%s)\n' "$((i + 1))" "$mark" "${GAME_NAME[$appid]}" "$appid"
  done

  printf '\n  Toggle games by number ("1 3 5-7"), or type "all" / "none".\n'
  printf '  Press Enter with no input to keep the current selection: '
  local input
  read -r input

  case "$input" in
    "") ;;
    all)
      SELECTED=()
      for appid in "${appids[@]}"; do SELECTED["$appid"]=1; done
      ;;
    none)
      SELECTED=()
      ;;
    *)
      local -a tokens
      read -ra tokens <<< "$input"
      local token start end idx
      for token in "${tokens[@]}"; do
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          start="${BASH_REMATCH[1]}"
          end="${BASH_REMATCH[2]}"
        elif [[ "$token" =~ ^[0-9]+$ ]]; then
          start="$token"
          end="$token"
        else
          warn "Ignoring unrecognized selection token: $token"
          continue
        fi
        for ((idx = start; idx <= end; idx++)); do
          if ((idx >= 1 && idx <= ${#appids[@]})); then
            appid="${appids[$((idx - 1))]}"
            if [[ "${SELECTED[$appid]:-}" == "1" ]]; then
              unset "SELECTED[$appid]"
            else
              SELECTED["$appid"]=1
            fi
          else
            warn "Ignoring out-of-range selection: $idx"
          fi
        done
      done
      ;;
  esac

  save_selection
  log "Selection saved to $SELECTION_FILE (${#SELECTED[@]} game(s))."
}

# Sunshine's apps.json "image-path" is documented as pointing to a PNG,
# and in practice doesn't render box art supplied as JPG -- but Steam's CDN
# only serves JPG. So this downloads the JPG to a scratch file and converts
# it to the actual (cached) PNG destination before handing back a path.
convert_jpg_to_png() {
  local jpg="$1" png="$2"
  if have_command magick; then
    magick "$jpg" "$png" 2>/dev/null
  elif have_command convert; then
    convert "$jpg" "$png" 2>/dev/null
  elif have_command ffmpeg; then
    ffmpeg -y -loglevel error -i "$jpg" "$png"
  else
    return 1
  fi
}

fetch_cover_art() {
  local appid="$1"
  local dest="$SUNSHINE_COVERS_DIR/$appid.png"
  # ffmpeg picks its output muxer from the filename's extension, so the
  # scratch files must end in the real extension (.jpg/.png), not a
  # trailing ".tmp" -- a dot-prefixed name keeps them out of the way and
  # out of any directory listing of real covers.
  local tmp_jpg="$SUNSHINE_COVERS_DIR/.tmp-$appid.jpg"
  local tmp_png="$SUNSHINE_COVERS_DIR/.tmp-$appid.png"

  [[ -f "$dest" ]] && { printf '%s\n' "$dest"; return 0; }
  [[ "$DRY_RUN" == "1" ]] && return 1

  mkdir -p "$SUNSHINE_COVERS_DIR"

  local url downloaded=0
  for url in \
    "https://cdn.akamai.steamstatic.com/steam/apps/$appid/library_600x900.jpg" \
    "https://cdn.akamai.steamstatic.com/steam/apps/$appid/header.jpg" \
    "https://cdn.akamai.steamstatic.com/steam/apps/$appid/library_hero.jpg" \
    "https://cdn.akamai.steamstatic.com/steam/apps/$appid/capsule_616x353.jpg"; do
    if curl -fsSL --max-time 15 -o "$tmp_jpg" "$url" 2>/dev/null; then
      downloaded=1
      break
    fi
  done

  if [[ "$downloaded" != "1" ]]; then
    rm -f "$tmp_jpg"
    vlog "Could not download cover art for appid $appid from Steam's CDN."
    return 1
  fi

  if ! convert_jpg_to_png "$tmp_jpg" "$tmp_png"; then
    rm -f "$tmp_jpg" "$tmp_png"
    vlog "Downloaded cover art for appid $appid but could not convert it to PNG."
    return 1
  fi

  rm -f "$tmp_jpg"
  mv "$tmp_png" "$dest"
  printf '%s\n' "$dest"
  return 0
}

# Deletes all but the newest $2 "$1.bak.<timestamp>" backups. The
# timestamps sort by name, oldest first.
prune_backups() {
  local file="$1" keep="$2"
  local -a backups=()
  mapfile -t backups < <(compgen -G "$file.bak.*" | sort)
  ((${#backups[@]} > keep)) || return 0
  rm -f -- "${backups[@]:0:${#backups[@]}-keep}"
}

sync_apps_json() {
  mkdir -p "$SUNSHINE_CONFIG_DIR"

  local existing='{"env": {}, "apps": []}'
  if [[ -f "$SUNSHINE_APPS_JSON" ]]; then
    existing="$(cat "$SUNSHINE_APPS_JSON")"
    jq -e . >/dev/null 2>&1 <<<"$existing" || die "$SUNSHINE_APPS_JSON is not valid JSON; fix or remove it before syncing."
  fi

  local -a entries=() appids=()
  local appid name image
  # By appid, so the games keep the same order in Sunshine on every sync
  # (associative arrays have no order of their own).
  mapfile -t appids < <(printf '%s\n' "${!SELECTED[@]}" | sort -n)
  for appid in "${appids[@]}"; do
    [[ -n "$appid" ]] || continue
    name="${GAME_NAME[$appid]:-}"
    [[ -n "$name" ]] || continue

    image=""
    if [[ "$FETCH_COVER_ART" == "1" ]]; then
      # A dry run downloads nothing, so only cached covers are found then;
      # that's not worth a warning.
      if ! image="$(fetch_cover_art "$appid")" && [[ "$DRY_RUN" != "1" ]]; then
        warn "Could not prepare cover art for '$name' (appid $appid); syncing without image-path."
      fi
    fi

    entries+=("$(jq -n \
      --arg name "$name" \
      --arg appid "$appid" \
      --arg launch "$STEAM_LAUNCH_COMMAND" \
      --arg image "$image" \
      --arg stream_ws "$NIRI_STREAM_WORKSPACE" \
      --arg native_ws "$NIRI_NATIVE_WORKSPACE" \
      --argjson quit_steam "$([[ "$QUIT_STEAM_ON_STREAM_END" == "1" ]] && printf true || printf false)" \
      '{name: $name, detached: [$launch + " steam://rungameid/" + $appid]}
       + (if $image != "" then {"image-path": $image} else {} end)
       + {"prep-cmd": (
           [{
             "do": ("niri msg action focus-workspace " + $stream_ws),
             "undo": ("niri msg action focus-workspace " + $native_ws)
           }]
           + (if $quit_steam then
               [{
                 "do": "",
                 "undo": "sh -c \"steam -shutdown 2>/dev/null || flatpak kill com.valvesoftware.Steam 2>/dev/null || true\""
               }]
             else [] end)
         )}')")
  done

  local new_apps='[]'
  if ((${#entries[@]})); then
    new_apps="$(printf '%s\n' "${entries[@]}" | jq -s '.')"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run: would sync $(jq 'length' <<<"$new_apps") game(s) into $SUNSHINE_APPS_JSON (nothing written)."
    log "Dry run: each would switch niri to the '$NIRI_STREAM_WORKSPACE' workspace while streaming, and back to '$NIRI_NATIVE_WORKSPACE' afterwards."
    if [[ "$QUIT_STEAM_ON_STREAM_END" == "1" ]]; then
      log "Dry run: each would quit Steam when the stream ends."
    fi
    return 0
  fi

  local merged
  merged="$(jq --argjson new "$new_apps" '
    .env //= {}
    | .apps = ((.apps // [])
        | map(select((.detached // [] | any(contains("steam://rungameid/"))) | not)))
        + $new
  ' <<<"$existing")"

  if [[ -f "$SUNSHINE_APPS_JSON" ]]; then
    cp -p "$SUNSHINE_APPS_JSON" "$SUNSHINE_APPS_JSON.bak.$(date +%Y%m%d-%H%M%S)"
    prune_backups "$SUNSHINE_APPS_JSON" "$APPS_JSON_BACKUPS_TO_KEEP"
  fi

  printf '%s\n' "$merged" | jq '.' > "$SUNSHINE_APPS_JSON.tmp"
  mv "$SUNSHINE_APPS_JSON.tmp" "$SUNSHINE_APPS_JSON"
  record_change "Synced $(jq 'length' <<<"$new_apps") Steam game(s) into $SUNSHINE_APPS_JSON."
  record_change "Every synced game will switch niri to the '$NIRI_STREAM_WORKSPACE' workspace while streaming, and back to '$NIRI_NATIVE_WORKSPACE' when the stream ends."

  if [[ "$QUIT_STEAM_ON_STREAM_END" == "1" ]]; then
    record_change "Every synced game will quit Steam when the stream ends."
  fi

  # Cleans up <appid>.jpg covers cached by older versions of this script,
  # back when it wrote JPG straight through instead of converting to PNG.
  # Only those: other JPGs in the folder may be yours.
  local jpg removed=0
  if [[ -d "$SUNSHINE_COVERS_DIR" ]]; then
    for jpg in "$SUNSHINE_COVERS_DIR"/*.jpg; do
      [[ -f "$jpg" && "$(basename "$jpg")" =~ ^[0-9]+\.jpg$ ]] || continue
      rm -f -- "$jpg"
      removed=1
    done
  fi
  if ((removed)); then
    record_change "Removed stale JPG cover-art files from $SUNSHINE_COVERS_DIR (superseded by PNG)."
  fi
}

# Sunshine's user service: app-dev.lizardbyte.app.Sunshine.service in current
# packages (sunshine.service is only an alias of it), sunshine.service in
# older ones.
sunshine_unit() {
  local unit
  for unit in app-dev.lizardbyte.app.Sunshine.service sunshine.service; do
    if systemctl --user cat "$unit" >/dev/null 2>&1; then
      printf '%s' "$unit"
      return 0
    fi
  done
  return 1
}

maybe_restart_sunshine() {
  [[ "$DRY_RUN" == "1" ]] && return 0
  have_command systemctl || return 0

  local unit
  unit="$(sunshine_unit || true)"
  if [[ -n "$unit" ]] && systemctl --user is-active --quiet "$unit" 2>/dev/null; then
    if systemctl --user try-restart "$unit" 2>/dev/null; then
      record_change "Restarted the Sunshine user service ($unit) to pick up the new apps.json."
      return 0
    fi
    warn "Could not restart the Sunshine user service ($unit); restart it manually or hit Apply in the Sunshine web UI."
  else
    warn "Sunshine is not running as an active user service; open the Sunshine web UI (https://localhost:47990) and hit Apply, or start/restart Sunshine manually, to pick up the changes."
  fi
}

print_summary() {
  printf '\n%s  ────────────────────────────────────────────%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  Sync complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  ────────────────────────────────────────────%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '  Selected games: %s\n' "${#SELECTED[@]}"
  printf '  apps.json:      %s\n' "$SUNSHINE_APPS_JSON"
  printf '  Cover art:      %s\n' "$SUNSHINE_COVERS_DIR"
  printf '  Selection file: %s\n' "$SELECTION_FILE"

  if ((${#CHANGES[@]})); then
    printf '\n  %sChanges:%s\n' "$COLOR_GREEN" "$COLOR_RESET"
    local item
    for item in "${CHANGES[@]}"; do
      printf '  %s✓%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$item"
    done
  fi

  if ((${#WARNINGS[@]})); then
    printf '\n  %sWarnings:%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
    local item
    for item in "${WARNINGS[@]}"; do
      printf '  %s⚠%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$item"
    done
  fi
  printf '\n'
}

main() {
  parse_args "$@"

  if [[ "$LIST_ONLY" == "1" ]]; then
    list_selection
    exit 0
  fi

  check_dependencies
  resolve_steam_launch_command
  discover_installed_games
  load_selection

  if [[ "$FORCE_SELECT" == "1" || ! -f "$SELECTION_FILE" ]]; then
    run_picker
  fi

  ((${#SELECTED[@]})) || warn "No games selected; nothing to sync. Run again with --select to choose games."

  sync_apps_json
  maybe_restart_sunshine
  print_summary
}

main "$@"
