# synology-plex-arr-stack

Docker Compose stack for a Synology DSM 7.x NAS: Gluetun (VPN gateway) + qBittorrent +
Prowlarr + Radarr + Sonarr + Chaptarr (books/audiobooks) + Audiobookshelf, feeding a Plex media library. VPN provider is Private
Internet Access (PIA), routed through Gluetun so only qBittorrent's traffic is tunneled.

## Architecture

```
Internet ─── Gluetun (VPN gateway container, PIA)
                 └── qBittorrent (network_mode: service:gluetun)
Prowlarr ──indexers──> Radarr / Sonarr / Chaptarr ──sends jobs──> qBittorrent (via Gluetun)
Radarr/Sonarr ──rename/move completed files──> /media/movies, /media/tv
Plex (native DSM package, not containerized) ──reads──> /media ──streams──> Apple TV
Chaptarr ──imports──> /media/books ──read by──> Audiobookshelf ──streams──> iPhone / iPad
```

Plex itself runs as the native Synology Package Center app, not a container, to keep
hardware transcoding (Quick Sync) simple. Everything else runs via this compose file.

## Repo layout

```
.
├── docker-compose.yml    # the stack definition
├── restart-media-stack.sh # NAS: git pull + update images + restart
├── remote-restart-media-stack.sh # laptop: runs the above on the NAS over SSH
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

The NAS keeps a git clone of this repo at `/volume1/plex/docker/synology-plex-arr-stack`,
which is also the folder the Container Manager project (`media-stack`) points at. Make
changes on your workstation, push to GitHub, then pull on the NAS — don't edit files
directly on the NAS, or `git pull` will refuse to overwrite them.

First-time setup on the NAS (SSH in, then `sudo -i`):

1. Install **Git Server** from Package Center (it provides the `git` command).
2. Create an SSH key for root and add `/root/.ssh/github_deploy.pub` to the repo as a
   read-only **Deploy key** on GitHub, with this in `/root/.ssh/config`:

   ```
   Host github.com
     IdentityFile /root/.ssh/github_deploy
     IdentitiesOnly yes
   ```

3. Clone the repo and create the real `.env`:

   ```bash
   cd /volume1/plex/docker && git clone git@github.com:pottegil/synology-plex-arr-stack.git
   cd synology-plex-arr-stack && cp .env.example .env   # then fill in real PIA credentials
   git config core.fileMode false
   ```

4. Start the stack: `docker compose up -d`
5. See `docs/setup-guide.md` for full post-deploy configuration (Prowlarr indexers,
   Radarr/Sonarr download client wiring, quality profiles, Apple TV playback settings).

## Updating

The quick way — `restart-media-stack.sh` runs all of the steps below (git pull, image
pull, recreate, prune, status):

```bash
sudo /volume1/plex/docker/synology-plex-arr-stack/restart-media-stack.sh
```

From your laptop, without SSHing in first, `remote-restart-media-stack.sh` runs that same
script on the NAS over SSH (it prompts for your NAS password for `sudo`):

```bash
./remote-restart-media-stack.sh                     # logs in as pottegil
NAS_USER=someone-else ./remote-restart-media-stack.sh   # different DSM account
```

Defaults: `NAS_HOST=10.1.1.165`, `NAS_USER=pottegil`,
`NAS_REPO=/volume1/plex/docker/synology-plex-arr-stack` — override any of them with
environment variables. Push your changes to GitHub first; the NAS pulls from there.

Or run the commands by hand on the NAS as root (`sudo -i`) from the repo folder.

Pull new container versions (all images use `:latest`, so `docker compose up -d` on
its own never checks for updates):

```bash
cd /volume1/plex/docker/synology-plex-arr-stack
docker compose pull
docker compose up -d
docker image prune -f
```

`pull` downloads newer images, `up -d` recreates only the containers whose image
changed (settings survive — they live in `/volume1/plex/docker/media-stack/<app>`),
and `image prune` deletes the old image versions to free space.

Apply changes pushed to this repo (new services, config edits), and update images too:

```bash
cd /volume1/plex/docker/synology-plex-arr-stack
git pull
docker compose pull
docker compose up -d
docker image prune -f
```

Check everything came back up:

```bash
docker compose ps
```

If gluetun was updated, qBittorrent restarts with it and the forwarded port may change —
re-check it (see below).

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
- The compose file sets `name: media-stack` so the CLI and Container Manager manage the
  same project. Without it, `docker compose` names the project after the folder and
  fails with "container name already in use".
- New appdata folders created over SSH can inherit a Synology ACL that leaves them
  `d---------+` and unwritable (the container then restart-loops). Check with
  `ls -ln /volume1/plex/docker/media-stack/`; create folders from inside the container
  (`docker exec -u 1000 <app> mkdir -p /path`) or `chown 1000:1000` + `chmod 775` them.
- Chaptarr root folders are one type each: use `/books/audiobooks` (Audiobooks) and
  `/books/ebooks` (Ebooks) as two separate root folders.

## Audiobookshelf (audiobooks + ebooks on iPhone/iPad)

Web UI at `http://<nas-ip>:13378`. On first visit, create the admin account, then add
two libraries:

- **Audiobooks** library → folder `/books/audiobooks`
- **Books** library → folder `/books/ebooks`

New books that Chaptarr imports show up automatically. On iOS, install the
**Audiobookshelf** app (or **ShelfPlayer**) and use `http://<nas-ip>:13378` as the
server address. For access away from home, use Tailscale (Synology Package Center +
iOS app) rather than forwarding the port on your router.
