# synology-plex-arr-stack

Docker Compose stack for a Synology DSM 7.x NAS: Gluetun (VPN gateway) + qBittorrent +
Prowlarr + Radarr + Sonarr, feeding a Plex media library. VPN provider is Private
Internet Access (PIA), routed through Gluetun so only qBittorrent's traffic is tunneled.

## Architecture

```
Internet ─── Gluetun (VPN gateway container, PIA)
                 └── qBittorrent (network_mode: service:gluetun)
Prowlarr ──indexers──> Radarr / Sonarr ──sends jobs──> qBittorrent (via Gluetun)
Radarr/Sonarr ──rename/move completed files──> /media/movies, /media/tv
Plex (native DSM package, not containerized) ──reads──> /media ──streams──> Apple TV
```

Plex itself runs as the native Synology Package Center app, not a container, to keep
hardware transcoding (Quick Sync) simple. Everything else runs via this compose file.

## Repo layout

```
.
├── docker-compose.yml    # the stack definition
├── .env.example           # template for required secrets/config — copy to .env
├── .gitignore              # keeps .env and container appdata out of git
└── docs/
    └── setup-guide.md      # full walkthrough: DSM shares, PIA signup, quality profiles, Apple TV tuning
```

## Prerequisites on the NAS

- DSM 7.2+ with Container Manager installed
- One shared folder, `plex`, created in DSM, with subfolders `docker`, `downloads`,
  and `media` underneath it (created via File Station — see docs/setup-guide.md)
- A PIA account with port forwarding enabled on a supporting region (not US)

## Usage

1. Clone this repo onto your workstation (or directly note the values — DSM
   Container Manager Projects can pull from a folder, not a git remote directly, so
   in practice: clone locally, copy `docker-compose.yml` + your real `.env` into a
   Container Manager Project folder on the NAS via File Station or `scp`).
2. `cp .env.example .env` and fill in real PIA credentials.
3. Deploy via Container Manager → Project, or `docker compose up -d` if running
   compose directly over SSH on the NAS.
4. See `docs/setup-guide.md` for full post-deploy configuration (Prowlarr indexers,
   Radarr/Sonarr download client wiring, quality profiles, Apple TV playback settings).

## Notes / gotchas

- Gluetun's PIA integration is OpenVPN-native; WireGuard for PIA isn't natively
  supported by Gluetun as of this writing.
- Port forwarding only works on non-US PIA regions.
- Forwarded port rotates ~every 60 days — check
  `docker exec gluetun cat /gluetun/forwarded_port` periodically and update
  qBittorrent's listening port.
- `downloads` and `media` live under the same `plex` shared folder by design, so
  they're always on the same DSM volume — required for Radarr/Sonarr hardlink
  imports to work (avoids slow copy + double disk usage).
