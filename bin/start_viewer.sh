#!/bin/bash

# Create necessary directories
mkdir -p \
    /data/.screenly \
    /data/screenly_assets \
    /data/.local/share/ScreenlyWebview \
    /data/.cache/ScreenlyWebview \
    /data/.pki \
    /data/hotspot

# Set correct ownership and permissions
chown -R viewer:video /data/.screenly /data/screenly_assets /data/.local /data/.cache /data/.pki /data/hotspot
chgrp -f video /dev/vchiq 2>/dev/null || true
chmod -f g+rwX /dev/vchiq 2>/dev/null || true
 
# Remove or comment out the swappiness line (example)
# echo 10 > /sys/fs/cgroup/memory/memory.swappiness

# Create watchdog file
touch /tmp/screenly.watchdog
chown viewer:video /tmp/screenly.watchdog

# Start the viewer
echo "Starting viewer..."
sudo -E -u viewer python3 /usr/src/app/viewer.py

# Example process management (adjust based on your script)
# PID=$!  # Captures the PID of the last background process, if applicable
# if [ -n "$PID" ] && ps -p $PID > /dev/null; then
#     kill $PID
# else
#     echo "No process found to kill"
# fi