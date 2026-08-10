#!/bin/sh
# Build the patched Ghostty and install it to /Applications.
#
# /usr/local/bin/libtool is GNU libtool 1.4, which rejects Apple's `-static`
# flag and fails the xcframework step. Put /usr/bin first so Apple's wins.
set -eu

PATH=/usr/bin:$PATH
export PATH

install=1
[ "${1:-}" = "--no-install" ] && install=0

cd "$(dirname "$0")/.."

# -Dxcframework-target=native builds only the native (arm64 macOS) slice. The
# default, universal, also builds x86_64, iOS and the iOS simulator — slices
# that never run here, and which are what makes .zig-cache reach tens of GB.
echo "==> Building (ReleaseFast, native slice only)"
zig build -Doptimize=ReleaseFast -Dxcframework-target=native

app=$(find macos/build -maxdepth 3 -name Ghostty.app -type d 2>/dev/null | head -1)
[ -n "$app" ] || { echo "Build produced no Ghostty.app" >&2; exit 1; }
echo "==> Built $app"

# Re-sign with a stable identity.
#
# Xcode signs local builds ad-hoc, and an ad-hoc signature has no stable
# identity — it is just the binary hash, so every rebuild looks like a
# different app. macOS TCC keys its "Allow" decisions on that identity, so
# permission grants (Accessibility, "access data from other apps", etc.) are
# thrown away on each rebuild and the prompts come back forever.
#
# Signing with a real certificate gives a designated requirement that survives
# rebuilds, so a grant is remembered once. Create the cert with:
#   custom/make-signing-cert.sh
IDENTITY=${GHOSTTY_SIGN_IDENTITY:-Ghostty Local Signing}
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "==> Signing as '$IDENTITY'"
  sign() { codesign --force --options runtime --sign "$IDENTITY" "$@" >/dev/null; }

  # Nested code must be signed before the bundle that contains it.
  sparkle="$app/Contents/Frameworks/Sparkle.framework"
  if [ -d "$sparkle" ]; then
    for nested in \
      "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
      "$sparkle/Versions/B/XPCServices/Installer.xpc" \
      "$sparkle/Versions/B/Updater.app" \
      "$sparkle/Versions/B/Autoupdate" \
      "$sparkle/Versions/B/Sparkle"
    do
      [ -e "$nested" ] && sign "$nested"
    done
    sign "$sparkle"
  fi

  sign --entitlements macos/GhosttyReleaseLocal.entitlements "$app"
  codesign --verify --deep --strict "$app" || {
    echo "Signature verification failed" >&2; exit 1; }
else
  echo "==> WARNING: identity '$IDENTITY' not found; leaving the ad-hoc" >&2
  echo "    signature in place. Permission prompts will recur after every" >&2
  echo "    rebuild. Run custom/make-signing-cert.sh to fix." >&2
fi

[ "$install" -eq 1 ] || exit 0

# Refuse to clobber a running copy; a swapped-out bundle crashes the app.
# Match on the bundle path: the executable is lowercase `ghostty`, so
# `pgrep -x Ghostty` silently never matches.
if pgrep -f "Ghostty.app/Contents/MacOS/" >/dev/null 2>&1; then
  echo "Ghostty is running. Quit it first, then re-run." >&2
  exit 1
fi

echo "==> Installing to /Applications/Ghostty.app"
rm -rf /Applications/Ghostty.app
cp -R "$app" /Applications/Ghostty.app
# Self-built bundles aren't notarized; clear quarantine so Gatekeeper allows it.
xattr -dr com.apple.quarantine /Applications/Ghostty.app 2>/dev/null || true
echo "==> Done. $(/Applications/Ghostty.app/Contents/MacOS/ghostty --version | head -1)"
