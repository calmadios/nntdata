#!/bin/sh

# Diff 2 SQL database dumps, with respect to entries, ignoring rowid
#
# Author: calmadios, 2020
# License: MIT

# TODO: Rewrite in C, work on multiple threads.

# Regular search for removed and updated entries
while IFS= read -r L; do
	ENTRY="$(printf "%s\n" "$L" | awk -F"'" '{print $2}')"
	[ -z "$ENTRY" ] && continue
	OLD_VALUE="$(printf "%s\n" "$L" | awk -vORS="\\\n" -F"'" '{print $4}' | awk '{print substr($0, 1, length($0)-2)}')"
	NEW_VALUE="$(grep "'$ENTRY'" ".$2.dump" | awk -vORS="\\\n" -F"'" '{print $4}' | awk '{print substr($0, 1, length($0)-2)}')"

	# Removed
	if [ -z "$NEW_VALUE" ]; then
		printf "%s\t%s\t%s\n" "---" "'$ENTRY'" "'$OLD_VALUE'"
	fi

	# Updated
	if [ "$OLD_VALUE" != "$NEW_VALUE" ]; then
		printf "%s\t%s\t%s\t%s\n" "~~~" "'$ENTRY'" "'$OLD_VALUE'" "'$NEW_VALUE'"
	fi
done < ".$1.dump"

# Reverse search for new entries
while IFS= read -r L; do
	ENTRY="$(printf "%s\n" "$L" | awk -F"'" '{print $2}')"
	[ -z "$ENTRY" ] && continue
	NEW_VALUE="$(printf "%s\n" "$L" | awk -vORS="\\\n" -F"'" '{print $4}' | awk '{print substr($0, 1, length($0)-2)}')"
	OLD_VALUE="$(grep "'$ENTRY'" ".$1.dump" | awk -vORS="\\\n" -F"'" '{print $4}' | awk '{print substr($0, 1, length($0)-2)}')"

	# Added
	if [ -z "$OLD_VALUE" ]; then
		printf "%s\t%s\t%s\n" "+++" "'$ENTRY'" "'$NEW_VALUE'"
	fi
done < ".$2.dump"
