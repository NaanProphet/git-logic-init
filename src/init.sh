#!/bin/bash

### This script is used to bootstrap a blank Apple Logic repo with the
### required Git commit hooks for Git LFS and Git Store Meta.
### It stores the hooks in a custom Hooks location called .githooks
### which can then be committed into source control.
###
### If the .githooks folder is already present, then this script
### bypasses bootstrapping and simply re-initializes the .githooks
### folder. This is required after each new clone.
###
### See https://github.com/danny0838/git-store-meta for more info about
### how file timestamps are preserved with commit hooks.
###
### Platform: Mac OS X
### Dependencies: Homebrew, Git (>= 2.9), Git LFS, Git Store Meta
###
### Development notes:
### - The bootstrapping process is NOT idempotent.
### - To start over, remove all temp files using: `rm -rf .git*`
###
### Author: Krishna Bhamidipati (NaanProphet)
### version: 0.1
###


LFS_TYPES=('*.wav' '*.aif' '*.aiff' '*.mp3' '*.m4a' '*.zip' '*.gz' '*.tgz')
GIT_META_VERSION=2.0.1
HOOKS_DIR="./.git/hooks"
DEST_DIR=".githooks"
MIN_GIT_VERSION="2.9"

# -----------------------------------------------------------------------------

# Special thanks to: https://stackoverflow.com/a/3511118/1603489
function compareVersions () {
  typeset    IFS='.'
  typeset -a v1=( $1 )
  typeset -a v2=( $2 )
  typeset    n diff

  for (( n=0; n<4; n+=1 )); do
    diff=$((v1[n]-v2[n]))
    if [ $diff -ne 0 ] ; then
      [ $diff -le 0 ] && return -1 || return 1
      return
    fi
  done
  return 0
}

function backup_hook () {
  local hook_name=$1
  local hook_path="${HOOKS_DIR}/${hook_name}"

  if [ -f "${hook_path}" ]; then
    echo "Backing up exiting ${hook_name} hook"
    mv "${hook_path}" "${hook_path}.orig"
  fi
}

function merge_hook () {
  local hook_name=$1
  local hook_path="${HOOKS_DIR}/${hook_name}"

  if [ -f "${hook_path}.orig" ]; then
    mv "${hook_path}" "${hook_path}.meta"
    cp "${hook_path}.orig" "${hook_path}"
    # exclude double shebang
    echo "" >> "${hook_path}"
    cat "${hook_path}.meta" | sed '/^#!/ d' >> "${hook_path}"
    echo "Merged changes into ${hook_name} hook"
  fi
}

bootstrap_repo () {

  # Initialize Git

  git init

  # Initialize Git LFS

  git lfs install
  for t in ${LFS_TYPES[@]}; do
    git lfs track $t
  done

  # Preserve file timestamps of Audio Files. Otherwise Logic
  # will re-calculate waveforms after checkout and change
  # the checksums!! Special thanks to:
  # https://github.com/danny0838/git-store-meta
  #
  # Run install to write commit hooks pre-commit, post-checkout
  # and post-merge *before* LFS' hooks. Otherwise the `install`
  # command will fail.

  # move originals from LFS, if present
  backup_hook pre-commit
  backup_hook post-checkout
  backup_hook post-merge

  echo "Initializing Git Store Meta"
  # creates pre-commit, post-checkout and post-merge
  git-store-meta.pl --install

  # merge with originals and remove double shebang if present
  merge_hook pre-commit
  merge_hook post-checkout
  merge_hook post-merge

  # cleanup any files left behind
  rm -f ${HOOKS_DIR}/pre-commit.meta ${HOOKS_DIR}/pre-commit.orig \
    ${HOOKS_DIR}/post-checkout.meta ${HOOKS_DIR}/post-checkout.orig \
    ${HOOKS_DIR}/post-merge.meta ${HOOKS_DIR}/post-merge.orig \
    ${HOOKS_DIR}/*.sample

  # move hooks folder out of .git so it can be committed
  mv -f "${HOOKS_DIR}" "${DEST_DIR}"

  # copy git-store-meta locally to make clones easier for others
  cp `which git-store-meta.pl` "${DEST_DIR}/"

}

# -----------------------------------------------------------------------------

# Check for binaries

if ! [ -x "$(command -v brew)" ]; then
  echo "\033[31m Homebrew is not installed. \033[0m" >&2
  echo "\033[31m Visit https://brew.sh for one-line install instructions. \033[0m"
  exit 1
fi

if ! [ -x "$(command -v git)" ]; then
  echo "\033[31m Git is not installed. Use \`brew install git\` to install. \033[0m" >&2
  exit 1
fi

# check minimum version for git config core.hooksPath
git_version=`git --version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/'`
compareVersions $MIN_GIT_VERSION $git_version
if [ $? -lt 0 ] ; then
  echo "\033[31m Git version $git_version must be >= $MIN_GIT_VERSION. Use \`brew upgrade git\` to upgrade. \033[0m" >&2
  exit 1
fi

if ! [ -x "$(command -v git-lfs)" ]; then
  echo "\033[31m Git LFS is not installed. Use \`brew install git-lfs\` to install. \033[0m" >&2
  exit 1
fi

if ! [ -x "$(command -v git-store-meta.pl)" ] && ! [ -f "${DEST_DIR}/git-store-meta.pl" ]; then
  echo "\033[31m Git Store Meta is not installed. \033[0m" >&2
  echo "\033[31m Use \`brew cask install NaanProphet/ninjabrew/git-store-meta\` to install. \033[0m" >&2
  exit 1
fi

# make sure local hook is executable, if exists
if [ -f "${DEST_DIR}/git-store-meta.pl" ]; then
  chmod a+x "${DEST_DIR}/git-store-meta.pl"
fi

# Check ignore rules. Assume owner of repo has access to all plugins so
# that Freeze Files are not needed. Otherwise, manually zip up the Freeze Files
# folder if needed to the archive
#
# Special thanks to:
# https://stackoverflow.com/a/3557165/1603489
touch .gitignore
grep -qxF '.DS_Store' .gitignore || echo '.DS_Store' >> .gitignore
grep -qxF 'Freeze Files' .gitignore || echo 'Freeze Files' >> .gitignore
grep -qxF '*.rxdoc' .gitignore || echo '*.rxdoc' >> .gitignore

if ! [ -d "${DEST_DIR}" ]; then
  set -e
  # Any subsequent(*) commands which fail will cause the shell script to exit immediately
  # Special thanks to: https://stackoverflow.com/a/2871034/1603489

  bootstrap_repo
fi

# initialize hooks location (must be done after each clone)
git config core.hooksPath "${DEST_DIR}"
echo "${DEST_DIR} successfully initialized"
