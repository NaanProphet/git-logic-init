#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

## This script will download the official/vanilla Git Store Meta code (from a fork, for backup)
## and apply the DST patch needed for Logic X.

GIT_META_REPO="https://raw.githubusercontent.com/NaanProphet/git-store-meta"
# commit for tag v2.0.1
TAG_COMMIT=5e98a67eedbb7e23a4b71f8decc9a7405591e5e1
curl -o "${DIR}/git-store-meta.pl" -s -L -O "${GIT_META_REPO}/${TAG_COMMIT}/git-store-meta.pl"

# apply patch file
# special thanks to: https://www.shellhacks.com/create-patch-diff-command-linux/
# create diff using `diff -u OriginalFile UpdatedFile > PatchFile`
patch "${DIR}/git-store-meta.pl" < "${DIR}/dst-hack.patch"

# splice dst hack functions for single executable
# special thanks to: https://superuser.com/a/1390700
if [ "$(uname)" == "Darwin" ]; then
    # Mac OS X platform does not have `tac`
    tail -n +9 "${DIR}/dst-hack.pl" | tail -r | tail -n +3 | tail -r >> "${DIR}/git-store-meta.pl"
else
    # GNU/Linux platform i.e. Travis CI
    tail -n +9 "${DIR}/dst-hack.pl" | tac | tail -n +3 | tac >> "${DIR}/git-store-meta.pl"
fi
