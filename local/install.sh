#!/bin/sh
# Download the latest CI build and install it to /Applications.
#
# CI signs ad-hoc because the signing certificate never leaves this machine.
# An ad-hoc signature is identified by the binary hash, so macOS TCC treats
# every build as a different app and re-asks for permissions forever. Re-signing
# here with a stable certificate gives a designated requirement tied to the
# certificate instead, so one "Allow" sticks across builds.
#
#   ./local/install.sh              # latest successful run
#   ./local/install.sh <run-id>     # a specific run
set -eu

REPO=${GHOSTTY_CI_REPO:-realav/ghostty-fork-ci}
IDENTITY=${GHOSTTY_SIGN_IDENTITY:-Ghostty Local Signing}

command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }

run=${1:-}
if [ -z "$run" ]; then
  run=$(gh run list --repo "$REPO" --workflow build-mac.yml \
        --status success --limit 1 --json databaseId --jq '.[0].databaseId')
  [ -n "$run" ] || { echo "No successful run found." >&2; exit 1; }
fi
echo "==> Using run $run"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

gh run download "$run" --repo "$REPO" --dir "$tmp"
zip=$(find "$tmp" -name '*.zip' | head -1)
[ -n "$zip" ] || { echo "No zip in artifact." >&2; exit 1; }

ditto -x -k "$zip" "$tmp/app"
app=$(find "$tmp/app" -maxdepth 2 -name Ghostty.app -type d | head -1)
[ -n "$app" ] || { echo "No Ghostty.app in artifact." >&2; exit 1; }

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "==> Re-signing as '$IDENTITY'"
  sign() { codesign --force --options runtime --sign "$IDENTITY" "$@" >/dev/null; }
  sparkle="$app/Contents/Frameworks/Sparkle.framework"
  if [ -d "$sparkle" ]; then
    # Nested code must be signed before the bundle containing it.
    for n in "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
             "$sparkle/Versions/B/XPCServices/Installer.xpc" \
             "$sparkle/Versions/B/Updater.app" \
             "$sparkle/Versions/B/Autoupdate" \
             "$sparkle/Versions/B/Sparkle"; do
      [ -e "$n" ] && sign "$n"
    done
    sign "$sparkle"
  fi
  ent=""
  [ -f "$(dirname "$0")/Ghostty.entitlements" ] && ent="$(dirname "$0")/Ghostty.entitlements"
  if [ -n "$ent" ]; then sign --entitlements "$ent" "$app"; else sign "$app"; fi
  codesign --verify --deep --strict "$app" || { echo "signature invalid" >&2; exit 1; }
else
  echo "==> WARNING: '$IDENTITY' not found; leaving the CI ad-hoc signature." >&2
  echo "    Permission prompts will recur. Run local/make-signing-cert.sh." >&2
fi

if pgrep -f "Ghostty.app/Contents/MacOS/" >/dev/null 2>&1; then
  echo "Ghostty is running. Quit it first, then re-run." >&2
  exit 1
fi

echo "==> Installing to /Applications/Ghostty.app"
rm -rf /Applications/Ghostty.app
cp -R "$app" /Applications/Ghostty.app
xattr -dr com.apple.quarantine /Applications/Ghostty.app 2>/dev/null || true
echo "==> Done. $(/Applications/Ghostty.app/Contents/MacOS/ghostty +version | head -1)"
