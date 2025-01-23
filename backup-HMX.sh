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

# Step 4: Choose software to backup
echo "Step 4: Choose the software to back up."
echo "1. Marzban"
echo "2. x-ui"
echo "3. Hiddify"
read -r -p "Enter your choice (1, 2, or 3): " xmh_choice

case "$xmh_choice" in
    1)
        xmh="m"
        xmh_choice_name="Marzban"
        echo "You selected Marzban."
        
        # Marzban Backup Logic
        echo "Performing Marzban backup..."

        # Check for Marzban directory
        if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
            echo "The folder exists at $dir"
        else
            echo "The folder does not exist."
            exit 1
        fi

        # Validate MySQL directory and proceed with backup
        if [ -d "/var/lib/marzban/mysql" ]; then
            # Sanitize the .env file
            sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env

            # Ensure backup directory exists inside the Docker container
            docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"

            # Check if Docker container is running
            if ! docker ps --format '{{.Names}}' | grep -q "^marzban-mysql-1$"; then
                echo "Error: Docker container 'marzban-mysql-1' is not running."
                exit 1
            fi

            # Source the .env file for MySQL credentials
            source /opt/marzban/.env

            # Check MYSQL_ROOT_PASSWORD environment variable
            if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
                echo "Error: MYSQL_ROOT_PASSWORD is missing in the .env file."
                exit 1
            fi

            # Create the database backup script inside the MySQL container
            docker exec marzban-mysql-1 bash -c "cat > /var/lib/mysql/db-backup/backup-HMX.sh" <<EOL
#!/bin/bash

USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"

databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in \$databases; do
if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
echo "Dumping database: \$db"
mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
fi
done
EOL

            # Set execute permission for the backup script
            docker exec marzban-mysql-1 bash -c "chmod +x /var/lib/mysql/db-backup/backup-HMX.sh"

            # Run the backup script
            docker exec marzban-mysql-1 bash -c "/var/lib/mysql/db-backup/backup-HMX.sh"

            # Find the latest SQL backup file
            backup_dir="/var/lib/marzban/mysql/db-backup"
            latest_file=$(docker exec marzban-mysql-1 bash -c "ls -t $backup_dir/*.sql 2>/dev/null | head -n1")

            # Validate that a backup file was created
            if [[ -z "$latest_file" ]]; then
                echo "Error: No backup file found in $backup_dir."
                exit 1
            fi

            # Download the backup file from the container
            docker cp marzban-mysql-1:"$latest_file" /tmp/

            # Send the backup file to Telegram
            curl -F chat_id="${chatid}" \
            -F caption="${caption} - Marzban Database Backup" \
            -F parse_mode="HTML" \
            -F document=@"/tmp/$(basename "$latest_file")" \
            https://api.telegram.org/bot${tk}/sendDocument

            # Clean up the temporary file
            rm -f "/tmp/$(basename "$latest_file")"

            echo "Backup file sent to Telegram successfully."
        else
            echo "MySQL directory not found for Marzban."
            exit 1
        fi
        ;;
    2)
        xmh="x"
        xmh_choice_name="x-ui"
        echo "You selected x-ui."

        # x-ui Backup Logic
        echo "Performing x-ui backup..."

        # Check if x-ui database directory exists
        if dbDir=$(find /etc /opt/freedom -type d -iname "x-ui*" -print -quit); then
            echo "The folder exists at $dbDir"

            # Adjust path if located in /opt/freedom/x-ui
            if [[ $dbDir == *"/opt/freedom/x-ui"* ]]; then
                dbDir="${dbDir}/db/"
            fi
        else
            echo "The folder does not exist."
            exit 1
        fi

        # Check if x-ui config directory exists
        if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
            echo "The folder exists at $configDir"
        else
            echo "The folder does not exist."
            exit 1
        fi

        # Backup logic: only send the latest x-ui.db and config.json files
        latest_backup_files=()

        # Find the latest 'x-ui.db' file in the database directory
        latest_backup_file_db=$(find "$dbDir" -type f -name "x-ui.db" -print -quit)
        if [[ -n "$latest_backup_file_db" ]]; then
            latest_backup_files+=("$latest_backup_file_db")
        else
            echo "Error: No x-ui.db file found."
            exit 1
        fi

        # Find the 'config.json' file in the config directory
        latest_backup_file_config=$(find "$configDir" -type f -name "config.json" -print -quit)
        if [[ -n "$latest_backup_file_config" ]]; then
            latest_backup_files+=("$latest_backup_file_config")
        else
            echo "Error: No config.json file found."
            exit 1
        fi

        # Send both the x-ui.db and config.json files to Telegram
        for backup_file in "${latest_backup_files[@]}"; do
            curl -F chat_id="${chatid}" \
            -F caption="${caption} - x-ui Backup" \
            -F parse_mode="HTML" \
            -F document=@"$backup_file" \
            "https://api.telegram.org/bot${tk}/sendDocument"
        done

        echo "Backup files sent to Telegram successfully."
        ;;
    3)
        xmh="h"
        xmh_choice_name="Hiddify"
        echo "You selected Hiddify."

        # Hiddify Backup Logic
        validate_directory "$BACKUP_DIR_HIDDIFY"
        latest_file=$(ls -t "$BACKUP_DIR_HIDDIFY"/*.json 2>/dev/null | head -n1)
        if [[ -z "$latest_file" || ! -f "$latest_file" ]]; then
            echo "Error: No valid backup file found in $BACKUP_DIR_HIDDIFY."
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
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

# Define backup script path
BACKUP_SCRIPT_PATH="/root/backup-HMX-${xmh}.sh"

# Step 5: Select Backup Interval
echo "Choose backup interval:"
echo "1. Every 1 minute"
echo "2. Every 3 hours"
echo "3. Every 6 hours"
echo "4. Custom time (minute and hour)"
read -r -p "Enter your choice (1-4): " choice

case "$choice" in
    1)
        cron_time="* * * * *"  # Every 1 minute
        ;;
    2)
        cron_time="0 */3 * * *"  # Every 3 hours
        ;;
    3)
        cron_time="0 */6 * * *"  # Every 6 hours
        ;;
    4)
        while true; do
            echo "Enter custom cron time (minute hour, e.g. '30 6' for 6:30 AM):"
            read -r minute hour
            if [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
                cron_time="${minute} ${hour} * * *"
                break
            else
                echo "Invalid input. Please enter valid minute and hour (0-59 for minute, 0-23 for hour)."
            fi
        done
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

# Remove old cron job if it exists
crontab -l | grep -v "$BACKUP_SCRIPT_PATH" | crontab -

# Add new cron job for scheduled backup
{ crontab -l; echo "${cron_time} /bin/bash $BACKUP_SCRIPT_PATH >/dev/null 2>&1"; } | crontab -

# Run the backup script immediately
bash "$BACKUP_SCRIPT_PATH"

echo "Cron job successfully scheduled with the following timing: $cron_time"
echo "Backup will run according to the selected interval."

# Final confirmation
echo -e "\nBackup completed successfully. The backup has been sent to Telegram."
echo "To access the menu anytime, type 'menux' in your terminal."
