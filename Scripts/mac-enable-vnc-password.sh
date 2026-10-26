#!/usr/bin/env bash
# Turns on the standard VNC password ("VNC viewers may control screen with password") for macOS
# Screen Sharing. Needed because RealVNC / TigerVNC cannot use the Apple sign-in of recent macOS
# versions ("Protocol error: key length too large").
#
# Run it yourself, it asks for the VNC password (max 8 characters, VNC protocol limit):
#   ssh -t -i <key.pem> ec2-user@<mac-host> "bash ~/c4f_mobile_sdk_ios/Scripts/mac-enable-vnc-password.sh"
#
# Port 5900 stays closed to the internet; connect through the SSH tunnel (Scripts/connect-mac.ps1).
set -euo pipefail

read -r -s -p "New VNC password (max 8 characters): " PASS; echo
read -r -s -p "Repeat VNC password: " PASS2; echo
if [[ "$PASS" != "$PASS2" ]]; then echo "Passwords do not match." >&2; exit 1; fi
if [[ -z "$PASS" ]]; then echo "Password must not be empty." >&2; exit 1; fi
if (( ${#PASS} > 8 )); then echo "Only the first 8 characters are used by VNC."; fi

# macOS stores the legacy VNC password XOR-obfuscated with a fixed key in VNCSettings.txt.
printf '%s' "$PASS" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA" }
  $_ = <STDIN>; $_ = "" unless defined; s/^(.{8}).*/$1/s; @p = unpack "C*", $_;
  foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) } print "\n"' \
  | sudo tee /Library/Preferences/com.apple.VNCSettings.txt >/dev/null
sudo chmod 600 /Library/Preferences/com.apple.VNCSettings.txt
unset PASS PASS2

sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist VNCLegacyConnectionsEnabled -bool YES
sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null \
  || { sudo launchctl unload /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true;
       sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist; }

echo "Done. In the VNC viewer connect to localhost:5900 and enter only this VNC password."
echo "After connecting, sign in to the Mac desktop as ec2-user with the account password."
