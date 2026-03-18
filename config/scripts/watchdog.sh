#!/bin/bash
# OpenClaw WhatsApp Connection Watchdog
# This script monitors WhatsApp connection and restarts gateway if disconnected

LOG_FILE="$HOME/.openclaw/logs/watchdog.log"
CHECK_INTERVAL=60  # Check every 60 seconds
MAX_RECONNECT_ATTEMPTS=3

mkdir -p "$HOME/.openclaw/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_connection() {
    # Check if gateway is running
    if ! pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
        log "Gateway not running, starting via launchctl..."
        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null
        sleep 10
    fi
    
    # Check WhatsApp connection status
    STATUS=$(OPENROUTER_API_KEY="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" openclaw channels status 2>&1 | grep -i "whatsapp" | head -1)
    
    if echo "$STATUS" | grep -q "connected"; then
        log "WhatsApp connected OK"
        return 0
    elif echo "$STATUS" | grep -q "disconnected\|error\|401"; then
        log "WhatsApp disconnected! Status: $STATUS"
        return 1
    else
        log "WhatsApp status unknown: $STATUS"
        return 2
    fi
}

reconnect() {
    log "Attempting to reconnect WhatsApp..."
    
    # Restart the gateway
    launchctl kickstart -k gui/$(id -u)/ai.openclaw.gateway 2>/dev/null
    sleep 15
    
    # Check if it reconnected
    STATUS=$(OPENROUTER_API_KEY="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" openclaw channels status 2>&1 | grep -i "whatsapp" | head -1)
    
    if echo "$STATUS" | grep -q "connected"; then
        log "WhatsApp reconnected successfully!"
        return 0
    else
        log "WhatsApp reconnection failed. May need manual QR scan."
        return 1
    fi
}

# Main loop
log "========== Watchdog started =========="

while true; do
    if ! check_connection; then
        reconnect_attempts=0
        while [ $reconnect_attempts -lt $MAX_RECONNECT_ATTEMPTS ]; do
            reconnect_attempts=$((reconnect_attempts + 1))
            log "Reconnect attempt $reconnect_attempts/$MAX_RECONNECT_ATTEMPTS"
            
            if reconnect; then
                break
            fi
            
            sleep 30
        done
        
        if [ $reconnect_attempts -ge $MAX_RECONNECT_ATTEMPTS ]; then
            log "Max reconnect attempts reached. Manual intervention may be required."
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
