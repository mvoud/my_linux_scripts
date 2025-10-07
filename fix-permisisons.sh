#!/bin/bash
# fix-permissions.sh
# Fix ownership and permissions for /mnt/shared

TARGET_DIR="/mnt/shared"
USER="mvoud"
GROUP="mvoud"

echo "Changing ownership to $USER:$GROUP..."
sudo chown -R $USER:$GROUP "$TARGET_DIR"

echo "Setting directory permissions to 755..."
sudo find "$TARGET_DIR" -type d -exec chmod 755 {} \;

echo "Setting file permissions to 644..."
sudo find "$TARGET_DIR" -type f -exec chmod 644 {} \;

echo "Done! All files and directories in $TARGET_DIR are now writable by $USER."
