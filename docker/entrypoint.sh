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
