#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$HOME/dotfiles/bin/src/capture.bash"
failures=0
assert() {
	if "$@"; then printf 'ok - %s\n' "$*"; else printf 'not ok - %s\n' "$*" >&2; failures=$((failures + 1)); fi
}
if [ ! -f "$root/scripts/tmp-cleanup" ]; then
	printf 'not ok - cleanup implementation is missing\n' >&2
	exit 1
fi
source "$root/scripts/tmp-cleanup"

# Exhaust the timestamp boundary product against the declared inactivity rule.
for access in 13599 13600 13601; do
	for modify in 13599 13600 13601; do
		for change in 13599 13600 13601; do
			expected=1
			if (( access <= 13600 && modify <= 13600 && change <= 13600 )); then expected=0; fi
			if tmp_cleanup_eligible 100000 "$access" "$modify" "$change"; then actual=0; else actual=$?; fi
			assert test "$actual" -eq "$expected"
		done
	done
done

fixture=$(mktemp -d) || exit 1
trap 'rm-safe -r -- "$fixture" >/dev/null' EXIT
mkdir -p "$fixture/tmp/busy" "$fixture/tmp/mapped" "$fixture/tmp/idle-directory" "$fixture/proc/123/fd" "$fixture/recovery"
mkdir -p "$fixture/tmp/fresh-access" "$fixture/tmp/fresh-modify" "$fixture/tmp/mounted" "$fixture/proc/self"
printf 'recently accessed\n' > "$fixture/tmp/fresh-access/content"
printf 'recently modified\n' > "$fixture/tmp/fresh-modify/content"
touch -a -d '@10000000001' "$fixture/tmp/fresh-access/content"
touch -m -d '@10000000001' "$fixture/tmp/fresh-modify/content"
printf 'nested mount\n' > "$fixture/tmp/mounted/content"
printf '1 0 0:1 / %s rw - tmpfs tmpfs rw\n' "$fixture/tmp/mounted" > "$fixture/proc/self/mountinfo"
mkfifo "$fixture/tmp/socket-like-fifo"
printf 'idle tree\n' > "$fixture/tmp/idle-directory/content"
printf 'recover me\n' > "$fixture/tmp/old file.txt"
printf 'keep me\n' > "$fixture/tmp/busy/old.txt"
printf 'mapped data\n' > "$fixture/tmp/mapped/old.txt"
printf '0000-1000 rw-p 00000000 00:00 0       \n1000-2000 r--p 00000000 00:01 1 %s\n' "$fixture/tmp/mapped/old.txt" > "$fixture/proc/123/maps"
printf 'symlink target\n' > "$fixture/target"
ln -s "$fixture/target" "$fixture/tmp/link"
ln -s "$fixture/tmp/busy/old.txt" "$fixture/proc/123/fd/7"
# The injected clock makes newly created fixtures deterministically older than
# one day, including ctime; wall-clock sleeps and privileged time changes vanish.
out='' err='' rc=0
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/recovery" 10000000000 dry-run
assert test "$rc" -eq 0
assert test -f "$fixture/tmp/old file.txt"
assert test -f "$fixture/tmp/busy/old.txt"
assert test -f "$fixture/tmp/mapped/old.txt"
mkdir -p "$fixture/shadow-bin"
printf '#!/usr/bin/env bash\nexit 97\n' > "$fixture/shadow-bin/rm"
chmod +x "$fixture/shadow-bin/rm"
original_path="$PATH"
PATH="$fixture/shadow-bin:$PATH"
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/recovery" 10000000000 apply
PATH="$original_path"
assert test "$rc" -eq 0
assert test ! -e "$fixture/tmp/old file.txt"
assert test ! -e "$fixture/tmp/idle-directory"
assert test -f "$fixture/tmp/busy/old.txt"
assert test -f "$fixture/tmp/mapped/old.txt"
assert test -L "$fixture/tmp/link"
assert test -f "$fixture/tmp/fresh-access/content"
assert test -f "$fixture/tmp/fresh-modify/content"
assert test -f "$fixture/tmp/mounted/content"
assert test -p "$fixture/tmp/socket-like-fifo"
mapfile -t recovered < <(find "$fixture/recovery" -type f -name 'old file.txt')
assert test "${#recovered[@]}" -eq 0
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/recovery" 10000000000 apply
assert test "$rc" -eq 0
mapfile -t recovered < <(find "$fixture/recovery" -type f -name 'old file.txt')
assert test "${#recovered[@]}" -eq 0

# A process whose cwd is the root protects the entire temporary filesystem.
ln -s "$fixture/tmp" "$fixture/proc/123/cwd"
printf 'whole root busy\n' > "$fixture/tmp/protected.txt"
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/recovery" 10000000000 apply
assert test "$rc" -eq 0
assert test -f "$fixture/tmp/protected.txt"
capture tmp_cleanup_run / "$fixture/proc" "$fixture/recovery" 10000000000 apply
assert test "$rc" -ne 0

capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/tmp/recovery" 10000000000 apply
assert test "$rc" -ne 0

# Inspection failure must not turn into an empty busy set.
readlink() { return 1; }
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/recovery" 10000000000 apply
assert test "$rc" -ne 0
assert test -f "$fixture/tmp/protected.txt"
unset -f readlink

# A per-file error leaves that file and does not prevent an independent move.
unlink "$fixture/proc/123/cwd"
printf 'retain after error\n' > "$fixture/tmp/problem"
printf 'independent retirement\n' > "$fixture/tmp/independent"
stat() {
	if [[ "${*: -1}" == */problem ]]; then printf 'fixture stat failure\n' >&2; return 1; fi
	command stat "$@"
}
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/recovery" 10000000000 apply
assert test "$rc" -ne 0
assert test -f "$fixture/tmp/problem"
assert test ! -e "$fixture/tmp/independent"
assert test "${#err}" -gt 0
unset -f stat

printf 'cleanup tests: %d failure(s)\n' "$failures"
exit "$failures"
