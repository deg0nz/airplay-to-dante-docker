#!/bin/bash
set -e

# ── Defaults ──────────────────────────────────────────────────────────────────
AIRPLAY_NAME="${AIRPLAY_NAME:-Dante Bridge}"
DANTE_DEVICE_NAME="${DANTE_DEVICE_NAME:-inferno}"
DANTE_INTERFACE="${DANTE_INTERFACE:-eth0}"
AIRPLAY_INTERFACE="${AIRPLAY_INTERFACE:-eth1}"
DANTE_BIND_IP="${DANTE_BIND_IP:-}"
DANTE_SAMPLE_RATE="${DANTE_SAMPLE_RATE:-44100}"
DANTE_TX_CHANNELS="${DANTE_TX_CHANNELS:-2}"
DANTE_RX_CHANNELS="${DANTE_RX_CHANNELS:-2}"
INFERNO_LOG_LEVEL="${INFERNO_LOG_LEVEL:-info}"

# ── Auto-detect DANTE_BIND_IP from interface ───────────────────────────────────
if [ -z "${DANTE_BIND_IP}" ]; then
    DANTE_BIND_IP=$(ip -4 addr show "${DANTE_INTERFACE}" \
        | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    echo "Auto-detected DANTE_BIND_IP: ${DANTE_BIND_IP}"
fi

export AIRPLAY_NAME DANTE_DEVICE_NAME DANTE_INTERFACE AIRPLAY_INTERFACE \
       DANTE_BIND_IP DANTE_SAMPLE_RATE DANTE_TX_CHANNELS DANTE_RX_CHANNELS \
       INFERNO_LOG_LEVEL

# ── Write env file for systemd units ─────────────────────────────────────────
# systemd does not inherit the container environment; services read this file
# via EnvironmentFile=/etc/inferno-dante/env.
mkdir -p /etc/inferno-dante
cat > /etc/inferno-dante/env << EOF
AIRPLAY_NAME=${AIRPLAY_NAME}
DANTE_DEVICE_NAME=${DANTE_DEVICE_NAME}
DANTE_INTERFACE=${DANTE_INTERFACE}
AIRPLAY_INTERFACE=${AIRPLAY_INTERFACE}
DANTE_BIND_IP=${DANTE_BIND_IP}
DANTE_SAMPLE_RATE=${DANTE_SAMPLE_RATE}
DANTE_TX_CHANNELS=${DANTE_TX_CHANNELS}
DANTE_RX_CHANNELS=${DANTE_RX_CHANNELS}
INFERNO_LOG_LEVEL=${INFERNO_LOG_LEVEL}
EOF

# ── Render config templates ────────────────────────────────────────────────────
mkdir -p /etc/inferno-dante /etc/avahi

envsubst < /etc/inferno-dante/inferno-ptpv1.toml.tmpl  > /etc/inferno-dante/inferno-ptpv1.toml
envsubst < /etc/inferno-dante/shairport-sync.conf.tmpl > /etc/inferno-dante/shairport-sync.conf
envsubst < /etc/inferno-dante/asound.conf.tmpl         > /etc/asound.conf
envsubst < /etc/inferno-dante/avahi-daemon.conf.tmpl   > /etc/avahi/avahi-daemon.conf

# ── machine-id (required by systemd and avahi) ────────────────────────────────
if [ ! -s /etc/machine-id ]; then
    systemd-machine-id-setup
fi

# ── Hostname (used by avahi for mDNS) ────────────────────────────────────────
echo "${DANTE_DEVICE_NAME}" > /etc/hostname
hostname "${DANTE_DEVICE_NAME}"

# ── Hand off to systemd as PID 1 ─────────────────────────────────────────────
exec /sbin/init
