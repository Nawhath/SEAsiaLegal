#!/bin/bash

# Telegram Bot Token AND Chat ID
TELEGRAM_BOT_TOKEN="7512739719:AAFWb5x73F8VJVh1oaD7sVZ7r_vaf8PhtkY"
TELEGRAM_CHAT_ID="-4963020838"

# Website URL to check
WEBSITE_URL="https://seasialegal.com/"

# Telegram
send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message"
}

# Check Website for database connection error
check_website() {
    if curl -s "$WEBSITE_URL" | grep -q "Error establishing a database connection"; then
        echo "Website shows database connection error. Attempting to restart MySQL and Apache2..."
        send_telegram_message "🚨 Website $(hostname) shows 'Error establishing a database connection'. Attempting to restart MySQL and Apache2..."

        # Restart MySQL
        if service mysql restart; then
            echo "MySQL service restarted successfully."
            send_telegram_message "✅ MySQL service on $(hostname) has been successfully restarted."
        else
            echo "Failed to restart MySQL service."
            send_telegram_message "❌ Failed to restart MySQL service on $(hostname)."
            return 1
        fi

        # Restart Apache2
        if service apache2 restart; then
            echo "Apache2 service restarted successfully."
            send_telegram_message "✅ Apache2 service on $(hostname) has been successfully restarted."
        else
            echo "Failed to restart Apache2 service."
            send_telegram_message "❌ Failed to restart Apache2 service on $(hostname)."
            return 1
        fi

        # Verify website after restart
        sleep 5  # Wait for services to stabilize
        if curl -s "$WEBSITE_URL" | grep -q "Error establishing a database connection"; then
            send_telegram_message "❌ Website $(hostname) still shows database connection error after restart. Please check manually!"
            return 1
        else
            send_telegram_message "✅ Website $(hostname) is back online after service restart."
            return 0
        fi
    else
        echo "Website is accessible with no database connection error."
        # send_telegram_message "🟢 Website $(hostname) is running normally."
        return 0
    fi
}

# Check MySQL service
SERVICE="mysql"
if ! service $SERVICE status | grep -q "start/running"; then
    echo "MySQL service is not running. Attempting to restart..."
    send_telegram_message "🚨 MySQL service on $(hostname) is DOWN! Attempting to restart..."

    # Retry restart service
    if service $SERVICE restart; then
        echo "MySQL service restarted successfully."
        send_telegram_message "✅ MySQL service on $(hostname) has been successfully restarted."
    else
        echo "Failed to restart MySQL service."
        send_telegram_message "❌ Failed to restart MySQL service on $(hostname). Please check manually!"
    fi
else
    echo "MySQL service is running."
    # Check website only if MySQL is running
    check_website
fi
