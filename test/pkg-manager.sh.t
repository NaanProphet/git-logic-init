#!/bin/bash

## Unit tests for detect_pkg_manager() in scripts/init.sh
## See https://github.com/NaanProphet/git-logic-init/issues/13
##
## To run tests, simply run `bash pkg-manager.sh.t` from this folder.
## Output is TAP-ish; exits non-zero if any assertion fails.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# source init.sh for its functions only, without running the installer
SOURCE_FUNCTIONS_ONLY=true
# shellcheck source=../scripts/init.sh
. "${DIR}/../scripts/init.sh"
unset SOURCE_FUNCTIONS_ONLY

count=0
failed=0

function ok () {
  local description=$1
  count=$((count+1))
  echo "ok ${count} - ${description}"
}

function not_ok () {
  local description=$1
  count=$((count+1))
  failed=$((failed+1))
  echo "not ok ${count} - ${description}"
}

## ---------------------
## fake package managers on disk, so the tests do not depend on whatever
## happens to be installed on the machine running them
## ---------------------
STUB_ROOT="$(mktemp -d)"
trap 'rm -rf "${STUB_ROOT}"' EXIT

function make_stub () {
  local dir=$1
  local name=$2

  mkdir -p "${dir}"
  printf '#!/bin/sh\nexit 0\n' > "${dir}/${name}"
  chmod a+x "${dir}/${name}"
}

make_stub "${STUB_ROOT}/brew-only" brew
make_stub "${STUB_ROOT}/port-only" port
make_stub "${STUB_ROOT}/both" brew
make_stub "${STUB_ROOT}/both" port
mkdir -p "${STUB_ROOT}/neither"

## ---------------------
## detect_pkg_manager() writes brew, port or nothing to stdout, based on PATH.
## The assignment happens inside the command substitution's subshell so the
## real PATH is never disturbed -- `command -v`, `[` and `echo` are all bash
## builtins, so an otherwise empty PATH is safe.
## ---------------------
function detects () {
  local dir=$1
  local expected=$2
  local description=$3
  local actual
  actual=$( PATH="${dir}"; detect_pkg_manager )

  if [ "$actual" = "$expected" ]; then
    ok "${description} is '${expected}'"
  else
    not_ok "${description} is '${expected}' (got '${actual}')"
  fi
}

echo "# each package manager is found on its own"
detects "${STUB_ROOT}/brew-only" "brew" "a machine with only Homebrew"
detects "${STUB_ROOT}/port-only" "port" "a machine with only MacPorts"

## ---------------------
## Homebrew wins the tie because its install needs no sudo
## ---------------------
echo "# Homebrew takes precedence when both are installed"
detects "${STUB_ROOT}/both" "brew" "a machine with both"

## ---------------------
## the empty string is what triggers the warning in init.sh -- it must not
## fall through to a bare "brew", which is the bug this issue is about
## ---------------------
echo "# neither installed reports nothing, so init.sh warns and continues"
detects "${STUB_ROOT}/neither" "" "a machine with neither"

## ---------------------
echo "1..${count}"
if [ "$failed" -gt 0 ]; then
  echo "# FAILED ${failed} of ${count} tests"
  exit 1
fi
echo "# passed ${count} tests"
