#!/usr/bin/env bash
# clean-history.py --apply: classification, de-duplication and the write. The
# write is the dangerous part - it replaces the user's history file - so this is
# about what it may never do: drop a real command as "prose", collapse two
# different commands into one, lose an entry another shell appended while it
# ran, or leave the history readable by anyone on the way.
#
# Real zsh does the classifying and the verification, with HOME and ZDOTDIR
# pointed at an empty scratch directory so the user's own config, aliases and
# abbreviations play no part.
. "${TESTS_DIR:?}/lib/harness.sh"
test_init "history-cleanup: --apply"
require_tool python3 zsh

CLEAN="$REPO_DIR/.agents/skills/history-cleanup/scripts/clean-history.py"
export HOME="$TMP/home" ZDOTDIR="$TMP/home"
mkdir -p "$HOME"
unset HISTFILE ABBR_USER_ABBREVIATIONS_FILE
hist="$TMP/home/.zsh_history"

clean() { _capture "$REALBIN/python3" -I -B "$CLEAN" --history "$hist" "$@"; }

# The program goes in -c, not on stdin: stdin is where the fixture arrives. -B,
# because importing the module would otherwise leave a __pycache__ in the repo.
py() {
  "$REALBIN/python3" -I -B -c "import importlib.util, sys
spec = importlib.util.spec_from_file_location('ch', sys.argv[1])
ch = importlib.util.module_from_spec(spec); spec.loader.exec_module(ch)
$1" "$CLEAN"
}

# --- real commands are not prose --------------------------------------------------
# An unknown command with real arguments is for a human to decide on
# (unresolved-args); "not-a-command" is dropped by default, so a real command
# landing there is the dangerous direction.
bucket_of() {
  py "
es, _, _ = ch.parse(sys.stdin.read())
ch.classify(es, {'echo', 'ls'}, [], True)
print(es[0].bucket)
" <<<"$1"
}
assert_eq "an uninstalled tool with a capitalised argument" "unresolved-args" \
  "$(bucket_of 'terraform workspace select Production')"
assert_eq "a command behind env and an assignment is that command" "None" \
  "$(bucket_of 'env PATH=/bin echo hello')"
assert_eq "while pasted prose still is prose" "not-a-command" \
  "$(bucket_of 'The build failed because the cache was cold')"

# --- dedup compares the command exactly -------------------------------------------
n="$(py "
es, _, _ = ch.parse(': 1:0;printf %s a\\\\ \n: 2:0;printf %s a\\\\\t\n')
print(len(ch.dedup(es)))
")"
assert_eq "a trailing escaped space and an escaped tab are two commands" 2 "$n"

# --- --drop-command condemns a command --------------------------------------------
printf ': 1:0;ls\n: 2:0;oldtool --flag x\n: 3:0;echo hi\n' >"$hist"
clean --drop-command oldtool --apply --drop-bucket command
assert_exit "--drop-command applies" 0
assert_not_contains "the condemned command is gone" "$(cat "$hist")" "oldtool"
assert_contains "and nothing else" "$(cat "$hist")" "echo hi"

# --- an entry with a secret in it keeps its bucket ---------------------------------
# Redaction rebuilt the entry through its constructor, which reset the bucket
# classification had already given it: the one entry a --drop-pattern purge
# most wants gone - the one with a key in it - was the one that survived it.
printf ': 1:0;ls\n: 2:0;curl https://cookies.example/x?token=ac9f2122fbffde01\n' >"$hist"
clean --drop-pattern cookies --apply --drop-bucket pattern
assert_not_contains "a purged entry with a secret in it is purged" "$(cat "$hist")" "cookies"

# --- the write --------------------------------------------------------------------
printf ': 1:0;ls\n: 2:0;nosuchtool-xyz\n: 3:0;echo hi\n' >"$hist"
chmod 600 "$hist"
clean --apply --drop-bucket unresolved-bare
assert_exit "an ordinary apply exits 0" 0
assert_contains "and verifies" "$STDOUT" "(OK)"
assert_not_contains "the dead command is gone" "$(cat "$hist")" "nosuchtool-xyz"
backup="$(find "$TMP/home" -name '.zsh_history.bak-*' -print | head -n 1)"
assert_eq "the backup is private" 600 "$(stat -c %a "$backup")"
assert_eq "and so is the history" 600 "$(stat -c %a "$hist")"

# Two applies inside one second used to share a backup name, and the second
# overwrote the first - with history the first had already cleaned.
printf ': 1:0;ls\n: 2:0;nosuchtool-a\n' >"$hist"
cp "$hist" "$TMP/orig-a"
rm -f "$TMP/home"/.zsh_history.bak-*
clean --apply --drop-bucket unresolved-bare
clean --apply --drop-bucket unresolved-bare
assert_eq "two applies in a second keep two backups" 2 \
  "$(find "$TMP/home" -name '.zsh_history.bak-*' | awk 'END { print NR }')"
found=0
for b in "$TMP/home"/.zsh_history.bak-*; do cmp -s "$b" "$TMP/orig-a" && found=1; done
assert_eq "and one of them is the original" 1 "$found"

# --- an append from another shell is not lost --------------------------------------
# SHARE_HISTORY appends while the script runs. A zsh that stands in for the
# user's interactive shell appends one entry while being asked for its command
# names - after the script's first read, before its write.
printf ': 1:0;ls\n: 2:0;nosuchtool-b\n' >"$hist"
realzsh="$REALBIN/zsh"
cat >"$STUBDIR/zsh" <<EOF
#!$HARNESS_BASH
for a in "\$@"; do
  if [[ "\$a" == *'(k)commands'* && ! -e "$TMP/appended" ]]; then
    printf ': 9:0;echo typed-meanwhile\n' >>"$hist"
    : >"$TMP/appended"
  fi
done
exec "$realzsh" "\$@"
EOF
chmod +x "$STUBDIR/zsh"
PATH="$STUBDIR:$PATH" clean --apply --drop-bucket unresolved-bare
assert_exit "an apply with a concurrent append exits 0" 0
assert_contains "the appended entry survives" "$(cat "$hist")" "echo typed-meanwhile"
assert_not_contains "and the cleaning still happened" "$(cat "$hist")" "nosuchtool-b"
rm -f "$STUBDIR/zsh"

# --- a verification that fails is not OK -------------------------------------------
printf ': 1:0;ls\n' >"$hist"
cat >"$STUBDIR/zsh" <<EOF
#!$HARNESS_BASH
for a in "\$@"; do
  # the verification call: claim the right count, but fail
  [[ "\$a" == *'fc -R'* ]] && { echo ls; exit 3; }
done
exec "$realzsh" "\$@"
EOF
chmod +x "$STUBDIR/zsh"
PATH="$STUBDIR:$PATH" clean --apply
assert_not_contains "a failed zsh re-read is not reported OK" "$STDOUT" "(OK)"
rm -f "$STUBDIR/zsh"

# --- a zsh that fails while listing its commands ------------------------------------
# Whatever it printed before failing is a partial list, and every command missing
# from it would be called dead. So the classifier is switched off instead.
printf ': 1:0;ls\n: 2:0;git status\n' >"$hist"
cat >"$STUBDIR/zsh" <<EOF
#!$HARNESS_BASH
for a in "\$@"; do
  [[ "\$a" == *'(k)commands'* ]] && { echo ls; exit 1; }
done
exec "$realzsh" "\$@"
EOF
chmod +x "$STUBDIR/zsh"
PATH="$STUBDIR:$PATH" clean
assert_contains "a failed listing disables dead-command detection" "$STDERR" \
  "dead-command detection disabled"
assert_not_contains "rather than calling git dead" "$STDOUT" "unresolved-args"
rm -f "$STUBDIR/zsh"
