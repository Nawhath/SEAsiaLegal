#!/bin/bash

# Website Monitoring Script for Ubuntu 14.04
# Description: Monitors website for database connection errors and restarts services if needed

# Configuration
TELEGRAM_BOT_TOKEN="7512739719:AAFWb5x73F8VJVh1oaD7sVZ7r_vaf8PhtkY"
TELEGRAM_CHAT_ID="-4963020838"
WEBSITE_URL="https://seasialegal.com/"
LOG_FILE="/var/log/website_monitor.log"
TIMEOUT=15  # Timeout for curl requests
MAX_RETRIES=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Create log file if it doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
fi

# Send Telegram notification
send_telegram_message() {
    local message="$1"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT \
            -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            -d "text=$message" \
            -d "parse_mode=HTML" > /dev/null 2>&1; then
            log "INFO" "Telegram message sent successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "WARN" "Failed to send Telegram message (attempt $retry_count/$MAX_RETRIES)"
            sleep 2
        fi
    done
    
    log "ERROR" "Failed to send Telegram message after $MAX_RETRIES attempts"
    return 1
}

# Check if service is running (Ubuntu 14.04 compatible)
check_service_status() {
    local service_name="$1"
    
    # Ubuntu 14.04 uses Upstart for most services
    if command -v initctl >/dev/null 2>&1; then
        # Check with initctl (Upstart)
        if initctl status "$service_name" 2>/dev/null | grep -q "start/running"; then
            return 0
        fi
    fi
    
    # Fallback to service command
    if service "$service_name" status 2>/dev/null | grep -q -E "(running|start/running|Active: active)"; then
        return 0
    fi
    
    # Additional check for MySQL specific
    if [ "$service_name" = "mysql" ]; then
        if pgrep mysqld > /dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Restart service with proper error handling
restart_service() {
    local service_name="$1"
    log "INFO" "Attempting to restart $service_name service..."
    
    # Stop service first
    service "$service_name" stop >/dev/null 2>&1
    sleep 3
    
    # Start service
    if service "$service_name" start >/dev/null 2>&1; then
        sleep 5  # Wait for service to stabilize
        
        # Verify service is running
        if check_service_status "$service_name"; then
            log "INFO" "$service_name service restarted successfully"
            return 0
        else
            log "ERROR" "$service_name service failed to start properly"
            return 1
        fi
    else
        log "ERROR" "Failed to start $service_name service"
        return 1
    fi
}

# Check website for database connection error
check_website() {
    local retry_count=0
    local website_content
    
    log "INFO" "Checking website: $WEBSITE_URL"
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Download website content with timeout and proper headers
        website_content=$(curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT \
            -H "User-Agent: Mozilla/5.0 (compatible; WebsiteMonitor/1.0)" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            "$WEBSITE_URL" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$website_content" ]; then
            break
        else
            retry_count=$((retry_count + 1))
            log "WARN" "Failed to fetch website content (attempt $retry_count/$MAX_RETRIES)"
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $MAX_RETRIES ]; then
        log "ERROR" "Unable to fetch website content after $MAX_RETRIES attempts"
        send_telegram_message "🚨 <b>CRITICAL:</b> Unable to access website $(hostname) - Connection timeout or network error!"
        return 2
    fi
    
    # Check for database connection error
    if echo "$website_content" | grep -q -i "error establishing a database connection\|database connection error\|unable to connect to database"; then
        log "ERROR" "Database connection error detected on website"
        send_telegram_message "🚨 <b>ALERT:</b> Website $(hostname) shows 'Error establishing a database connection'. Attempting to restart services..."
        return 1
    else
        log "INFO" "Website is accessible with no database connection error"
        return 0
    fi
}

# Verify website after service restart
verify_website_recovery() {
    local wait_time=10
    log "INFO" "Waiting ${wait_time} seconds for services to stabilize..."
    sleep $wait_time
    
    case $(check_website) in
        0)
            log "INFO" "Website recovered successfully"
            send_telegram_message "✅ <b>RESOLVED:</b> Website $(hostname) is back online after service restart."
            return 0
            ;;
        1)
            log "ERROR" "Website still shows database connection error after restart"
            send_telegram_message "❌ <b>CRITICAL:</b> Website $(hostname) still shows database connection error after restart. Manual intervention required!"
            return 1
            ;;
        2)
            log "ERROR" "Website is still inaccessible after restart"
            send_telegram_message "❌ <b>CRITICAL:</b> Website $(hostname) is still inaccessible after restart. Please check manually!"
            return 1
            ;;
    esac
}

# Main monitoring function
main() {
    log "INFO" "Starting website monitoring check..."
    
    # Check MySQL service status
    if ! check_service_status "mysql"; then
        log "WARN" "MySQL service is not running"
        send_telegram_message "🚨 <b>ALERT:</b> MySQL service on $(hostname) is DOWN! Attempting to restart..."
        
        if restart_service "mysql"; then
            send_telegram_message "✅ MySQL service on $(hostname) has been successfully restarted."
        else
            send_telegram_message "❌ <b>CRITICAL:</b> Failed to restart MySQL service on $(hostname). Manual intervention required!"
            exit 1
        fi
    else
        log "INFO" "MySQL service is running"
    fi
    
    # Check Apache2 service status
    if ! check_service_status "apache2"; then
        log "WARN" "Apache2 service is not running"
        send_telegram_message "🚨 <b>ALERT:</b> Apache2 service on $(hostname) is DOWN! Attempting to restart..."
        
        if restart_service "apache2"; then
            send_telegram_message "✅ Apache2 service on $(hostname) has been successfully restarted."
        else
            send_telegram_message "❌ <b>CRITICAL:</b> Failed to restart Apache2 service on $(hostname). Manual intervention required!"
            exit 1
        fi
    else
        log "INFO" "Apache2 service is running"
    fi
    
    # Check website for database errors
    case $(check_website) in
        0)
            # Website is working fine
            log "INFO" "Website monitoring check completed - All OK"
            ;;
        1)
            # Database connection error detected
            log "ERROR" "Database connection error detected, attempting to fix..."
            
            # Restart MySQL first
            if restart_service "mysql"; then
                send_telegram_message "✅ MySQL service on $(hostname) has been successfully restarted."
            else
                send_telegram_message "❌ <b>CRITICAL:</b> Failed to restart MySQL service on $(hostname)."
                exit 1
            fi
            
            # Restart Apache2
            if restart_service "apache2"; then
                send_telegram_message "✅ Apache2 service on $(hostname) has been successfully restarted."
            else
                send_telegram_message "❌ <b>CRITICAL:</b> Failed to restart Apache2 service on $(hostname)."
                exit 1
            fi
            
            # Verify website recovery
            verify_website_recovery
            ;;
        2)
            # Website is completely inaccessible
            log "ERROR" "Website is completely inaccessible"
            exit 1
            ;;
    esac
    
    log "INFO" "Website monitoring completed successfully"
}

# Execute main function
main "$@"
