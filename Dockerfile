FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends attr nftables iproute2 netcat-traditional iputils-ping net-tools vim-tiny nano ca-certificates curl && rm -rf /var/lib/apt/lists/*
#RUN find / -type f -exec getfattr -n security.capability {} + 2>/dev/null -exec setfattr -x security.capability {} \; -print || true
RUN setfattr -x security.capability /usr/bin/ping
# Strip unnecessary bloat from the image
# gconv: charset conversion modules, not needed in UTF-8 only environments
# perl: only used by dpkg/debconf scripts, not needed at runtime
RUN rm -rf /usr/lib/*/gconv \
    /usr/lib/*/perl-base \
    /usr/bin/perl \
    /usr/share/doc \
    /usr/share/man \
    /usr/share/locale \
    /usr/share/vim \
    /var/lib/dpkg/info \
    /var/cache/* \
    /var/log/*

#squash layers to lose the extended attr layer
FROM scratch
COPY --from=builder / /
