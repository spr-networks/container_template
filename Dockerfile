FROM ubuntu:23.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends nftables iproute2 netcat-traditional iputils-ping net-tools vim-tiny nano ca-certificates curl && rm -rf /var/lib/apt/lists/*
