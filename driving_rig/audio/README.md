# Sounds

Drop files in here and the rig picks them up — no code, no importing, no scene changes.

    audio/default/          used by every vehicle
    audio/<profile>/        overrides for one vehicle, named after its profile file:
                            audio/city_bus/, audio/quad_atv/, audio/garbage_truck/,
                            audio/limo/, audio/sedan_awd/, audio/sports_rwd/,
                            audio/hatch_fwd/, audio/suv_awd/

A vehicle's own folder wins; anything it doesn't have falls back to `default`. Anything missing
anywhere is simply silent — the rig never errors over a sound it can't find. `.ogg` is preferred
(it loops cleanly); `.wav` also works.

You can also put files in `<AppData>/Godot/app_userdata/Driving Rig/audio/…` instead, which
works in an exported build without rebuilding.

## File names

| name | what it should be | how it's used |
|---|---|---|
| `engine_0800.ogg`, `engine_2500.ogg`, `engine_5200.ogg` … | steady engine loops, named for the rpm they were recorded at. Any number of them, at any rpm. | the two nearest the current rpm are crossfaded, and each is pitched to hit the exact rpm. One file alone works; three sounds properly. |
| `tyre_roll.ogg` | rolling tyre / road noise, seamless loop | gain and pitch follow road speed |
| `skid.ogg` | tyre scrub or squeal, seamless loop | gain follows how hard the tyres are sliding, with a little pitch jitter |
| `wind.ogg` | wind, seamless loop | fades in above ~30 km/h |
| `scrape.ogg` | body dragging along something, seamless loop | sustained contact |
| `impact_01.ogg`, `impact_02.ogg` … | one-shot hits. Two or three is plenty. | one picked at random per collision, with ±8 % pitch variance; level follows how hard it hit |
| `bump_01.ogg`, `bump_02.ogg` … | one-shot suspension thumps | played on landing after all four wheels have been off the ground |

Numbered files can use any number of digits (`impact_1.ogg` or `impact_01.ogg`).

## Recording notes

- **Loops** should be seamless and roughly **2–5 s** long. Trim silence off both ends.
- **Engine loops** should be steady-state at one rpm, not a sweep. Mono is fine — these play as
  3D sound from the car. Keep the level consistent between layers or the crossfade will pump.
- **Impacts and bumps** should start right on the transient, with no lead-in.
- Two or three engine layers (idle, mid, near-redline) plus `skid`, `tyre_roll` and a couple of
  `impact_NN` files is a complete-sounding set.

## Per-vehicle rpm ranges

A vehicle's rpm range and pretend gearbox are in its car profile (Sound group): `engine_idle_rpm`,
`engine_redline_rpm`, `gear_count`, `engine_volume_db`, and `audio_set` if you want it to use a
folder that isn't named after the profile. The bus and the garbage truck idle low and redline at
about 2 600 — a petrol engine's loops pitched down that far will sound wrong, so give the diesels
their own folder.
