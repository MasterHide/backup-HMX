#!/bin/bash

# Step 1: Bot Token
# --------------------------------------------------------
echo "Step 1: Enter your Telegram Bot Token."
# Get the bot token from the user and store it in the variable 'tk'
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done
echo "Bot token received successfully."

# Step 2: Chat ID
# --------------------------------------------------------
echo "Step 2: Enter your Telegram Chat ID."
# Get the Chat ID from the user and store it in the variable 'chatid'
while [[ -z "$chatid" ]]; do
    echo "Chat ID: "
    read -r chatid
    if [[ $chatid == $'\0' ]]; then
        echo "Invalid input. Chat ID cannot be empty."
        unset chatid
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a valid number."
        unset chatid
    fi
done
echo "Chat ID received successfully."

# Step 3: Caption for Backup File
# --------------------------------------------------------
echo "Step 3: Enter a caption to identify your backup (e.g., your domain)."
read -r caption
echo "Caption set as: $caption"

# Step 4: Choose Cronjob Schedule
# --------------------------------------------------------
echo "Step 4: Choose the schedule for periodic backups."
while true; do
    echo "1. Every 3 hours"
    echo "2. Every 6 hours"
    echo "Enter your choice (1 or 2):"
    read -r cron_choice

    case "$cron_choice" in
        1)
            cron_time="0 */3 * * *"  # Every 3 hours
            break
            ;;
        2)
            cron_time="0 */6 * * *"  # Every 6 hours
            break
            ;;
        *)
            echo "Invalid choice. Please enter 1 for 3-hour intervals or 2 for 6-hour intervals."
            ;;
    esac
done
echo "Cronjob schedule set to: $cron_time"

# Step 5: Choose Backup Software
# --------------------------------------------------------
echo "Step 5: Choose the software to back up."
while true; do
    echo "Choose software (x-ui, Marzban, or Hiddify) [x/m/h]: "
    read -r xmh
    case "$xmh" in
        x|m|h) break ;;
        *)
            echo "Invalid choice. Please choose x, m, or h."
            ;;
    esac
done
echo "Software chosen: $xmh"

# Step 6: Clear Previous Cronjobs (Optional)
# --------------------------------------------------------
while true; do
    echo "Step 6: Do you want to clear previous cronjobs? [y/n]: "
    read -r crontabs
    case "$crontabs" in
        y|n) break ;;
        *)
            echo "Invalid input. Please choose y or n."
            ;;
    esac
done

# If yes, remove previous cronjobs
if [[ "$crontabs" == "y" ]]; then
    sudo crontab -l | grep -vE '/root/backup-HMX.+\.sh' | crontab -
    echo "Previous cronjobs cleared."
else
    echo "No cronjobs cleared."
fi

# Step 7: Perform the Backup Based on the Software Chosen
# --------------------------------------------------------
echo "Step 7: Preparing backup for the chosen software."

if [[ "$xmh" == "m" ]]; then
    echo "Step 7a: Preparing Marzban backup."
    # Ensure the Marzban directory exists
    if ! dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
        echo "The Marzban folder does not exist."
        exit 1
    fi

    if [ -d "/var/lib/marzban/mysql" ]; then
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env
        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup" || { echo "Docker command failed. Exiting."; exit 1; }
        source /opt/marzban/.env

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

        ZIP=$(cat <<EOF
docker exec marzban-mysql-1 bash -c "/var/lib/mysql/backup-HMX.sh"
zip -r /root/backup-HMX.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/*
zip -r /root/backup-HMX.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
    else
        ZIP="zip -r /root/backup-HMX.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
    fi

    MasterHide="MasterHide Marzban backup"

elif [[ "$xmh" == "x" ]]; then
    echo "Step 7b: Preparing x-ui backup."
    # Ensure the x-ui directories exist
    if ! dbDir=$(find /etc -type d -iname "x-ui*" -print -quit); then
        echo "The x-ui folder does not exist."
        exit 1
    fi

    if ! configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
        echo "The x-ui configuration directory does not exist."
        exit 1
    fi

    ZIP="zip /root/backup-HMX-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    MasterHide="MasterHide x-ui backup"

elif [[ "$xmh" == "h" ]]; then
    echo "Step 7c: Preparing Hiddify backup."
    if ! find /opt/hiddify-config/hiddify-panel/ -type d -iname "backup" -print -quit; then
        echo "The folder does not exist."
        exit 1
    fi

    ZIP=$(cat <<EOF
cd /opt/hiddify-config/hiddify-panel/
if [ \$(find /opt/hiddify-config/hiddify-panel/backup -type f | wc -l) -gt 100 ]; then
  find /opt/hiddify-config/hiddify-panel/backup -type f -delete
fi
python3 -m hiddifypanel backup
cd /opt/hiddify-config/hiddify-panel/backup
latest_file=\$(ls -t *.json | head -n1)
rm -f /root/backup-HMX-h.zip
zip /root/backup-HMX-h.zip /opt/hiddify-config/hiddify-panel/backup/\$latest_file
EOF
)
    MasterHide="MasterHide Hiddify backup"

else
    echo "Invalid selection. Please choose 'm', 'x', or 'h'."
    exit 1
fi

# Step 8: Create Backup and Send to Telegram
# --------------------------------------------------------
echo "Step 8: Creating backup and sending it to Telegram..."
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

# Install zip if necessary
if ! command -v zip &> /dev/null; then
    read -p "zip is required. Do you want to install it? (y/n): " install_zip
    if [[ "$install_zip" == "y" ]]; then
        sudo apt install zip -y
    else
        echo "zip is required to proceed. Exiting."
        exit 1
    fi
fi

cat > "/root/backup-HMX-${xmh}.sh" <<EOL
rm -rf /root/backup-HMX-${xmh}.zip
$ZIP
echo -e "$comment" | zip -z /root/backup-HMX-${xmh}.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/root/backup-HMX-${xmh}.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL

# Add cronjob for periodic execution
if ! sudo crontab -l &> /dev/null; then
    echo "No permission to modify crontab. Exiting."
    exit 1
fi
{ crontab -l -u root; echo "${cron_time} /usr/bin/bash /root/backup-HMX-${xmh}.sh >/dev/null 2>&1"; } | crontab -u root -

# Run the script
bash "/root/backup-HMX-${xmh}.sh"

# Clean up
rm -f /root/backup-HMX-${xmh}.sh /root/backup-HMX-${xmh}.zip

# Final Step - Completion
# --------------------------------------------------------
echo -e "\nBackup process completed successfully! The backup has been sent to Telegram."
