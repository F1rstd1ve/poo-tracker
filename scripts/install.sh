#!/usr/bin/env bash
# Build Gassi-Depot and copy it onto the USB-connected watch (GARMIN/Apps).
#   scripts/install.sh               -> epix2pro51mm (Jörg's watch)
#   scripts/install.sh epix2pro47mm
# Needs: brew install libmtp. Quit OpenMTP/Android File Transfer first (they lock the device).
set -euo pipefail
DEVICE="${1:-epix2pro51mm}"
cd "$(dirname "$0")/.."
scripts/build.sh "$DEVICE"
if [[ ! -x bin/mtpput || tools/mtpput.c -nt bin/mtpput ]]; then
    clang -O1 -o bin/mtpput tools/mtpput.c $(pkg-config --cflags --libs libmtp)
fi
LANG=en_US.UTF-8 bin/mtpput "bin/GassiDepot-$DEVICE.prg" GARMIN/Apps GassiDepot.prg 2>&1 \
    | grep -v -E 'extended association|^ 0x|cached device'
echo "Fertig. Uhr abstecken – die App wird beim Trennen installiert."
