FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends attr nftables iproute2 netcat-traditional iputils-ping net-tools vim-tiny nano ca-certificates curl && rm -rf /var/lib/apt/lists/*
#RUN find / -type f -exec getfattr -n security.capability {} + 2>/dev/null -exec setfattr -x security.capability {} \; -print || true
RUN setfattr -x security.capability /usr/bin/ping

#squash layers to lose the extended attr layer
FROM scratch
COPY --from=builder / /
