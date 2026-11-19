#!/bin/sh
# Super3DX+ inside a container: the steps of setup.sh, without the questions.
#
#   s3dx doctor              what is installed, what is missing
#   s3dx build [/game]       the whole build: data, the player, the package
#   s3dx data [/game]        convert your copy of the game into data/
#   s3dx gensrc [/game]      only the generated sources (the tables, the physics)
#   s3dx refresh [/game]     the quick update: the sources and the player
#   s3dx exe                 compile the player
#   s3dx package             make build/linux/package/
#   s3dx bundle [folder]     copy SDL2 next to the game, so it runs on a
#                            machine without it (a Steam Deck)
#   s3dx appimage [folder]   the same game as one self-contained .AppImage
#   s3dx run [args]          play the game (the packaged folder, or $S3DX_GAME)
#   s3dx shell               a shell in the container
#
# The environment:
#   S3DX_SRC    the project folder            (default /src)
#   S3DX_GAME   your copy of the arcade game  (default /game)
#   S3DX_OUT    where the finished package goes (default /out, optional)

set -eu

SRC="${S3DX_SRC:-/src}"
GAME="${S3DX_GAME:-/game}"
OUT="${S3DX_OUT:-/out}"

say() { printf '%s\n' "$*"; }

usage() {
    cat <<'USAGE'
Super3DX+ inside a container: the steps of setup.sh, without the questions.

  s3dx doctor              what is installed, what is missing
  s3dx build [/game]       the whole build: data, the player, the package
  s3dx data [/game]        convert your copy of the game into data/
  s3dx gensrc [/game]      only the generated sources (the tables, the physics)
  s3dx refresh [/game]     the quick update: the sources and the player
  s3dx exe                 compile the player
  s3dx package             make build/linux/package/
  s3dx bundle [folder]     copy SDL2 next to the game, for a Steam Deck
  s3dx appimage [folder]   the same game as one self-contained .AppImage
  s3dx run [args]          play the game (the packaged folder, or $S3DX_GAME)
  s3dx shell               a shell in the container

The environment:
  S3DX_SRC    the project folder            (default /src)
  S3DX_GAME   your copy of the arcade game  (default /game)
  S3DX_OUT    where the finished package goes (default /out, optional)

Anything else is run as it is: s3dx python3 tools/pipeline.py steps
USAGE
}

need_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        say "This image has no Python: it can only play the game (s3dx run)."
        exit 1
    fi
}

check_dump() {
    d="$1"
    if [ ! -f "$d/main" ] || [ ! -d "$d/data" ]; then
        say "That folder is not an arcade dump: it needs a 'main' file and a 'data' folder."
        say "  got: $d"
        say "Mount your own copy of the game, e.g. -v '/path/to/dump':/game:ro"
        exit 1
    fi
}

copy_out() {
    [ -n "$OUT" ] && [ -d "$OUT" ] && [ -w "$OUT" ] || return 0
    dir="$1"
    [ -d "$dir" ] || return 0
    say "copying the game to $OUT ..."
    rm -rf "$OUT/$(basename "$dir")"
    cp -a "$dir" "$OUT/$(basename "$dir")"
    say "game: $OUT/$(basename "$dir") (play it with ./play.sh)"
}

# The finished game goes next to the sources, in Super3DXPlus-<region>, the way
# setup.sh leaves it (the region comes from the game's own `main`).
finish() {
    dump="$1"
    pk="$SRC/build/linux/package"
    [ -d "$pk" ] || return 0
    region=$(cd "$SRC" && python3 - "$dump" <<'PY'
import hashlib, os, sys
sys.path.insert(0, ".")
import build
md5 = hashlib.md5(open(os.path.join(sys.argv[1], "main"), "rb").read()).hexdigest()
print(build.KNOWN.get(md5, "Custom"))
PY
) || region=""
    [ -n "$region" ] || region="Custom"
    dest="$SRC/Super3DXPlus-$region"
    say "putting the game in $dest"
    if [ -d "$dest" ]; then
        rm -rf "$dest.old"
        if [ -d "$dest/save" ]; then
            cp -a "$dest/save" "$pk/save"
        fi
        mv "$dest" "$dest.old"
    fi
    mv "$pk" "$dest"
    rm -rf "$dest.old"
    say "Your game is in $dest: run play.sh in it. Your saves are kept in its save folder."
    copy_out "$dest"
}

# Copy the player's SDL2 next to the game and point play.sh at it, so the
# package runs on a machine with no SDL2 installed (a Steam Deck, for instance:
# its SDL2 would have to be installed again after every OS update).
bundle() {
    dir="${1:-}"
    [ -n "$dir" ] || dir=$(find_game_dir || true)
    [ -n "$dir" ] || dir="$SRC/build/linux/package"
    [ -f "$dir/play.sh" ] || {
        say "No game to bundle at $dir (build it first: s3dx build)"
        exit 1
    }
    say "bundling SDL2 into $dir ..."
    mkdir -p "$dir/sdl-libs"
    sdl_lib=/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0
    [ -f "$sdl_lib" ] || sdl_lib=$(ls /usr/lib/libSDL2-2.0.so.0 2>/dev/null || true)
    [ -n "$sdl_lib" ] || {
        say "no SDL2 in this image (it is in the 'build' image, or install libsdl2-2.0-0)"
        exit 1
    }
    cp -a /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0* "$dir/sdl-libs/" 2>/dev/null || cp -a /usr/lib/libSDL2-2.0.so.0* "$dir/sdl-libs/"
    # ...and everything SDL2 needs, except the C library and Mesa's GL stack
    # (libdrm/libgbm must match the system's own video drivers), and libpulse
    # (it carries a hard-coded path; it is on every desktop Linux anyway).
    for lib in $(ldd "$sdl_lib" | awk '/=> \//{print $3}'); do
        case "$lib" in
            */libc.so*|*/libm.so*|*/libpthread.so*|*/libdl.so*|*/librt.so*|*/ld-linux*|*/libdrm*|*/libgbm*|*/libpulse*) continue ;;
        esac
        cp -aL "$lib" "$dir/sdl-libs/" 2>/dev/null || true
    done
    if ! grep -q "sdl-libs" "$dir/play.sh"; then
        sed -i '/^cd "/a export LD_LIBRARY_PATH="$PWD/sdl-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' "$dir/play.sh"
    fi
    say "done: $dir now carries its SDL2 (play it with ./play.sh)"
}

# The one self-contained file: AppImage. The game's data goes inside (it is the
# arcade's, so the file is for personal use, not for sharing); the saves go to
# ~/.local/share/Super3DXPlus, so an updated AppImage keeps them.
find_game_dir() {
    dir=""
    for d in "$SRC"/Super3DXPlus-*/; do
        case "$d" in *.old*/|*.old/) continue ;; esac
        [ -d "$d" ] && [ -f "$d/play.sh" ] && { dir="${d%/}"; break; }
    done
    [ -n "$dir" ] || dir="$SRC/build/linux/package"
    [ -f "$dir/play.sh" ] || return 1
    printf '%s\n' "$dir"
}

appimage() {
    dir="${1:-}"
    [ -n "$dir" ] || dir=$(find_game_dir || true)
    if [ -z "$dir" ] || [ ! -f "$dir/play.sh" ]; then
        say "No game to pack at $dir (build it first: s3dx build)"
        exit 1
    fi
    tool=/opt/appimage/appimagetool-x86_64.AppImage
    [ -f "$tool" ] || {
        say "appimagetool is not in this image (it is in the 'build' image)"
        exit 1
    }
    free=$(df -k --output=avail "$SRC" | tail -n1 || true)
    [ -n "$free" ] && [ "$free" -gt 8000000 ] || say "WARNING: the drive looks full; packing the data into the AppImage needs a few more GB."
    say "packing $dir into an AppImage (the data is copied in; a few minutes) ..."
    appdir="$SRC/build/linux/appimage/AppDir"
    rm -rf "$SRC/build/linux/appimage"
    mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"
    cp "$dir/super3dx" "$appdir/usr/bin/super3dx"
    cp -a "$dir/data" "$appdir/usr/data"
    if [ ! -d "$dir/sdl-libs" ]; then
        bundle "$dir"
    fi
    cp -a "$dir/sdl-libs" "$appdir/usr/sdl-libs"

    cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$here/usr/sdl-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
save="${XDG_DATA_HOME:-$HOME/.local/share}/Super3DXPlus"
mkdir -p "$save/save"
exec "$here/usr/bin/super3dx" "$here/usr/data" --save "$save/save" "$@"
RUN
    chmod 0755 "$appdir/AppRun"
    cat > "$appdir/super3dx.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Super3DX+
Comment=An accessibility-focused native port of Wangan Midnight Maximum Tune 3DX+
Exec=super3dx
Icon=super3dx
Categories=Game;
Terminal=false
DESKTOP
    cp "$appdir/super3dx.desktop" "$appdir/usr/share/applications/super3dx.desktop"
    python3 - "$appdir" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont
appdir = sys.argv[1]
s = 256
img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle((8, 8, s - 8, s - 8), radius=48, fill=(24, 28, 44, 255), outline=(90, 160, 255, 255), width=6)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 74)
except OSError:
    font = ImageFont.load_default()
text = "3DX+"
w = d.textbbox((0, 0), text, font=font)
d.text(((s - (w[2] - w[0])) / 2 - w[0], (s - (w[3] - w[1])) / 2 - w[1] - 10), text, font=font, fill=(235, 240, 250, 255))
img.save(appdir + "/usr/share/icons/hicolor/256x256/apps/super3dx.png")
PY
    icon="$appdir/usr/share/icons/hicolor/256x256/apps/super3dx.png"
    [ -f "$icon" ] || {
        say "the icon could not be made (appimagetool needs it)"
        exit 1
    }
    cp "$icon" "$appdir/super3dx.png"
    cp "$icon" "$appdir/.DirIcon"
    out="$SRC/$(basename "$dir").AppImage"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out"
    rm -rf "$SRC/build/linux/appimage"
    say "AppImage: $out (move this one file to another machine; the saves live in ~/.local/share/Super3DXPlus)"
    if [ -n "$OUT" ] && [ -d "$OUT" ] && [ -w "$OUT" ]; then
        cp -a "$out" "$OUT/"
        say "copied to $OUT/"
    fi
}

run_game() {
    dir="$SRC/build/linux/package"
    if [ ! -x "$dir/super3dx" ] && [ -x "$GAME/super3dx" ]; then
        dir="$GAME"
    fi
    if [ ! -x "$dir/super3dx" ]; then
        say "No game found. Build it first (s3dx build), or mount the packaged folder at $GAME."
        exit 1
    fi
    cd "$dir"
    mkdir -p save
    if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
        exec xvfb-run -a ./super3dx data --save save "$@"
    fi
    exec ./super3dx data --save save "$@"
}

cmd="${1:-help}"
orig="$cmd"
if [ $# -gt 0 ]; then shift; fi

case "$cmd" in
    doctor)
        need_python
        cd "$SRC" && exec python3 build.py doctor
        ;;
    build)
        need_python
        dump="${1:-$GAME}"
        check_dump "$dump"
        cd "$SRC"
        python3 build.py all "$dump" --target linux
        finish "$dump"
        ;;
    data)
        need_python
        dump="${1:-$GAME}"
        check_dump "$dump"
        cd "$SRC" && exec python3 build.py data "$dump" --target linux
        ;;
    gensrc)
        need_python
        dump="${1:-$GAME}"
        check_dump "$dump"
        cd "$SRC" && exec python3 build.py gensrc "$dump"
        ;;
    refresh)
        need_python
        dump="${1:-$GAME}"
        check_dump "$dump"
        cd "$SRC" && exec python3 build.py refresh "$dump" --target linux
        ;;
    exe)
        need_python
        cd "$SRC" && exec python3 build.py exe --target linux
        ;;
    package)
        need_python
        cd "$SRC" && exec python3 build.py package --target linux
        ;;
    bundle)
        bundle "${1:-}"
        ;;
    appimage)
        appimage "${1:-}"
        ;;
    run)
        run_game "$@"
        ;;
    shell)
        exec /bin/bash
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        exec "$orig" "$@"
        ;;
esac
