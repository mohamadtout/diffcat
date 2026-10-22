#!/usr/bin/env bash
# Raw store screenshots on several devices, ONE AT A TIME: each emulator/simulator is booted, used and shut down
# before the next starts (several Android emulators at once exhaust memory). See store/README.md.
#
#   store/take_screenshots.sh "iphone-6.3=iPhone 17 Pro,android-phone=Shots_Phone,..."
#
# Each entry is NAME=TARGET. NAME is the folder the frame tool expects. TARGET is an Android AVD name, an iOS
# simulator name or UDID, or the id of an already-connected device (`flutter devices`), which is used as it is.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
PORT=5554
SERIAL="emulator-$PORT"

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: $0 \"NAME=TARGET,NAME=TARGET,...\"" >&2; exit 2; }

failed=()
EMU_PID=""
SIM_UDID=""

cleanup() {
  if [ -n "$EMU_PID" ]; then
    "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1
    # Wait until the process is really gone so its memory is back before the next device.
    for _ in $(seq 30); do kill -0 "$EMU_PID" 2>/dev/null || break; sleep 1; done
    kill "$EMU_PID" 2>/dev/null
    pkill -f "qemu-system.* -port $PORT " 2>/dev/null
    EMU_PID=""
  fi
  if [ -n "$SIM_UDID" ]; then
    xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1
    SIM_UDID=""
  fi
}
trap 'cleanup; exit 130' INT TERM

# Both start_* functions set DEVICE (the flutter device id) and must not run in a subshell: the PIDs they set are
# what cleanup shuts down.
start_avd() { # $1 = AVD name, $2 = NAME
  "$ADB" start-server >/dev/null 2>&1
  "$EMULATOR" -avd "$1" -port "$PORT" -gpu host -no-snapshot -no-boot-anim -no-audio >/dev/null 2>&1 &
  EMU_PID=$!
  "$ADB" -s "$SERIAL" wait-for-device
  for _ in $(seq 120); do
    [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
    kill -0 "$EMU_PID" 2>/dev/null || return 1
    sleep 2
  done
  # Android tablets are shot in landscape (narrower than the 840dp split view in portrait).
  case "$2" in
    android-tablet-*) "$ADB" -s "$SERIAL" shell settings put system accelerometer_rotation 0
                      "$ADB" -s "$SERIAL" shell settings put system user_rotation 1 ;;
  esac
  sleep 5
  DEVICE="$SERIAL"
}

start_sim() { # $1 = simulator name or UDID
  local udid
  udid=$(xcrun simctl list devices available | grep -F "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$udid" ] || udid=$(xcrun simctl list devices available | grep -F "$1" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$udid" ] || return 1
  if xcrun simctl list devices | grep -F "$udid" | grep -q Booted; then
    DEVICE="$udid" # already running: use it, leave it running
    return 0
  fi
  xcrun simctl boot "$udid" >/dev/null 2>&1 && xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || return 1
  SIM_UDID="$udid"
  DEVICE="$udid"
}

IFS=',' read -r -a entries <<<"$1"
avds=$("$EMULATOR" -list-avds 2>/dev/null)

for entry in "${entries[@]}"; do
  name="${entry%%=*}"
  target="${entry#*=}"
  [ -n "$name" ] && [ "$name" != "$entry" ] && [ -n "$target" ] || { echo "bad entry '$entry' (want NAME=TARGET)" >&2; exit 2; }
  echo "=== $name on $target"

  DEVICE=""
  if grep -qxF "$target" <<<"$avds"; then
    start_avd "$target" "$name"
  elif command -v xcrun >/dev/null && start_sim "$target"; then
    :
  else
    DEVICE="$target"
  fi

  if [ -n "$DEVICE" ] && make -C "$ROOT" store-screenshot DEVICE="$DEVICE" NAME="$name"; then
    echo "--- $name done"
  else
    echo "--- $name FAILED" >&2
    failed+=("$name")
  fi
  cleanup
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}" >&2
  exit 1
fi
echo "All done → app/build/store/raw/. Next: make store-frames"
