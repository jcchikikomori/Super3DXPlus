# Building in Docker (Linux)

`setup.sh` needs a Linux box with a compiler, SDL2 and ffmpeg, and it asks you
questions while it works. If that is not what you have (or you do not want to
install those packages on your machine), the `Dockerfile` in this repository does
the same thing inside a container: it installs the packages `docs/BUILDING.md`
lists, installs the Python packages the converters need, and runs
`python3 build.py all <your game folder>`.

Nothing of the arcade game is in the image: the container needs *your own* copy
of the game (a folder with `main` and `data/`) mounted into it, read-only.

## The short version

```sh
# 1. the image (once, or again after every git pull)
docker build -t super3dxplus .

# 2. the build: your project folder at /src, your copy of the game at /game
docker run --rm -it \
    -v "$PWD":/src \
    -v "/path/to/your/game/folder":/game:ro \
    super3dxplus build /game
```

The build takes an hour or more (the data conversion is the long part) and needs
about 15 GB of free space. It writes into `/src`, so the converted data, the
generated sources and the finished player end up in your project folder, exactly
as they would with `setup.sh`.

When it is done you have:

```
Super3DXPlus-Export/          the game: super3dx, play.sh, data/, README.txt
build/linux/super3dx          the player on its own
data/                         the converted game data
```

`Super3DXPlus-Japan` or `Super3DXPlus-Export`, depending on which version of
the game you mounted (the region is read from the game's own `main`). This is
the same folder `setup.sh` leaves next to the sources, with your saves in its
`save` folder.

## What to mount

| Mount | Why |
|---|---|
| your project folder at `/src` | so the build writes its results where you can see them (and so an earlier conversion is reused instead of done again) |
| your copy of the game at `/game` (read-only) | the build reads it; it never writes to it |
| a folder at `/out` (optional) | the finished game is copied there when the build finishes |

Mounting the project folder is what makes the build restartable: the converters
skip the files they have already made, so a build that stopped halfway (a failed
ffmpeg step, for instance) continues where it stopped.

## The commands

```sh
docker run --rm -it -v "$PWD":/src -v "/path/to/dump":/game:ro super3dxplus doctor
docker run --rm -it -v "$PWD":/src -v "/path/to/dump":/game:ro super3dxplus build /game
docker run --rm -it -v "$PWD":/src -v "/path/to/dump":/game:ro super3dxplus data /game
docker run --rm -it -v "$PWD":/src -v "/path/to/dump":/game:ro super3dxplus refresh /game
docker run --rm -it -v "$PWD":/src super3dxplus exe
docker run --rm -it -v "$PWD":/src super3dxplus package
docker run --rm -it -v "$PWD":/src super3dxplus run
docker run --rm -it -v "$PWD":/src super3dxplus shell
```

- `doctor` lists what is installed and what is missing (the same list as
  `python3 build.py doctor`).
- `build` does the whole thing: the tables and the recompiled physics, the data
  conversion, the player and the package. It leaves the game in
  `Super3DXPlus-Export` (or `-Japan`) next to the sources.
- `data` only converts your copy of the game into `data/`.
- `refresh` is the quick update after a `git pull`: the generated sources and
  the player, no data conversion.
- `exe` and `package` are the two halves of the player build, on their own.
- `run` plays the game from `build/linux/package/` (it needs a screen; in a
  headless container it uses Xvfb and Mesa's software renderer).
- `shell` gives you a shell in the image, to look around or run the tools by
  hand.

Anything the entry point does not know is run as it is, so
`docker run --rm -it super3dxplus python3 tools/pipeline.py steps` works too.

## Playing the game

The package needs SDL2 and OpenGL on the machine that runs it. On Debian or
Ubuntu:

```sh
sudo apt install libsdl2-2.0-0 libgl1 libegl1 libgles2 libgl1-mesa-dri
Super3DXPlus-Export/play.sh
```

Or use the small runtime image, which has all of that:

```sh
docker build --target runtime -t super3dxplus-runtime .
docker run --rm -it -v "$PWD/Super3DXPlus-Export":/game super3dxplus-runtime
```

With a GPU, pass `--device /dev/dri` and `--group video` to the container.

## Notes

- **Who writes where.** The container runs as root by default. Under Podman
  (rootless) that is mapped to your own user, so the mounted folders are
  writable and the files land in them owned by you. On Docker you can get the
  same with `--user "$(id -u):$(id -g)"` — in that case mount the project
  folder, because the image's own `/src` copy is not writable by that user.
- The image is Debian bookworm (Python 3.11). `python3 build.py all` is the
  non-interactive path: `wizard` (what `setup.sh` starts) asks questions and
  waits for an answer that never comes in a container.
- `build.py` does not read `CC` or `CFLAGS`; the compiler is gcc from
  `build-essential`, and `--cc` changes it.
- The fonts the converters draw a few menu pictures with
  (`fonts-urw-base35`, `fonts-dejavu-core`, `fonts-noto-cjk`) are in the image.
  If you want others, put them in a folder and set `MT3DX_FONT_DIRS`.
- The Raspberry Pi and Android builds are separate (`setup-pi.sh`,
  `setup-android.sh`); this image is for the Linux/PC build.
