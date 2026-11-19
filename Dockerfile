# syntax=docker/dockerfile:1
#
# Super3DX+ - a Linux build image (what setup.sh does, in a container).
#
# docs/BUILDING.md says, by hand, on Linux:
#
#     sudo apt install build-essential libsdl2-dev libegl1-mesa-dev \
#          libgles2-mesa-dev ffmpeg python3-pip python3-venv
#     pip install -r tools/requirements.txt
#     python3 build.py all /path/to/your/game/folder
#
# This image installs exactly that, so the build needs nothing from the host but
# Docker and your own copy of the arcade game (a folder with 'main' and 'data/').
#
#   docker build -t super3dxplus .
#   docker run --rm -it -v "$PWD":/src -v "/path/to/dump":/game:ro \
#              super3dxplus build /game
#
# See docs/DOCKER.md for the whole story.

# -----------------------------------------------------------------------------
# base: the libraries the player needs to run (SDL2, OpenGL/EGL/GLES2 and Mesa's
# software renderer, so it also runs without a GPU) and Xvfb, for a headless box.
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim AS base

ARG DEBIAN_FRONTEND=noninteractive
ENV S3DX_SRC=/src \
    S3DX_GAME=/game \
    S3DX_OUT=/out \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        libsdl2-2.0-0 \
        libgl1 \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        libglx-mesa0 \
        libx11-6 \
        libxext6 \
        libxrandr2 \
        libxcursor1 \
        libxi6 \
        libxrender1 \
        xvfb \
        x11-utils \
    && rm -rf /var/lib/apt/lists/*

# The container's own entry point: setup.sh without the questions.
COPY docker/entrypoint.sh /usr/local/bin/s3dx
RUN chmod 0755 /usr/local/bin/s3dx

# -----------------------------------------------------------------------------
# runtime: a small image to play the finished game: the packaged folder (the
# player, its data/ and play.sh) mounted in at /game.
#
#   docker build --target runtime -t super3dxplus-runtime .
#   docker run --rm -it -v "/path/to/package":/game super3dxplus-runtime
# -----------------------------------------------------------------------------
FROM base AS runtime

ENTRYPOINT ["/usr/local/bin/s3dx"]
CMD ["run"]

# -----------------------------------------------------------------------------
# build: the full toolchain, so the game can be built here. This is the last
# stage on purpose: a plain `docker build` gives you this one.
# -----------------------------------------------------------------------------
FROM base AS build

ARG DEBIAN_FRONTEND=noninteractive
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/opt/venv/bin:$PATH

# The packages setup.sh asks you to install (docs/BUILDING.md), plus pkg-config
# (the build finds SDL2 through it), binutils (c++filt, the C++ demangler) and
# the fonts the converters draw the menu pictures with.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        binutils \
        pkg-config \
        squashfs-tools \
        file \
        libsdl2-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
        ffmpeg \
        python3 \
        python3-pip \
        python3-venv \
        fonts-dejavu-core \
        fonts-urw-base35 \
        fonts-noto-cjk \
        ca-certificates \
        curl \
        git \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# appimagetool, for `s3dx appimage`: the one self-contained file to move the
# game to another machine (a Steam Deck, for instance).
RUN mkdir -p /opt/appimage \
    && curl -fsSL -o /opt/appimage/appimagetool-x86_64.AppImage \
        https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
    && chmod 0755 /opt/appimage/appimagetool-x86_64.AppImage

# The Python packages the converters need (capstone, unicorn, pillow, numpy).
RUN python3 -m venv /opt/venv
COPY tools/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# The project itself (the build context; .dockerignore keeps the game's data
# and the toolchain out of the image).
WORKDIR /src
COPY . /src

# A normal user (uid/gid configurable), so the container can also be run with
# `--user "$UID:$GID"` or podman's `--userns=keep-id`. The default run is root:
# under rootless podman that maps to your own user, which is what makes the
# mounted folders writable.
ARG USER_UID=1000
ARG USER_GID=1000
RUN (groupadd --gid ${USER_GID} s3dx 2>/dev/null || true) \
    && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash s3dx

# Fail the image build if a dependency is missing: 'doctor' lists what the build
# needs, so an image that cannot build the game is never handed out.
RUN set -eu; \
    python3 build.py doctor | tee /tmp/doctor.txt; \
    for need in "python module capstone" "python module unicorn" "python module PIL" \
                "python module numpy" "C++ demangler" "ffmpeg" "gcc / clang" \
                "SDL2 (Linux dev files)"; do \
      if grep -F "$need" /tmp/doctor.txt | grep -q "MISSING"; then \
        echo "MISSING: $need" >&2; exit 1; \
      fi; \
    done; \
    echo "every build dependency is present"

ENTRYPOINT ["/usr/local/bin/s3dx"]
CMD ["help"]
