#!/bin/bash
#
# Build, install, and launch Eventrail on an iOS simulator.
#
# Stands in for SweetPad's "Launch" task, which fails on Xcode 27: SweetPad
# hardcodes `open -a Simulator`, and Xcode 27 no longer ships Simulator.app.
# The bundled simulator UI is now DeviceHub.app (com.apple.dt.Devices).
#
# Usage: .vscode/run-simulator.sh [simulator name or UDID]
#
# Without an argument the device is taken from sweetpad.build.destination in
# .vscode/settings.json, then from whatever simulator is already booted.
#
# Environment:
#   CONFIGURATION=Release   build a different configuration (default Debug)
#   SIM_FOREGROUND=0        leave DeviceHub in the background
#   SIM_CONSOLE=0           install and launch, but do not stream the app's log
#   SIM_WAIT_FOR_DEBUGGER=1 launch suspended so a debugger can attach, then exit
#                           (this is what the "Debug on Simulator" launch config uses)

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Eventrail.xcodeproj"
SCHEME="${SCHEME:-Eventrail}"
CONFIGURATION="${CONFIGURATION:-Debug}"

# ---------------------------------------------------------------- device ----

UDID=$(python3 - "${1:-}" <<'PY'
import json, re, subprocess, sys, pathlib

explicit = sys.argv[1] if len(sys.argv) > 1 else ""
wanted = explicit

if not wanted:
    try:
        raw = pathlib.Path(".vscode/settings.json").read_text()
        raw = re.sub(r"^\s*//.*$", "", raw, flags=re.M)
        dest = json.loads(raw).get("sweetpad.build.destination") or {}
        wanted = str(dest.get("id", "")).removeprefix("iossimulator-")
    except Exception:
        wanted = ""

devices = json.loads(
    subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True, text=True, check=True,
    ).stdout
)["devices"]

ios = [
    d
    for runtime, entries in devices.items()
    if "iOS" in runtime
    for d in entries
]

match = next((d for d in ios if wanted in (d["udid"], d["name"])), None) if wanted else None

# Fall back to whatever is booted only when the device was not named on the
# command line -- an explicit name that matches nothing is an error.
if not match and not explicit:
    match = next((d for d in ios if d["state"] == "Booted"), None)

if not match:
    label = f"No iOS simulator matching {explicit!r}." if explicit else "No iOS simulator available."
    print(label, "Known devices:", file=sys.stderr)
    for d in ios:
        print(f"  {d['name']}  {d['udid']}  ({d['state']})", file=sys.stderr)
    sys.exit(1)

print(match["udid"])
PY
)

echo "==> Simulator $UDID"
xcrun simctl bootstatus "$UDID" -b

if [[ "${SIM_FOREGROUND:-1}" != "0" ]]; then
    # The Xcode 27 replacement for `open -a Simulator`.
    open -b com.apple.dt.Devices || true
fi

# ----------------------------------------------------------------- build ----

echo "==> Building $SCHEME ($CONFIGURATION)"
if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" -destination "id=$UDID" build | xcbeautify
else
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" -destination "id=$UDID" build
fi

# ------------------------------------------------------- install & launch ---

eval "$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" -destination "id=$UDID" -showBuildSettings 2>/dev/null |
        awk -F' = ' '
            $1 ~ /^ +BUILT_PRODUCTS_DIR$/    { printf "BUILT_PRODUCTS_DIR=%s\n", $2 }
            $1 ~ /^ +FULL_PRODUCT_NAME$/     { printf "FULL_PRODUCT_NAME=%s\n", $2 }
            $1 ~ /^ +PRODUCT_BUNDLE_IDENTIFIER$/ { printf "BUNDLE_ID=%s\n", $2 }
        ' | sed 's/=\(.*\)/="\1"/'
)"

APP="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"

# launch.json needs a path it can hardcode, but DerivedData's is hashed from the
# project location. Republish it under a stable name on every build. LLDB matches
# the running process by basename, so this only has to exist and be current.
mkdir -p .vscode/.build
ln -sfn "$APP" ".vscode/.build/$FULL_PRODUCT_NAME"

echo "==> Installing $APP"
xcrun simctl install "$UDID" "$APP"

echo "==> Launching $BUNDLE_ID"
if [[ "${SIM_WAIT_FOR_DEBUGGER:-0}" != "0" ]]; then
    xcrun simctl launch --wait-for-debugger --terminate-running-process "$UDID" "$BUNDLE_ID"
    echo "==> Suspended before main(); waiting for the debugger to attach."
elif [[ "${SIM_CONSOLE:-1}" != "0" ]]; then
    exec xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE_ID"
else
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"
fi
