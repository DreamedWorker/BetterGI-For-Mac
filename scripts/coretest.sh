#!/bin/bash
# Regenerates the extracted upstream code, builds the app and runs the headless core self-test.
# Usage: scripts/coretest.sh [extra args for --coretest]
cd "$(dirname "$0")/.."
export PATH="$HOME/.dotnet:$PATH" DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
[ -d "$HOME/.dotnet" ] && export DOTNET_ROOT="$HOME/.dotnet"
python3 scripts/extract-upstream-members.py > /dev/null || exit 1
dotnet build src/BetterGI.Mac -clp:ErrorsOnly -p:WarningLevel=0 2>&1 | grep -E " error " | sed -E 's| \[/Users.*||; s|^.*/BetterGI-Mac/||' | sort -u | head -30
[ "${PIPESTATUS[0]}" -ne 0 ] && exit 1
dotnet src/BetterGI.Mac/bin/Debug/net10.0/BetterGI.dll --coretest "$@" 2>&1 | grep -v "^\[..:..:.. \(DBG\|INF\)" | tail -40
