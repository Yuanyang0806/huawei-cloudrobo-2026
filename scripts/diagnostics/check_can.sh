#!/usr/bin/env bash
set -u

echo "===== KERNEL ====="
uname -r

echo
echo "===== GS_USB MODULE ====="
if lsmod | grep -q '^gs_usb'; then
    echo "gs_usb: loaded"
else
    echo "gs_usb: not loaded"
fi

echo
echo "===== USB DEVICES ====="
lsusb

echo
echo "===== CAN INTERFACES ====="
ip -details link show type can 2>/dev/null || true

echo
echo "===== CAN-UTILS ====="
command -v candump || echo "candump: NOT FOUND"
command -v cansend || echo "cansend: NOT FOUND"
