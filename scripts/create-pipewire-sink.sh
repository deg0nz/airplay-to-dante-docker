#!/bin/bash
# Creates the inferno ALSA sink node in PipeWire.
# object.linger=1 keeps the node alive after this process exits.
# api.alsa.path=inferno references the device defined in /etc/asound.conf
# (avoids inline arg strings which PipeWire may silently truncate).

export XDG_RUNTIME_DIR=/run/pipewire
export PIPEWIRE_RUNTIME_DIR=/run/pipewire

pw-cli create-node adapter '{
  object.linger            = 1
  factory.name             = api.alsa.pcm.sink
  node.name                = inferno_sink
  node.description         = "Inferno Dante Sink"
  media.class              = Audio/Sink
  api.alsa.path            = inferno
  api.alsa.headroom        = 128
  session.suspend-timeout-seconds = 0
  node.pause-on-idle       = false
  node.suspend-on-idle     = false
  node.always-process      = true
}'
