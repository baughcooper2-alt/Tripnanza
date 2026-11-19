# Tripnanza

An endless low-poly snowboarding run down a mountain that slowly starts to move.
You drop in from the summit, carve, hit kickers, land flips and spins, and pass
**BLINKER** checkpoints. The longer you survive, the deeper the mushroom trip.

Built with **Godot 4.3** and GDScript. All models, animations and shaders are
procedural and original (no imported assets).

## Play

Controller layout follows **Steep** (Xbox):

| Action | Xbox controller | Keyboard |
| --- | --- | --- |
| Steer / carve (tap = correction, hold = full lean) | Left stick | A / D or ← / → |
| Brake / tuck (on snow) | Right stick down / up | S / W |
| Jump: hold to crouch, release to pop | RT | Space |
| In the air: frontflip / backflip | Left stick up / down | W / S |
| In the air: spin | Left stick left / right | A / D |
| Right-hand grab (Indy) / left-hand grab (Melon), both = Japan | RT / LT (in the air) | K / J |
| Switch stance | Push the sticks in opposite directions | Q |
| Restart from the summit | Hold Y | Hold R |
| Change camera (Chase / Close / High) | LB | C |
| Photo mode (freeze, orbit with right stick, zoom with triggers) | Click both sticks | F (orbit A/D/W/S, zoom Q/E) |
| Deliberately fall | D-pad up | X |
| Pause | Start | Esc / P |
| Ride again after a wipeout | Y or A | R or Enter |

* Grabs score more the longer you hold them, but still holding one at
  touchdown makes the landing sketchy.
* Points for distance, plus tricks you actually land. Clean landings score
  110 %, sketchy (survivable) ones 50 %. Flip + spin combos score ×1.5.
* Holding a flip/spin input tucks the rider and rotates. Let go to untuck and
  slow down. Landings close to upright get gently straightened.
* Hard tree/rock hits, landing too sideways or too far off upright, or too-hard
  impacts end the run.
* A BLINKER sits every 150 m. A luminous seam crosses the whole slope, and the
  gate arch lights up from the snow toward its crown as you approach. Crossing it
  pays a growing bonus and pushes the trip into a stronger phase.
* Settings (summit menu): **Reduced trip effects**, **Trip strength**, Fullscreen.

## Run it

1. Install Godot **4.3** (standard, not .NET) from
   https://godotengine.org/download/archive/4.3-stable/
2. Open Godot → **Import** → choose this folder's `project.godot` → **Import & Edit**.
3. Press **F5** (or the ▶ button).

Command line on a Mac, once Godot.app is in /Applications:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /path/to/Tripnanza
```

## Export (macOS / Windows)

Presets for **macOS** (universal, ad-hoc signed) and **Windows Desktop** (x86_64,
single .exe) are in `export_presets.cfg`. Install the matching export templates
once (Editor → Manage Export Templates → Download), then either use
Project → Export… or:

```bash
mkdir -p build/macos build/windows
godot --headless --path . --export-release "macOS" build/macos/Tripnanza.zip
godot --headless --path . --export-release "Windows Desktop" build/windows/Tripnanza.exe
```

The macOS build is ad-hoc signed, not notarized. On first launch, right-click
the app → Open (or allow it in System Settings → Privacy & Security). `build/`
is git-ignored.

## Where things live

| System | Script | What to tune in the Inspector |
| --- | --- | --- |
| Game flow (summit → intro → ride → wipeout) | `scripts/core/main.gd` (`Main`) | sun angle (long shadows), wipeout card delay, wind powder |
| Rider physics, tricks, landings, intro | `scripts/rider/rider.gd` (`Rider`) | **Handling** (turn rates, lean build time, grip, drag), **Jumping** (ollie strength, lip pop), **Tricks** (flip/spin speed, landing tolerances) |
| Rider model, poses, IK | `scripts/rider/rider_model.gd` | jacket/board colours, pose smoothing, `POSES` table |
| Camera | `scripts/camera/camera_rig.gd` (`CameraRig`) | **pitch angle**, distance, FOV, rider screen height (lower third), air pull-back, summit menu shot |
| World shape & sections | `scripts/world/mountain.gd` (autoload `Mountain`) | slope steepness, summit, gullies, seed, obstacle density growth |
| Terrain streaming | `scripts/world/terrain_streamer.gd` | view distance in sections |
| Horizon peaks | `scripts/world/backdrop.gd` | ring radius, peak height |
| Trip progression | `scripts/trip/trip_director.gd` (`TripDirector`) | **intensity_over_time** curve + `ramp_seconds`, blinker boost, strength, `preview_intensity` (force a level while tuning) |
| Deep-trip encounters | `scripts/trip/encounters.gd` | tunnel length/radius, flower count, peak-split duration |
| BLINKER checkpoints | `scripts/checkpoints/blinker_manager.gd`, `blinker_gate.gd` | **interval** (150 m), first gate, bonus, gate width |
| Score | `scripts/core/score_keeper.gd` | points per metre, clean/sketchy multipliers |
| Interface | `scripts/ui/game_ui.gd` | layout, fonts, colours, animations |
| Shaders | `shaders/` | terrain (all on-snow trip effects), props (solid hazards), hallucination (decor), sky, backdrop, post (screen-edge effects), tracks, gate |

### The trip, briefly

`TripDirector` maps survival time through an editable Curve to an overall
intensity (plus a permanent step and a short surge per BLINKER). Each effect
fades in over its own intensity band and breathes on its own slow wave, so
effects rise and fall while the total keeps climbing. Phases:

* **Onset**: snow grain drifts against your travel; tree banks breathe
  together; your carve leaves a faint colour echo.
* **Rising**: contour lines bloom out of your tracks; shadows split into colour
  ribbons; distant treetops fold into mirrored forms and resolve as you near
  them; landed flips send a wave of colour downhill.
* **Deep**: encounters. A rainbow tunnel curls up from the slope sides, its exit
  framing the trail. Fractal flowers grow out of the mountainside. The horizon
  peaks split apart and recombine.
* **Peak**: liquid marbling and Julia-set spirals in the far snow, sky mandala,
  edge kaleidoscope, melting drips and radial echo, scaling with speed.

On top of that, the screen compositor (`scripts/trip/trip_compositor.gd` +
`shaders/trip_post.gdshader`) adds effects modelled on the reference images:
tracers (frame feedback), false-colour palettes that change at every BLINKER
(Dusk Smear → Infrared → Cyan Forest → Paint By Number → Net Of Being),
paint-by-number posterizing with ink lines and unpainted patches, colour grain
in the shadows, and a radial zoom smear. Eyes open in the distant snow and
follow you. `scripts/trip/apparitions.gd` spawns "random things" well off your
line (giant glowing mushrooms, a watching eye, a ghost of the rider, fractal
flowers, halo rings), and they dissolve before you reach them.

Readability rules: nothing distorts near the rider or the line just ahead.
Solid hazards stay matte and opaque with a darkening rim. Hallucinations are
glowing, translucent, unshaded and never collide. The **Reduced trip effects**
setting cuts strength and turns off the vertex warps and the kaleidoscope.
Nothing flashes.

## Testing tools

* `scenes/debug/pose_gallery.tscn` renders every rider pose side by side.
* Automated playtests (scripted inputs, screenshots from the real camera):

```bash
godot --path . -- --scenario=first_minute --capture=/tmp/shots --no-save
godot --path . -- --scenario=long_run --invincible --duration=180 --trip-offset=90 --capture=/tmp/shots --no-save
```

`--trip-offset=<seconds>` starts the trip further along. Debug files are
excluded from exports.

## Rider model

The rider is the imported snowboarder in `assets/characters/snowboarder/` (see
the CREDITS.md there; confirm its licence before publishing). Its own clips do
the riding: Idle, Turn_Left and Turn_Right are blended by how hard you lean, and
Fall is scrubbed for the summit sit, the stand-up and wipeouts.
`scripts/rider/rider_ik.gd` adds crouch, tuck, landing compression, grabs, the
mushroom and the hand plant with two-bone IK on top. To use a different
character, change `RiderAvatar.GLB` (the code expects the same bone names).

## Music, sound and full screen

* **Music:** `assets/music/` (High Hills, I Can Fly Away) plays as a crossfading
  playlist. As the trip deepens the music picks up phaser, chorus and echo.
  Add or reorder tracks in `MUSIC` at the top of `scripts/core/audio.gd`.
* **Sound effects** are synthesized in code at startup (no files needed): snow
  carve, skid/brake scrape, wind, spin whoosh, pop, landings (clean/hard/sketchy),
  crashes, tree bumps, grabs, trick chimes, blinker bell, phase swell, the summit
  intro (munch, hand plant, board slap) and UI ticks. To use a recorded sound
  instead, map its name to a file in `SFX_OVERRIDES`.
* **Controller rumble** on pops, landings, bumps, crashes and blinkers (can be
  turned off in Settings).
* **Full screen:** F11, Alt+Enter, the Xbox View button, or Settings. The choice
  is remembered.
* Settings also has music and effects volume.

## Status (prototype 0.1)

Verified by the automated playtests on Linux (Godot 4.3, Vulkan, software renderer):

* Summit → intro → first kicker (clean backflip) → BLINKER 1 → wipeout → Ride Again.
* 3 km+ long runs: terrain keeps streaming, blinkers keep coming, and all three
  deep-trip encounters cycle at peak intensity.
* Reduced-effects mode at peak.

The macOS and Windows exports build from `export_presets.cfg`, but they haven't
been launched on those systems yet.
