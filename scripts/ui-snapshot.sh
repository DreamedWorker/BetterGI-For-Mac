#!/bin/bash
# Renders one page of the app to a PNG without needing Screen Recording: scripts/ui-snapshot.sh <page index> <out.png>
cd "$(dirname "$0")/.."
export DOTNET_ROOT="$HOME/.dotnet"
rm -f "$2"
BGI_UI_SNAPSHOT="$2" BGI_UI_PAGE="$1" "$HOME/.dotnet/dotnet" src/BetterGI.Mac/bin/Debug/net10.0/BetterGI.dll > /dev/null 2>&1 &
PID=$!
for i in $(seq 1 20); do [ -f "$2" ] && break; perl -e 'select(undef,undef,undef,1)'; done
perl -e 'select(undef,undef,undef,0.5)'
kill $PID 2>/dev/null
ls -la "$2" | awk '{print $5, $9}'
