#!/bin/zsh
# Run the demo build (fake gear/battery data) in the Connect IQ simulator.
#   scripts/simulate.sh            one full-screen field
#   scripts/simulate.sh layouts    a full Edge page with the field in several sizes
#   scripts/simulate.sh lowbatt    the same page with a low Di2 battery (tone + red label)
#   scripts/simulate.sh trialend   the same page after the 500 km trial (lock screen)
set -e
cd "${0:A:h:h}"
scripts/build.sh ${1:-demo}
CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK=${CIQ_SDK:-$(cat "$CIQ/current-sdk.cfg" 2>/dev/null | sed 's:/*$::')}
[[ -x "$SDK/bin/monkeydo" ]] || SDK=$(print -l "$CIQ/Sdks/"connectiq-sdk-*(/N) | tail -1)
[[ -x /opt/homebrew/opt/openjdk@17/bin/java ]] && export JAVA_HOME=/opt/homebrew/opt/openjdk@17 PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH
"$SDK/bin/connectiq" &
sleep 5
"$SDK/bin/monkeydo" bin/Di2Demo.prg ${DEVICE:-edgeexplore2}
