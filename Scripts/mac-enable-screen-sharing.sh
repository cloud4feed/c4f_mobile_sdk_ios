#!/usr/bin/env bash
# One-time setup on the EC2 Mac so its desktop can be opened with a VNC viewer
# (AWS guide: "Connect to your instance's graphical user interface").
#
# Run it yourself in an SSH session, because it asks for a new password:
#   ssh -i <key.pem> ec2-user@<mac-host>
#   bash ~/c4f_mobile_sdk_ios/Scripts/mac-enable-screen-sharing.sh
#
# The password is only used for the desktop login and the VNC sign-in. SSH keeps using the key.
set -euo pipefail

echo "== 1. Password for ec2-user (used to sign in to the desktop through VNC)"
sudo passwd ec2-user

echo "== 2. Turn on macOS Screen Sharing"
sudo launchctl enable system/com.apple.screensharing
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true

echo "== 3. Optional: a larger screen resolution (makes the Simulator easier to use)"
if command -v brew >/dev/null; then
  if ! command -v displayplacer >/dev/null; then
    brew tap jakehilborn/jakehilborn && brew install displayplacer || true
  fi
  if command -v displayplacer >/dev/null; then
    echo "Available modes (pick one later with: displayplacer \"id:<id> res:1920x1080 origin:(0,0) degree:0\"):"
    displayplacer list | head -n 40 || true
  fi
fi

echo
echo "Done. On Windows run:"
echo "  .\\Scripts\\connect-mac.ps1 -MacHost <mac-host> -KeyPath <key.pem>"
echo "Sign in as ec2-user with the password from step 1, then open the Simulator:"
echo "  open -a Simulator"
