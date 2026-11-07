# Increment 01e — Relief coverage and transitions

The director reports v0.1.3 still runs at 120 fps but raised detail visibly appears close to the player. The previous 32-nearest-face cap caused an effective flat-ground boundary of roughly three blocks, independently of the configured maximum distance. Whole-block updates also abruptly reassigned pooled patches.

Replace abrupt selection with stable face residency, admission/retirement transitions, and broader coverage. Batch shared meshes to keep draw submissions low. Preserve material choices, controls and collision. Explicitly bound the higher geometry budget and verify transition continuity across movement, reversal, saturation and teleporting. Build and publish an updated debug APK through the lead, reporting device testing separately from cloud evidence.
