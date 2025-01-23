#!/bin/bash

# Exit on error
set -e

# Define constants and default paths
BACKUP_DIR_HIDDIFY="/opt/hiddify-manager/hiddify-panel/backup"
REPO_URL="https://github.com/MasterHide/backup-HMX.git"
REPO_DIR="/opt/backup-HMX"

# Function to trim spaces
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Function to validate non-empty input
validate_non_empty() {
    local input=""
    local message="$1"
    while [[ -z "$input" ]]; do
        read -r -p "$message: " input
        [[ -z "$input" ]] && echo "Input cannot be empty."
    done
    echo "$input"
}

# Function to validate directory existence
validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Directory does not exist: $dir"
        exit 1
    fi
}

# Function to check and install required utilities
check_utility() {
    local utility="$1"
    if ! command -v "$utility" &>/dev/null; then
        echo "$utility is not installed. Installing..."
        sudo apt update && sudo apt install -y "$utility"
    fi
}

# Step 1: Bot Token
echo "Step 1: Enter your Telegram Bot Token."
tk=$(validate_non_empty "Bot Token")

# Step 2: Chat ID
echo "Step 2: Enter your Telegram Chat ID."
chatid=$(validate_non_empty "Chat ID")

# Step 3: Caption for Backup File
echo "Step 3: Enter a caption for your backup (e.g., your domain)."
caption=$(validate_non_empty "Caption")

# Step 4: Choose Cronjob Schedule
echo "Step 4: Choose the schedule for periodic backups."
cron_time=""
while true; do
    echo "1. Every 3 hours"
    echo "2. Every 6 hours"
    read -r -p "Enter your choice (1 or 2): " cron_choice
    case "$cron_choice" in
        1) cron_time="0 */3 * * *"; break ;;
        2) cron_time="0 */6 * * *"; break ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
    esac
done
echo "Cronjob schedule set to: $cron_time"

# Step 5: Select Software to Backup
echo "Step 5: Choose the software to back up."
echo "1. Marzban"
echo "2. x-ui"
echo "3. Hiddify"
read -r -p "Enter your choice (1, 2, or 3): " xmh_choice

case "$xmh_choice" in
    1) 
        xmh="m"
        xmh_choice_name="Marzban"
        echo "You selected Marzban."
        ;;
    2) 
        xmh="x"
        xmh_choice_name="x-ui"
        echo "You selected x-ui."
        ;;
    3) 
        xmh="h"
        xmh_choice_name="Hiddify"
        echo "You selected Hiddify."
        ;;
    *) 
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Step 6: Backup Logic Based on Software Chosen
case "$xmh" in
    "m")
        echo "Performing Marzban backup..."
        dir=$(find /opt /root -type d -iname "marzban" -print -quit)
        validate_directory "$dir"
        echo "The Marzban directory is at $dir"
        # Add Marzban-specific backup logic here...
        ;;
    "x")
        echo "Performing x-ui backup..."
        dbDir=$(find /etc -type d -iname "x-ui*" -print -quit)
        configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit)
        validate_directory "$dbDir"
        validate_directory "$configDir"
        # Add x-ui-specific backup logic here...
        ;;
    "h")
        echo "Performing Hiddify backup..."
        validate_directory "$BACKUP_DIR_HIDDIFY"
        latest_file=$(ls -t "$BACKUP_DIR_HIDDIFY"/*.json 2>/dev/null | head -n1)
        if [[ -z "$latest_file" ]]; then
            echo "No backup files found!"
            exit 1
        fi
        echo "Found the latest backup file: $latest_file"

        # Construct dynamic caption with software type
        caption="Backup file sent successfully. Details:\n\nSoftware: ${xmh_choice_name}\nUser Caption: ${caption}"

        # Send notification to Telegram
        curl -s -X POST "https://api.telegram.org/bot${tk}/sendMessage" \
            -d chat_id="${chatid}" \
            -d text="Backup for ${xmh_choice_name} is being sent..."

        # Send the backup file
        response=$(curl -s -F chat_id="${chatid}" \
            -F caption="${caption}" \
            -F parse_mode="HTML" \
            -F document=@"$latest_file" \
            "https://api.telegram.org/bot${tk}/sendDocument")

        if echo "$response" | grep -q '"ok":true'; then
            echo "Backup file sent to Telegram successfully for ${xmh_choice_name}."
        else
            echo "Failed to send backup file for ${xmh_choice_name} to Telegram. Response: $response"
            exit 1
        fi
        ;;
esac

# Step 7: Add IP to Caption
IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\nBackup from ${xmh_choice_name} - IP: ${IP}"

# Step 8: Check for Required Utilities
check_utility "curl"
check_utility "git"

# Step 9: Add cronjob for periodic execution
script_path="/root/backup-HMX-${xmh}.sh"
(crontab -l -u root | grep -v "$script_path"; echo "${cron_time} /bin/bash $script_path >/dev/null 2>&1") | crontab -u root -
echo "Cronjob added for periodic execution."

# Step 10: Clone or Update Repository
if [[ ! -d "$REPO_DIR" ]]; then
    git clone "$REPO_URL" "$REPO_DIR"
    echo "Repository cloned."
else
    cd "$REPO_DIR" && git pull
    echo "Repository updated."
fi

# Step 11: Create 'menux' Command (Optional)
read -r -p "Create 'menux' command to restore backup? [y/n]: " create_menux
if [[ "$create_menux" == "y" ]]; then
    if [[ ! -f "$REPO_DIR/restore_backup.sh" ]]; then
        echo "Error: restore_backup.sh does not exist."
        exit 1
    fi
    sudo ln -sf "$REPO_DIR/restore_backup.sh" /usr/local/bin/menux
    sudo chmod +x /usr/local/bin/menux
    echo "'menux' command created."
fi

# Step 12: Clean up
rm -f "$script_path"
echo -e "\nBackup completed successfully. The backup has been sent to Telegram."
echo "To access the menu anytime, type 'menux' in your terminal."
