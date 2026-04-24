# 🪓 Midgard Reborn — Valheim Dedicated Server

> Self-hosted Valheim server on a Linux VPS using Docker, with automated hourly world backups to UploadThing and a browser-based setup panel for uploading local save files.

---

## 📁 Project Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Runs the Valheim dedicated server container |
| `valheim-backup.sh` | Hourly backup script — zips world saves and uploads to UploadThing |
| `valheim-panel.html` | Self-contained browser panel for setup, save file upload, and docs |
| `README.md` | This file |

---

## 🖥 VPS Requirements

| Resource | Minimum | Recommended (10 players) |
|---|---|---|
| CPU | 1 vCPU | 2 vCPU |
| RAM | 2 GB | 4 GB |
| Disk | 20 GB SSD | 40 GB SSD |
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |
| Network | Broadband | Low-latency, close to players |

> **Note:** CPU spikes are normal when players explore new areas — world generation is compute-heavy. Modded servers require meaningfully more RAM and CPU.

---

## 🚀 Quick Start (10 minutes)

### 1 — Install Docker on your VPS

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 curl jq
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker   # apply group change without logging out
```

### 2 — Upload files to your VPS

```bash
scp docker-compose.yml valheim-backup.sh root@YOUR_VPS_IP:/opt/valheim/
ssh root@YOUR_VPS_IP
cd /opt/valheim
chmod +x valheim-backup.sh
```

### 3 — Open firewall ports

```bash
sudo ufw allow 2456:2457/udp
sudo ufw allow 22/tcp        # keep SSH open
sudo ufw enable
sudo ufw reload
sudo ufw status              # verify
```

### 4 — Set your UploadThing API key

```bash
# Temporary (current session only)
export UPLOADTHING_API_KEY="sk_live_YOUR_KEY_HERE"

# Permanent (survives reboots)
echo 'export UPLOADTHING_API_KEY="sk_live_YOUR_KEY_HERE"' >> /etc/environment
source /etc/environment
```

### 5 — Start the server

```bash
docker compose up -d
docker compose logs -f   # watch startup — takes 2–5 min on first run
```

### 6 — Register the hourly backup cron

```bash
crontab -e
# Add this line:
0 * * * * /opt/valheim/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1
```

### 7 — Connect in-game

Open Valheim → **Start Game → Join Game → Add Server** → enter `YOUR_VPS_IP:2456`

Or if set to public, search for `Midgard Reborn` in the server browser.

---

## 🔑 UploadThing Setup

UploadThing provides cloud storage for world backups and optionally hosts your existing save files during server creation.

1. Go to [uploadthing.com](https://uploadthing.com) and create a free account
2. Click **Create a new app**
3. Navigate to **API Keys** → copy your `sk_live_...` key
4. Set it on your VPS as shown in Step 4 above

**Free tier limits:** 2 GB storage, unlimited uploads. Each backup archive is typically 1–15 MB depending on world size, so the free tier comfortably holds hundreds of snapshots.

---

## 🗂 Uploading Existing Save Files (Browser Panel)

If you already have a Valheim world on your PC and want to continue it on the server, use the included browser panel.

**Open `valheim-panel.html`** in any browser — no installation needed. The panel is a fully self-contained HTML file.

### Where your save files are located

| OS | Path |
|---|---|
| Windows | `%AppData%\..\LocalLow\IronGate\Valheim\worlds_local\` |
| macOS | `~/Library/Application Support/unity3d/IronGate/Valheim/worlds_local/` |
| Linux | `~/.config/unity3d/IronGate/Valheim/worlds_local/` |

### Required files

Each world is made of exactly two files. For a world named `MidgardWorld`:

```
MidgardWorld.db    ← world terrain, buildings, items
MidgardWorld.fwl   ← metadata: seed, name, timestamps
```

> ⚠️ **Both files are required.** One without the other will cause the server to generate a blank world.

### Panel workflow

1. Open `valheim-panel.html` in your browser
2. Enter your world name and UploadThing API key
3. Drag and drop your `.db` and `.fwl` files into the upload zone
4. Click **Forge the Server** — files upload directly from your browser to UploadThing
5. The panel generates `docker-compose.yml`, `valheim-backup.sh`, and `README.md` pre-filled with your config
6. Download all files via **⬇ Download All Files**

### Copy uploaded saves to your VPS

After uploading via the panel, retrieve the file URLs from your UploadThing dashboard and run on the VPS:

```bash
# Stop the server first if running
cd /opt/valheim && docker compose down

# Download saves into the Docker volume
docker run --rm -v midgard_valheim_config:/config alpine sh -c "
  mkdir -p /config/worlds_local &&
  wget -O /config/worlds_local/MidgardWorld.db  'https://YOUR_APP_ID.ufs.sh/f/FILE_KEY_DB' &&
  wget -O /config/worlds_local/MidgardWorld.fwl 'https://YOUR_APP_ID.ufs.sh/f/FILE_KEY_FWL'
"

# Restart server
docker compose up -d
docker compose logs -f
```

### Alternative: SCP direct transfer (skip UploadThing)

```bash
# From your local machine:
scp MidgardWorld.db MidgardWorld.fwl \
  root@YOUR_VPS_IP:/var/lib/docker/volumes/midgard_valheim_config/_data/worlds_local/

ssh root@YOUR_VPS_IP "cd /opt/valheim && docker compose restart"
```

> ⚠️ `WORLD_NAME` in `docker-compose.yml` must exactly match the filename (case-sensitive on Linux).

---

## 🐳 Docker Architecture

### Why this image?

`lloesche/valheim-server-docker` is the gold standard community image. It handles automatic game updates, graceful shutdown/restart, and keeps world data in named Docker volumes cleanly separated from the container binary.

### Volume layout

| Volume | Host Path | Purpose |
|---|---|---|
| `midgard_valheim_config` | `/var/lib/docker/volumes/midgard_valheim_config/_data/` | **World saves, player data, config — back this up** |
| `midgard_valheim_data` | `/var/lib/docker/volumes/midgard_valheim_data/_data/` | Server binaries — re-downloadable, no backup needed |

### Environment variables reference

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `Midgard Reborn` | Name shown in server browser |
| `WORLD_NAME` | `MidgardWorld` | Must match `.db` / `.fwl` filenames exactly |
| `SERVER_PASS` | *(set yours)* | Min 5 chars, cannot equal `SERVER_NAME` |
| `SERVER_PUBLIC` | `1` | `1` = visible in server list, `0` = private (join by IP only) |
| `UPDATE_CRON` | `*/15 * * * *` | How often to check for game updates |
| `BACKUPS` | `false` | Disabled — we use `valheim-backup.sh` instead |
| `TZ` | `Asia/Singapore` | Timezone for logs |
| `SERVER_ARGS` | *(unset)* | Extra launch flags e.g. `-crossplay` |

### Ports

| Port | Protocol | Purpose |
|---|---|---|
| `2456` | UDP | Game traffic (primary) |
| `2457` | UDP | Game traffic (secondary) |

---

## ⏰ Backup System

### How `valheim-backup.sh` works

Each run (every hour by default):

1. Reads world files from the Docker volume at `worlds_local/`
2. Creates a timestamped archive: `valheim_MidgardWorld_20250424_130000.tar.gz`
3. Calls UploadThing `POST /v6/uploadFiles` to get a presigned upload URL
4. Uploads the archive via HTTP POST to the presigned URL
5. Logs the UploadThing file key for later recovery
6. Removes all but the 3 newest local copies from `/tmp/valheim_backups/`

### Testing the backup manually

```bash
/opt/valheim/valheim-backup.sh

# Watch log output
tail -f /var/log/valheim-backup.log
```

### Cron schedule options

```bash
# Every hour (default)
0 * * * * /opt/valheim/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1

# Every 30 minutes
*/30 * * * * /opt/valheim/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1

# Every 6 hours
0 */6 * * * /opt/valheim/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1

# Once daily at 3 AM
0 3 * * * /opt/valheim/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1
```

### Restoring from a backup

```bash
# 1. Get the archive URL from your UploadThing dashboard
wget -O /tmp/restore.tar.gz "https://YOUR_APP_ID.ufs.sh/f/FILE_KEY"

# 2. Stop the server
cd /opt/valheim && docker compose down

# 3. Extract into the volume
tar -xzf /tmp/restore.tar.gz \
  -C /var/lib/docker/volumes/midgard_valheim_config/_data/worlds_local/

# 4. Restart
docker compose up -d
docker compose logs -f
```

---

## 🔄 Server Management

### Common commands

| Action | Command |
|---|---|
| Start server | `docker compose up -d` |
| Stop server (graceful) | `docker compose down` |
| Restart container | `docker compose restart` |
| View live logs | `docker compose logs -f` |
| Update to latest image | `docker compose pull && docker compose up -d` |
| Check resource usage | `docker stats midgard_valheim` |
| Open shell in container | `docker exec -it midgard_valheim bash` |

### Auto-restart on VPS reboot

The compose file uses `restart: unless-stopped` — the server comes back automatically after a VPS reboot. Verify Docker itself starts on boot:

```bash
sudo systemctl is-enabled docker   # should print "enabled"
# If not:
sudo systemctl enable docker
```

### Admin commands in-game

Add your Steam64 ID to the admin list, then restart:

```bash
# Find your Steam64 ID at steamidfinder.com
echo "76561198XXXXXXXXX" >> \
  /var/lib/docker/volumes/midgard_valheim_config/_data/adminlist.txt
docker compose restart
```

In-game press `F5` to open console, then type commands like `ban`, `kick`, `save`, `devcommands`.

### Access control files

All files live in `/var/lib/docker/volumes/midgard_valheim_config/_data/`:

| File | Purpose |
|---|---|
| `adminlist.txt` | One Steam64 ID per line — grants console/admin access |
| `permittedlist.txt` | Whitelist — only these IDs can join (leave empty to allow all) |
| `bannedlist.txt` | Blocked Steam64 IDs |

---

## 🛠 Troubleshooting

### Server not appearing in the server browser

- Check ports are open: `sudo ufw status` — confirm `2456:2457/udp ALLOW`
- Connect directly: **Add Server** → `YOUR_VPS_IP:2456`
- It can take up to 5 minutes after startup for the server to appear publicly
- Check the container is running: `docker compose ps`

### Players can't connect / PlayFab errors in logs

This is a known issue with the Linux dedicated server and crossplay:

```yaml
# In docker-compose.yml, add to environment:
SERVER_ARGS: "-crossplay"
# Or remove -crossplay entirely to disable crossplay support
```

### World resets to blank on each start

The world name in `docker-compose.yml` must exactly match the `.db` / `.fwl` filenames — Linux is case-sensitive.

```bash
# Check what files exist in the volume
ls /var/lib/docker/volumes/midgard_valheim_config/_data/worlds_local/

# Should show e.g.:
# MidgardWorld.db
# MidgardWorld.fwl
```

If `WORLD_NAME=MidgardWorld` and your files are named `midgardworld.db`, the server won't find them.

### Backup script errors

```bash
# Check log for specific error
tail -50 /var/log/valheim-backup.log

# "jq not found"
sudo apt install -y jq

# "UPLOADTHING_API_KEY not set"
echo $UPLOADTHING_API_KEY   # empty = not set
source /etc/environment     # reload env vars

# "Worlds path not found"
docker volume inspect midgard_valheim_config
# Look for "Mountpoint" in the output to find the actual path

# Test API key manually
curl -s -X POST "https://api.uploadthing.com/v6/uploadFiles" \
  -H "X-Uploadthing-Api-Key: $UPLOADTHING_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"files":[{"name":"test.txt","size":4,"type":"text/plain"}]}'
```

### High CPU or RAM usage

- CPU spikes on exploration are normal — world chunks generate on the fly
- For 6–10 concurrent players: upgrade to 4 vCPU / 8 GB RAM
- Monitor live: `docker stats midgard_valheim`
- Mods increase requirements significantly — budget 1–2 extra GB RAM per major mod pack

### Server crashes or randomly restarts

```bash
# Check recent container events
docker events --filter container=midgard_valheim --since 1h

# Check logs for crash reason
docker compose logs --tail=200 | grep -i "error\|crash\|fatal\|exception"

# Check for OOM (out of memory) kills
dmesg | grep -i "oom\|killed"
```

---

## 📎 Useful Links

- [Valheim Wiki — Dedicated Servers](https://valheim.fandom.com/wiki/Dedicated_servers)
- [lloesche/valheim-server-docker on GitHub](https://github.com/lloesche/valheim-server-docker)
- [UploadThing Documentation](https://docs.uploadthing.com)
- [SteamID Finder](https://www.steamidfinder.com) — for admin/ban lists
- [LinuxGSM Valheim](https://linuxgsm.com/servers/vhserver/) — alternative bare-metal install
