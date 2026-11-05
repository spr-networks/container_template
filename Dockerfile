# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Reproducible build: every input below is pinned (base image by digest, apt by
# Ubuntu snapshot, CA bundle bootstrapped from a pinned image). See reproducible.env.
ARG ALPINE_REF=alpine@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
ARG UBUNTU_REF=ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
# SOURCE_DATE_EPOCH is auto-propagated by buildx; declared here so BuildKit clamps
# layer/file timestamps for reproducible output.
ARG SOURCE_DATE_EPOCH

# Bootstrap CA bundle donor: the minimal ubuntu image ships no certs, so we copy a
# trusted bundle from a pinned image to enable the first HTTPS handshake to the
# snapshot archive. apt still verifies every package by GPG signature.
FROM ${ALPINE_REF} AS cacerts

FROM ${UBUNTU_REF} AS builder
ENV DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_SNAPSHOT=20261105T120000Z
COPY --from=cacerts /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
# Pin apt to the Ubuntu snapshot archive. The snapshot host serves every arch and
# every pocket (noble/updates/security) under one path, so a single stanza freezes
# all package versions. GPG signatures are still verified against the archive keyring.
RUN set -eux; \
    printf 'Types: deb\nURIs: https://snapshot.ubuntu.com/ubuntu/%s\nSuites: noble noble-updates noble-security\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' "${UBUNTU_SNAPSHOT}" > /etc/apt/sources.list.d/ubuntu.sources; \
    printf 'APT::Install-Recommends "false";\nAcquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99reproducible
# CVE-2026-109518: disable retries before updating APT itself.
RUN printf 'Acquire::Retries "0";\n' > /etc/apt/apt.conf.d/99spr-apt-security \
    && apt-get -o Acquire::Retries=0 update \
    && apt-get -o Acquire::Retries=0 install -y --only-upgrade apt '?and(?installed,?source-package(^apt$))' \
    && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' apt)" ge 2.8.4ubuntu0.1 \
    && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' libapt-pkg6.0t64)" ge 2.8.4ubuntu0.1 \
    && apt-get -o Acquire::Retries=0 install -y --no-install-recommends attr nftables iproute2 netcat-traditional iputils-ping net-tools vim-tiny nano ca-certificates curl && rm -rf /var/lib/apt/lists/*
#RUN find / -type f -exec getfattr -n security.capability {} + 2>/dev/null -exec setfattr -x security.capability {} \; -print || true
RUN setfattr -x security.capability /usr/bin/ping

#squash layers to lose the extended attr layer.
# The snapshot apt config copied below is inherited by every service image that
# builds FROM container_template, so their apt installs are pinned too.
# The retry mitigation is also inherited, including by third-party install scripts.
FROM scratch
COPY --from=builder / /
