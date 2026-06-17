# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Reproducible build: every input below is pinned (base image by digest, apt by
# Ubuntu snapshot, CA bundle bootstrapped from a pinned image). See reproducible.env.
ARG ALPINE_REF=alpine@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
ARG UBUNTU_REF=ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54
# SOURCE_DATE_EPOCH is auto-propagated by buildx; declared here so BuildKit clamps
# layer/file timestamps for reproducible output.
ARG SOURCE_DATE_EPOCH

# Bootstrap CA bundle donor: the minimal ubuntu image ships no certs, so we copy a
# trusted bundle from a pinned image to enable the first HTTPS handshake to the
# snapshot archive. apt still verifies every package by GPG signature.
FROM ${ALPINE_REF} AS cacerts

FROM ${UBUNTU_REF} AS builder
ENV DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_SNAPSHOT=20260601T000000Z
COPY --from=cacerts /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
# Pin apt to the Ubuntu snapshot archive. The snapshot host serves every arch and
# every pocket (noble/updates/security) under one path, so a single stanza freezes
# all package versions. GPG signatures are still verified against the archive keyring.
RUN set -eux; \
    printf 'Types: deb\nURIs: https://snapshot.ubuntu.com/ubuntu/%s\nSuites: noble noble-updates noble-security\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' "${UBUNTU_SNAPSHOT}" > /etc/apt/sources.list.d/ubuntu.sources; \
    printf 'APT::Install-Recommends "false";\nAcquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99reproducible
RUN apt-get update && apt-get install -y --no-install-recommends attr nftables iproute2 netcat-traditional iputils-ping net-tools vim-tiny nano ca-certificates curl && rm -rf /var/lib/apt/lists/*
#RUN find / -type f -exec getfattr -n security.capability {} + 2>/dev/null -exec setfattr -x security.capability {} \; -print || true
RUN setfattr -x security.capability /usr/bin/ping

#squash layers to lose the extended attr layer.
# The snapshot apt config copied below is inherited by every service image that
# builds FROM container_template, so their apt installs are pinned too.
FROM scratch
COPY --from=builder / /
