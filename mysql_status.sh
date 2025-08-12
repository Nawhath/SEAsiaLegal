#!/bin/bash

# Telegram Bot Token AND Chat ID
TELEGRAM_BOT_TOKEN="7512739719:AAFWb5x73F8VJVh1oaD7sVZ7r_vaf8PhtkY"
TELEGRAM_CHAT_ID="-4963020838"

#Telegram
send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message"
}

# CHECK MySQL service
SERVICE="mysql"
if ! service $SERVICE status | grep -q "running"; then
    echo "MySQL service is not running. Attempting to restart..."
    
    # ALERT 
    send_telegram_message "🚨 MySQL service on $(hostname) is DOWN! Attempting to restart..."

    # RETRY restart service
    if service $SERVICE restart; then
        echo "MySQL service restarted successfully."
        send_telegram_message "✅ MySQL service on $(hostname) has been successfully restarted."
    else
        echo "Failed to restart MySQL service."
        send_telegram_message "❌ Failed to restart MySQL service on $(hostname). Please check manually!"
    fi
else
    echo "MySQL service is running."
    # send_telegram_message "🟢 MySQL service on $(hostname) is running normally."
fi
