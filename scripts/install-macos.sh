#!/bin/zsh
# Copy bin/Di2.prg to a USB-connected Edge (macOS, MTP). Close Garmin Express first.
# Needs: brew install libmtp
set -e
cd "${0:A:h:h}"
[[ -f bin/Di2.prg ]] || { echo "Build first: scripts/build.sh"; exit 1; }
if [[ ! -x build/mtp-push ]]; then
  mkdir -p build
  clang -O2 -o build/mtp-push scripts/mtp-push.c $(pkg-config --cflags --libs libmtp)
fi
build/mtp-push bin/Di2.prg Garmin/Apps DI2.PRG 2>&1 | grep -v "association"
echo "Done. Unplug the Edge to install."
