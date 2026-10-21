# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Reproducible build: every input below is pinned (base image by digest, apt by
# Ubuntu snapshot, CA bundle bootstrapped from a pinned image). See reproducible.env.
ARG ALPINE_REF=alpine@sha256:c6b073f8e9e58d881f6ffba6ebf3b9ebd60b9e7d6e8337018c0e68bb5c356873
ARG UBUNTU_REF=ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
# SOURCE_DATE_EPOCH is auto-propagated by buildx; declared here so BuildKit clamps
# layer/file timestamps for reproducible output.
ARG SOURCE_DATE_EPOCH

# Bootstrap CA bundle donor: the minimal ubuntu image ships no certs, so we copy a
# trusted bundle from a pinned image to enable the first HTTPS handshake to the
# snapshot archive. apt still verifies every package by GPG signature.
FROM ${ALPINE_REF} AS cacerts

FROM ${UBUNTU_REF} AS builder
ENV DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_SNAPSHOT=20261021T000000Z
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
