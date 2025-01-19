#!/bin/bash

# Function to display the main menu
show_menu() {
    clear
    echo "======================================="
    echo " Marzban Backup Restore Script"
    echo "======================================="
    echo "1. Restore Backup from Telegram"
    echo "2. Restore Backup from Local File"
    echo "3. Exit"
    echo -n "Please choose an option (1-3): "
}

# Function to download the backup from Telegram using file ID
restore_from_telegram() {
    read -p "Enter the Telegram bot token: " bot_token
    read -p "Enter the Telegram file ID: " file_id
    echo "Downloading the backup from Telegram..."
    
    # Get the file URL from Telegram
    file_url=$(curl -s "https://api.telegram.org/bot${bot_token}/getFile?file_id=${file_id}" | jq -r '.result.file_path')
    
    # Construct the download URL
    download_url="https://api.telegram.org/file/bot${bot_token}/${file_url}"
    
    # Download the file to the Marzban backup folder
    backup_path="/opt/marzban/backup/backup-HMX.zip"
    curl -L -o $backup_path $download_url
    
    echo "Backup file downloaded successfully."
    extract_backup $backup_path
}

# Function to restore from a local file
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
    # Restore the database (optional)
    restore_database
    # Restore configuration files
    restore_configuration_files
}

# Function to restore the database
restore_database() {
    read -p "Do you want to restore the database? (y/n): " restore_db
    if [[ "$restore_db" == "y" ]]; then
        # Database restore
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
        # Copy configuration files
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
    read -p "Do you want to restart Marzban service? (y/n): " restart_choice
    if [[ "$restart_choice" == "y" ]]; then
        # Restart Marzban service
        echo "Restarting Marzban service..."
        systemctl restart marzban
        echo "Marzban service restarted successfully."
    else
        echo "Skipping Marzban service restart."
    fi
}

# Main script logic
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1)
            restore_from_telegram
            break
            ;;
        2)
            restore_from_local
            break
            ;;
        3)
            echo "Exiting script."
            break
            ;;
        *)
            echo "Invalid choice! Please choose 1, 2, or 3."
            ;;
    esac
done

# After completing the restoration, ask about restarting Marzban
restart_marzban

