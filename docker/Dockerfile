FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends     xorriso     squashfs-tools     python3     make     rsync     ca-certificates     && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
