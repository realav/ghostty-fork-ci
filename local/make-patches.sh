#!/bin/sh
# Regenerate patches/ from the local fork at ~/ghostty (branch `custom`).
#
# Only source changes are exported. The fork's own tooling under custom/ lives
# in this repo instead, so it never becomes a patch against upstream.
set -eu
FORK=${GHOSTTY_FORK:-$HOME/ghostty}
cd "$(dirname "$0")/.."
CI=$PWD

cd "$FORK"
BASE=$(git merge-base upstream/main custom)
echo "==> base $BASE"

git branch -D ci-export 2>/dev/null || true
git checkout -q -b ci-export "$BASE"
# Cherry-pick each source commit, dropping anything under custom/.
for c in $(git log --reverse --format=%H "$BASE"..custom -- src include macos); do
  git cherry-pick -n "$c" >/dev/null 2>&1 || true
  rm -rf custom 2>/dev/null || true
  git commit -q -m "$(git log -1 --format=%s "$c")" || true
done

rm -f "$CI/patches"/*.patch
git format-patch -o "$CI/patches" "$BASE"..HEAD >/dev/null
echo "$BASE" > "$CI/.fork-base"

git checkout -q custom
git branch -D ci-export >/dev/null 2>&1 || true
echo "==> wrote:"; ls "$CI/patches"
