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

        # Step 6: Marzban Backup Logic
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

        # Step 6: x-ui Backup Logic
        echo "Performing x-ui backup..."

        # Search for the database and configuration directories
        dbDir=$(find /etc -type d -iname "x-ui*" -print -quit)
        configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit)

        # Validate that both directories are found
        if [[ -z "$dbDir" ]]; then
            echo "Error: x-ui database directory not found."
            exit 1
        fi
        if [[ -z "$configDir" ]]; then
            echo "Error: x-ui configuration directory not found."
            exit 1
        fi

        # Locate JSON files in the database directory
        json_file=$(find "$dbDir" -type f -name "*.json" -print -quit)

        # Validate that a JSON file exists
        if [[ -z "$json_file" || ! -f "$json_file" ]]; then
            echo "Error: No valid JSON backup files found in $dbDir."
            exit 1
        fi

        # Send the JSON backup file to Telegram
        curl -F chat_id="${chatid}" \
            -F caption="${caption} - x-ui Backup" \
            -F parse_mode="HTML" \
            -F document=@"$json_file" \
            https://api.telegram.org/bot${tk}/sendDocument

        echo "Backup file sent to Telegram successfully."
        ;;
    3)
        xmh="h"
        xmh_choice_name="Hiddify"
        echo "You selected Hiddify."

        # Step 6: Hiddify Backup Logic
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
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Step 7: Add IP to Caption
IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\nBackup from ${xmh_choice_name} - IP: ${IP}"

# Step 8: Check for Required Utilities
check_utility "curl"
check_utility "git"

# Step 9: Setup Cronjob for Periodic Backups
echo "Step 9: Setting up cronjob for periodic backups..."
if [[ ! -f "$script_path" ]]; then
    echo "Error: Backup script $script_path does not exist."
    exit 1
fi
cronjob="* * * * * $script_path"
(crontab -l ; echo "$cronjob") | crontab -

echo "Cronjob has been successfully added."

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
