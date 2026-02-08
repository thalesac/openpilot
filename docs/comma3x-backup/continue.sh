#!/usr/bin/env bash

# Start Tailscale daemon in background
sudo /data/tailscale/tailscaled --state=/data/tailscale/tailscaled.state --socket=/data/tailscale/tailscaled.sock &>/data/tailscale/tailscaled.log &

cd /data/openpilot
exec ./launch_openpilot.sh
