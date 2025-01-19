#!/bin/bash

# Function to show the main menu for backup/restore options
show_main_menu() {
    clear
    echo "=============================================="
    echo "       MasterHide Backup/Restore Tool"
    echo "=============================================="
    echo "1. Backup Marzban (Upload and Send)"
    echo "2. Backup X-UI (Inbuilt)"
    echo "3. Backup Hiddify (Inbuilt)"
    echo "4. Restore Backup from Telegram"
    echo "5. Restore Backup from Local File"
    echo "6. Exit"
    echo -n "Please choose an option (1-6): "
}

# Function to perform backup (upload and send to Telegram) for Marzban
backup_marzban() {
    bash /root/backup-HMX-m.sh  # Trigger Marzban backup process
    echo "Marzban backup completed and sent to Telegram."
}

# Function to handle X-UI backup option (inform user about inbuilt upload option)
backup_x_ui() {
    echo "This web panel has an inbuilt backup upload option, so you can use it."
    echo "Thanks for using this."
}

# Function to handle Hiddify backup option (inform user about inbuilt upload option)
backup_hiddify() {
    echo "This web panel has an inbuilt backup upload option, so you can use it."
    echo "Thanks for using this."
}

# Function to restore from Telegram (file ID)
restore_from_telegram() {
    read -p "Enter the Telegram bot token: " bot_token
    read -p "Enter the Telegram file ID: " file_id
    echo "Downloading the backup from Telegram..."

    # Get file URL from Telegram and construct download URL
    file_url=$(curl -s "https://api.telegram.org/bot${bot_token}/getFile?file_id=${file_id}" | jq -r '.result.file_path')
    download_url="https://api.telegram.org/file/bot${bot_token}/${file_url}"

    # Set backup destination
    backup_path="/opt/marzban/backup/backup-HMX.zip"
    curl -L -o $backup_path $download_url

    echo "Backup file downloaded successfully."
    extract_backup $backup_path
}

# Function to restore from local backup file
restore_from_local() {
    read -p "Enter the full path to the backup file (e.g., /path/to/backup-HMX.zip): " backup_file
    if [ ! -f "$backup_file" ]; then
        echo "Error: File not found!"
        return
    fi
    echo "Restoring backup from local file..."
    cp "$backup_file" /opt/marzban/backup/backup-HMX.zip
    extract_backup /opt/marzban/backup/backup-HMX.zip
}

# Function to extract the backup and restore the database and files
extract_backup() {
    backup_file=$1

    echo "Extracting the backup file..."
    unzip -o $backup_file -d /opt/marzban/backup/
    rm -f $backup_file  # Clean up the zip file

    echo "Backup extracted successfully."
    restore_database
    restore_configuration_files
}

# Function to restore the database
restore_database() {
    read -p "Do you want to restore the database? (y/n): " restore_db
    if [[ "$restore_db" == "y" ]]; then
        echo "Restoring database..."
        mysql -u root -p -e "CREATE DATABASE marzban;"
        mysql -u root -p marzban < /opt/marzban/backup/marzban_backup.sql
        echo "Database restored successfully."
    else
        echo "Skipping database restore."
    fi
}

# Function to restore configuration files
restore_configuration_files() {
    read -p "Do you want to restore configuration files? (y/n): " restore_config
    if [[ "$restore_config" == "y" ]]; then
        echo "Restoring configuration files..."
        cp /opt/marzban/backup/config.json /etc/marzban/
        cp /opt/marzban/backup/.env /opt/marzban/
        echo "Configuration files restored successfully."
    else
        echo "Skipping configuration files restore."
    fi
}

# Function to restart the Marzban service
restart_marzban() {
    read -p "Do you want to restart the Marzban service? (y/n): " restart_choice
    if [[ "$restart_choice" == "y" ]]; then
        echo "Restarting Marzban service..."
        systemctl restart marzban
        echo "Marzban service restarted successfully."
    else
        echo "Skipping Marzban service restart."
    fi
}

# Main script loop for menu navigation
while true; do
    show_main_menu
    read -r choice

    case $choice in
        1)
            backup_marzban
            break
            ;;
        2)
            backup_x_ui
            break
            ;;
        3)
            backup_hiddify
            break
            ;;
        4)
            restore_from_telegram
            break
            ;;
        5)
            restore_from_local
            break
            ;;
        6)
            echo "Exiting script."
            break
            ;;
        *)
            echo "Invalid choice! Please choose 1, 2, 3, 4, 5, or 6."
            ;;
    esac
done

# After restoring or completing a backup, prompt for a Marzban restart
restart_marzban
