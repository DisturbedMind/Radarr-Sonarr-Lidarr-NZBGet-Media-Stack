# Paths And Download Clients

Use these exact values unless you intentionally change the stack layout.

## Never Use Localhost Between Containers

Inside Radarr, Sonarr, or Lidarr:

```text
NZBGet host: nzbget
NZBGet port: 6789
```

Do not use:

```text
localhost
127.0.0.1
the Debian server LAN IP
```

The apps are on the same Docker network, so the service name `nzbget` is the stable address.

## Do Not Add Remote Path Mappings

Remote path mappings are for mismatched paths. This stack deliberately avoids that.

All Arr apps and NZBGet see downloads as:

```text
/data/usenet
```

NZBGet reports completed downloads such as:

```text
/data/usenet/completed/radarr/Movie.Name
/data/usenet/completed/sonarr/Show.Name
/data/usenet/completed/lidarr/Artist.Name
```

The Arr apps can read those paths directly and import into:

```text
/data/media/movies
/data/media/series
/data/media/music
```

Those final media paths are bind mounts from the Debian SMB mount:

```text
//192.168.137.110/cinema -> /mnt/cinema
/mnt/cinema/movies -> /data/media/movies
/mnt/cinema/series -> /data/media/series
/mnt/cinema/music  -> /data/media/music
```

## Categories

Use lowercase category names:

```text
Radarr: radarr
Sonarr: sonarr
Lidarr: lidarr
```

These match the NZBGet folders created by `scripts/bootstrap-nzbget-paths.sh`.

## Reverse Proxy Names

The internal HTTP names are:

```text
radarr.wolf.den
sonarr.wolf.den
lidarr.wolf.den
nzbget.wolf.den
stream.wolf.den
emby.wolf.den
```

Point all six names to the Debian proxy server IP. Caddy proxies the Emby names to:

```text
stream.wolf.den -> 192.168.137.118:8096
emby.wolf.den   -> 192.168.137.110:8096
```
