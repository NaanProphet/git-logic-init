#!/bin/bash

## Unit tests for the hook dispatcher and the .d part harvesting in scripts/init.sh
## See https://github.com/NaanProphet/git-logic-init/issues/19
##
## To run tests, simply run `bash hooks-dispatcher.sh.t` from this folder.
## Output is TAP-ish; exits non-zero if any assertion fails.
##
## Everything here runs against throwaway folders under mktemp -- no real repo,
## no git-lfs and no Logic are needed, so this runs unchanged on CI.

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

function is () {
  local actual=$1
  local expected=$2
  local description=$3

  if [ "$actual" = "$expected" ]; then
    ok "${description}"
  else
    not_ok "${description} (expected '${expected}', got '${actual}')"
  fi
}

function file_exists () {
  local path=$1
  local description=$2

  if [ -f "${path}" ]; then
    ok "${description}"
  else
    not_ok "${description} (no such file: ${path})"
  fi
}

function file_missing () {
  local path=$1
  local description=$2

  if [ -e "${path}" ]; then
    not_ok "${description} (unexpectedly present: ${path})"
  else
    ok "${description}"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# a fresh <case>/{.githooks,staging} pair, echoed for the caller to cd into
function make_case () {
  local name=$1
  mkdir -p "${WORK}/${name}/.githooks" "${WORK}/${name}/staging"
  echo "${WORK}/${name}"
}

# a stub part that appends its own label and its arguments to ${WORK}/log,
# then exits with the given status
function make_part () {
  local path=$1
  local label=$2
  local status=$3

  mkdir -p "$(dirname "${path}")"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s:$*" >> "%s/log"\nexit %s\n' \
    "${label}" "${WORK}" "${status}" > "${path}"
  chmod a+x "${path}"
}

# the post-checkout hook git-store-meta v2.0.1 writes, verbatim enough to
# exercise both the interpreter lookup and the arguments Git passes in
function make_store_meta_hook () {
  local path=$1
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<'EOF'
#!/bin/sh
# when running the hook, cwd is the top level of working tree

script=$(dirname "$0")/git-store-meta.pl
[ ! -x "$script" ] && script=git-store-meta.pl

sha_old=$1
sha_new=$2
change_br=$3

# apply metadata only when HEAD is changed
if [ ${sha_new} != ${sha_old} ]; then
    "$script" --apply
fi
EOF
  chmod a+x "${path}"
}

## ---------------------
## The interpreter rewrite. Parts live one folder deeper than the hooks
## git-store-meta generates for, so the relative lookup has to be adjusted or
## post-* parts die with 127 -- which Git ignores, so timestamps would silently
## stop being restored.
## ---------------------
echo "# the git-store-meta interpreter path is rewritten on the way in"

CASE="$(make_case rewrite)"
make_store_meta_hook "${CASE}/staging/post-checkout"
harvest_store_meta_parts "${CASE}/staging" "${CASE}/.githooks"
is "$?" "0" "harvesting a well-formed hook succeeds"

PART="${CASE}/.githooks/post-checkout.d/${META_PART}"
file_exists "${PART}" "the part lands at post-checkout.d/${META_PART}"

if [ -x "${PART}" ]; then
  ok "the part is executable"
else
  not_ok "the part is executable"
fi

if grep -qF 'script=$(dirname "$0")/../git-store-meta.pl' "${PART}"; then
  ok "the interpreter path points one folder up"
else
  not_ok "the interpreter path points one folder up"
fi

file_missing "${CASE}/staging/post-checkout" "the staged copy is consumed"

## ---------------------
## The whole point of the rewrite: run the part the way Git runs it, from the
## top of the working tree. This is the reproduction from issue #19, which
## exits 127 without the rewrite.
## ---------------------
echo "# the harvested part locates the interpreter when run from the repo root"

printf '#!/bin/sh\nexit 0\n' > "${CASE}/.githooks/git-store-meta.pl"
chmod a+x "${CASE}/.githooks/git-store-meta.pl"
( cd "${CASE}" && ./.githooks/post-checkout.d/"${META_PART}" a b 1 )
is "$?" "0" "the part runs from the repository root"

## ---------------------
## A changed upstream format has to fail loudly at TAG_COMMIT bump time. It
## must not leave a half-written part behind either: `>` truncates before sed
## runs, so writing straight to the destination would leave a zero-byte file
## that the dispatcher skips as non-executable.
## ---------------------
echo "# a changed interpreter line aborts instead of shipping a broken part"

CASE="$(make_case changed-format)"
# the escapeshellarg form later git-store-meta releases emit
make_store_meta_hook "${CASE}/staging/post-checkout"
sed "s|^script=\(.*\)/git-store-meta\.pl\$|script=\1/'git-store-meta.pl'|" \
  "${CASE}/staging/post-checkout" > "${CASE}/staging/rewritten"
mv "${CASE}/staging/rewritten" "${CASE}/staging/post-checkout"

harvest_store_meta_parts "${CASE}/staging" "${CASE}/.githooks" 2>/dev/null
is "$?" "1" "harvesting an unrecognized hook fails"
file_missing "${CASE}/.githooks/post-checkout.d/${META_PART}" "no part is written"
file_missing "${CASE}/staging/post-checkout.tmp" "no temp file is left behind"

## ---------------------
## The same "verify it was produced" check for the git-lfs parts
## ---------------------
echo "# git-lfs parts are verified before they are moved"

CASE="$(make_case lfs)"
printf '#!/bin/sh\ncommand -v git-lfs >/dev/null 2>&1 || exit 2\ngit lfs post-checkout "$@"\n' \
  > "${CASE}/staging/post-checkout"
harvest_lfs_parts "${CASE}/staging" "${CASE}/.githooks"
is "$?" "0" "harvesting a git-lfs hook succeeds"
file_exists "${CASE}/.githooks/post-checkout.d/${LFS_PART}" "the part lands at post-checkout.d/${LFS_PART}"

CASE="$(make_case lfs-bad)"
printf '#!/bin/sh\nexit 0\n' > "${CASE}/staging/post-checkout"
harvest_lfs_parts "${CASE}/staging" "${CASE}/.githooks" 2>/dev/null
is "$?" "1" "a hook that is not from git-lfs fails"

CASE="$(make_case lfs-empty)"
harvest_lfs_parts "${CASE}/staging" "${CASE}/.githooks" 2>/dev/null
is "$?" "1" "generating no hooks at all fails"

## ---------------------
## Dispatch order and argument passing. Prefixes are sort order, not priority:
## LFS has to restore file contents before git-store-meta stamps mtimes.
## ---------------------
echo "# parts run in sort order and receive the hook's arguments"

CASE="$(make_case order)"
make_part "${CASE}/.githooks/post-checkout.d/${LFS_PART}" lfs 0
make_part "${CASE}/.githooks/post-checkout.d/${META_PART}" meta 0
write_dispatcher "${CASE}/.githooks" post-checkout
is "$?" "0" "the dispatcher is generated"

rm -f "${WORK}/log"
"${CASE}/.githooks/post-checkout" old new 1
is "$?" "0" "the dispatcher exits 0 when every part succeeds"
is "$(tr '\n' ' ' < "${WORK}/log")" "lfs:old new 1 meta:old new 1 " \
  "parts run 10- before 20-, each with the hook's arguments"

## ---------------------
## Skipped files. A non-executable part is inert, and so is an editor backup --
## which keeps its mode when copied from an executable part, hence the
## explicit suffix check.
## ---------------------
echo "# non-executable files and editor backups are skipped"

make_part "${CASE}/.githooks/post-checkout.d/15-not-executable" notexec 0
chmod a-x "${CASE}/.githooks/post-checkout.d/15-not-executable"
make_part "${CASE}/.githooks/post-checkout.d/16-editor~" backup 0
make_part "${CASE}/.githooks/post-checkout.d/17-editor.bak" bak 0

rm -f "${WORK}/log"
"${CASE}/.githooks/post-checkout" old new 1
is "$(tr '\n' ' ' < "${WORK}/log")" "lfs:old new 1 meta:old new 1 " \
  "only the executable, non-backup parts run"

## ---------------------
## Exit-code policy. A failing pre-* part has to block the operation; Git
## ignores the status of post-* hooks, so aborting there would only skip the
## remaining parts for no benefit.
## ---------------------
echo "# pre-* aborts on the first failure, post-* records it and continues"

CASE="$(make_case exit-policy)"
make_part "${CASE}/.githooks/pre-commit.d/10-fails" fails 3
make_part "${CASE}/.githooks/pre-commit.d/20-later" later 0
write_dispatcher "${CASE}/.githooks" pre-commit

rm -f "${WORK}/log"
"${CASE}/.githooks/pre-commit" 2>/dev/null
is "$?" "3" "pre-commit exits with the failing part's status"
is "$(tr '\n' ' ' < "${WORK}/log")" "fails: " "pre-commit does not run later parts"

make_part "${CASE}/.githooks/post-checkout.d/10-fails" fails 3
make_part "${CASE}/.githooks/post-checkout.d/20-later" later 0
write_dispatcher "${CASE}/.githooks" post-checkout

rm -f "${WORK}/log"
"${CASE}/.githooks/post-checkout" old new 1 2>/dev/null
is "$(tr '\n' ' ' < "${WORK}/log")" "fails:old new 1 later:old new 1 " \
  "post-checkout runs later parts anyway"

## ---------------------
## The failing part has to be named, otherwise a failing hook means hunting
## through the .d folder for which one it was.
## ---------------------
echo "# a failing part is named on stderr"

rm -f "${WORK}/log"
STDERR="$("${CASE}/.githooks/post-checkout" old new 1 2>&1 >/dev/null)"
case "${STDERR}" in
  *"post-checkout: part 10-fails exited 3"*) ok "the dispatcher names the failing part and its status" ;;
  *) not_ok "the dispatcher names the failing part and its status (got '${STDERR}')" ;;
esac

## ---------------------
## stdin is a stream, so the first part to read it consumes it. Only pre-push
## and post-rewrite receive anything on stdin and each has a single part today,
## so no buffering is implemented -- but a second part would silently see EOF,
## so refuse rather than pretend.
## ---------------------
echo "# a stdin-consuming hook refuses to dispatch more than one part"

CASE="$(make_case stdin)"
make_part "${CASE}/.githooks/pre-push.d/${LFS_PART}" lfs 0
write_dispatcher "${CASE}/.githooks" pre-push
is "$?" "0" "one part in pre-push.d is fine"

# added after init.sh ran, so only the dispatcher's own check catches it
make_part "${CASE}/.githooks/pre-push.d/50-user-script" user 0
STDERR="$("${CASE}/.githooks/pre-push" origin git@example.com:x.git </dev/null 2>&1 >/dev/null)"
STATUS=$?
if [ "${STATUS}" -ne 0 ]; then
  ok "a second pre-push part makes the dispatcher exit non-zero"
else
  not_ok "a second pre-push part makes the dispatcher exit non-zero (got ${STATUS})"
fi
case "${STDERR}" in
  *"stdin buffering"*) ok "the dispatcher explains why it refused" ;;
  *) not_ok "the dispatcher explains why it refused (got '${STDERR}')" ;;
esac

# and init.sh itself refuses to regenerate while the second part is there
write_dispatcher "${CASE}/.githooks" pre-push 2>/dev/null
is "$?" "1" "generating a pre-push dispatcher with two parts fails"

## ---------------------
## Regenerating is idempotent: the dispatcher is byte-identical run to run --
## no timestamps, no version strings -- and parts nobody else owns are never
## touched. Both are what keeps `git status` clean after a re-init.
## ---------------------
echo "# regeneration leaves user parts and the dispatcher itself untouched"

CASE="$(make_case idempotent)"
make_part "${CASE}/.githooks/post-checkout.d/${LFS_PART}" lfs 0
make_part "${CASE}/.githooks/post-checkout.d/50-user-script" user 0
USER_PART="${CASE}/.githooks/post-checkout.d/50-user-script"
USER_BEFORE="$(cksum < "${USER_PART}")"

write_dispatcher "${CASE}/.githooks" post-checkout
FIRST="$(cksum < "${CASE}/.githooks/post-checkout")"
write_dispatcher "${CASE}/.githooks" post-checkout
SECOND="$(cksum < "${CASE}/.githooks/post-checkout")"

is "${SECOND}" "${FIRST}" "the dispatcher is byte-identical on the second run"
is "$(cksum < "${USER_PART}")" "${USER_BEFORE}" "a user-supplied part is untouched"

rm -f "${WORK}/log"
"${CASE}/.githooks/post-checkout" old new 1
is "$(tr '\n' ' ' < "${WORK}/log")" "lfs:old new 1 user:old new 1 " \
  "the user-supplied part still runs"

## ---------------------
## remove_parts clears out only the generated part, so a hook a tool stops
## generating does not keep a stale one -- without disturbing anything else.
## ---------------------
echo "# regenerating clears the previous generated part only"

remove_parts "${CASE}/.githooks" "${LFS_PART}"
file_missing "${CASE}/.githooks/post-checkout.d/${LFS_PART}" "the generated part is removed"
file_exists "${USER_PART}" "the user-supplied part survives"

## ---------------------
## Migration. Existing repos have single-file merged hooks; the generated
## halves are recreated anyway, so the backup exists only so that hand-edited
## content is recoverable.
## ---------------------
echo "# merged hooks are backed up before they are regenerated"

CASE="$(make_case migrate)"
printf '#!/bin/sh\n# hand-edited\n' > "${CASE}/.githooks/pre-commit"
printf '#!/bin/sh\n# already a dispatcher\n' > "${CASE}/.githooks/post-checkout"
mkdir -p "${CASE}/.githooks/post-checkout.d"
printf '#!/usr/bin/perl\n' > "${CASE}/.githooks/git-store-meta.pl"

migrate_legacy_hooks "${CASE}/.githooks" 2>/dev/null
is "$?" "0" "migration succeeds"
file_exists "${CASE}/.githooks/${MIGRATION_DIR}/pre-commit" "the merged hook is backed up"
is "$(cat "${CASE}/.githooks/${MIGRATION_DIR}/pre-commit")" \
  "$(cat "${CASE}/.githooks/pre-commit")" "the backup is a faithful copy"
file_missing "${CASE}/.githooks/${MIGRATION_DIR}/post-checkout" \
  "a hook that already has a .d folder is left alone"
file_missing "${CASE}/.githooks/${MIGRATION_DIR}/git-store-meta.pl" \
  "files that are not hook names are ignored"

## ---------------------
## Anything already sitting in the staging folder is somebody's hook, so it is
## set aside rather than deleted. Git's own samples are just boilerplate.
## ---------------------
echo "# the staging folder is emptied without losing anyone's hooks"

CASE="$(make_case staging)"
printf '#!/bin/sh\nexit 0\n' > "${CASE}/staging/pre-commit.sample"
printf '#!/bin/sh\n# somebody else\n' > "${CASE}/staging/commit-msg"

clear_staging_hooks "${CASE}/staging" "${CASE}/.githooks" 2>/dev/null
is "$?" "0" "clearing the staging folder succeeds"
file_missing "${CASE}/staging/pre-commit.sample" "Git's samples are removed"
file_missing "${CASE}/staging/commit-msg" "the staging folder ends up empty"
file_exists "${CASE}/.githooks/${MIGRATION_DIR}/commit-msg.staging" \
  "an unexpected staged hook is set aside"

## ---------------------
echo "1..${count}"
if [ "$failed" -gt 0 ]; then
  echo "# FAILED ${failed} of ${count} tests"
  exit 1
fi
echo "# passed ${count} tests"
