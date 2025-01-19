#!/bin/bash

# Bot token
# Get the bot token from the user and store it in the variable 'tk'
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# Chat ID
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

# Caption
# Get a caption for the backup file, for easier identification (e.g., your domain)
echo "Caption (e.g., your domain to identify the database file more easily): "
read -r caption

# Cronjob
# Set the schedule for running the script periodically
while true; do
    echo "Cronjob (minutes and hours) (e.g: 30 6 or 0 12): "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} */${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (minutes and hours, e.g: 0 6 or 30 12)"
    fi
done

# x-ui, Marzban or Hiddify?
# Ask the user to select which software backup to perform
while [[ -z "$xmh" ]]; do
    echo "Choose software (x-ui, Marzban or Hiddify) [x/m/h]: "
    read -r xmh
    if [[ $xmh == $'\0' ]]; then
        echo "Invalid input. Please choose x, m, or h."
        unset xmh
    elif [[ ! $xmh =~ ^[xmh]$ ]]; then
        echo "${xmh} is not a valid option. Please choose x, m, or h."
        unset xmh
    fi
done

# Ask if the previous crontabs should be cleared
while [[ -z "$crontabs" ]]; do
    echo "Would you like to clear the previous crontabs? [y/n]: "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

# If yes, remove previous cronjobs
if [[ "$crontabs" == "y" ]]; then
    sudo crontab -l | grep -vE '/root/backup-HMX.+\.sh' | crontab -
fi

# Marzban Backup (removed upload section)
# Create a backup file for Marzban software and store it in backup-HMX.zip
if [[ "$xmh" == "m" ]]; then

    if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
        echo "The folder exists at $dir"
    else
        echo "The folder does not exist."
        exit 1
    fi

    if [ -d "/var/lib/marzban/mysql" ]; then
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env
        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
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

fi

# x-ui Backup
# Create a backup file for X-UI software and store it in backup-HMX.zip
elif [[ "$xmh" == "x" ]]; then

    if dbDir=$(find /etc -type d -iname "x-ui*" -print -quit); then
        echo "The folder exists at $dbDir"
    else
        echo "The folder does not exist."
        exit 1
    fi

    if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
        echo "The folder exists at $configDir"
    else
        echo "The folder does not exist."
        exit 1
    fi

    ZIP="zip /root/backup-HMX-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    MasterHide="MasterHide x-ui backup"

# Hiddify Backup
# Create a backup file for Hiddify software and store it in backup-HMX.zip
elif [[ "$xmh" == "h" ]]; then

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
    echo "Please choose m, x, or h only!"
    exit 1
fi

# Trim the caption
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

# Install zip
# Install the 'zip' package if it's not already installed
sudo apt install zip -y

# Send the backup to Telegram
# Send the backup file to the Telegram bot
cat > "/root/backup-HMX-${xmh}.sh" <<EOL
rm -rf /root/backup-HMX-${xmh}.zip
$ZIP
echo -e "$comment" | zip -z /root/backup-HMX-${xmh}.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/root/backup-HMX-${xmh}.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL

# Add cronjob for periodic execution
{ crontab -l -u root; echo "${cron_time} /bin/bash /root/backup-HMX-${xmh}.sh >/dev/null 2>&1"; } | crontab -u root -

# Run the script
bash "/root/backup-HMX-${xmh}.sh"

# Clean up
rm -f /root/backup-HMX-${xmh}.sh /root/backup-HMX-${xmh}.zip

echo -e "\nDone\n"
