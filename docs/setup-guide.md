# Plex + Prowlarr/Radarr/Sonarr/qBittorrent on Synology DSM 7.x

**Goal:** high-bitrate movies/TV, automated acquisition, VPN-protected download traffic, clean streaming to Apple TV via Plex.

**Legal note (read once, then ignore):** all of this software is legal — Plex, Prowlarr, Radarr, Sonarr, and qBittorrent are general-purpose media-server and download-automation tools. What you point qBittorrent at is what determines legality (public domain works, your own ripped media, content from properly licensed usenet/private-tracker sources vs. copyrighted material you don't have rights to). I'm giving you the technical setup; the sourcing is on you.

---

## 1. Architecture

```
Internet ─── Gluetun (VPN gateway container)
                 └── qBittorrent (network_mode: service:gluetun)
Prowlarr ──indexers──> Radarr / Sonarr ──sends jobs──> qBittorrent (via Gluetun)
Radarr/Sonarr ──rename/move completed files──> /media/movies, /media/tv
Plex ──reads──> /media/movies, /media/tv ──streams──> Apple TV
```

Only qBittorrent's traffic goes through the VPN tunnel. Prowlarr/Radarr/Sonarr/Plex stay on your LAN network — they don't need VPN protection and hiding them behind one just adds complexity and breaks LAN access to their web UIs.

---

## 2. Shared folders (do this in DSM first)

**Control Panel → Shared Folder → Create**, make these (adjust names to taste, but keep them consistent — you'll reference these paths in every container):

| Shared folder | Purpose |
|---|---|
| `docker` | Config/appdata for every container |
| `downloads` | qBittorrent's landing zone (temp + complete) |
| `media` | Final Plex library — subfolders `movies/`, `tv/` |

Inside `downloads`, Radarr/Sonarr expect qBittorrent to use subfolders like `downloads/complete` and `downloads/incomplete` — the compose file below sets this up.

**Important:** `downloads` and `media` should be on the **same DSM volume**. Radarr/Sonarr "import" completed downloads into the media library by hardlinking (instant, no duplicate space used) — but hardlinks only work within the same filesystem/volume. If they're on different volumes, imports fall back to slow copies and you double your disk usage temporarily.

---

## 3. VPN provider: Private Internet Access (PIA)

**Why PIA:** cheap (~$2/mo on multi-year plans), unlimited devices per account, native OpenVPN port-forwarding support in Gluetun, and it's the provider most commonly documented in the Radarr/Sonarr self-hosting community, so troubleshooting help is easy to find.

**Important wrinkle:** Gluetun's PIA integration only has native support for **OpenVPN**, not WireGuard — the maintainers note WireGuard support for PIA specifically "cannot be added [natively], but this is a slow work in progress" (you can hand-build a custom WireGuard config as a workaround, but it's fragile and not worth it here). So we're using OpenVPN below, which is simpler and fully supported anyway.

### 3a. Sign up for PIA

1. Go to **[privateinternetaccess.com](https://www.privateinternetaccess.com/)**
2. Pick a plan — the multi-year plan is the one that gets you to ~$2/mo; monthly is available if you want to test first
3. Checkout creates your account — PIA uses an auto-generated username (format `pXXXXXXX`) and a password you set, **not your email**. This username/password pair is what Gluetun needs — write it down or save it in a password manager now.
4. No app install needed on your side — you won't use PIA's own desktop/router app at all, since Gluetun is acting as the PIA client for your NAS.

That's it — no keys to generate, no dashboard config. PIA's OpenVPN auth is just that username/password.

### 3b. Enable port forwarding on your PIA account

Port forwarding needs a PIA server location that supports it. Not all regions do — the Netherlands, and several other non-US/non-5-Eyes locations, reliably support it. **US servers do not support port forwarding on PIA.** So there's a small privacy/speed tradeoff: you'll pick a non-US region for the VPN tunnel to get port forwarding working.

One caveat worth knowing going in: PIA doesn't support inbound connections on the forwarded port for general purposes (e.g., hosting a webserver) — <cite index="33-1">PIA has confirmed their service does not support incoming connections over a forwarded port for general use, though incoming connections on the forwarded port work fine for P2P protocols</cite> like BitTorrent. Since that's exactly your use case, you're fine.

You'll drop the PIA username/password into the `.env` file below — port forwarding itself is enabled via environment variables, not PIA's website.

---

## 4. Container Manager: create the Project

DSM 7.2+ Container Manager has a **Project** feature that's just docker-compose under the hood — this is the easiest path since you have zero compose experience yet.

1. Open **Container Manager → Project → Create**
2. Name it `media-stack`
3. Path: point it at a new folder, e.g. `/docker/media-stack` (create it in File Station first, inside your `docker` shared folder)
4. Source: **Create docker-compose.yml**, paste the file below
5. Container Manager will also let you upload a `.env` file alongside it — do that too (step 5 below)

### `docker-compose.yml`

```yaml
version: "3.8"

services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - 8080:8080   # qBittorrent WebUI (exposed here since qbit shares gluetun's network)
      - 6881:6881
      - 6881:6881/udp
    volumes:
      - /volume1/docker/media-stack/gluetun:/gluetun
    environment:
      - VPN_SERVICE_PROVIDER=private internet access
      - VPN_TYPE=openvpn
      - OPENVPN_USER=${PIA_USER}
      - OPENVPN_PASSWORD=${PIA_PASS}
      - SERVER_REGIONS=${PIA_REGION}
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_STATUS_FILE=/gluetun/forwarded_port
      - TZ=America/Los_Angeles
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"   # <-- all its traffic routes through the VPN
    depends_on:
      - gluetun
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Los_Angeles
      - WEBUI_PORT=8080
    volumes:
      - /volume1/docker/media-stack/qbittorrent:/config
      - /volume1/downloads:/downloads
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Los_Angeles
    volumes:
      - /volume1/docker/media-stack/prowlarr:/config
    ports:
      - 9696:9696
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Los_Angeles
    volumes:
      - /volume1/docker/media-stack/radarr:/config
      - /volume1/downloads:/downloads
      - /volume1/media/movies:/movies
    ports:
      - 7878:7878
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Los_Angeles
    volumes:
      - /volume1/docker/media-stack/sonarr:/config
      - /volume1/downloads:/downloads
      - /volume1/media/tv:/tv
    ports:
      - 8989:8989
    restart: unless-stopped
```

**Adjust `/volume1/...` paths** to match your actual volume number (check File Station — could be `/volume1` or `/volume2` etc.) and your shared folder names from step 2.

### `.env` file (same project folder)

```
PIA_USER=p1234567
PIA_PASS=your_pia_password_here
PIA_REGION=Netherlands
```

- `PIA_USER` / `PIA_PASS` — the auto-generated username and the password you set at signup (step 3a above). Not your email.
- `PIA_REGION` — must be a port-forwarding-capable region. **Netherlands** is a safe, low-latency default for US-based users; other options include Sweden, Romania, and Switzerland. Avoid US regions here — they don't support port forwarding on PIA.

Deploy the project. Give it a minute — Gluetun needs to establish the tunnel before qBittorrent (which shares its network stack) will be reachable.

**Verify the VPN is actually working before doing anything else:**
```bash
docker exec gluetun wget -qO- ifconfig.me
```
That IP should match your VPN provider's location (e.g., a Netherlands IP), **not** your home IP. If qBittorrent's WebUI (port 8080) won't load, check `docker logs gluetun` — almost always a credentials mismatch or a region that doesn't support port forwarding.

### Get the forwarded port and set it in qBittorrent

Gluetun writes PIA's forwarded port to a file inside the container once the tunnel is up (that's what `VPN_PORT_FORWARDING_STATUS_FILE` in the compose file is for). Read it with:

```bash
docker exec gluetun cat /gluetun/forwarded_port
```

That'll print a number like `54321`. Take that number into qBittorrent's WebUI → **Settings → Connection → Listening Port**, set it there, and uncheck "Use different port on each startup." PIA rotates you to a new forwarded port roughly every 60 days (as long as the `/gluetun` volume persists across restarts, per Gluetun's docs), so you'll want to recheck this occasionally — or automate it later with a small script that re-reads the file and hits qBittorrent's API on a schedule if it starts to bother you.

---

## 5. Install Plex — use the native DSM package, not a container

For Plex specifically, I'd steer you away from a container and toward **Package Center → Plex Media Server**. Reason: hardware transcoding (Intel Quick Sync) is much easier to wire up through the native Synology package, and since your whole goal here is *avoiding* quality loss, you want transcoding to be a rare fallback (for a client that can't direct-play your codec) rather than something fighting for `/dev/dri` access inside a container. If your NAS model doesn't have Quick Sync (check your model's spec page), it doesn't matter either way and a container is fine.

After installing: point Plex's library folders at `/volume1/media/movies` and `/volume1/media/tv` (same paths Radarr/Sonarr write to).

---

## 6. Configure the stack (order matters)

**A. Prowlarr first** (`http://your-nas-ip:9696`)
1. **Indexers → Add Indexer** — add your torrent trackers and/or usenet indexers (Prowlarr treats both the same way)
2. **Settings → Apps** — add Radarr and Sonarr as "Applications." Use each app's internal Docker network address, e.g. `http://radarr:7878` and `http://sonarr:8989`, with their API keys (found in each app's Settings → General). Prowlarr will then auto-push indexers to both — you don't configure indexers separately in Radarr/Sonarr.

**B. Radarr / Sonarr** (`:7878` / `:8989`)
1. **Settings → Download Clients → Add → qBittorrent.** Host: `gluetun` (the container name, since qBittorrent shares its network namespace), port `8080`, plus the qBittorrent username/password you set in its WebUI on first login.
2. **Settings → Media Management** — root folder `/movies` (Radarr) or `/tv` (Sonarr) — matches the container volume mount, not the DSM path.
3. Enable **Rename** so files land in Plex-friendly naming (Plex's matching depends heavily on clean filenames/folder structure).

**C. qBittorrent** (`:8080` through Gluetun)
1. First login is `admin` / a temp password — check `docker logs qbittorrent` for it, then change it immediately.
2. **Settings → Downloads** — default save path `/downloads/complete`, incomplete path `/downloads/incomplete`.
3. **Settings → BitTorrent → Listening Port** — set to the forwarded port you pulled in the "Get the forwarded port" step above.

---

## 7. Bitrate/quality settings — the part that actually matters for your goal

This is where you control "better than streaming services." Streaming services typically cap at 15–25 Mbps even for 4K (Netflix 4K ≈ 16 Mbps, Disney+ similar) — a good remux or high-bitrate encode can run 40–80+ Mbps for 4K, or 15–25 Mbps for well-encoded 1080p, with visibly less compression artifacting.

**In Radarr — Settings → Profiles → Quality Profiles:**
- Create a profile prioritizing **Remux-1080p / Remux-2160p** at the top (remuxes are the untouched Blu-ray video stream, just repackaged — largest files, zero re-encoding loss), then **Bluray-1080p/2160p** as fallback, then high-bitrate WEB-DL below that.
- Under **Settings → Custom Formats**, you can add formats to prefer specific encode groups or penalize heavily-compressed releases — useful once you're dialed in, skip it for now.
- **Settings → Quality → Size limits** — remuxes run 15-60GB+ per movie for 4K, so check your storage headroom before setting min/max thresholds.

**In Sonarr:** same idea — WEB-DL 1080p/2160p from major streaming sources is usually the best size-to-quality tradeoff for TV (true remuxes are less common for episodic content). Set your quality profile accordingly.

**Storage reality check:** a single 4K remux can be 50-80GB. If you're planning a real library, plan your Synology volume size accordingly — this is the single biggest gotcha people hit with this setup.

---

## 8. Getting the highest quality onto Apple TV specifically

The pipeline can pull a perfect remux, but two more things determine what actually reaches your TV:

1. **Plex client setting on Apple TV:** in the Plex app → Settings → Player → set **quality to "Original / Maximum"** and disable any bandwidth cap. There's a "Prefer High-Bitrate encodes" style toggle in some Plex client versions — set it to max.
2. **Direct Play vs. transcoding:** Apple TV (4K models) natively supports HEVC/H.264 and most common audio codecs, so most Blu-ray-quality content will **Direct Play** — meaning Plex hands the file over untouched, full original bitrate, zero quality loss. Transcoding only kicks in if the codec/container isn't Apple TV-compatible (rare with standard MKV/H.264/HEVC) or if you're on a slow remote connection and Plex auto-downgrades. On your home network streaming to your own Apple TV, you should be getting Direct Play almost always — check the "..." info button during playback, it'll say "Direct Play" if you're getting the full original stream.
3. **Network:** wired Ethernet to the Apple TV (or a strong 5GHz link) matters more than people expect — a 60-80 Mbps 4K remux over weak WiFi will force Plex to transcode/throttle even though the source and NAS could easily deliver it.

---

## Next steps I can help with
- Troubleshooting Gluetun/PIA connection issues if `docker logs gluetun` shows errors
- Custom Formats in Radarr/Sonarr for finer quality control
- A script to auto-refresh the forwarded port in qBittorrent on a schedule (so you don't have to check it manually every couple months)
- A reverse proxy setup if you ever want remote access to these UIs (not needed for local-only use)
