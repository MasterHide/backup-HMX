#!/bin/bash

# Exit on error
set -e

# Step 1: Bot Token
echo "Step 1: Enter your Telegram Bot Token."
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ -z "$tk" ]]; then
        echo "Invalid input. Token cannot be empty."
    fi
done
echo "Bot token received successfully."

# Step 2: Chat ID
echo "Step 2: Enter your Telegram Chat ID."
while [[ -z "$chatid" ]]; do
    echo "Chat ID: "
    read -r chatid
    if [[ -z "$chatid" ]]; then
        echo "Invalid input. Chat ID cannot be empty."
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a valid number."
    fi
done
echo "Chat ID received successfully."

# Step 3: Caption for Backup File
echo "Step 3: Enter a caption to identify your backup (e.g., your domain)."
read -r caption
echo "Caption set as: $caption"

# Step 4: Choose Cronjob Schedule
echo "Step 4: Choose the schedule for periodic backups."
while true; do
    echo "1. Every 3 hours"
    echo "2. Every 6 hours"
    echo "Enter your choice (1 or 2):"
    read -r cron_choice
    case "$cron_choice" in
    1)
        cron_time="0 */3 * * *" # Every 3 hours
        break
        ;;
    2)
        cron_time="0 */6 * * *" # Every 6 hours
        break
        ;;
    *)
        echo "Invalid choice. Please enter 1 for 3-hour intervals or 2 for 6-hour intervals."
        ;;
    esac
done
echo "Cronjob schedule set to: $cron_time"

# Step 5: Choose Backup Software
echo "Step 5: Choose the software to back up."
while [[ -z "$xmh" ]]; do
    echo "Choose software (x-ui, Marzban, or Hiddify) [x/m/h]: "
    read -r xmh
    if [[ ! $xmh =~ ^[xmh]$ ]]; then
        echo "Invalid choice. Please choose x, m, or h."
    fi
done
echo "Software chosen: $xmh"

# Step 6: Clear Previous Cronjobs (Optional)
echo "Step 6: Do you want to clear previous cronjobs? [y/n]: "
read -r crontabs
if [[ "$crontabs" == "y" ]]; then
    sudo crontab -l | grep -vE '/root/backup-HMX.+\.sh' | crontab -
    echo "Previous cronjobs cleared."
else
    echo "No cronjobs cleared."
fi

# Step 7: Backup Logic Based on Software Chosen
# --------------------------------------------------------
if [[ "$xmh" == "m" ]]; then
    # Marzban Backup
    echo "Performing Marzban backup..."
    dir=$(find /opt /root -type d -iname "marzban" -print -quit)
    if [[ -z "$dir" ]]; then
        echo "The Marzban directory does not exist."
        exit 1
    fi
    echo "The Marzban directory exists at $dir"

    if [[ -d "/var/lib/marzban/mysql" ]]; then
        echo "MySQL is detected for Marzban. Preparing database backup..."

        # Clean up the .env file for correct formatting
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env

        # Ensure backup directory exists in MySQL
        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
        source /opt/marzban/.env

        # Create backup script for MySQL databases
        cat > "/var/lib/marzban/mysql/backup-HMX.sh" <<EOL
#!/bin/bash

USER="root"
PASSWORD="\$MYSQL_ROOT_PASSWORD"

databases=\$(mysql --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
        mysqldump --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
        chmod +x /var/lib/marzban/mysql/backup-HMX.sh

        # Backup command including MySQL dump and Marzban files
        ZIP=$(cat <<EOF
docker exec marzban-mysql-1 bash -c "/var/lib/marzban/mysql/backup-HMX.sh"
zip -r /root/backup-HMX.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/*
zip -r /root/backup-HMX.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
)
        MasterHide="MasterHide Marzban MySQL backup"

    else
        # Non-MySQL Marzban backup logic
        ZIP="zip -r /root/backup-HMX.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
        MasterHide="MasterHide Marzban non-MySQL backup"
    fi

elif [[ "$xmh" == "x" ]]; then
    # x-ui Backup
    echo "Performing x-ui backup..."
    dbDir=$(find /etc -type d -iname "x-ui*" -print -quit)
    configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit)

    if [[ -z "$dbDir" || -z "$configDir" ]]; then
        echo "One or both x-ui directories do not exist."
        exit 1
    fi

    ZIP="zip /root/backup-HMX-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    MasterHide="MasterHide x-ui backup"

elif [[ "$xmh" == "h" ]]; then
    # Hiddify Backup
    echo "Performing Hiddify backup..."
    if [[ ! -d "/opt/hiddify-config/hiddify-panel/backup" ]]; then
        echo "Backup directory does not exist."
        exit 1
    fi

    BACKUP_FILE="/root/backup-HMX-h-$(date +%Y%m%d%H%M%S).zip"
    ZIP=$(cat <<EOF
cd /opt/hiddify-config/hiddify-panel/
if [ \$(find /opt/hiddify-config/hiddify-panel/backup -type f | wc -l) -gt 100 ]; then
    find /opt/hiddify-config/hiddify-panel/backup -type f -delete
fi
python3 -m hiddifypanel backup
cd /opt/hiddify-config/hiddify-panel/backup
latest_file=\$(ls -t *.json | head -n1)
rm -f $BACKUP_FILE
zip $BACKUP_FILE /opt/hiddify-config/hiddify-panel/backup/\$latest_file
EOF
    )
    MasterHide="MasterHide Hiddify backup"

else
    echo "Please choose m, x, or h only!"
    exit 1
fi


# Step 8: Trim the Caption
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\n${MasterHide}\n<code>${IP}</code>\nCreated by @MasterHide - https://github.com/MasterHide/backup"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=$(trim "$comment")

# Step 9: Install zip (if not installed)
if ! command -v zip &> /dev/null; then
    sudo apt install zip -y
fi

# Step 10: Ensure curl is installed
if ! command -v curl &> /dev/null; then
    sudo apt install curl -y
fi

# Step 11: Send the backup to Telegram
cat > "/root/backup-HMX-${xmh}.sh" <<EOL
rm -rf /root/backup-HMX-${xmh}.zip
$ZIP
echo -e "$comment" | zip -z /root/backup-HMX-${xmh}.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/root/backup-HMX-${xmh}.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL

# Step 12: Add cronjob for periodic execution
(crontab -l -u root | grep -v "/root/backup-HMX-${xmh}.sh"; echo "${cron_time} /bin/bash /root/backup-HMX-${xmh}.sh >/dev/null 2>&1") | crontab -u root -

# Step 13: Clone or Update the repository
repo_url="https://github.com/MasterHide/backup-HMX.git"
repo_dir="/opt/backup-HMX"

if [[ ! -d "$repo_dir" ]]; then
    git clone "$repo_url" "$repo_dir"
    echo "Repository cloned to $repo_dir."
else
    cd "$repo_dir" && git pull
    echo "Repository updated."
fi

# Step 14: Create 'menux' Command
echo "Step 14: Do you want to create the 'menux' command to access the restore_backup.sh script? [y/n]"
read -r create_menux
if [[ "$create_menux" == "y" ]]; then
    if [[ ! -f "$repo_dir/restore_backup.sh" ]]; then
        echo "Error: restore_backup.sh does not exist."
        exit 1
    fi
    sudo ln -sf "$repo_dir/restore_backup.sh" /usr/local/bin/menux
    sudo chmod +x /usr/local/bin/menux
    echo "'menux' command has been created."
fi

# Step 15: Run the backup script
bash "/root/backup-HMX-${xmh}.sh"

# Step 16: Clean up
rm -f /root/backup-HMX-${xmh}.sh /root/backup-HMX-${xmh}.zip

echo -e "\nBackup process completed successfully! The backup has been sent to Telegram."
echo -e "To access the menu anytime, type 'menux' in your terminal."
