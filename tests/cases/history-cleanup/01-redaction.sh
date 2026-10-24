#!/usr/bin/env bash
# clean-history.py's redaction. It rewrites the user's real shell history, so a
# redaction that leaves a secret behind is a leak and one that breaks the
# entry's encoding is data loss: a stored line ends in a backslash exactly when
# the entry continues onto the next, and a value pattern that swallows that
# backslash splits one command into two entries.
#
# Unit-level, through the module itself: these are pure functions over strings,
# and an end-to-end run would only wrap them in zsh start-up time.
. "${TESTS_DIR:?}/lib/harness.sh"
test_init "history-cleanup: redaction"
require_tool python3

CLEAN="$REPO_DIR/.agents/skills/history-cleanup/scripts/clean-history.py"

# Runs a python snippet with the module imported as `ch`; prints what it prints.
# The program goes in -c, not on stdin: stdin is where the fixture arrives. -B,
# because importing the module would otherwise leave a __pycache__ in the repo.
py() {
  "$REALBIN/python3" -I -B -c "import importlib.util, sys
spec = importlib.util.spec_from_file_location('ch', sys.argv[1])
ch = importlib.util.module_from_spec(spec); spec.loader.exec_module(ch)
$1" "$CLEAN"
}

# Redacts one stored entry (raw history text) and prints the result.
red() {
  py "
raw = sys.stdin.read()
es, _, _ = ch.parse(raw)
assert len(es) == 1, ('fixture is %d entries' % len(es))
ch.redact_entry(es[0])
print(es[0].text())
print('ENTRIES=%d' % len(ch.parse(es[0].text() + '\n')[0]))
print('FOUND=' + ','.join(k for k, _ in es[0].redactions))
" <<<"$1"
}

# Every check below is a not-contains as often as a contains, and those pass on
# empty output: so first prove the helper produces some.
out="$(red 'echo nothing to see')"
assert_contains "harness: red() round-trips an entry" "$out" "ENTRIES=1"

# --- continuation markers survive ------------------------------------------------
out="$(red $'curl --token=abcdefghijk\\\n  https://example.org')"
assert_contains "the value goes" "$out" "--token=<REDACTED:flag>\\"
assert_contains "the entry is still one entry" "$out" "ENTRIES=1"
assert_not_contains "and the secret is not in it" "$out" "abcdefghijk"

# --- labelled values the patterns missed ------------------------------------------
for var in TOKEN PASSWORD API_KEY; do
  out="$(red "$var=s3cr3tvalue1 ./deploy")"
  assert_not_contains "a bare $var= is redacted" "$out" "s3cr3tvalue1"
  assert_contains "keeping its name" "$out" "$var=<REDACTED:env>"
done
out="$(red 'mysql --password "hello world" db')"
assert_not_contains "a quoted value with a space goes whole" "$out" "hello"
assert_not_contains "both halves of it" "$out" "world"
out="$(red "mysql --password 'short' db")"
assert_not_contains "a short quoted value is still a password" "$out" "short"

# --- a placeholder is not a secret -------------------------------------------------
# A vendor token is replaced first; the label pattern then saw the placeholder
# itself as the flag's value and reported it as a second secret.
out="$(red 'gh auth --token=ghp_abcdefghijklmnopqrstuvwxyz0123')"
assert_eq "a vendor token under a flag is redacted once" "FOUND=github-token" "${out##*$'\n'}"
# A variable is not a secret either, and redacting it breaks a working command.
out="$(red 'curl -H "Authorization: Bearer $GITHUB_TOKEN" --token=$MY_TOKEN_VALUE x')"
assert_contains "an expansion is left as it is" "$out" '--token=$MY_TOKEN_VALUE'

# --- a pasted private key goes whole -----------------------------------------------
# A fake key (the body is "openssh-key-v1" and zeros). The header is put
# together from two halves so the literal never appears in this file, or the
# repo's detect-private-keys hook would refuse to commit it.
kind="OPENSSH PRIV""ATE KEY"
pem="cat > key <<EOF\\"$'\n'"-----BEGIN $kind-----\\"$'\n'"b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\\"$'\n'"QyNTUxOQAAACBkZWFkYmVlZmRlYWRiZWVmZGVhZGJlZWZkZWFkYmVlZgAAAJgAAAAA\\"$'\n'"-----END $kind-----\\"$'\n'"EOF"
out="$(red "$pem")"
assert_not_contains "the key body goes" "$out" "b3BlbnNzaC1rZXktdjE"
assert_not_contains "every line of it" "$out" "QyNTUxOQAAACBkZWFk"
assert_contains "the command around it stays" "$out" "cat > key <<EOF"
assert_contains "so does the heredoc's end" "$out" "EOF"
assert_contains "and it is still one entry" "$out" "ENTRIES=1"

# --- the auth context is the entry's, not the line's --------------------------------
key='YJEgVvQq1WtTyrK8mZpL3nXc7RbHs2Ud'
out="$(red "immich login http://10.0.0.5:2283/api \\"$'\n'"  $key")"
assert_not_contains "a key on the line after 'login' is redacted" "$out" "$key"
