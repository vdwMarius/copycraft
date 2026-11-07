# Texture packs

Fancraft builds all block textures into two `Texture2DArray`s at runtime, so a pack
can use any square resolution from 16 px up to 2048 px and every block face tiles
seamlessly. The built-in **Fancraft Default** pack is generated on your GPU at the
resolution you choose in Settings (16–512 px), so it adds nothing to the APK size.
Its style is crisp and hand-painted: bevelled shapes, deep crevices and painted light
from the top-left of each tile. Fine grain scales with resolution, so 256 and 512 px
show more detail rather than just upscaled noise. Pack authors who want a matching
look should use strong, shape-driven height maps, because the block shader's parallax
and cavity shading are driven by height.

## Installing a pack

1. Settings → Texture packs → **Import .zip…** and pick the zip in the phone's file picker.
2. The pack is copied into the game's private storage and activated.
3. Switch between packs with **Use**; remove imported packs with **Delete**.

Desktop / adb alternative: copy an unzipped pack folder to `<user data>/packs/<id>/`
(on Android: `/data/data/<package>/files/packs/`, reachable with `adb shell run-as`).

The **Texture resolution** setting resamples every pack (nearest-neighbour upscaling
for pixel-art packs, Lanczos otherwise). Set it to *Native* (0) to use the pack's own size.

## Layout

```
my_pack.zip
└── my_pack/                 (optional single top-level folder)
    ├── pack.json
    └── textures/
        ├── stone.png        albedo (RGB colour, alpha = opacity)
        ├── stone_h.png      optional height map (greyscale, white = high)
        ├── stone_n.png      optional normal map (OpenGL / +Y up convention)
        └── stone_r.png      optional roughness (greyscale, white = rough)
```

`pack.json`:

```json
{
  "name": "My Pack",
  "description": "Shown in the pack list",
  "author": "you",
  "resolution": 128,
  "pixel_art": false
}
```

Only `name` is required. `pixel_art: true` keeps texels crisp (nearest filtering).

## Texture names

`grass_top grass_side dirt stone cobblestone sand log_top log_side planks leaves glass
water bricks snow gravel crystal mossy_stone marble terracotta slate`

* `grass_side`: image top = top of the block (grass fringe goes at the top).
* `leaves`: alpha below 0.5 is cut out (holes). `glass`, `water`, `crystal` use alpha
  for translucency.

## What happens to missing files

| Missing | Fallback |
| --- | --- |
| `<name>.png` | the whole layer (colour + surface) comes from the built-in pack |
| `<name>_h.png` | height derived from colour brightness (softened) |
| `<name>_n.png` | normal map computed from the height (Sobel filter) |
| `<name>_r.png` | the built-in material's roughness |

Height maps drive the parallax ("3D depth") effect, so supplying good `_h.png` files is
the single biggest visual upgrade a pack can make: keep mortar, cracks and gaps dark,
raised surfaces bright.

## Limits

* Zip ≤ 64 MB unpacked, each image ≤ 2048 × 2048 px, PNG only.
* Files outside `textures/`, unknown names and unsafe paths (`..`, absolute) are ignored
  or rejected.
* Non-square images are cropped to a square from the top-left.

## Making a test pack

`python3 tools/make_example_pack.py` writes `build/example_pack.zip`
(a checker stone with a height map and pink planks). See `packs_example/README.md`.
