# Playing Super3DX+ on a Steam Deck

The Deck runs SteamOS, a normal 64-bit Linux. The game builds for Linux as it
is, so a build made on another machine (with the `Dockerfile`, see
`docs/DOCKER.md`) can simply be copied over and played. Nothing needs to be
installed on the Deck.

**One thing to know about SteamOS:** it updates as a whole image, so anything
installed under `/usr` (SDL2, for instance) is gone again after an OS update.
That is why the two ways below carry the libraries the game needs inside
themselves, and why the AppImage is preferable: it lives in your home folder,
which updates do not touch.

**Copyright:** the AppImage and the folder contain the arcade game's data,
converted from *your own* copy of the game. Keep them to yourself; do not
upload or share them.

## What a build gives you

After `s3dx build /game` (on your PC, in the container) you have, next to the
sources:

- `Super3DXPlus-Export/` (or `-Japan`): the game. `super3dx` (the player),
  `data/` (the converted game), `play.sh` (a launcher) and, if you ran
  `s3dx bundle`, `sdl-libs/` (the SDL2 the Deck may not have).
- `Super3DXPlus-Export.AppImage` (after `s3dx appimage`): the same thing as one
  file. The data is inside it; the saves go to
  `~/.local/share/Super3DXPlus/save`.

The Deck does **not** need your copy of the arcade game (`main` and `data/`) —
that is only for building. The converted data is already inside the folder or
the AppImage.

## Getting it onto the Deck

From the machine where you built it, over the network (enable SSH on the Deck
first, or use its IP in the same way):

```sh
# the AppImage (one file)
rsync -av --progress Super3DXPlus-Export.AppImage deck@<deck-ip>:~/Applications/

# or the folder
rsync -av --progress Super3DXPlus-Export deck@<deck-ip>:~/Games/
```

Or copy it to a USB stick and move it with the file manager in Desktop Mode.
`~/Applications` and `~/Games` are suggestions; any folder in your home works.
Do not put it in a folder Steam manages, and not on the read-only part of the
system.

## Playing it

### The AppImage

In **Desktop Mode**, make the file executable once, and try it:

```sh
chmod +x ~/Applications/Super3DXPlus-Export.AppImage
~/Applications/Super3DXPlus-Export.AppImage
```

If nothing happens (the Deck may miss the FUSE library AppImages use), run it
extracted instead — it needs no FUSE then:

```sh
~/Applications/Super3DXPlus-Export.AppImage --appimage-extract-and-run
```

Then add it to Steam so it appears in **Game Mode**: in Desktop Mode, Steam →
**Add a Non-Steam Game** → browse to the AppImage. If the game did not start
with a plain double-click, set the launch options: right-click it in Steam →
Properties → Launch Options →
`--appimage-extract-and-run %command%`.

Your saves are in `~/.local/share/Super3DXPlus/save` — a new AppImage (a
rebuilt game) finds them there again.

### The folder

Same idea: copy `Super3DXPlus-Export/` over, then add its `play.sh` to Steam as
a non-Steam game (or just run it in Desktop Mode: `./play.sh`). The saves go
into the folder's own `save/` directory, so copy the new player into the old
folder when you update, and they are kept.

## Screen and controls

- The layout is 4:3. The Deck's screen is wider, so the game opens bigger than
  it: use `play.sh --size 1024x768`, or in Game Mode set `--fullscreen` in the
  launch options (the compositor letterboxes it).
- Everything is controller-first: the Deck's sticks, d-pad, bumpers, triggers
  and haptics work as a normal gamepad, and remapping is in `docs/INPUT.md`
  (`--fullscreen` and window sizes are options of `super3dx`, see the README).
- A Deck is far more powerful than the Raspberry Pi this also runs on; the
  high-quality effects (`MT3DX_HQ`) are on by default and should be fine.

## Rebuilding and updating

When the sources change (a new version of Super3DX+), build again on your PC —
the setup reuses the converted data and only rebuilds the player, so it takes
minutes (`docs/DOCKER.md`). Then:

- AppImage: run `s3dx appimage` and copy the new file over; the saves stay.
- Folder: copy just the new `super3dx` over the old one; the saves stay.

## Building on the Deck itself

Possible, if you would rather not use another machine: install
[distrobox](https://distrobox.it) in your home folder, get a Debian container,
and build inside it (the Deck has enough power; the conversion takes an hour or
more, like anywhere else):

```sh
curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local
distrobox create -n build -i debian:bookworm && distrobox enter build
sudo apt update && sudo apt install -y build-essential pkg-config libsdl2-dev \
    libegl1-mesa-dev libgles2-mesa-dev ffmpeg python3-pip python3-venv \
    fonts-urw-base35 fonts-dejavu-core fonts-noto-cjk
cd ~/src/Super3DXPlus && ./setup.sh
```

The container gives the build the SDL2 and ffmpeg it needs, and the game comes
out in `Super3DXPlus-Export/` in your home folder, ready to play. Your copy of
the game (the dump) still has to be somewhere the container can read, e.g.
mounted in the project folder.
