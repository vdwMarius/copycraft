# Fancraft

An original, mobile-first survival and crafting sandbox (in progress) built with Godot 4.6.3.
It has smooth diggable terrain (Voxel Tools, MIT, native GDExtension), free-form building at
quarter-block precision, painted cel-shaded textures, and texture packs that players can
import themselves.

See **[docs/PLAN.md](docs/PLAN.md)** for the vision, architecture and milestones, and
**[docs/TEXTURE_PACKS.md](docs/TEXTURE_PACKS.md)** for the pack format.

## Install the test build

Download `releases/fancraft-<version>-debug.apk` to the phone and open it. You may need to
allow installs from your browser or file manager. It is ARM64-only and debug-signed. Later
builds install over earlier ones as long as they are signed with the same debug key.

## Controls (touch)

| Where | What |
| --- | --- |
| Left half | Floating joystick. Push to the edge to sprint. |
| DIG tool (first hotbar slot) | Tap raises ground; hold digs. With a material selected, tap places a piece and hold breaks pieces or digs ground. |
| Right half | Drag to look. **Tap** places the selected piece where you tap; **hold** breaks (a ring fills, keep holding to keep breaking). |
| PIECE | Block → Slab → Thin slab → Half cube → Quarter → Pillar → Beam → Panel → Post |
| ROT | Rotates the piece (turned, or laid on its side). |
| SNAP | Quarter / Half / Block: how pieces line up on the surface you touch. |
| PICK | Copies the material under the crosshair. |
| Hotbar / ALL | Picks a material, or opens the full material grid. |
| FLY / DOWN | Creative flight. JUMP rises; DOWN descends. |
| MENU | Quality presets, frame-rate cap (up to 120), view distance, 3D resolution (Auto by default), texture resolution (16–512), 3D surface depth, shadows, anti-aliasing, and the texture pack manager. |

Pieces are placed flush against the surface you touch, so half a block can sit on top of
another half, straddle two cells, or overhang. Breaking removes a piece-sized region.

Desktop: WASD, mouse, Space, Shift, F to fly, Q to descend, LMB to break, RMB to place,
MMB to pick, R/T/G for rotate/piece/snap, Tab for materials, M for the menu, Esc to free
the cursor.

## Build from source (Linux)

```sh
python3 tools/bootstrap.py          # Godot 4.6.3, export templates, debug keystore (outside Git)
tools/godot.sh --headless --import --quit
python3 tools/checks.py             # headless regression suites
tools/build_apk.sh                  # -> build/fancraft-debug.apk
xvfb-run -a tools/godot.sh --rendering-driver opengl3 -- --capture   # screenshots -> build/
```

Install on a USB-connected phone with `adb install -r build/fancraft-debug.apk`.
