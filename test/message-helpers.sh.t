#!/bin/bash

## Unit tests for err(), warn() and info() in scripts/init.sh
## See https://github.com/NaanProphet/git-logic-init/issues/15
##
## To run tests, simply run `bash message-helpers.sh.t` from this folder.
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

# the escape character itself, for comparing against what the helpers emit
ESC=$(printf '\033')

## ---------------------
## The bug: the echo builtin only expands \033 when xpg_echo is on, which Apple's
## build enables in sh mode only. Under plain bash -- which is how CI runs this
## file, and what the shebang declares -- the old code printed the six literal
## characters \033[ instead of an escape sequence.
## ---------------------
function emits_escape () {
  local helper=$1
  local color=$2
  local actual
  actual=$( "${helper}" 'hello' 2>&1 )

  if [ "$actual" = "${ESC}[${color}m hello ${ESC}[0m" ]; then
    ok "${helper}() emits a real escape sequence"
  else
    not_ok "${helper}() emits a real escape sequence (got '${actual}')"
  fi
}

echo "# escapes are expanded, not printed literally"
emits_escape err 31
emits_escape warn 33
emits_escape info 32

## ---------------------
## The same output is required in sh/POSIX mode. That mode cannot be exercised
## by running this file under sh: CI is Linux, where /bin/sh is dash, and dash
## cannot even parse init.sh (typeset -a, [[ ]], function name ()). Setting
## xpg_echo inside bash reproduces the flag that made macOS sh differ, which is
## the actual variable under test.
## ---------------------
function identical_under_xpg_echo () {
  local helper=$1
  local default_mode
  local xpg_mode
  default_mode=$( "${helper}" 'hello' 2>&1 )
  xpg_mode=$( shopt -s xpg_echo; "${helper}" 'hello' 2>&1 )

  if [ "$default_mode" = "$xpg_mode" ]; then
    ok "${helper}() renders identically with xpg_echo set"
  else
    not_ok "${helper}() renders identically with xpg_echo set (got '${xpg_mode}')"
  fi
}

echo "# rendering does not depend on the xpg_echo flag"
identical_under_xpg_echo err
identical_under_xpg_echo warn
identical_under_xpg_echo info

## ---------------------
## Messages interpolate paths and version strings, so they must be passed as %s
## arguments rather than as the format string itself
## ---------------------
function passes_message_through () {
  local helper=$1
  local message=$2
  local description=$3
  local actual
  actual=$( "${helper}" "${message}" 2>&1 )

  if [ "$actual" = "${ESC}[31m ${message} ${ESC}[0m" ] \
    || [ "$actual" = "${ESC}[33m ${message} ${ESC}[0m" ] \
    || [ "$actual" = "${ESC}[32m ${message} ${ESC}[0m" ]; then
    ok "${helper}() ${description}"
  else
    not_ok "${helper}() ${description} (got '${actual}')"
  fi
}

echo "# a % in the message is not read as a format specifier"
passes_message_through err '100%s done' 'keeps a literal %s'
passes_message_through warn 'saved to /tmp/50%d' 'keeps a literal %d'
passes_message_through info 'discount: 50%' 'keeps a trailing %'

## ---------------------
## Every message is diagnostic output, so stdout stays clean for anything that
## pipes the script
## ---------------------
function writes_to_stderr_only () {
  local helper=$1
  local on_stdout
  on_stdout=$( "${helper}" 'hello' 2>/dev/null )

  if [ -z "$on_stdout" ]; then
    ok "${helper}() writes nothing to stdout"
  else
    not_ok "${helper}() writes nothing to stdout (got '${on_stdout}')"
  fi
}

echo "# messages go to stderr"
writes_to_stderr_only err
writes_to_stderr_only warn
writes_to_stderr_only info

## ---------------------
## Regression guard for the acceptance criteria: no escape sequence may be
## handed to echo again, in any script
## ---------------------
echo "# no echo carries backslash escapes"
offenders=$( grep -n 'echo .*\\033' "${DIR}"/../scripts/*.sh )
if [ -z "$offenders" ]; then
  ok "scripts/*.sh use printf for coloured output"
else
  not_ok "scripts/*.sh use printf for coloured output (found: ${offenders})"
fi

## ---------------------
echo "1..${count}"
if [ "$failed" -gt 0 ]; then
  echo "# FAILED ${failed} of ${count} tests"
  exit 1
fi
echo "# passed ${count} tests"
