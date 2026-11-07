# Changelog

## 0.3.0: art direction from the reference images

Target style is `docs/art-reference/03-target-style-scene.jpg`, with the rock and tree sheets as material references.
- **Built-in textures redrawn in a cel-shaded painted style:**
  - flat 2–3 tone bands per shape, warm top-left highlight edges and thin dark line work;
  - lime grass with flower specks, and a hanging grass lip on block sides;
  - chunky sandstone and grey cut-stone bricks, with moss spilling over mossy stone;
  - warm dirt clods, reddish bark plates, turquoise water with white foam, clumped leaves.
- **Cel-shaded block lighting:**
  - soft lit and shade bands, crisp shadows, small toon highlights;
  - a thin rim of light, and sunlight glowing through leaves.
- **New trees:** rounded clump canopies sculpted at quarter-block resolution, in three shapes
  (round broadleaf, tiered conifer, bush).
- **Sky and colour:** brighter, more saturated palette, filmic tonemapping, bluer sky, lighter fog.

## 0.2.0: phone feedback fixes and the stylised look

**Fixed**
- **Building delay / blocks appearing in batches.** Edits waited behind world streaming,
  and stale results were dropped, so several edits appeared at once. Edits now remesh on a
  high-priority worker job and are applied as soon as they finish, in order. Measured in
  the cloud: about 2–3 frames from tap to new geometry.
- **Corrupted chunk meshes.** Godot 4 shares packed arrays by reference, so editing a
  chunk could change data a worker thread was still meshing. Edits now copy before
  writing. A regression test covers this.
- **Settings menu could not be used.** The menu's root control had zero size, so its
  scroll area was 0 px tall. Menus also handle touches directly now (tap to press, drag to scroll).
- **Stuck at 60 fps.**
  - The first-launch preset check used the display's current refresh rate, which phones
    often report as 60 Hz, so it picked the 60 fps preset. It now uses RAM and CPU cores only.
  - Android's Swappy frame pacing is disabled so the Vulkan renderer can follow the
    panel's 120 Hz, and the frame-rate cap is applied by the engine.
- **Slow world loading.** Godot gave background work only about 30% of worker threads.
  This is now 60%, and meshing is split per chunk so threads free up quickly.

**New look**
- All built-in materials are redrawn in a crisp, hand-painted stylised style: hard-edged
  bevelled shapes, deep crevices, painted light, and extra detail at 256/512 px.
- Default texture resolution is 256 px on the Ultra preset and 128 px otherwise, with 4×
  anisotropic filtering.
- Stylised sky shader with a sun halo and crisp clouds.
- Warm sun with cool sky-lit shade, wrap-around diffuse, rim sheen, stronger corner
  ambient occlusion, height fog, soft-light glow, and 2/4-split shadow cascades by preset.

## 0.1.0: first playable
World streaming, free-form quarter-block building, parallax materials, texture packs.
