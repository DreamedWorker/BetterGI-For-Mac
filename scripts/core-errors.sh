#!/bin/bash
# Builds src/BetterGI.Core and prints a summary of the compile errors (porting progress meter).
cd "$(dirname "$0")/.."
export PATH="$HOME/.dotnet:$PATH" DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
[ -d "$HOME/.dotnet" ] && export DOTNET_ROOT="$HOME/.dotnet"
LOG="${1:-/tmp/bgi-core-build.log}"
dotnet build src/BetterGI.Core -clp:ErrorsOnly -p:WarningLevel=0 2>&1 | grep "error" | sort -u > "$LOG"
echo "errors: $(wc -l < "$LOG" | tr -d ' ')   files: $(grep -oE 'upstream/[^(]+\.cs' "$LOG" | sort -u | wc -l | tr -d ' ')"
grep -oE "error [A-Z]+[0-9]+" "$LOG" | sort | uniq -c | sort -rn | head -8
