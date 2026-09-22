"""Low-poly proxy bodies for the rig's vehicles.

Each body is built from the vehicle's own profile numbers, so it fits the car it belongs to:

  * length and height stay inside the collision box (`body_size`), so what you see is still what
    the physics uses
  * width goes out to the track, with the sills pulled in inside the wheels' inner faces, so the
    wheels stay visible and nothing intersects them
  * the body colour from the profile is baked into the glb's material

Run:  python3 build_vehicles.py <dims.json> <output dir>
"""
from __future__ import annotations

import json
import sys

from glb import Mesh, write_glb

GLASS = (0.10, 0.13, 0.17, 1.0, 0.0, 0.25)
TRIM = (0.09, 0.09, 0.10, 1.0, 0.1, 0.7)
LIGHT = (0.95, 0.93, 0.80, 1.0, 0.0, 0.3)
TAIL = (0.60, 0.07, 0.07, 1.0, 0.0, 0.3)


def frame(d: dict) -> dict:
    """The space the body has to live in, from the vehicle's own numbers."""
    bx, by, bz = d["body"]
    wheel_y = d["hardpoint"] - (d["susp_rest"] - d["comp"])
    inner = d["track_f"] / 2 - d["wheel_w"] / 2          # inner face of the front tyre
    return {
        "L": bz, "top": by / 2, "bottom": -by / 2,
        "hw": max(bx / 2, d["track_f"] / 2 + d["wheel_w"] * 0.25),
        "sill": max(0.25, inner - 0.03),                 # tucked inside the wheels
        "wheel_top": wheel_y + d["wheel_r"],
        "wheel_y": wheel_y,
        "front": -bz / 2, "back": bz / 2,
    }


def car(d: dict, style: dict) -> Mesh:
    """A generic three-box car: nose, bonnet, greenhouse, tail. `style` gives the proportions
    as fractions of the length, measured from the nose."""
    f = frame(d)
    m = Mesh()
    L, hw, sill = f["L"], f["hw"], f["sill"]
    bottom, top = f["bottom"], f["top"]
    # the waistline has to clear the tyre tops, or the bodywork swallows the wheels
    waist = max(bottom + (top - bottom) * style["waist"], f["wheel_top"] + 0.07)
    roof = top - (top - bottom) * style.get("roof_drop", 0.0)
    z = lambda t: f["front"] + L * t                     # noqa: E731 - fraction to metres

    # main tub: narrow as far up as the tyre tops (so the wheels sit in open arches), then
    # flaring out to full width at the waistline
    arch = min(waist - 0.03, f["wheel_top"] + 0.02)
    m.hexa("body", (z(0.06), sill, sill, bottom, arch), (z(0.94), sill, sill, bottom, arch))
    m.hexa("body", (z(0.06), sill, hw, arch, waist), (z(0.94), sill, hw, arch, waist))
    # nose and tail caps, tapered in and down
    m.hexa("body", (f["front"], hw * 0.72, hw * 0.80, bottom + 0.05, waist - 0.02),
           (z(0.06), sill, hw, bottom, waist))
    m.hexa("body", (z(0.94), sill, hw, bottom, waist),
           (f["back"], hw * 0.78, hw * 0.86, bottom + 0.05, waist - 0.02))
    del arch
    # bonnet and boot lids
    m.hexa("body", (z(0.02), hw * 0.80, hw * 0.74, waist - 0.02, waist + style["hood"]),
           (z(style["cabin_a"]), hw * 0.96, hw * 0.92, waist, waist + style["hood"] * 1.4))
    m.hexa("body", (z(style["cabin_b"]), hw * 0.96, hw * 0.92, waist, waist + style["boot"] * 1.4),
           (z(0.98), hw * 0.82, hw * 0.76, waist - 0.02, waist + style["boot"]))
    # greenhouse: glass, raked at both ends and narrower than the body
    gh = hw * style.get("cabin_w", 0.86)
    # the glass stops under the roof panel: when both came up to the same height their top
    # faces sat in one plane and flickered against each other
    under = roof - 0.045
    m.hexa("glass", (z(style["cabin_a"]), gh * 0.94, gh * 0.80, waist + style["hood"] * 1.4, under - 0.02),
           (z(style["cabin_a"] + 0.10), gh, gh * 0.92, waist + style["hood"] * 1.4, under))
    m.hexa("glass", (z(style["cabin_a"] + 0.10), gh, gh * 0.92, waist, under),
           (z(style["cabin_b"] - 0.08), gh, gh * 0.92, waist, under))
    m.hexa("glass", (z(style["cabin_b"] - 0.08), gh, gh * 0.92, waist + style["boot"] * 1.4, under),
           (z(style["cabin_b"]), gh * 0.94, gh * 0.80, waist + style["boot"] * 1.4, under - 0.02))
    # roof panel over the glass, reaching down to meet it
    m.hexa("body", (z(style["cabin_a"] + 0.09), gh * 0.98, gh * 0.90, under, roof),
           (z(style["cabin_b"] - 0.07), gh * 0.98, gh * 0.90, under, roof))
    _lights(m, f, waist, style)
    return m


def _lights(m: Mesh, f: dict, waist: float, style: dict) -> None:
    hw = f["hw"]
    y = waist - 0.02 - style.get("light_drop", 0.04)
    w = hw * 0.30
    m.mirror_x("light", (hw * 0.50, y, f["front"] + 0.07), (w, 0.09, 0.10))
    m.mirror_x("tail", (hw * 0.52, y + 0.04, f["back"] - 0.07), (w, 0.10, 0.10))
    m.box("trim", (0.0, y - 0.06, f["front"] + 0.08), (hw * 1.2, 0.10, 0.14))     # bumper
    m.box("trim", (0.0, y - 0.04, f["back"] - 0.08), (hw * 1.2, 0.10, 0.14))


def bus(d: dict) -> Mesh:
    f = frame(d)
    m = Mesh()
    hw, sill, bottom, top = f["hw"], f["sill"], f["bottom"], f["top"]
    z = lambda t: f["front"] + f["L"] * t                                          # noqa: E731
    floor = max(bottom + (top - bottom) * 0.30, f["wheel_top"] + 0.06)
    belt = bottom + (top - bottom) * 0.62
    m.hexa("body", (z(0.01), sill, sill, bottom, f["wheel_top"] + 0.02),
           (z(0.99), sill, sill, bottom, f["wheel_top"] + 0.02))
    m.hexa("body", (z(0.01), sill, hw, f["wheel_top"] + 0.02, floor),
           (z(0.99), sill, hw, f["wheel_top"] + 0.02, floor))
    m.hexa("glass", (z(0.005), hw * 0.97, hw * 0.94, floor, belt), (z(0.06), hw, hw, floor, belt))
    m.hexa("glass", (z(0.06), hw, hw, floor, belt), (z(0.94), hw, hw, floor, belt))
    m.hexa("glass", (z(0.94), hw, hw, floor, belt), (z(0.995), hw * 0.97, hw * 0.94, floor, belt))
    m.hexa("body", (z(0.005), hw * 0.96, hw * 0.88, belt, top), (z(0.99), hw * 0.96, hw * 0.88, belt, top))
    m.box("trim", (0.0, belt + (top - belt) * 0.45, z(0.02)), (hw * 1.1, 0.26, 0.10))   # destination sign
    m.mirror_x("light", (hw * 0.62, floor - 0.18, f["front"] + 0.07), (0.26, 0.16, 0.10))
    m.mirror_x("tail", (hw * 0.62, floor - 0.18, f["back"] - 0.07), (0.26, 0.16, 0.10))
    m.box("trim", (0.0, bottom + 0.12, f["front"] + 0.07), (hw * 1.8, 0.22, 0.12))
    return m


def garbage_truck(d: dict) -> Mesh:
    f = frame(d)
    m = Mesh()
    hw, sill, bottom, top = f["hw"], f["sill"], f["bottom"], f["top"]
    z = lambda t: f["front"] + f["L"] * t                                          # noqa: E731
    chassis = max(bottom + (top - bottom) * 0.22, f["wheel_top"] + 0.07)
    cab_top = bottom + (top - bottom) * 0.74
    m.hexa("body", (z(0.02), sill, sill, bottom, f["wheel_top"] + 0.02),
           (z(0.99), sill, sill, bottom, f["wheel_top"] + 0.02))
    m.hexa("body", (z(0.02), sill, hw * 0.92, f["wheel_top"] + 0.02, chassis),
           (z(0.99), sill, hw * 0.92, f["wheel_top"] + 0.02, chassis))
    # cab at the front, with a deep screen
    m.hexa("body", (z(0.0), hw * 0.92, hw * 0.88, chassis, chassis + 0.30),
           (z(0.26), hw * 0.96, hw * 0.94, chassis, chassis + 0.30))
    m.hexa("glass", (z(0.005), hw * 0.90, hw * 0.86, chassis + 0.30, cab_top),
           (z(0.24), hw * 0.94, hw * 0.92, chassis + 0.30, cab_top))
    m.hexa("body", (z(0.005), hw * 0.92, hw * 0.84, cab_top, cab_top + 0.16),
           (z(0.26), hw * 0.96, hw * 0.88, cab_top, cab_top + 0.16))
    # hopper body, taller than the cab, with a sloped tailgate
    m.hexa("body", (z(0.28), hw * 0.94, hw, chassis, top - 0.05), (z(0.86), hw * 0.94, hw, chassis, top))
    m.hexa("body", (z(0.86), hw * 0.94, hw, chassis, top), (z(0.995), hw * 0.90, hw * 0.80, chassis - 0.08, top - 0.55))
    m.box("trim", (0.0, top - 0.08, z(0.55)), (hw * 1.2, 0.14, f["L"] * 0.40))       # top rail
    m.mirror_x("light", (hw * 0.62, chassis - 0.12, f["front"] + 0.06), (0.24, 0.18, 0.10))
    m.mirror_x("tail", (hw * 0.60, chassis + 0.10, f["back"] - 0.06), (0.22, 0.20, 0.10))
    m.box("trim", (0.0, bottom + 0.14, f["front"] + 0.07), (hw * 1.7, 0.24, 0.12))
    return m


def quad(d: dict) -> Mesh:
    f = frame(d)
    m = Mesh()
    hw, bottom, top = f["hw"], f["bottom"], f["top"]
    z = lambda t: f["front"] + f["L"] * t                                          # noqa: E731
    deck = bottom + (top - bottom) * 0.35
    m.hexa("body", (z(0.10), hw * 0.42, hw * 0.52, bottom + 0.04, deck),
           (z(0.90), hw * 0.42, hw * 0.52, bottom + 0.04, deck))
    m.hexa("body", (z(0.02), hw * 0.34, hw * 0.46, deck - 0.06, deck + 0.10),     # front rack
           (z(0.22), hw * 0.44, hw * 0.50, deck - 0.02, deck + 0.14))
    m.hexa("body", (z(0.26), hw * 0.40, hw * 0.34, deck, deck + 0.20),            # tank
           (z(0.52), hw * 0.44, hw * 0.34, deck, deck + 0.22))
    m.hexa("trim", (z(0.52), hw * 0.44, hw * 0.40, deck + 0.02, deck + 0.16),     # seat
           (z(0.80), hw * 0.46, hw * 0.42, deck + 0.02, deck + 0.14))
    m.hexa("body", (z(0.80), hw * 0.44, hw * 0.50, deck - 0.02, deck + 0.12),     # rear rack
           (z(0.98), hw * 0.36, hw * 0.46, deck - 0.06, deck + 0.08))
    m.box("trim", (0.0, deck + 0.30, z(0.30)), (hw * 0.90, 0.06, 0.06))           # handlebar
    m.box("trim", (0.0, deck + 0.20, z(0.31)), (0.07, 0.24, 0.07))                # stem
    m.mirror_x("light", (hw * 0.22, deck + 0.16, z(0.06)), (0.14, 0.10, 0.08))
    m.mirror_x("tail", (hw * 0.24, deck + 0.06, z(0.97)), (0.10, 0.08, 0.06))
    return m


def monster_truck(d: dict) -> Mesh:
    """A pickup shell riding high over the tyres: a narrow frame between the wheels, the body
    above the tyre tops, and the tyres standing well proud of it."""
    f = frame(d)
    m = Mesh()
    L, bottom, top, sill = f["L"], f["bottom"], f["top"], f["sill"]
    z = lambda t: f["front"] + L * t                                              # noqa: E731
    deck = f["wheel_top"] + 0.06                         # body starts above the tyre tops
    hw = min(d["body"][0] / 2, sill + 0.35)
    m.hexa("trim", (z(0.10), sill * 0.55, sill * 0.55, bottom + 0.05, deck),       # chassis rails
           (z(0.90), sill * 0.55, sill * 0.55, bottom + 0.05, deck))
    m.hexa("body", (z(0.02), hw * 0.86, hw * 0.80, deck, deck + 0.34),            # bonnet
           (z(0.36), hw, hw * 0.96, deck, deck + 0.38))
    m.hexa("body", (z(0.36), hw, hw, deck, deck + 0.20), (z(0.98), hw, hw, deck, deck + 0.20))   # floor
    cab_top = top - 0.06                                 # the light bar sits on top of this
    under = cab_top - 0.05
    m.hexa("glass", (z(0.36), hw * 0.92, hw * 0.82, deck + 0.20, under - 0.03),
           (z(0.44), hw * 0.94, hw * 0.86, deck + 0.20, under))
    m.hexa("glass", (z(0.44), hw * 0.94, hw * 0.86, deck + 0.20, under),
           (z(0.62), hw * 0.94, hw * 0.86, deck + 0.20, under))
    m.hexa("body", (z(0.43), hw * 0.96, hw * 0.88, under, cab_top),               # cab roof
           (z(0.63), hw * 0.96, hw * 0.88, under, cab_top))
    m.hexa("body", (z(0.62), hw, hw, deck + 0.20, deck + 0.52), (z(0.66), hw, hw, deck + 0.20, deck + 0.52))  # cab back
    for x in (-1.0, 1.0):                                                          # bed sides
        m.hexa("body", (z(0.66), 0.05, 0.05, deck + 0.20, deck + 0.46),
               (z(0.98), 0.05, 0.05, deck + 0.20, deck + 0.46), x=x * (hw - 0.05))
    m.hexa("body", (z(0.97), hw - 0.10, hw - 0.10, deck + 0.20, deck + 0.44),     # tailgate
           (z(0.99), hw - 0.10, hw - 0.10, deck + 0.20, deck + 0.44))
    m.mirror_x("light", (hw * 0.6, deck + 0.20, f["front"] + 0.12), (0.30, 0.14, 0.10))
    m.mirror_x("tail", (hw * 0.7, deck + 0.34, f["back"] - 0.08), (0.18, 0.18, 0.10))
    m.box("trim", (0.0, deck - 0.05, f["front"] + 0.10), (hw * 1.9, 0.18, 0.16))  # bumper
    m.box("trim", (0.0, top - 0.03, z(0.53)), (hw * 1.2, 0.06, 0.10))             # roof light bar
    return m


def dune_buggy(d: dict) -> Mesh:
    """An open tub between the wheels, a pointed nose, the engine behind the seats, and a roll
    cage made of bars - the frame's sections can slope along the car, which is all a cage needs."""
    f = frame(d)
    m = Mesh()
    L, bottom, top, sill = f["L"], f["bottom"], f["top"], f["sill"]
    z = lambda t: f["front"] + L * t                                              # noqa: E731
    floor = bottom + 0.06
    rim = f["wheel_top"] + 0.18
    hw = min(d["body"][0] / 2, sill + 0.06)
    m.hexa("body", (z(0.02), sill * 0.35, sill * 0.45, floor + 0.12, floor + 0.34),   # nose cone
           (z(0.26), sill * 0.80, sill * 0.85, floor, rim - 0.04))
    m.hexa("body", (z(0.26), sill * 0.80, hw, floor, rim), (z(0.70), sill * 0.80, hw, floor, rim))   # tub
    m.hexa("trim", (z(0.70), sill * 0.70, sill * 0.62, floor, rim + 0.10),        # engine
           (z(0.97), sill * 0.60, sill * 0.52, floor + 0.04, rim + 0.02))
    m.hexa("trim", (z(0.42), 0.20, 0.20, floor + 0.04, rim - 0.06),                # seats
           (z(0.58), 0.20, 0.20, floor + 0.04, rim + 0.10), x=-0.28)
    m.hexa("trim", (z(0.42), 0.20, 0.20, floor + 0.04, rim - 0.06),
           (z(0.58), 0.20, 0.20, floor + 0.04, rim + 0.10), x=0.28)
    # roll cage: two hoops of bars, joined over the top
    bar = 0.04
    cage_top = top - bar
    for x in (-1.0, 1.0):
        post_x = x * (hw - 0.08)
        m.hexa("trim", (z(0.30), bar, bar, rim - bar, rim + bar),                  # A-pillar, sloped
               (z(0.42), bar, bar, cage_top - bar, cage_top + bar), x=post_x)
        m.hexa("trim", (z(0.42), bar, bar, cage_top - bar, cage_top + bar),        # roof rail
               (z(0.64), bar, bar, cage_top - bar, cage_top + bar), x=post_x)
        m.hexa("trim", (z(0.64), bar, bar, cage_top - bar, cage_top + bar),        # rear leg, sloped
               (z(0.80), bar, bar, rim - bar, rim + bar), x=post_x)
    m.box("trim", (0.0, cage_top, z(0.43)), (2 * (hw - 0.08) - 2 * bar, bar * 2, bar * 2))   # cross bars
    m.box("trim", (0.0, cage_top, z(0.63)), (2 * (hw - 0.08) - 2 * bar, bar * 2, bar * 2))
    m.mirror_x("light", (0.16, rim - 0.02, z(0.30)), (0.14, 0.12, 0.08))
    m.mirror_x("tail", (sill * 0.40, rim - 0.06, z(0.975)), (0.10, 0.08, 0.05))
    return m


STYLES = {
    "sedan_awd":  {"waist": 0.46, "hood": 0.10, "boot": 0.09, "cabin_a": 0.36, "cabin_b": 0.80},
    "hatch_fwd":  {"waist": 0.48, "hood": 0.09, "boot": 0.07, "cabin_a": 0.30, "cabin_b": 0.86,
                   "cabin_w": 0.88},
    "sports_rwd": {"waist": 0.50, "hood": 0.07, "boot": 0.07, "cabin_a": 0.40, "cabin_b": 0.78,
                   "cabin_w": 0.84, "roof_drop": 0.06},
    "suv_awd":    {"waist": 0.42, "hood": 0.12, "boot": 0.12, "cabin_a": 0.32, "cabin_b": 0.88,
                   "cabin_w": 0.90},
    "limo":       {"waist": 0.44, "hood": 0.10, "boot": 0.10, "cabin_a": 0.22, "cabin_b": 0.88,
                   "cabin_w": 0.88},
}
SPECIAL = {"city_bus": bus, "garbage_truck": garbage_truck, "quad_atv": quad,
           "monster_truck": monster_truck, "dune_buggy": dune_buggy}


def main(dims_path: str, out_dir: str) -> None:
    dims = json.load(open(dims_path))
    for key, d in sorted(dims.items()):
        mesh = SPECIAL[key](d) if key in SPECIAL else car(d, STYLES[key])
        colour = tuple(d["color"]) + (1.0, 0.05, 0.55)
        mats = {"body": colour, "glass": GLASS, "trim": TRIM, "light": LIGHT, "tail": TAIL}
        mats = {k: v for k, v in mats.items() if k in mesh.groups}
        info = write_glb("%s/%s.glb" % (out_dir, key), mesh, mats, d["name"])
        fits = (abs(info["lo"][1]) <= d["body"][1] / 2 + 1e-3
                and info["hi"][1] <= d["body"][1] / 2 + 1e-3
                and info["size"][2] <= d["body"][2] + 1e-3)
        print("%-14s %4d tris  %5.2f x %5.2f x %5.2f m  inside its collider: %s" % (
            key, info["tris"], info["size"][0], info["size"][1], info["size"][2], fits))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
