#!/bin/bash

## Unit tests for compareVersions() and the Git version gate in scripts/init.sh
## See https://github.com/NaanProphet/git-logic-init/issues/14
##
## To run tests, simply run `bash compare-versions.sh.t` from this folder.
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
## compareVersions($v1, $v2) writes -1, 0 or 1 to stdout
## ---------------------
function is_version () {
  local v1=$1
  local v2=$2
  local expected=$3
  local actual
  actual=$(compareVersions "$v1" "$v2")

  if [ "$actual" = "$expected" ]; then
    ok "compareVersions '${v1}' '${v2}' is ${expected}"
  else
    not_ok "compareVersions '${v1}' '${v2}' is ${expected} (got '${actual}')"
  fi
}

## ---------------------
## the real version gate from init.sh, verbatim:
## the minimum echoing 1 against the installed version means too old
## ---------------------
function gate_fires () {
  local installed=$1

  if [ "$(compareVersions "$MIN_GIT_VERSION" "$installed")" -eq 1 ]; then
    ok "git ${installed} is rejected as older than ${MIN_GIT_VERSION}"
  else
    not_ok "git ${installed} is rejected as older than ${MIN_GIT_VERSION}"
  fi
}

function gate_passes () {
  local installed=$1

  if [ "$(compareVersions "$MIN_GIT_VERSION" "$installed")" -eq 1 ]; then
    not_ok "git ${installed} is accepted as at least ${MIN_GIT_VERSION}"
  else
    ok "git ${installed} is accepted as at least ${MIN_GIT_VERSION}"
  fi
}

## ---------------------
## the constant the gate depends on
## ---------------------
echo "# MIN_GIT_VERSION sourced from init.sh"
if [ -n "$MIN_GIT_VERSION" ]; then
  ok "MIN_GIT_VERSION is set (${MIN_GIT_VERSION})"
else
  not_ok "MIN_GIT_VERSION is set"
fi

## ---------------------
## given a version older than core.hooksPath support (added in git 2.9),
## the gate must fire -- otherwise the repo initializes with no active hooks
## ---------------------
echo "# versions older than ${MIN_GIT_VERSION} are rejected"
gate_fires "1.8.0"
gate_fires "1.8.5"
gate_fires "2.8.0"
gate_fires "2.8.5"

echo "# versions at or above ${MIN_GIT_VERSION} are accepted"
gate_passes "2.9"
gate_passes "2.9.0"
gate_passes "2.9.1"
gate_passes "2.43.0"
gate_passes "3.0"

## ---------------------
## an unparsed version (empty string) must fail closed, not sail through
## ---------------------
echo "# an unparsable git version fails closed"
is_version "$MIN_GIT_VERSION" "" 1

## ---------------------
## 2, 3 and 4 component version strings compare against each other
## ---------------------
echo "# 2, 3 and 4 component version strings"
is_version "2.9" "2.9.0" 0
is_version "2.9.0" "2.9" 0
is_version "2.9.0.0" "2.9" 0
is_version "2.9" "2.9.0.0" 0
is_version "1.8.5.2" "1.8.5.3" -1
is_version "1.8.5.3" "1.8.5.2" 1
is_version "2.9.1" "2.9" 1
is_version "2.9" "2.9.1" -1

## ---------------------
## ordering is numeric, not lexicographic (2.10 is newer than 2.9)
## ---------------------
echo "# ordering is numeric, not lexicographic"
is_version "2.43.0" "2.9" 1
is_version "2.9" "2.43.0" -1
is_version "2.10" "2.9" 1
is_version "2.9" "2.10" -1
is_version "10.0" "9.0" 1

## ---------------------
## a zero-padded component is base 10, not octal
## ---------------------
echo "# zero-padded components are base 10"
is_version "2.09" "2.9" 0
is_version "2.08" "2.9" -1

## ---------------------
echo "1..${count}"
if [ "$failed" -gt 0 ]; then
  echo "# FAILED ${failed} of ${count} tests"
  exit 1
fi
echo "# passed ${count} tests"
