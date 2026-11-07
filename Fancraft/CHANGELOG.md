# Changelog

## 0.5.0: fewer draw calls, Minecraft-style breaking

Phone report on 0.4.0: Max Fidelity ran at about 20 fps even with 3D resolution at 50%, so it
was not limited by pixels. Ultra 120 ran at 80+ fps.

**Performance**
- **One merged mesh per chunk column** instead of one per chunk. Merging runs on worker
  threads (high priority for edits). This roughly halves to thirds the draw calls in both
  the main and shadow passes, the likely cause of Max Fidelity's CPU-bound frame time.
- **Stats overlay** now shows CPU and GPU frame time and draw calls, so the next phone
  report can pinpoint the bottleneck.
- **Max Fidelity parallax** uses 16 steps instead of 24, with the same self-shadowing.

**Building**
- **Minecraft-style break timing:**
  - each material has a hardness (leaves 0.15 s, dirt 0.4 s, stone and brick about 0.8 s);
  - smaller pieces break faster;
  - there is a 0.3 s cooldown after each broken piece before the next one starts.
- **No floating ghost block.**
- **Swiping during a break** no longer turns the view. The current block's progress stops
  and the break moves to the block under your finger, starting over.
- Input regression test covers swiping during a break, and checks that a normal drag still turns the view.

## 0.4.0: performance and Minecraft-style building

Phone report on 0.2.0 at max settings: 50–70 fps (sometimes 90), lowest near water, and
about 20 fps with 512 px textures.

**Performance**
- **Auto 3D resolution, now the default in every preset.** It scales 3D render resolution
  (50–100%, with FSR upscaling) to hold the frame-rate target. It uses GPU render time when
  the driver reports it, otherwise missed frames, and changes are rate-limited. Max settings
  previously rendered at the panel's full resolution (about 3120×1440) with 4× MSAA.
- **Water, glass and crystal** now light themselves cheaply in the shader instead of going
  through the full lit-transparency path (per-light and shadow sampling for every water pixel).
- **Parallax** samples height one mip level coarser (half the bandwidth, which matters most
  at 256/512 px) and uses fewer steps with distance.
- **Presets rebalanced:** MSAA capped at 2×, the high shadow setting uses 2 cascades instead
  of 4, and the stats overlay shows the current 3D resolution. Saved settings from older
  versions are migrated to Auto resolution once.

**Building**
- **Tap to place, hold to break, like Minecraft.** A ring fills around your finger; keep
  holding to keep breaking. A hold never places and a tap never breaks. The BUILD and MODE
  buttons are gone, and the preview follows your finger while you hold.
- Pieces lift up to 3 quarters along the surface when the ground next to them is slightly
  higher, so blocks place reliably on quarter-terraced terrain.
- Snap now defaults to Block (grid-aligned like Minecraft); Half and Quarter are on the SNAP button.
- New headless input regression test (`-- --inputtest`) simulates a finger holding and tapping.

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
