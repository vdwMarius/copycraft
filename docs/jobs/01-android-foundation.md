# Job 01 — Android foundation and profiling

## Prerequisites

Read README.md and docs/ROADMAP.md. Obtain the creative director's engine decision before engine-specific implementation. Identify the minimum target phone; independent build/tooling work can continue while hardware details are pending.

## Deliverable

Create a reproducibly buildable native Android prototype with a small original voxel scene, touch movement and camera controls, collision, and a visible profiling overlay. Include desktop development execution where the chosen engine supports it. Keep streaming and polished art for later increments.

Inspect available tooling and environment credentials before installing dependencies or requesting access. Pin engine/module/tool versions, verify downloaded artifacts, and document build commands. Evaluate native module licensing and Android ABI/backend compatibility before adoption.

## Validation

- Build the Android debug APK and record its location and tool versions.
- Run the scene and validate movement, camera controls, and collision using available execution tools.
- Validate profiling output includes frame times and active rendering settings.
- Install and test on the named phone if accessible. Otherwise report device validation as outstanding and provide installation instructions; do not infer phone FPS from desktop or emulator runs.
- Review changes, commit, and push through the lead agent. Record failures without substituting trivial checks.

## Handoff

Report the milestone commit, exact build/run commands, verified behavior, outstanding hardware checks, and a job 02 brief for deterministic chunk streaming.
