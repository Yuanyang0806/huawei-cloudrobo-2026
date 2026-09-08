#!/usr/bin/env bash
set -u

echo "===== USB VIDEO DEVICES ====="
lsusb | grep -Ei 'camera|video|webcam|orbbec|intel|realsense' || true

echo
echo "===== V4L2 DEVICES ====="
v4l2-ctl --list-devices 2>/dev/null || echo "No V4L2 devices found"

echo
echo "===== /dev/video* ====="
ls -l /dev/video* 2>/dev/null || echo "No /dev/video* devices"

echo
echo "===== STABLE DEVICE PATHS ====="
if [ -d /dev/v4l/by-id ]; then
    ls -l /dev/v4l/by-id/
else
    echo "/dev/v4l/by-id not available"
fi

echo
echo "===== STABLE PATH RESOLUTION ====="
if [ -d /dev/v4l/by-id ]; then
    for dev in /dev/v4l/by-id/*; do
        [ -e "$dev" ] || continue
        printf "%s -> %s\n" "$dev" "$(readlink -f "$dev")"
    done
fi
