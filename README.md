# backup-HMX    TEST
Backup script for database and user data fetch

Install (still in development)

```
sudo apt update && sudo apt install -y zip git curl && git clone https://github.com/MasterHide/backup-HMX.git /opt/backup-HMX && bash -c "$(curl -fsSL https://raw.githubusercontent.com/MasterHide/backup-HMX/main/backup-HMX.sh)"
```

Update the repository (if you want the latest version) and then run the script again

```
cd /opt/backup-HMX && git pull && bash backup-HMX.sh
```

Uninstall (still in development)

```
sudo rm -rf /opt/backup-HMX && sudo apt update && sudo apt install -y zip git curl && git clone https://github.com/MasterHide/backup-HMX.git /opt/backup-HMX && bash -c "$(curl -fsSL https://raw.githubusercontent.com/MasterHide/backup-HMX/main/backup-HMX.sh)"
```
