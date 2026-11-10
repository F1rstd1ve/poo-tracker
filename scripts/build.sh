#!/usr/bin/env bash
# Build Gassi-Depot for one device.
#   scripts/build.sh                 -> epix2pro47mm
#   scripts/build.sh epix2pro51mm
# Output: bin/GassiDepot-<device>.prg (copy that file to GARMIN/APPS on the watch).
set -euo pipefail

DEVICE="${1:-epix2pro47mm}"
cd "$(dirname "$0")/.."

# Java: use the Homebrew openjdk@17 (keg-only) when no system Java is installed.
if ! /usr/libexec/java_home >/dev/null 2>&1 && [[ -x /opt/homebrew/opt/openjdk@17/bin/java ]]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@17
    export PATH="$JAVA_HOME/bin:$PATH"
fi

CIQ_HOME="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK_DIR=""
if [[ -f "$CIQ_HOME/current-sdk.cfg" ]]; then
    SDK_DIR="$(tr -d '\n' < "$CIQ_HOME/current-sdk.cfg")"
fi
if [[ -z "$SDK_DIR" || ! -x "$SDK_DIR/bin/monkeyc" ]]; then
    SDK_DIR="$(ls -d "$CIQ_HOME"/Sdks/*/ 2>/dev/null | sort | tail -1)"
fi
SDK_DIR="${SDK_DIR%/}"
if [[ ! -x "$SDK_DIR/bin/monkeyc" ]]; then
    echo "Connect IQ SDK nicht gefunden. Bitte im SDK Manager ein SDK installieren." >&2
    exit 1
fi

KEY="${GARMIN_DEV_KEY:-$HOME/.garmin-dev/developer_key.der}"
if [[ ! -f "$KEY" ]]; then
    echo "Entwicklerschlüssel fehlt: $KEY" >&2
    exit 1
fi

mkdir -p bin
"$SDK_DIR/bin/monkeyc" \
    -d "$DEVICE" \
    -f monkey.jungle \
    -o "bin/GassiDepot-$DEVICE.prg" \
    -y "$KEY" \
    -w
echo "OK: bin/GassiDepot-$DEVICE.prg"
