# Comma 3X Tailscale Restore Guide

After a reflash/reinstall, run these commands to restore Tailscale:

## 1. Copy files to the device

```bash
# From your local machine (adjust IP if needed)
scp -r /path/to/this/folder/tailscaled.state comma@<device-ip>:/tmp/

ssh comma@<device-ip>
```

## 2. Install Tailscale

```bash
mkdir -p /data/tailscale
curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.94.1_arm64.tgz" \
  -o /tmp/tailscale.tgz
tar xzf /tmp/tailscale.tgz -C /data/tailscale --strip-components=1
rm /tmp/tailscale.tgz
```

## 3. Restore state (preserves node identity — no re-auth needed)

```bash
sudo cp /tmp/tailscaled.state /data/tailscale/tailscaled.state
sudo chown root:root /data/tailscale/tailscaled.state
sudo chmod 600 /data/tailscale/tailscaled.state
```

## 4. Update continue.sh for auto-start

```bash
cat > /data/continue.sh << 'EOF'
#!/usr/bin/env bash

# Start Tailscale daemon in background
sudo /data/tailscale/tailscaled --state=/data/tailscale/tailscaled.state --socket=/data/tailscale/tailscaled.sock &>/data/tailscale/tailscaled.log &

cd /data/openpilot
exec ./launch_openpilot.sh
EOF
```

## 5. Start and verify

```bash
sudo /data/tailscale/tailscaled --state=/data/tailscale/tailscaled.state \
  --socket=/data/tailscale/tailscaled.sock &>/data/tailscale/tailscaled.log &
sleep 2
sudo /data/tailscale/tailscale --socket=/data/tailscale/tailscaled.sock set --operator=comma
/data/tailscale/tailscale --socket=/data/tailscale/tailscaled.sock status
```

## Files in this backup

| File | Purpose |
|------|---------|
| `tailscaled.state` | Auth keys + node identity (restoring this skips re-authentication) |
| `continue.sh` | Boot script with Tailscale auto-start |
