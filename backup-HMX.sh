#!/bin/bash

# Exit on error
set -e

# Function to send Telegram notifications
send_telegram_message() {
    local message="$1"
    local chat_id="$TELEGRAM_CHAT_ID"
    local bot_token="$TELEGRAM_BOT_TOKEN"
    local telegram_url="https://api.telegram.org/bot$bot_token/sendMessage"
    
    curl -s -X POST "$telegram_url" \
        -d "chat_id=$chat_id" \
        -d "text=$message" > /dev/null
}

# Function to send a file to Telegram
send_telegram_file() {
    local file_path="$1"
    local chat_id="$TELEGRAM_CHAT_ID"
    local bot_token="$TELEGRAM_BOT_TOKEN"
    local telegram_url="https://api.telegram.org/bot$bot_token/sendDocument"

    curl -s -X POST "$telegram_url" \
        -F "chat_id=$chat_id" \
        -F "document=@$file_path" > /dev/null
}

# Ensure required dependencies are installed
dependencies=(curl zip mysqldump docker grep)
for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed. Please install it (e.g., sudo apt install $cmd)."
        exit 1
    fi
done

# Step 1: Telegram Bot Token
while [[ -z "$TELEGRAM_BOT_TOKEN" ]]; do
    read -r -p "Enter your Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    [[ -z "$TELEGRAM_BOT_TOKEN" ]] && echo "Bot Token cannot be empty."
done

# Step 2: Telegram Chat ID
while [[ -z "$TELEGRAM_CHAT_ID" ]]; do
    read -r -p "Enter your Telegram Chat ID: " TELEGRAM_CHAT_ID
    if [[ -z "$TELEGRAM_CHAT_ID" || ! "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
        echo "Invalid Chat ID. Please enter a valid number."
        TELEGRAM_CHAT_ID=""
    fi
done

# Step 3: Caption for Backup File
read -r -p "Enter a caption for your backup (e.g., your domain): " caption
[[ -z "$caption" ]] && caption="Backup"

# Step 4: Cronjob Schedule
while true; do
    echo "Choose the schedule for periodic backups:"
    echo "1. Every 3 hours"
    echo "2. Every 6 hours"
    read -r -p "Enter your choice (1 or 2): " cron_choice
    case "$cron_choice" in
        1) cron_time="0 */3 * * *"; break ;;
        2) cron_time="0 */6 * * *"; break ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
    esac
done

# Step 5: Backup Software Selection
while [[ -z "$software_choice" ]]; do
    read -r -p "Choose the software to back up (x-ui, Marzban, Hiddify) [x/m/h]: " software_choice
    case "$software_choice" in
        x|m|h) ;;
        *) echo "Invalid choice. Please enter x, m, or h."; software_choice="" ;;
    esac
done

# Step 6: Clear Previous Cronjobs
read -r -p "Do you want to clear previous cronjobs? [y/n]: " clear_cron
if [[ "$clear_cron" == "y" ]]; then
    crontab -l | grep -vE 'backup-HMX.sh' | crontab -
    echo "Previous cronjobs cleared."
fi

# Step 7: Backup Logic
BACKUP_FILE=""
case "$software_choice" in
    m)
        echo "Performing Marzban backup..."
        dir=$(find /opt /root -type d -iname "marzban" -print -quit)
        if [[ -z "$dir" ]]; then
            echo "Error: Marzban directory not found."
            exit 1
        fi

        # Prompt for MySQL root password if not set
        if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
            read -r -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
            echo
        fi

        if [[ -d "/var/lib/marzban/mysql" ]]; then
            echo "MySQL detected. Preparing database backup..."
            docker exec marzban-mysql-1 bash -c "
                mkdir -p /var/lib/mysql/db-backup
                databases=\$(mysql -uroot -p\$MYSQL_ROOT_PASSWORD -e 'SHOW DATABASES;' | grep -v -E '(Database|mysql|performance_schema|sys|information_schema)')
                for db in \$databases; do
                    mysqldump -uroot -p\$MYSQL_ROOT_PASSWORD \$db > /var/lib/mysql/db-backup/\$db.sql
                done
            "
        fi

        zip -r /root/backup-HMX.zip /opt/marzban /var/lib/marzban
        BACKUP_FILE="/root/backup-HMX.zip"
        backup_caption="Marzban Backup"
        ;;
    x)
        echo "Performing x-ui backup..."
        db_dir=$(find /etc -type d -iname "x-ui*" -print -quit)
        config_dir=$(find /usr/local -type d -iname "x-ui*" -print -quit)
        zip /root/backup-HMX-x.zip "$db_dir/x-ui.db" "$config_dir/config.json"
        BACKUP_FILE="/root/backup-HMX-x.zip"
        backup_caption="x-ui Backup"
        ;;
    h)
        echo "Performing Hiddify backup..."
        read -r -p "Enter Hiddify API Key: " api_key
        read -r -p "Enter IP/Proxy Path: " ip_proxy_path

        response=$(curl -s -o /root/backup-HMX-h.zip -w "%{http_code}" -X POST \
            "https://api.hiddify.xyz/api/backup" \
            -H "Authorization: Bearer $api_key" \
            -d "ip_proxy=$ip_proxy_path")

        if [[ "$response" != "200" ]]; then
            echo "Hiddify backup failed. HTTP response code: $response"
            send_telegram_message "❌ Hiddify backup failed."
            exit 1
        fi

        BACKUP_FILE="/root/backup-HMX-h.zip"
        backup_caption="Hiddify Backup"
        ;;
esac

# Step 8: Schedule Cronjob
(crontab -l | grep -v "/root/backup-HMX.sh"; echo "$cron_time /root/backup-HMX.sh") | crontab -
echo "Cronjob scheduled: $cron_time"

# Step 9: Notify Telegram
if [[ -f "$BACKUP_FILE" ]]; then
    send_telegram_message "✅ Backup completed successfully: $backup_caption"
    send_telegram_file "$BACKUP_FILE"
    echo "Backup completed and sent to Telegram."
else
    send_telegram_message "❌ Backup failed: $backup_caption"
    echo "Backup failed."
fi
