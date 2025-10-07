#!/bin/bash

set -e

CONFIG_FILE="$HOME/.webftp_setup.conf"
WEB_ROOT="/mnt/shared/www"
FTP_ROOT="/mnt/shared"

# Function to ask Y/N or skip
ask_yn() {
    local prompt="$1"
    local default="$2"
    read -p "$prompt [Y/N] (Nothing = Skip): " answer
    answer=${answer^^}
    if [[ "$answer" == "Y" ]]; then
        echo "Y"
    elif [[ "$answer" == "N" ]]; then
        echo "N"
    else
        echo "$default"
    fi
}

# Load saved preferences
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Save preferences
save_config() {
    echo "SAVE_PREFERENCES=$1" > "$CONFIG_FILE"
    echo "ENABLE_APACHE=$2" >> "$CONFIG_FILE"
    echo "ENABLE_MYSQL=$3" >> "$CONFIG_FILE"
    echo "ENABLE_PHP=$4" >> "$CONFIG_FILE"
}

load_config

echo "=== WEB SERVER + FTP SETUP ==="

# Web setup
ENABLE_APACHE=$(ask_yn "Do you want to enable Apache?" "$ENABLE_APACHE")
ENABLE_MYSQL=$(ask_yn "Do you want to enable MySQL?" "$ENABLE_MYSQL")
ENABLE_PHP=$(ask_yn "Do you want to enable PHP?" "$ENABLE_PHP")
SAVE_PREF=$(ask_yn "Save preferences for future setups?" "$SAVE_PREFERENCES")

if [[ "$SAVE_PREF" == "Y" ]]; then
    save_config "$SAVE_PREF" "$ENABLE_APACHE" "$ENABLE_MYSQL" "$ENABLE_PHP"
fi

if [[ "$ENABLE_APACHE" == "Y" ]]; then
    INSTALL_PMA=$(ask_yn "Do you want to install PHPMyAdmin?" "N")
fi

read -p "Enter website/dnsmasq hostname: " WEBSITE_HOST
read -p "Which folder should Apache point to (Nothing = $WEB_ROOT): " APACHE_ROOT
APACHE_ROOT=${APACHE_ROOT:-$WEB_ROOT}

# Detect default IPs if empty
ETH_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
WIFI_IP=$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

read -p "Original IP [eth] for dnsmasq (Nothing = $ETH_IP): " ETH_IP_INPUT
ETH_IP=${ETH_IP_INPUT:-$ETH_IP}

read -p "Original IP [wifi] for dnsmasq (Nothing = $WIFI_IP): " WIFI_IP_INPUT
WIFI_IP=${WIFI_IP_INPUT:-$WIFI_IP}

ADD_PHPINFO=$(ask_yn "Add phpinfo.php to Apache root?" "N")

# === INSTALL COMPONENTS ===
apt update

if [[ "$ENABLE_APACHE" == "Y" ]]; then
    apt install -y apache2
    mkdir -p "$APACHE_ROOT"
    chown -R www-data:www-data "$APACHE_ROOT"
    sed -i "s|DocumentRoot .*|DocumentRoot $APACHE_ROOT|" /etc/apache2/sites-available/000-default.conf
    systemctl enable apache2
    systemctl restart apache2
fi

if [[ "$ENABLE_PHP" == "Y" ]]; then
    apt install -y php libapache2-mod-php
    systemctl restart apache2
    if [[ "$ADD_PHPINFO" == "Y" ]]; then
        echo "<?php phpinfo(); ?>" > "$APACHE_ROOT/phpinfo.php"
    fi
fi

if [[ "$ENABLE_MYSQL" == "Y" ]]; then
    apt install -y mariadb-server php-mysql
    systemctl enable mariadb
    systemctl start mariadb
fi

if [[ "$INSTALL_PMA" == "Y" ]]; then
    apt install -y phpmyadmin
    ln -s /usr/share/phpmyadmin "$APACHE_ROOT/phpmyadmin"
fi

# === FTP Setup ===
echo "=== FTP SETUP ==="
ADD_FTP=$(ask_yn "Do you want to use the Apache folder ($APACHE_ROOT) for FTP?" "Y")
if [[ "$ADD_FTP" == "Y" ]]; then
    FTP_ROOT="$APACHE_ROOT"
else
    read -p "Enter the folder to share via FTP: " FTP_ROOT
fi

ALLOW_ANON=$(ask_yn "Allow local users to access the folder without authentication?" "N")

apt install -y vsftpd
cp /etc/vsftpd.conf /etc/vsftpd.conf.bak
cat > /etc/vsftpd.conf <<EOL
listen=YES
listen_ipv6=NO
anonymous_enable=${ALLOW_ANON}
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_min_port=10000
pasv_max_port=10100
EOL

# FTP user creation
while [[ "$ALLOW_ANON" == "N" ]]; do
    read -p "Enter a username for the folder: " FTP_USER
    read -s -p "Enter a password for [$FTP_USER]: " FTP_PASS
    echo
    useradd -d "$FTP_ROOT" -s /usr/sbin/nologin "$FTP_USER"
    echo "$FTP_USER:$FTP_PASS" | chpasswd
    ADD_ANOTHER=$(ask_yn "Add another user?" "N")
    [[ "$ADD_ANOTHER" == "N" ]] && break
done

systemctl enable vsftpd
systemctl restart vsftpd

# === DNSMASQ Setup ===
echo "=== DNSMASQ SETUP ==="
apt install -y dnsmasq
cat > /etc/dnsmasq.d/$WEBSITE_HOST.conf <<EOL
address=/$WEBSITE_HOST/$ETH_IP
EOL
systemctl restart dnsmasq

echo "=== SETUP COMPLETED! ==="
echo "Web root: $APACHE_ROOT"
echo "FTP root: $FTP_ROOT"
echo "Local hostname: $WEBSITE_HOST"
if [[ "$INSTALL_PMA" == "Y" ]]; then
    echo "PHPMyAdmin available at $APACHE_ROOT/phpmyadmin"
fi
