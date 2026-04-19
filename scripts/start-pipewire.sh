#!/bin/bash
set -e

export XDG_RUNTIME_DIR=/run/pipewire
export PIPEWIRE_RUNTIME_DIR=/run/pipewire
mkdir -p /run/pipewire

# Start PipeWire daemon
/usr/bin/pipewire &
PIPEWIRE_PID=$!

# Wait for PipeWire socket (up to 15 s)
for i in $(seq 1 30); do
    [ -S "/run/pipewire/pipewire-0" ] && break
    sleep 0.5
done

if [ ! -S "/run/pipewire/pipewire-0" ]; then
    echo "ERROR: PipeWire socket not ready after 15 s" >&2
    kill "$PIPEWIRE_PID" 2>/dev/null
    exit 1
fi

# Start WirePlumber session manager
/usr/bin/wireplumber &

# Give WirePlumber a moment to initialise before creating the node
sleep 2

# Create the inferno ALSA sink node in the PipeWire graph.
# object.linger=1 keeps the node alive after pw-cli exits.
/usr/local/bin/create-pipewire-sink.sh

echo "PipeWire + inferno_sink ready"

# Keep service alive; if PipeWire dies the service restarts everything
wait "$PIPEWIRE_PID"
