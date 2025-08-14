#!/bin/bash

# Website Monitor Script for Ubuntu 14.04
# Updated with error handling and logging improvements

# Configuration
TELEGRAM_BOT_TOKEN="7512739719:AAFWb5x73F8VJVh1oaD7sVZ7r_vaf8PhtkY"
TELEGRAM_CHAT_ID="-4963020838"
WEBSITE_URL="https://seasialegal.com/"
LOG_FILE="/var/log/website_monitor.log"
MAX_RETRIES=3
CURL_TIMEOUT=30

# Logging function
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Telegram notification function with retry mechanism
send_telegram_message() {
    local message="$1"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -s --connect-timeout 10 --max-time 30 \
            -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$message" > /dev/null 2>&1; then
            log_message "Telegram notification sent: $message"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_message "Failed to send Telegram notification (attempt $retry_count/$MAX_RETRIES)"
            sleep 5
        fi
    done
    
    log_message "Failed to send Telegram notification after $MAX_RETRIES attempts: $message"
    return 1
}

# Enhanced service status check for Ubuntu 14.04
check_service_status() {
    local service_name="$1"
    
    # Try multiple methods to check service status
    if command -v status >/dev/null 2>&1; then
        # Using upstart (Ubuntu 14.04 default)
        if status "$service_name" 2>/dev/null | grep -q "start/running"; then
            return 0
        fi
    fi
    
    # Fallback to service command
    if service "$service_name" status 2>/dev/null | grep -q -E "(running|active|start/running)"; then
        return 0
    fi
    
    # Check process directly
    if pgrep -x "mysqld" >/dev/null 2>&1 && [ "$service_name" = "mysql" ]; then
        return 0
    fi
    
    return 1
}

# Enhanced service restart function
restart_service() {
    local service_name="$1"
    local retry_count=0
    
    log_message "Attempting to restart $service_name service..."
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Stop service first
        service "$service_name" stop >/dev/null 2>&1
        sleep 3
        
        # Start service
        if service "$service_name" start >/dev/null 2>&1; then
            sleep 5  # Wait for service to initialize
            
            # Verify service is running
            if check_service_status "$service_name"; then
                log_message "$service_name service restarted successfully"
                send_telegram_message "✅ $service_name service on $(hostname) has been successfully restarted."
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        log_message "Failed to restart $service_name (attempt $retry_count/$MAX_RETRIES)"
        
        if [ $retry_count -lt $MAX_RETRIES ]; then
            sleep 10
        fi
    done
    
    log_message "Failed to restart $service_name after $MAX_RETRIES attempts"
    send_telegram_message "❌ Failed to restart $service_name service on $(hostname) after $MAX_RETRIES attempts."
    return 1
}

# Enhanced website checking function
check_website() {
    local response
    local http_code
    
    log_message "Checking website: $WEBSITE_URL"
    
    # Get website response with timeout and follow redirects
    response=$(curl -s --connect-timeout 10 --max-time $CURL_TIMEOUT \
        -L -w "HTTPSTATUS:%{http_code}" "$WEBSITE_URL" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_message "Failed to connect to website"
        send_telegram_message "🚨 Cannot connect to website $(hostname) - $WEBSITE_URL. Connection failed!"
        return 1
    fi
    
    # Extract HTTP status code
    http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    response_body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
    
    # Check HTTP status code
    if [ "$http_code" -ge 400 ]; then
        log_message "Website returned HTTP error code: $http_code"
        send_telegram_message "🚨 Website $(hostname) returned HTTP $http_code error!"
        return 1
    fi
    
    # Check for database connection error
    if echo "$response_body" | grep -q -i "error establishing a database connection"; then
        log_message "Website shows database connection error"
        send_telegram_message "🚨 Website $(hostname) shows 'Error establishing a database connection'. Attempting to restart services..."
        
        # Restart MySQL first
        if restart_service "mysql"; then
            # Then restart Apache2
            if restart_service "apache2"; then
                # Wait and verify website after restart
                sleep 10
                return verify_website_after_restart
            else
                return 1
            fi
        else
            return 1
        fi
    fi
    
    log_message "Website is accessible and functioning normally"
    return 0
}

# Verify website after service restart
verify_website_after_restart() {
    local response
    local retry_count=0
    
    log_message "Verifying website after service restart..."
    
    while [ $retry_count -lt 3 ]; do
        sleep 5
        response=$(curl -s --connect-timeout 10 --max-time $CURL_TIMEOUT -L "$WEBSITE_URL" 2>/dev/null)
        
        if [ $? -eq 0 ] && ! echo "$response" | grep -q -i "error establishing a database connection"; then
            log_message "Website is back online after service restart"
            send_telegram_message "✅ Website $(hostname) is back online after service restart."
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_message "Website still showing issues (verification attempt $retry_count/3)"
    done
    
    log_message "Website still shows issues after service restart"
    send_telegram_message "❌ Website $(hostname) still shows database connection error after restart. Please check manually!"
    return 1
}

# Main execution
main() {
    log_message "Starting website monitoring check"
    
    # Check if script is running as root (recommended for service management)
    if [ "$(id -u)" -ne 0 ]; then
        log_message "Warning: Script is not running as root. Service restart may fail."
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check MySQL service first
    if check_service_status "mysql"; then
        log_message "MySQL service is running"
        # Check website only if MySQL is running
        if ! check_website; then
            log_message "Website check failed"
            exit 1
        fi
    else
        log_message "MySQL service is not running"
        send_telegram_message "🚨 MySQL service on $(hostname) is DOWN! Attempting to restart..."
        
        if restart_service "mysql"; then
            # After MySQL restart, check website
            if ! check_website; then
                log_message "Website check failed after MySQL restart"
                exit 1
            fi
        else
            log_message "Failed to restart MySQL service"
            exit 1
        fi
    fi
    
    log_message "Website monitoring check completed successfully"
}

# Run main function
main "$@"
