# Increment 01d — Selectable materials and raised detail

Approved by the creative director: surface grids of 1×1, 4×4 (16 cells), 8×8 (64 cells) per block face; independent 16×16, 64×64, 128×128 texture resolution; visual-only relief with simple existing collision. Prior visual APK is reported to run smoothly at 120 fps on the director's S26 Ultra.

Deliver one original material pack covering grass, soil, bark, stone, sand, leaves. Pair color and linear height data. Expose immediate saved settings through a touch/mouse/keyboard Materials panel which reserves input before movement/look. Use bounded nearby real raised geometry and cheaper distant shading. Keep geometry density independent from texture resolution; no per-texel game objects or collision.

Validate all 18 settings combinations, persistence/invalid settings, geometry depth/triangle/pool budgets, menu/input isolation, existing physics/controls, OpenGL rendering and a signed ARM64 APK. The prior phone result does not establish this new version's performance. Do not add arbitrary external pack importing or fractional construction in this increment.

Lead reviews, commits and pushes source and the downloadable APK. Record exact checks and remaining phone validation in docs/VALIDATION-01d.md.
