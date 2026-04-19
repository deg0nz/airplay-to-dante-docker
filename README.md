# inferno-dante

A Docker container that bridges AirPlay audio into a Dante network.

```
AirPlay (iPhone/Mac) → shairport-sync → PipeWire → inferno ALSA PCM → Dante network
```

PTP synchronisation:
```
Dante grandmaster → statime (PTPv1 slave) → inferno (via usrvclock)
```

## Network architecture

The container uses **two macvlan interfaces** to cleanly separate Dante and AirPlay traffic:

| Interface | Network | Services |
|-----------|---------|----------|
| `eth0` | Dante VLAN | inferno, statime, PTP multicast |
| `eth1` | Client VLAN | shairport-sync, Avahi/mDNS |

This avoids NAT (which breaks PTP multicast and Dante discovery) and keeps the AirPlay receiver invisible to Dante devices.

## Components

| Component | Source | Role |
|-----------|--------|------|
| [inferno](https://github.com/teodly/inferno/tree/dev) | built from source | ALSA PCM plugin that transmits audio over Dante |
| [statime](https://github.com/teodly/statime/tree/inferno-dev) | built from source | PTPv1 slave daemon for clock sync |
| [shairport-sync](https://packages.debian.org/trixie/shairport-sync) | Debian package | AirPlay receiver |
| PipeWire + WirePlumber | Debian package | Audio session management |

## Requirements

- Docker with macvlan support (Linux host or TrueNAS Scale)
- Two host network interfaces (or VLAN subinterfaces, e.g. `eth0.10`, `eth0.1`)
- A Dante grandmaster on the Dante VLAN

**TrueNAS Scale:** VLAN interfaces must be created in the TrueNAS network UI before they can be used as macvlan parents.

## Quick start

```bash
cp .env.example .env
# Edit .env with your IPs and host interface names
docker compose build
docker compose up -d
```

## Configuration

All configuration is via environment variables. Copy `.env.example` to `.env` and adjust.

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `DANTE_IP` | — | Container IP on the Dante VLAN (required) |
| `DANTE_HOST_INTERFACE` | `eth0` | Host interface for Dante VLAN macvlan |
| `DANTE_SUBNET` | `10.1.1.0/24` | Dante VLAN subnet |
| `DANTE_GATEWAY` | `10.1.1.1` | Dante VLAN gateway |
| `AIRPLAY_IP` | — | Container IP on the client VLAN (required) |
| `AIRPLAY_HOST_INTERFACE` | `eth1` | Host interface for client VLAN macvlan |
| `AIRPLAY_SUBNET` | `192.168.1.0/24` | Client VLAN subnet |
| `AIRPLAY_GATEWAY` | `192.168.1.1` | Client VLAN gateway |

### Audio / identity

| Variable | Default | Description |
|----------|---------|-------------|
| `AIRPLAY_NAME` | `Dante Bridge` | Name shown in AirPlay device picker |
| `DANTE_DEVICE_NAME` | `inferno` | Dante device name (visible in Dante Controller) |
| `DANTE_SAMPLE_RATE` | `44100` | Sample rate for inferno ALSA PCM |
| `DANTE_TX_CHANNELS` | `2` | Dante transmitter channels |
| `DANTE_RX_CHANNELS` | `2` | Dante receiver channels |

### Other

| Variable | Default | Description |
|----------|---------|-------------|
| `DANTE_INTERFACE` | `eth0` | Interface inside the container bound to the Dante VLAN |
| `AIRPLAY_INTERFACE` | `eth1` | Interface inside the container bound to the client VLAN |
| `DANTE_BIND_IP` | auto | IP inferno binds to; auto-detected from `DANTE_INTERFACE` if empty |
| `INFERNO_LOG_LEVEL` | `info` | statime log level (`trace`/`debug`/`info`/`warn`/`error`) |

## Service startup order

```
dbus → avahi-daemon → statime → pipewire-inferno → shairport-sync
```

`pipewire-inferno` starts PipeWire, then WirePlumber, then creates the inferno ALSA sink node via `pw-cli`. The PipeWire node (`inferno_sink`) persists after node creation thanks to `object.linger=1`.

## Building for x86_64 on Apple Silicon

```bash
docker buildx build --platform linux/amd64 -t inferno-dante:latest .
```

The Rust builder stage runs under QEMU emulation — expect 15–30 min on first build.

## Dante state persistence

The inferno Dante device ID is stored in `/root/.local/state/inferno_aoip` and mounted as a Docker volume. Without persistence the device gets a new ID on every restart, which clears all routing in Dante Controller.

## Troubleshooting

**AirPlay device not visible on iPhone**
- Check that `avahi-daemon` is running and bound to `eth1` (client VLAN).
- Verify mDNS traffic is not blocked between the client VLAN and your iPhone.

**No audio in Dante Controller**
- Check `statime` logs: `docker exec inferno-dante journalctl -u statime -f`
- Verify PTP multicast is reachable on the Dante VLAN.
- Confirm `DANTE_BIND_IP` resolved correctly in container logs at startup.

**PipeWire sink not found by shairport-sync**
- Check `pipewire-inferno` logs: `docker exec inferno-dante journalctl -u pipewire-inferno -f`
- The PipeWire node name must be `inferno_sink` — verify with `pw-cli list-objects` inside the container.

**Sample rate mismatch**
- AirPlay sends 44100 Hz; inferno is configured at 44100 Hz and handles resampling internally for the Dante network (typically 48000 Hz).
