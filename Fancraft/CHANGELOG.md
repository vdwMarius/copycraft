# Changelog

## 0.9.1: chopping, controls and terrain fixes (phone feedback)

- **Trees gave dirt, bushes couldn't be harvested.** Root cause: in this Voxel Tools
  version, the instancer's collision bodies were all stacked at one point instead of on
  the plants, so holds went straight through to the ground. Trees, bushes and rocks now
  come from a new deterministic flora system:
  - jittered placement filtered by height, slope and forest noise;
  - one multimesh per 64 m region and model, with detail switching at 45 m and 110 m;
  - real collision within 48 m;
  - every plant has a stable id (ready for saves).
  Aiming anywhere at a canopy, bush or rock targets that plant. The instancer still
  scatters grass and flowers.
- **Swiping to look sometimes dug:**
  - a still finger must now rest 0.32 s (was 0.2 s) before a hold starts;
  - swiping more than 48 px before the first dig or chop completes turns it back into a
    normal look.
- **During a real hold,** swiping moves the action to what's under your finger and nudges
  the camera slightly (22%) that way.
- **Joystick** now only activates in the lower-left corner (left 30%, lower 58% of the
  screen), so taps left of centre stay taps and looks.
- **Terrain** is smoother and more natural:
  - broad lowlands with lakes and beaches;
  - domain-warped rolling hills;
  - squared ridge noise for mountain ranges, only in some regions.
  A new test checks the native generator matches GDScript (0.015 m) and that the terrain
  isn't jagged.
- Digging under a plant removes it (no floating trees). Flora draw distance follows the
  view-distance setting.
- **Input test** now aims at a real tree canopy through the screen and checks that it
  chops for wood, plus bush and rock harvesting and both swipe behaviours.

## 0.9.0: S3, resources and inventory

Phone report on 0.8.0: stable 120 fps on Max Fidelity, occasional dips to 110.
- **Items:** wood, stone, dirt, sand, fiber, berries and flint, in a 24-slot bag with
  stacking (50 or 99 per stack). Icons are painted from the texture set, so packs restyle them.
- **Gathering:**
  - Chop trees for 4–6 wood.
  - Break rocks for 3–5 stone, with a 40% chance of flint.
  - Pick bushes for fiber and berries. Bushes are now targetable.
  - Dig for dirt, sand near the shore, and stone deeper down.
  The right tool is faster, but any tool works.
- **Costs:** building parts cost materials (for example a wood wall is 4 wood; stone parts
  cost stone, with 1 wood for roofs and stairs). Demolishing refunds in full. Raising
  ground costs 2 dirt (or sand).
- **UI:**
  - The hologram turns red when you can't afford a part.
  - The hint line shows have / need ("14/6 Wood").
  - The build menu lists each part's cost and dims parts you can't afford yet.
- **New HUD and bag:**
  - BAG button (or I on desktop) opens the inventory, with a Sort button.
  - A pickup feed on the left shows "+4 Wood".
- **Creative mode:** Settings → Game mode → Creative makes building free.
- Broadleaf trees are about 45% denser, so wood is closer to the spawn.
- **Tests:**
  - New headless inventory suite.
  - Input test covers dig yields, refusing to build without materials, paying, refunds,
    and harvesting a real instanced tree.

## 0.8.0: stylised 3D survival style (no more cubes)

- **Cubes are gone:** the cube structure layer, block pieces and block materials are removed.
- **Vegetation:** procedural stylised trees (3 broadleaf and 2 pine variants), bushes, rocks
  (some mossy), grass and flower tufts, all generated in code with no asset files. They are
  scattered natively by Voxel Tools' VoxelInstancer with distance-based detail levels:
  broadleaf trees are 780 / 356 / 48 triangles, and collision is created near the player.
  Grass grows only on topsoil and shrinks out with distance. Plants vanish if the ground
  under them is dug away.
- **Building parts** in wood or stone (Valheim-style) on a 2 m grid: foundation, floor,
  wall, doorway, window wall, half wall, 45° roof, stairs, pillar, beam. A hologram at the
  crosshair shows the snap (green = OK, red = blocked).
  - Walls snap to the nearest foundation or floor edge.
  - Aiming at a wall top builds the next storey.
  - Aiming at a side continues the same storey.
- **Tools** (bottom bar):
  - Shovel: tap raises ground, hold digs.
  - Axe: hold chops trees, bushes and rocks.
  - Hammer: tap places, hold demolishes.
  Any tool can do any hold action, just slower than the right tool.
- **Shaders:** foliage (cel shading, wind sway, back-light), grass (sway, distance fade)
  and props (texture-array cel shading).
- **Tests:** input test now covers foundation snapping, walls on edges, blocked double
  placement and upper floors on wall tops.
- **Repo fix:** `build/` ignore rules were also hiding `scripts/build/`; they are now
  anchored to the project roots.

## 0.7.0: S1, the smooth world (new direction)

Approved direction: smooth diggable terrain plus survival, crafting and exploration (see
docs/PLAN-v2-smooth-survival.md).
- **New terrain engine.** Smooth terrain from Voxel Tools (MIT, native C++), with level of
  detail, native threaded meshing and collision, and about 3× longer view distance.
  Visible triangles in the cloud test fell from about 2.6 M (blocky 0.6) to 0.27 M.
- **Digging and raising:**
  - hold on the ground to dig (continuous pulses);
  - select the new **DIG** terrain tool (first hotbar slot) and tap to raise dirt.
  Dug holes show dirt, then stone, deeper down.
- **Stylised terrain shader:** painted triplanar textures. Grass on flats, dirt and rock on
  slopes, sand at shores, snow on peaks. Same cel lighting as the pieces.
- **Water** is now a single cheap animated plane.
- **Building:** pieces still build on top of anything with tap to place and hold to break.
  Trees, boulders and crystals are breakable pieces.
- Spawning waits for terrain collision. Input regression test updated for dig and raise.

## 0.6.1
- The cracks overlay now fits the solid part of the piece being broken (for example a
  quarter-height terrace or a slab) instead of a full block-sized box.
- Proposed v2 direction (smooth diggable terrain, survival and crafting): see
  docs/PLAN-v2-smooth-survival.md.

## 0.6.0: break feedback, pacing, and the 4× MSAA cliff

Phone report on 0.5.0: about 60 fps on Ultra, 20–30 fps with 4× MSAA; movement too fast;
the break ring is too small.
- **Breaking:**
  - cracks overlay on the piece being broken, spreading in 10 stages like Minecraft;
  - break ring is now thumb-sized (radius 96 px) and thicker.
- **Movement:** Minecraft speeds of 4.3 m/s walking, 5.6 m/s sprinting and 10.9 m/s flying.
- **4× MSAA removed.** It cost 2–3× the frame time at phone resolution. Saved settings
  drop to 2× once.
- **Solid leaves.** Leaves render as solid painted clumps, matching the reference trees,
  instead of cut-out transparency. Texture gaps become dark shaded pockets. Cut-out
  transparency forces late depth testing on mobile GPUs, and solid leaves also hide each
  other's inner faces. Draw calls in the test scene fell from 193 to 126.

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
