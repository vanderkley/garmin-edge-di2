#!/bin/zsh
# Build the data field.
#   scripts/build.sh          -> bin/Di2.prg       (release, store defaults)
#   scripts/build.sh personal -> bin/Di2.prg       (with your bike from resources-personal/)
#   scripts/build.sh export   -> bin/Di2.iq        (store package, all devices)
#   scripts/build.sh demo     -> bin/Di2Demo.prg   (fake data, for the simulator)
#   scripts/build.sh layouts  -> bin/Di2Demo.prg   (fake data, full page with several fields)
#   scripts/build.sh lowbatt  -> bin/Di2Demo.prg   (page demo with a low Di2 battery)
#   scripts/build.sh trialend -> bin/Di2Demo.prg   (page demo after the 500 km trial)
# Needs: Connect IQ SDK (SDK Manager), Java 17, and a developer key:
#   export DEVELOPER_KEY=/path/to/developer_key.der
set -e
cd "${0:A:h:h}"
: ${DEVELOPER_KEY:?"Set DEVELOPER_KEY to your developer_key.der (see README)"}
DEVICE=${DEVICE:-edgeexplore2}
CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK=${CIQ_SDK:-$(cat "$CIQ/current-sdk.cfg" 2>/dev/null | sed 's:/*$::')}
[[ -x "$SDK/bin/monkeyc" ]] || SDK=$(print -l "$CIQ/Sdks/"connectiq-sdk-*(/N) | tail -1)
[[ -x /opt/homebrew/opt/openjdk@17/bin/java ]] && export JAVA_HOME=/opt/homebrew/opt/openjdk@17 PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH
mkdir -p bin
# the license secret is not in git: fall back to the public placeholder
[[ -f source/Di2Secret.mc ]] || cp source/Di2Secret.mc.example source/Di2Secret.mc
if [[ "$1" == "personal" ]]; then
  # your own bike defaults (resources-personal/, not in git) for sideloading
  [[ -d resources-personal ]] || { mkdir -p resources-personal; cp -R resources-defaults/settings resources-personal/; }
  [[ -f personal.jungle ]] || sed 's/resources-defaults/resources-personal/' monkey.jungle > personal.jungle
  "$SDK/bin/monkeyc" -d "$DEVICE" -f personal.jungle -o bin/Di2.prg -y "$DEVELOPER_KEY"
elif [[ "$1" == "export" ]]; then
  # store package (.iq) for all devices in manifest.xml
  "$SDK/bin/monkeyc" -e -r -f monkey.jungle -o bin/Di2.iq -y "$DEVELOPER_KEY"
elif [[ "$1" == "demo" || "$1" == "layouts" || "$1" == "lowbatt" || "$1" == "trialend" ]]; then
  "$SDK/bin/monkeyc" -d "$DEVICE" -f "$1.jungle" -o bin/Di2Demo.prg -y "$DEVELOPER_KEY"
else
  "$SDK/bin/monkeyc" -d "$DEVICE" -f monkey.jungle -o bin/Di2.prg -y "$DEVELOPER_KEY"
fi
