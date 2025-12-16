#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# ArxisOS Build + Branding Wrapper
# Fedora 43 based OS for Arxis
# Outline developed by Brad Heffernan
# ------------------------------------------------------------

ISO_DIR="${ISO_DIR:-$HOME/arxisos-build}"

BUILD_SCRIPT="$ISO_DIR/scripts/build-iso.sh"
BRAND_SCRIPT="$ISO_DIR/scripts/apply-composer-branding.sh"

# Put your logo here (recommended):
#   $ISO_DIR/branding/logos/arxisos-logo-full.png
# Or override with: TITLE_IMAGE=/path/to/logo.png ./scripts/build-and-brand.sh
TITLE_IMAGE="${TITLE_IMAGE:-$ISO_DIR/branding/logos/arxisos-logo-full.png}"

die() { echo "ERROR: $*" >&2; exit 1; }

print_title() {
  echo
  # If chafa is available + image exists, render the PNG as terminal art
  if command -v chafa >/dev/null 2>&1 && [[ -f "$TITLE_IMAGE" ]]; then
    chafa -s 90x --symbols braille "$TITLE_IMAGE" || true
    echo
  fi

  # Embedded ASCII (derived from your attached logo) as a guaranteed fallback
  cat <<'ASCII'
                                  -*.
                     #=         :#@@+
.     .  .          :@*       :*@@@@%
.     .  .          =@%     :*@@@@@@@-
.     .             +@@+    +#%%@@@@@#
.     .             -@@%:     :%@@@@@@:
.     .              %@@%.    =@@@%=*#+
.     .              -@@@%:  .%@@@=
.     .               =%@@%= *@@@#
.     .  .             -%@@@%@@@#.
.     .  :              .+%@@@@%:   -+
.     .  .               -%@@@@%#+:=%@+
.     .  .             :*@@@@#%@@@@@@@@+
.     .  .           -*@@@@#- .=%@@@@@@@+
.     .  .       .-*%@@@%*-    :%@@@@@@@@+
              :*#%@@%#+-.     .***********
ASCII

  cat <<'DESC'

Fedora 43 based OS for Arxis
Outline developed by Brad Heffernan

DESC
}

cleanup_outputs() {
  mkdir -p "$ISO_DIR"
  shopt -s nullglob
  local old=( "$ISO_DIR"/*.iso "$ISO_DIR"/*.png )
  shopt -u nullglob

  if (( ${#old[@]} )); then
    echo "Cleaning old outputs in: $ISO_DIR"
    rm -f -- "${old[@]}"
  else
    echo "No old .iso/.png to clean in: $ISO_DIR"
  fi
}

find_latest_iso() {
  shopt -s nullglob
  local isos=( "$ISO_DIR"/*.iso )
  shopt -u nullglob
  (( ${#isos[@]} )) || return 1
  ls -1t -- "${isos[@]}" | head -n 1
}

main() {
  print_title

  [[ -x "$BUILD_SCRIPT" ]] || die "Not found/executable: $BUILD_SCRIPT"
  [[ -x "$BRAND_SCRIPT" ]] || die "Not found/executable: $BRAND_SCRIPT"

  cleanup_outputs

  echo "Running build: $BUILD_SCRIPT --wait"
  ( cd "$ISO_DIR" && "$BUILD_SCRIPT" --wait )

  local iso_path
  iso_path="$(find_latest_iso)" || die "No ISO found in $ISO_DIR after build."

  echo
  echo "Newest ISO detected:"
  echo "  $iso_path"
  echo

  echo "Running branding: $BRAND_SCRIPT \"$iso_path\""
  ( cd "$ISO_DIR" && "$BRAND_SCRIPT" "$iso_path" )

  echo
  echo "Done ✅"
  echo "ISO: $iso_path"
}

main "$@"
