# 🪓 Midgard Reborn — Valheim Dedicated Server
> Docker + UploadThing hourly backup setup

---

## 📁 Files
| File | Purpose |
|---|---|
| `docker-compose.yml` | Runs the Valheim server via Docker |
| `valheim-backup.sh` | Hourly backup script → uploads to UploadThing |

---

## 🚀 Quick Start

### 1. Install dependencies
```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 curl jq
sudo systemctl enable --now docker
```

### 2. Upload files to your VPS
```bash
scp docker-compose.yml valheim-backup.sh root@YOUR_VPS_IP:/opt/valheim/
ssh root@YOUR_VPS_IP
cd /opt/valheim
```

### 3. Edit `docker-compose.yml`
Change these values:
- `SERVER_PASS` → your chosen password (min 5 chars)
- `SERVER_NAME` → keep "Midgard Reborn" or rename it
- `TZ` → your timezone (e.g. `Asia/Singapore`, `Europe/London`, `America/New_York`)

### 4. Start the server
```bash
docker compose up -d
docker compose logs -f   # watch startup (takes 2–5 min first time)
```

### 5. Open firewall ports
```bash
sudo ufw allow 2456:2457/udp
sudo ufw reload
```

---

## 🔑 UploadThing Setup

1. Go to [uploadthing.com](https://uploadthing.com) → create a free account
2. Create a new **App**
3. Go to **API Keys** → copy your `sk_live_...` key
4. Set it on your VPS:
```bash
export UPLOADTHING_API_KEY="sk_live_YOUR_KEY_HERE"
# Make it permanent:
echo 'export UPLOADTHING_API_KEY="sk_live_YOUR_KEY_HERE"' >> /etc/environment
```

### Test the backup script
```bash
chmod +x /opt/valheim/valheim-backup.sh
/opt/valheim/valheim-backup.sh
```

---

## ⏰ Set Up Hourly Cron

```bash
crontab -e
```

Add this line (runs every hour on the hour):
```
0 * * * * /opt/valheim/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1
```

View backup logs anytime:
```bash
tail -f /var/log/valheim-backup.log
```

---

## 📂 World Save Location (inside Docker volume)

```
/var/lib/docker/volumes/midgard_valheim_config/_data/worlds_local/
```

To copy your **existing world** from a Windows PC:
```bash
# On your Windows PC, world files are at:
# C:\Users\<YOU>\AppData\LocalLow\IronGate\Valheim\worlds_local\
scp MidgardWorld.* root@YOUR_VPS_IP:/var/lib/docker/volumes/midgard_valheim_config/_data/worlds_local/
docker compose restart
```

---

## 🔄 Server Management

| Action | Command |
|---|---|
| Start server | `docker compose up -d` |
| Stop server | `docker compose down` |
| Restart server | `docker compose restart` |
| View live logs | `docker compose logs -f` |
| Update server | `docker compose pull && docker compose up -d` |

---

## ⚙️ Useful Tweaks (`docker-compose.yml`)

| Env Var | Default | Notes |
|---|---|---|
| `SERVER_PUBLIC` | `1` | `0` = private (invite-only) |
| `UPDATE_CRON` | `*/15 * * * *` | How often to check for game updates |
| `SUPERVISOR_HTTP` | *(unset)* | Set to `true` + add `SUPERVISOR_HTTP_PORT` for web UI |

---

## 🛠 Troubleshooting

**Server not showing in browser?**
→ Make sure UDP ports 2456–2457 are open. Connect directly via IP: `your.ip.here:2456`

**PlayFab crossplay errors in logs?**
→ Add `SERVER_ARGS: "-crossplay"` or try without crossplay.

**Backup script fails with "Worlds path not found"?**
→ Run `docker volume inspect midgard_valheim_config` to confirm mount path.
