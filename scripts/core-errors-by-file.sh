#!/bin/bash
# Prints compile errors from a core-errors.sh log, compactly, optionally filtered by a path substring.
LOG="${1:?log}"; FILTER="${2:-}"
grep "$FILTER" "$LOG" | sed -E 's| \[/Users[^]]*\]$||; s|^.*/upstream/BetterGenshinImpact/||; s|: error (CS[0-9]+): |: \1 |; s| ?\(are you missing[^)]*\)||' | cut -c1-200 | sort -u
