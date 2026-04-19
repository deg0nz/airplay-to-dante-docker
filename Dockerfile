# syntax=docker/dockerfile:1

# ─── Stage 1: Builder ────────────────────────────────────────────────────────
FROM debian:trixie AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates build-essential pkg-config git \
    libasound2-dev \
    && rm -rf /var/lib/apt/lists/*

# Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path
ENV PATH="/root/.cargo/bin:${PATH}"

# inferno: alsa_pcm_inferno ALSA plugin (.so only, no daemon)
RUN git clone --recurse-submodules -b dev \
    https://github.com/teodly/inferno /build/inferno
WORKDIR /build/inferno
RUN cargo build --release -p alsa_pcm_inferno

# statime: Dante-compatible PTP daemon (teodly fork, separate repo)
RUN git clone --recurse-submodules -b inferno-dev \
    https://github.com/teodly/statime /build/statime
WORKDIR /build/statime
RUN cargo build --release -p statime-linux

# ─── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd \
    pipewire \
    wireplumber \
    shairport-sync \
    avahi-daemon \
    libasound2 \
    libpipewire-0.3-0 \
    libavahi-client3 \
    dbus \
    gettext-base \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# statime binary
COPY --from=builder /build/statime/target/release/statime-linux /usr/local/bin/statime

# inferno ALSA plugin — installed to architecture-specific alsa-lib dir
COPY --from=builder \
    /build/inferno/target/release/libasound_module_pcm_inferno.so \
    /tmp/libasound_module_pcm_inferno.so
RUN ALSA_DIR=$(find /usr/lib -type d -name "alsa-lib" | head -1) && \
    install -m 644 /tmp/libasound_module_pcm_inferno.so "$ALSA_DIR/" && \
    rm /tmp/libasound_module_pcm_inferno.so

# PipeWire drop-in: allow clock syscalls (needed for PTP clock adjustment)
RUN mkdir -p /etc/systemd/system/pipewire-inferno.service.d
COPY --from=builder \
    /build/inferno/os_integration/systemd_allow_clock.conf \
    /etc/systemd/system/pipewire-inferno.service.d/allow-clock.conf

# systemd units
COPY systemd/statime.service          /etc/systemd/system/
COPY systemd/pipewire-inferno.service /etc/systemd/system/
COPY systemd/shairport-sync.service   /etc/systemd/system/

# config templates (rendered at startup by entrypoint.sh via envsubst)
RUN mkdir -p /etc/inferno-dante
COPY config/inferno-ptpv1.toml.tmpl   /etc/inferno-dante/
COPY config/asound.conf.tmpl          /etc/inferno-dante/
COPY config/avahi-daemon.conf.tmpl    /etc/inferno-dante/
COPY config/shairport-sync.conf.tmpl  /etc/inferno-dante/

# PipeWire helper scripts
COPY scripts/start-pipewire.sh        /usr/local/bin/start-pipewire.sh
COPY scripts/create-pipewire-sink.sh  /usr/local/bin/create-pipewire-sink.sh
RUN chmod +x \
    /usr/local/bin/start-pipewire.sh \
    /usr/local/bin/create-pipewire-sink.sh

# entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# enable services
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /etc/systemd/system/statime.service \
        /etc/systemd/system/multi-user.target.wants/statime.service && \
    ln -sf /etc/systemd/system/pipewire-inferno.service \
        /etc/systemd/system/multi-user.target.wants/pipewire-inferno.service && \
    ln -sf /etc/systemd/system/shairport-sync.service \
        /etc/systemd/system/multi-user.target.wants/shairport-sync.service

# mask unneeded interactive units
RUN ln -sf /dev/null /etc/systemd/system/getty@tty1.service && \
    ln -sf /dev/null /etc/systemd/system/console-getty.service && \
    ln -sf /dev/null /etc/systemd/system/systemd-logind.service && \
    ln -sf /dev/null /etc/systemd/system/systemd-udevd.service && \
    ln -sf /dev/null /etc/systemd/system/systemd-udev-trigger.service && \
    ln -sf /dev/null /etc/systemd/system/systemd-udev-settle.service

# machine-id required by systemd and avahi
RUN systemd-machine-id-setup 2>/dev/null || echo "" > /etc/machine-id

STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/entrypoint.sh"]
