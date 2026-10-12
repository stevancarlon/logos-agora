FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 libgl1 libopengl0 libegl1 libxkbcommon0 libxcb-cursor0 libxcb-icccm4 \
    libxcb-keysyms1 libxcb-shape0 libxcb-xinerama0 libxcb-randr0 \
    libxcb-render-util0 libxcb-xfixes0 libxcb-image0 libxcb-sync1 \
    libdbus-1-3 libfontconfig1 libfreetype6 libharfbuzz0b libglib2.0-0 libnss3 \
    libnspr4 libasound2t64 libpulse0 libx11-xcb1 libxcomposite1 \
    libxdamage1 libxrandr2 libxtst6 libdrm2 libgbm1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
USER ubuntu
ENV APPIMAGE_EXTRACT_AND_RUN=1
WORKDIR /tmp
