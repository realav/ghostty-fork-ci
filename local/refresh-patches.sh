#!/bin/sh
# Rebase the patches onto a newer upstream and re-export them.
#
# Needs no persistent fork checkout: it clones upstream into a temp directory,
# replays patches/*.patch, rebases onto the target ref, and writes the result
# back to patches/ and .fork-base. The clone is deleted on success.
#
#   ./local/refresh-patches.sh            # rebase onto upstream main
#   ./local/refresh-patches.sh <ref>      # rebase onto a specific ref
#
# On a conflict the clone is KEPT so it can be resolved by hand; the script
# prints where it is and what to run afterwards.
set -eu

REF=${1:-main}
cd "$(dirname "$0")/.."
CI=$PWD
BASE=$(cat .fork-base)

work=$(mktemp -d)
keep=0
cleanup() { [ "$keep" -eq 1 ] || rm -rf "$work"; }
trap cleanup EXIT INT TERM

echo "==> Cloning upstream"
git clone -q https://github.com/ghostty-org/ghostty.git "$work/ghostty"
cd "$work/ghostty"
git config user.email ci@example.com
git config user.name "fork ci"

echo "==> Replaying current patches onto $BASE"
git checkout -q "$BASE"
git checkout -q -b custom
git am "$CI"/patches/*.patch

echo "==> Rebasing onto $REF"
git fetch -q origin "$REF"
if ! git rebase FETCH_HEAD; then
  keep=1
  cat >&2 <<EOF

Rebase stopped on a conflict. The clone has been kept:

  $work/ghostty

Resolve it there:
  git add <files> && git rebase --continue

Then re-export from that clone:
  cd "$work/ghostty"
  git format-patch -o "$CI/patches" FETCH_HEAD..custom
  git rev-parse FETCH_HEAD > "$CI/.fork-base"

EOF
  exit 1
fi

NEW=$(git rev-parse FETCH_HEAD)
rm -f "$CI"/patches/*.patch
git format-patch -q -o "$CI/patches" "$NEW"..custom
echo "$NEW" > "$CI/.fork-base"

echo "==> Rebased onto $NEW"
ls "$CI/patches"
echo
echo "Commit and push, then run the workflow to verify it still builds."
