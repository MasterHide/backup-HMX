#!/bin/bash

# Configuration File Path
CONFIG_FILE="/etc/backup-HMX.cfg"

# Function to check for Telegram credentials
check_telegram_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Telegram configuration file not found."
        echo "Please provide your Telegram Bot API token and chat ID."

        # Prompt user for Telegram API token and chat ID
        read -p "Enter Telegram Bot API Token: " TK
        read -p "Enter Telegram Chat ID: " CHATID

        # Save the details to the config file
        echo "TK=\"$TK\"" > "$CONFIG_FILE"
        echo "CHATID=\"$CHATID\"" >> "$CONFIG_FILE"
    else
        # Load the configuration from the file
        source "$CONFIG_FILE"
    fi

    # Debugging to check if values are being loaded correctly
    echo "Token: $TK"
    echo "Chat ID: $CHATID"

    # Validate Telegram API token and chat ID
    if [[ -z "$TK" || -z "$CHATID" ]]; then
        echo "Error: Telegram API token and chat ID must be provided."
        exit 1
    fi
}

# Validate directory existence
validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Directory does not exist: $dir"
        exit 1
    fi
}

# Call the function to check and load Telegram configuration
check_telegram_config

# Marzban Backup Logic
detect_marzban_path() {
    if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
        echo "Marzban detected at: $dir"
        MARZBAN_PATH="$dir"
    else
        echo "Error: Marzban not found on this system."
        exit 1
    fi
}

backup_marzban() {
    echo "Performing Marzban backup..."
    detect_marzban_path

    if [ -d "/var/lib/marzban/mysql" ]; then
        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"

        if ! docker ps --format '{{.Names}}' | grep -q "^marzban-mysql-1$"; then
            echo "Error: Docker container 'marzban-mysql-1' is not running."
            exit 1
        fi

        source "$MARZBAN_PATH/.env"
        if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
            echo "Error: MYSQL_ROOT_PASSWORD is missing in the .env file."
            exit 1
        fi

        docker exec marzban-mysql-1 bash -c "/var/lib/mysql/db-backup/backup-HMX.sh"

        backup_dir="/var/lib/marzban/mysql/db-backup"
        latest_file=$(docker exec marzban-mysql-1 bash -c "ls -t $backup_dir/*.sql 2>/dev/null | head -n1")

        if [[ -z "$latest_file" ]]; then
            echo "Error: No backup file found in $backup_dir."
            exit 1
        fi

        docker cp marzban-mysql-1:"$latest_file" /tmp/
        send_backup_to_telegram "Marzban" "/tmp/$(basename "$latest_file")"
        rm -f "/tmp/$(basename "$latest_file")"
    else
        echo "MySQL directory not found for Marzban."
        exit 1
    fi
}

# x-ui Backup Logic
detect_xui_path() {
    if dbDir=$(find /etc /opt/freedom -type d -iname "x-ui*" -print -quit); then
        if [[ $dbDir == *"/opt/freedom/x-ui"* ]]; then
            dbDir="${dbDir}/db/"
        fi
        echo "x-ui database detected at: $dbDir"
    else
        echo "Error: x-ui database folder not found."
        exit 1
    fi

    if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
        echo "x-ui configuration detected at: $configDir"
    else
        echo "Error: x-ui configuration folder not found."
        exit 1
    fi

    XUI_DB_DIR="$dbDir"
    XUI_CONFIG_DIR="$configDir"
}

backup_xui() {
    echo "Performing x-ui backup..."
    detect_xui_path

    latest_backup_file_db=$(find "$XUI_DB_DIR" -type f -name "x-ui.db" -print -quit)
    latest_backup_file_config=$(find "$XUI_CONFIG_DIR" -type f -name "config.json" -print -quit)

    if [[ -z "$latest_backup_file_db" || -z "$latest_backup_file_config" ]]; then
        echo "Error: x-ui.db or config.json not found."
        exit 1
    fi

    send_backup_to_telegram "x-ui" "$latest_backup_file_db"
    send_backup_to_telegram "x-ui" "$latest_backup_file_config"
}

# Hiddify Backup Logic
detect_hiddify_path() {
    if dir=$(find /opt -type d -name "hiddify-panel" -print -quit); then
        echo "Hiddify detected at: $dir"
        HIDDIFY_PATH="$dir/backup"
    else
        echo "Error: Hiddify not found on this system."
        exit 1
    fi
}

backup_hiddify() {
    echo "Performing Hiddify backup..."
    detect_hiddify_path
    validate_directory "$HIDDIFY_PATH"

    latest_file=$(ls -t "$HIDDIFY_PATH"/*.json 2>/dev/null | head -n1)
    if [[ -z "$latest_file" || ! -f "$latest_file" ]]; then
        echo "Error: No valid backup file found in $HIDDIFY_PATH."
        exit 1
    fi

    send_backup_to_telegram "Hiddify" "$latest_file"
}

# Function to send backup files to Telegram
send_backup_to_telegram() {
    local software_choice="$1"
    local backup_file="$2"
    local caption="Backup file sent successfully for $software_choice"

    echo "Sending backup for $software_choice to Telegram..."

    response=$(curl -s -F chat_id="${chatid}" \
        -F caption="${caption}" \
        -F parse_mode="HTML" \
        -F document=@"$backup_file" \
        "https://api.telegram.org/bot${tk}/sendDocument")

    if echo "$response" | grep -q '"ok":true'; then
        echo "Backup sent to Telegram successfully for $software_choice."
    else
        echo "Error: Failed to send backup file for $software_choice. Response: $response"
        exit 1
    fi
}

# Create Cron Job Function
create_cron_job() {
    local software_choice="$1"
    local interval="$2"
    local cron_command="/usr/local/bin/backup-HMX $software_choice"

    case "$interval" in
        "59sec") cron_schedule="* * * * * $cron_command" ;;
        "3h")    cron_schedule="0 */3 * * * $cron_command" ;;
        "6h")    cron_schedule="0 */6 * * * $cron_command" ;;
        *)       echo "Invalid interval." ; exit 1 ;;
    esac

    # Prompt to remove old cron jobs
    read -p "Do you want to remove old cron jobs before adding this one? (y/n): " remove_cron
    if [[ "$remove_cron" == "y" ]]; then
        echo "Removing old cron jobs..."
        crontab -r  # Remove all current cron jobs
        echo "Old cron jobs removed."
    elif [[ "$remove_cron" == "n" ]]; then
        echo "Old cron jobs will not be removed."
    else
        echo "Invalid choice, exiting."
        exit 1
    fi

    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_schedule") | crontab -
    echo "Cron job created for $software_choice with interval: $interval"
}

# Menu Function
menu() {
    # Check and load Telegram credentials
    check_telegram_config

    echo "Choose software for backup:"
    echo "1. Marzban"
    echo "2. x-ui"
    echo "3. Hiddify"
    read -p "Enter your choice (1-3): " choice

    case "$choice" in
        1) backup_marzban ;;
        2) backup_xui ;;
        3) backup_hiddify ;;
        *) echo "Invalid choice." ; exit 1 ;;
    esac

    echo "Set up a cron job for automated backups?"
    echo "1. Yes"
    echo "2. No"
    read -p "Enter your choice (1-2): " cron_choice

    if [[ "$cron_choice" == "1" ]]; then
        echo "Choose interval:"
        echo "1. Every 59 seconds"
        echo "2. Every 3 hours"
        echo "3. Every 6 hours"
        read -p "Enter your choice (1-3): " interval_choice

        case "$interval_choice" in
            1) create_cron_job "$choice" "59sec" ;;
            2) create_cron_job "$choice" "3h" ;;
            3) create_cron_job "$choice" "6h" ;;
            *) echo "Invalid choice." ; exit 1 ;;
        esac
    fi
}

# Start the menu
menu
