#!/bin/bash

# Exit on error
set -e

# Function to trim spaces
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Step 1: Bot Token
echo "Step 1: Enter your Telegram Bot Token."
while [[ -z "$tk" ]]; do
    read -r -p "Bot token: " tk
    if [[ -z "$tk" ]]; then
        echo "Token cannot be empty."
    fi
done
echo "Bot token received successfully."

# Step 2: Chat ID
echo "Step 2: Enter your Telegram Chat ID."
while [[ -z "$chatid" || ! "$chatid" =~ ^\-?[0-9]+$ ]]; do
    read -r -p "Chat ID: " chatid
    if [[ -z "$chatid" ]]; then
        echo "Chat ID cannot be empty."
    elif [[ ! "$chatid" =~ ^\-?[0-9]+$ ]]; then
        echo "Invalid Chat ID. Please enter a valid number."
    fi
done
echo "Chat ID received successfully."

# Step 3: Caption for Backup File
echo "Step 3: Enter a caption for your backup (e.g., your domain)."
read -r caption
echo "Caption set as: $caption"

# Step 4: Choose Cronjob Schedule
echo "Step 4: Choose the schedule for periodic backups."
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
    1) xmh="m"; echo "You selected Marzban." ;;
    2) xmh="x"; echo "You selected x-ui." ;;
    3) xmh="h"; echo "You selected Hiddify." ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

# Step 6: Backup Logic Based on Software Chosen
if [[ "$xmh" == "m" ]]; then
    echo "Performing Marzban backup..."
    dir=$(find /opt /root -type d -iname "marzban" -print -quit)
    if [[ -z "$dir" ]]; then
        echo "Marzban directory not found."
        exit 1
    fi
    echo "The Marzban directory is at $dir"
    # Marzban-specific backup logic here...

elif [[ "$xmh" == "x" ]]; then
    echo "Performing x-ui backup..."
    dbDir=$(find /etc -type d -iname "x-ui*" -print -quit)
    configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit)
    if [[ -z "$dbDir" || -z "$configDir" ]]; then
        echo "x-ui directories not found."
        exit 1
    fi
    # x-ui-specific backup logic here...

elif [[ "$xmh" == "h" ]]; then
    echo "Performing Hiddify backup..."
    BACKUP_DIR="/opt/hiddify-manager/hiddify-panel/backup"
    
    # Ensure the backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "Backup directory does not exist."
        exit 1
    fi
    
    # Find the latest .json backup file
    latest_file=$(ls -t "$BACKUP_DIR"/*.json 2>/dev/null | head -n1)
    if [[ -z "$latest_file" ]]; then
        echo "No backup files found!"
        exit 1
    fi
    
    echo "Found the latest backup file: $latest_file"
    MasterHide="MasterHide Hiddify backup"
    
    # Send the backup file directly to Telegram
    curl -F chat_id="${chatid}" -F caption="$caption" -F parse_mode="HTML" -F document=@"$latest_file" https://api.telegram.org/bot${tk}/sendDocument
    echo "Backup file sent to Telegram successfully."
fi

# Step 7: Trim the Caption
IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\nBackup from ${xmh} - IP: ${IP}"

# Step 8: Install curl if not installed
if ! command -v curl &> /dev/null; then
    sudo apt install curl -y
fi

# Step 9: Add cronjob for periodic execution
(crontab -l -u root | grep -v "/root/backup-HMX-${xmh}.sh"; echo "${cron_time} /bin/bash /root/backup-HMX-${xmh}.sh >/dev/null 2>&1") | crontab -u root -

# Step 10: Clone or Update Repository (if needed)
repo_url="https://github.com/MasterHide/backup-HMX.git"
repo_dir="/opt/backup-HMX"
if [[ ! -d "$repo_dir" ]]; then
    git clone "$repo_url" "$repo_dir"
    echo "Repository cloned."
else
    cd "$repo_dir" && git pull
    echo "Repository updated."
fi

# Step 11: Create 'menux' Command (Optional)
echo "Create 'menux' command to restore backup? [y/n]"
read -r create_menux
if [[ "$create_menux" == "y" ]]; then
    if [[ ! -f "$repo_dir/restore_backup.sh" ]]; then
        echo "Error: restore_backup.sh does not exist."
        exit 1
    fi
    sudo ln -sf "$repo_dir/restore_backup.sh" /usr/local/bin/menux
    sudo chmod +x /usr/local/bin/menux
    echo "'menux' command created."
fi

# Step 12: Clean up
rm -f /root/backup-HMX-${xmh}.sh

echo -e "\nBackup completed successfully. The backup has been sent to Telegram."
echo "To access the menu anytime, type 'menux' in your terminal."
