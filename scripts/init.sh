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
### version: 0.1.8
###

RELEASE_VERSION="v0.1.8"
RELEASE_BASEURL="https://github.com/NaanProphet/git-logic-init/releases/download"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
LFS_TYPES=(
  '*.wav' '*.aif' '*.aiff' '*.mp3' '*.m4a' '*.alac' '.*aifc'
  '*.zip' '*.gz' '*.tgz'
  'ProjectData'
)
# loosely based on https://sound.stackexchange.com/a/38454
GIT_IGNORE=(
  '.DS_Store'
  'Freeze Files'
  'Undo Data.nosync'
  'Project File Backups'
  'Autosave'
  '*.rxdoc'
)
GIT_META_FIELDS="file,type,mtime"
ORIG_HOOKS_DIR="./.git/hooks"
NEW_HOOKS_DIR=".githooks"
LFS_DIR="./.git/lfs"
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
  local hook_path="${ORIG_HOOKS_DIR}/${hook_name}"

  if [ -f "${hook_path}" ]; then
    echo "Backing up exiting ${hook_name} hook"
    mv "${hook_path}" "${hook_path}.orig"
  fi
}

function merge_hook () {
  local hook_name=$1
  local hook_path="${ORIG_HOOKS_DIR}/${hook_name}"

  if [ -f "${hook_path}.orig" ]; then
    mv "${hook_path}" "${hook_path}.meta"
    cp "${hook_path}.orig" "${hook_path}"
    # exclude double shebang
    echo "" >> "${hook_path}"
    cat "${hook_path}.meta" | sed '/^#!/ d' >> "${hook_path}"
    echo "Merged changes into ${hook_name} hook"
  fi
}

function init_repo () {

  # Initialize Git
  git init
  
  # Initialize Git LFS
  git lfs install
  for t in "${LFS_TYPES[@]}"; do
    git lfs track $t
  done

}

function bootstrap_hooks () {

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
  "${NEW_HOOKS_DIR}"/git-store-meta.pl --install

  # merge with originals and remove double shebang if present
  merge_hook pre-commit
  merge_hook post-checkout
  merge_hook post-merge

  # cleanup any files left behind
  rm -f ${ORIG_HOOKS_DIR}/pre-commit.meta ${ORIG_HOOKS_DIR}/pre-commit.orig \
    ${ORIG_HOOKS_DIR}/post-checkout.meta ${ORIG_HOOKS_DIR}/post-checkout.orig \
    ${ORIG_HOOKS_DIR}/post-merge.meta ${ORIG_HOOKS_DIR}/post-merge.orig \
    ${ORIG_HOOKS_DIR}/*.sample

  # move hooks folder out of .git so it can be committed
  mv -f "${ORIG_HOOKS_DIR}" "${NEW_HOOKS_DIR}"

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

if ! [ -d "${NEW_HOOKS_DIR}" ]; then
  mkdir "${NEW_HOOKS_DIR}"
fi

if ! [ -f "${NEW_HOOKS_DIR}/git-store-meta.pl" ]; then
  echo "\033[32mGit Store Meta not found, downloading... \033[0m" >&2
  curl -s -L -OO "${RELEASE_BASEURL}/${RELEASE_VERSION}/git-store-meta{.pl,.pl.sha256}"
  shasum -a256 -c git-store-meta.pl.sha256
  if [ $? -ne 0 ]; then
    echo "\033[31mError \033[0m" >&2
    exit 1
  fi
  mv "git-store-meta.pl" "${NEW_HOOKS_DIR}/git-store-meta.pl"
  mv "git-store-meta.pl.sha256" "${NEW_HOOKS_DIR}"
fi

# make sure local hook is executable, if exists
if [ -f "${NEW_HOOKS_DIR}/git-store-meta.pl" ]; then
  chmod a+x "${NEW_HOOKS_DIR}/git-store-meta.pl"
fi

# Check ignore rules. Assume owner of repo has access to all plugins so
# that Freeze Files are not needed. Otherwise, manually zip up the Freeze Files
# folder if needed to the archive
touch .gitignore
for g in "${GIT_IGNORE[@]}"; do
  # Special thanks to:
  # https://stackoverflow.com/a/3557165/1603489
  grep -qxF "$g" .gitignore || echo "$g" >> .gitignore
done

if ! [ -d "./.git" ]; then
  init_repo
fi

if ! [ -d "${LFS_DIR}" ]; then
  git lfs install
fi

# check if repo has a remote, pull LFS files
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1
if [ $? -eq 0 ]; then
  git lfs pull
fi

# look for one of the hooks
if ! [ -f "${NEW_HOOKS_DIR/pre-commit}" ]; then
  bootstrap_hooks
fi

# enable pre-commit hook
touch .git_store_meta

# initialize hooks location (must be done after each clone)
git config core.hooksPath "${NEW_HOOKS_DIR}"
echo "\033[32mgit config core.hooksPath [${NEW_HOOKS_DIR}] successfully initialized \033[0m" >&2

# apply changes for fresh clones
if [ -s .git_store_meta ]
then
   ./"${NEW_HOOKS_DIR}/git-store-meta.pl" --apply
else
   # configure empty file
   ./"${NEW_HOOKS_DIR}/git-store-meta.pl" --store -f "${GIT_META_FIELDS}"
fi
if [ $? -ne 0 ]; then
  echo "\033[31mError \033[0m" >&2
  exit 1
fi

echo "\033[32mCheers! \033[0m" >&2
