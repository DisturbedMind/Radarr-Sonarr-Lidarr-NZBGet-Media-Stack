![Wolf](assets/wolf.png)

This stack is built like a proper little media command center: clean Docker networking, persistent storage, safe SMB mounts, one tidy reverse proxy, and Arr/NZBGet paths that actually agree with each other. It is deliberately boring in the places that usually break, which is exactly why it should be pleasant to run.

# Arr, NZBGet, Emby Reverse Proxy Stack

This Debian 12 stack runs Radarr, Sonarr, Lidarr, NZBGet, and Caddy. Caddy also reverse proxies two existing Emby servers:

```text
stream.wolf.den -> 192.168.137.118:8096
emby.wolf.den   -> 192.168.137.110:8096
```

HTTPS is intentionally disabled because this is an internal LAN setup.

## Data Safety

Container destruction will not delete your data because:

- App configs live on the Debian host under `/srv/media-stack/config`.
- NZBGet downloads live on the Debian host under `/srv/media-stack/downloads`.
- Final media libraries live on your Windows SMB share, mounted on Debian at `/mnt/cinema`.
- Containers only bind-mount those host paths; no media is stored inside container writable layers.

The installer refuses to start the stack if the Windows share is not mounted. This prevents Radarr/Sonarr/Lidarr from writing into an empty local `/mnt/cinema` folder by mistake.

## Host Layout

Windows SMB source:

```text
\\192.168.137.110\cinema\movies
\\192.168.137.110\cinema\series
\\192.168.137.110\cinema\music
```

Debian mount:

```text
//192.168.137.110/cinema -> /mnt/cinema
```

Container paths:

```text
Radarr: /data/media/movies
Sonarr: /data/media/series
Lidarr: /data/media/music
NZBGet downloads: /data/usenet
```

## Install On Debian 12.11

Copy this folder or the ZIP to the Debian server, then:

```bash
cd arr-media-stack
cp .env.example .env
nano .env
```

Set the Windows share credentials:

```text
SMB_USERNAME=your_windows_user
SMB_PASSWORD=your_windows_password
```

Then install:

```bash
sudo bash install-debian.sh
```

The installer:

- Installs Docker and Compose if needed.
- Handles either `docker compose` or legacy `docker-compose`.
- Installs `cifs-utils` and `curl` if needed.
- Adds an `/etc/fstab` mount for `//192.168.137.110/cinema`.
- Refuses to start containers unless the SMB mount is live.
- Starts the stack and bootstraps NZBGet paths/categories.

## DNS

Point these names to the Debian reverse proxy server IP:

```text
radarr.wolf.den
sonarr.wolf.den
lidarr.wolf.den
nzbget.wolf.den
stream.wolf.den
emby.wolf.den
```

Important: once you proxy `stream.wolf.den` and `emby.wolf.den`, those names should resolve to the Debian Caddy proxy, not directly to the Emby machines. Caddy will forward internally to:

```text
192.168.137.118:8096
192.168.137.110:8096
```

## App Settings

### NZBGet

The bootstrap script sets:

```text
MainDir=/data/usenet
DestDir=${MainDir}/completed
InterDir=${MainDir}/intermediate
NzbDir=${MainDir}/nzb
QueueDir=${MainDir}/queue
TempDir=${MainDir}/tmp
Category radarr -> /data/usenet/completed/radarr
Category sonarr -> /data/usenet/completed/sonarr
Category lidarr -> /data/usenet/completed/lidarr
```

Add your Usenet server details inside NZBGet after the stack is running.

### Radarr

Root folder:

```text
/data/media/movies
```

Download client:

```text
Type: NZBGet
Host: nzbget
Port: 6789
Use SSL: No
URL Base: blank
Username: NZBGET_USER from .env
Password: NZBGET_PASS from .env
Category: radarr
```

### Sonarr

Root folder:

```text
/data/media/series
```

Download client:

```text
Type: NZBGet
Host: nzbget
Port: 6789
Use SSL: No
URL Base: blank
Username: NZBGET_USER from .env
Password: NZBGET_PASS from .env
Category: sonarr
```

### Lidarr

Root folder:

```text
/data/media/music
```

Download client:

```text
Type: NZBGet
Host: nzbget
Port: 6789
Use SSL: No
URL Base: blank
Username: NZBGET_USER from .env
Password: NZBGET_PASS from .env
Category: lidarr
```

## Operations

```bash
cd /opt/arr-media-stack
scripts/arrctl.sh status
scripts/arrctl.sh logs
scripts/arrctl.sh pull
scripts/arrctl.sh restart
scripts/validate-stack.sh
```

## The Path Rule

Do not add Arr remote path mappings for this stack.

Radarr/Sonarr/Lidarr and NZBGet all agree on:

```text
/data/usenet
```

The final libraries are mounted directly at:

```text
/data/media/movies
/data/media/series
/data/media/music
```
