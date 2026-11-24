# Terrain Tool

Standalone terrain editor built with Godot — exports Godot-ready scenes
(`.tscn` + `.res`) and `.glb` you can drop into any project or DCC.

## Run

Open this folder in Godot 4.3+ and press F5.

## Editing

| Input | Action |
|---|---|
| LMB drag | Sculpt / paint / place foliage |
| RMB drag | Orbit camera |
| RMB + WASD/QE | Fly camera |
| MMB drag | Pan camera |
| Wheel | Zoom |
| Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) | Undo / redo |
| Esc | Stop brush stroke |
| F12 | Screenshot → Pictures folder |
| Click minimap | Jump camera to that spot |

## File menu

- **New Project** (Ctrl+N) — resolution (129–1025) and world size
- **Open / Save / Save As** (Ctrl+O / Ctrl+S / Ctrl+Shift+S) — `.tres`
  project: heightmap, both splatmaps, foliage transforms
- **Import Heightmap** — PNG/JPG/EXR → normalized heightmap
- **Export .tscn** — baked mesh + 8-layer splat material + textures + foliage
- **Export .glb** — geometry + baked albedo texture

## Features

- Sculpting: Raise, Lower, Smooth, Flatten, **Noise**
- **8-layer** splatmap painting across two splatmaps
  (grass / rock / snow / sand / dirt / mud / gravel / moss)
- **Auto-material**: rule-based splat (steep→rock, high→snow, low flat→sand)
- **View modes**: Shaded / Height / Slope / Splat debug overlays
- **Water level**: adjustable transparent water plane
- **Minimap**: hillshaded preview + click-to-jump + camera marker
- **Hydraulic erosion** (droplet sim) and **thermal erosion** (talus),
  both on worker threads — UI stays responsive
- Foliage: bulk scatter + brush painting (trees on grass, rocks on rock)
- GPU vertex-displacement preview — no CPU mesh rebuild while editing
- Snapshot undo/redo, status bar, tooltips, scrollable panel
- Headless smoke test: `godot --headless -s tests/smoke_test.gd`

## Architecture

Mirrors Godot's own layering:

- `core/` — pure data + logic (`Heightmap`, `TerrainBrush`, `TerrainOps`,
  `HydraulicErosion`, `ThermalErosion`, `AutoMaterial`, `TerrainImporter`,
  `TerrainMinimap`, `AlbedoBake`, `TerrainProject`, `TerrainHistory`),
  no scene knowledge
- `systems/` — GPU terrain view, export mesh builder, foliage manager,
  splat shaders (the "server" layer)
- `ui/` — editor panels
- `main.gd` — app shell: menus, dialogs, camera, picking, history, file IO

## Data flow

The CPU-side `Image` heightmap is the single source of truth. Editing ops
mutate it; `GpuTerrainView` re-uploads it to the `heightmap` texture and the
vertex shader displaces a static grid mesh + derives normals. Picking is a
CPU ray-march against the same data, so hover and visuals never diverge.

## Pro editing additions (feature-parity round)

Researched against Terrain3D, Unreal Landscape, Unity Terrain Tools, and Gaea:

- **Modifier keys** (Terrain3D conventions): `Shift+LMB` smooth, `Ctrl+LMB` invert
  raise/lower (on paint: erase to base channel), `Alt+LMB` raise-only,
  `Ctrl+Alt+LMB` lower-only
- **Brush hotkeys**: `[` / `]` radius, `-` / `=` strength
- **Pinch brush** (Unity): pulls terrain features toward the brush center
- **Ramp tool** (Unreal): click start, click end — graded ramp across the
  segment, width = brush radius. Esc cancels.
- **Erase Foliage brush**: removes trees/rocks inside the brush radius
- **Filters** (Unity Terrain Tools, run on worker thread):
  Terrace (N steps), Contrast, Sharpen peaks, Smooth all
- **Contour view mode**: 5 m contour lines over the shaded terrain
- **Status bar**: hover slope angle next to x/z/h
