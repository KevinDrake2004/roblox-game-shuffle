#!/usr/bin/env python3
"""Casino polish pass: exterior resort facade + plaza, entrance vestibule,
and interior luxury atmosphere. Idempotent - safe to re-run.

Does NOT touch ArenaOrigins, Portals gameplay wiring, Floors height ladder
ownership of green/red layers, or Atmosphere.Tables / LoungeBar core geometry
beyond additive dress pieces under Atmosphere.PitDressing / BarGlow.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOBBY = ROOT / "src/map/Lobby.model.json"

# Palette (0-1 Color3)
DARK = [0.035, 0.02, 0.07]
MARBLE = [0.08, 0.07, 0.1]
MARBLE_VEIN = [0.14, 0.12, 0.16]
GOLD = [0.92, 0.75, 0.32]
GOLD_DIM = [0.72, 0.55, 0.22]
CYAN = [0.133, 0.827, 0.933]
MAGENTA = [0.925, 0.282, 0.6]
PURPLE = [0.659, 0.333, 0.969]
RED = [0.55, 0.04, 0.1]
RED_CARPET = [0.62, 0.05, 0.12]
ASPHALT = [0.12, 0.12, 0.14]
STONE = [0.22, 0.2, 0.24]
WATER = [0.25, 0.55, 0.7]
GREEN_PLANT = [0.12, 0.42, 0.22]
GLASS = [0.55, 0.75, 0.85]
WHITE = [0.95, 0.93, 0.88]
WARM = [1.0, 0.85, 0.55]

# Envelope (unchanged)
WALL_Z_S = 66.0
WALL_X = 92.0
ENTRY_HALF = 12.0  # clear opening roughly |x| < 12

# Plaza / facade extents (south of building)
PLAZA_Z0 = 66.5
PLAZA_Z1 = 118.0
SPAWN_POS = [0.0, 3.0, 100.0]

POLISH_FOLDERS = (
    "Exterior",
    "Plaza",
    "Vestibule",
    "PitDressing",
    "BarGlow",
    "LuxuryTrim",
    "CoveLights",
    "Coffers",
)


def find(node: dict, name: str):
    if node.get("name") == name:
        return node
    for child in node.get("children") or []:
        found = find(child, name)
        if found:
            return found
    return None


def ensure_folder(parent: dict, name: str) -> dict:
    kids = parent.setdefault("children", [])
    for child in kids:
        if child.get("name") == name and child.get("className") == "Folder":
            return child
    folder = {"name": name, "className": "Folder", "children": []}
    kids.append(folder)
    return folder


def clear_folder(folder: dict) -> None:
    folder["children"] = []


def remove_named(parent: dict, name: str) -> None:
    kids = parent.get("children") or []
    parent["children"] = [c for c in kids if c.get("name") != name]


def part(
    name: str,
    size,
    pos,
    color,
    *,
    material: str = "SmoothPlastic",
    can_collide: bool = False,
    orientation=None,
    transparency=None,
    shape=None,
    reflectance=None,
) -> dict:
    props = {
        "Anchored": True,
        "Size": [float(size[0]), float(size[1]), float(size[2])],
        "Position": [float(pos[0]), float(pos[1]), float(pos[2])],
        "Color": [float(c) for c in color],
        "Material": material,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
        "CanCollide": can_collide,
    }
    if orientation is not None:
        props["Orientation"] = [float(o) for o in orientation]
    if transparency is not None:
        props["Transparency"] = float(transparency)
    if shape is not None:
        props["Shape"] = shape
    if reflectance is not None:
        props["Reflectance"] = float(reflectance)
    return {"name": name, "className": "Part", "properties": props}


def light_part(name: str, pos, color, *, brightness=2.0, range_=28.0, size=(0.4, 0.4, 0.4)) -> dict:
    p = part(name, size, pos, color, material="Neon", can_collide=False, transparency=0.35)
    p["children"] = [
        {
            "name": "Light",
            "className": "PointLight",
            "properties": {
                "Brightness": float(brightness),
                "Range": float(range_),
                "Color": [float(c) for c in color],
            },
        }
    ]
    return p


def spot_part(name: str, pos, color, *, brightness=3.0, range_=40.0, angle=70.0) -> dict:
    """Invisible host for a SpotLight aimed at the facade (faces -Z / north into building)."""
    p = part(name, (0.5, 0.5, 0.5), pos, color, material="Neon", can_collide=False, transparency=1.0)
    p["children"] = [
        {
            "name": "Spot",
            "className": "SpotLight",
            "properties": {
                "Brightness": float(brightness),
                "Range": float(range_),
                "Angle": float(angle),
                "Face": "Front",
                "Color": [float(c) for c in color],
            },
        }
    ]
    # Orientation so Front (-Z local) aims toward -Z world (into facade from plaza)
    p["properties"]["Orientation"] = [0.0, 0.0, 0.0]
    return p


# ---------------------------------------------------------------------------
# Phase A - Exterior + plaza
# ---------------------------------------------------------------------------


def build_exterior() -> list:
    kids: list = []

    # --- Porte-cochere canopy ---
    kids.append(
        part("CanopyDeck", (40.0, 1.2, 18.0), (0.0, 19.2, 75.0), MARBLE, material="Slate", can_collide=True)
    )
    kids.append(
        part("CanopyGoldEdge", (41.0, 0.35, 0.5), (0.0, 19.95, 84.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("CanopyGoldEdgeN", (41.0, 0.35, 0.5), (0.0, 19.95, 66.2), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("CanopyGoldSideL", (0.5, 0.35, 18.0), (-20.25, 19.95, 75.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("CanopyGoldSideR", (0.5, 0.35, 18.0), (20.25, 19.95, 75.0), GOLD, material="Metal", can_collide=False)
    )
    # Underside cove neon
    kids.append(
        part("CanopyNeon", (36.0, 0.2, 14.0), (0.0, 18.45, 75.0), CYAN, material="Neon", can_collide=False, transparency=0.25)
    )

    # Canopy columns (porte-cochere posts)
    for i, x in enumerate((-16.0, 16.0)):
        for j, z in enumerate((70.0, 82.0)):
            kids.append(
                part(f"CanopyCol_{i}_{j}", (2.4, 18.5, 2.4), (x, 9.25, z), MARBLE, material="Slate", can_collide=True)
            )
            kids.append(
                part(f"CanopyColCap_{i}_{j}", (3.0, 0.55, 3.0), (x, 18.7, z), GOLD, material="Metal", can_collide=False)
            )
            kids.append(
                part(f"CanopyColBase_{i}_{j}", (3.0, 0.55, 3.0), (x, 0.55, z), GOLD, material="Metal", can_collide=False)
            )
            kids.append(
                part(
                    f"CanopyColNeon_{i}_{j}",
                    (0.35, 16.0, 0.35),
                    (x, 9.0, z + 1.35),
                    GOLD,
                    material="Neon",
                    can_collide=False,
                )
            )

    # --- Tall facade parapet / cornice above south wall ---
    kids.append(
        part("SouthParapet", (186.0, 4.5, 3.2), (0.0, 24.5, 66.2), DARK, material="Slate", can_collide=True)
    )
    kids.append(
        part("SouthCornice", (188.0, 0.7, 4.0), (0.0, 27.0, 66.5), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("SouthCorniceNeon", (180.0, 0.25, 0.35), (0.0, 26.5, 68.2), MAGENTA, material="Neon", can_collide=False)
    )

    # Glass curtain bands on south face (left / right of entry)
    for side, cx in (("L", -52.0), ("R", 52.0)):
        kids.append(
            part(
                f"GlassBand_{side}",
                (72.0, 10.0, 0.4),
                (cx, 12.0, 67.4),
                GLASS,
                material="Glass",
                can_collide=False,
                transparency=0.45,
                reflectance=0.25,
            )
        )
        kids.append(
            part(f"GlassGoldFrame_{side}", (74.0, 10.6, 0.25), (cx, 12.0, 67.15), GOLD, material="Metal", can_collide=False)
        )
        # Window glow strips (night read)
        for wi, wy in enumerate((8.0, 12.0, 16.0)):
            kids.append(
                part(
                    f"WindowGlow_{side}_{wi}",
                    (68.0, 0.35, 0.2),
                    (cx, wy, 67.55),
                    WARM,
                    material="Neon",
                    can_collide=False,
                    transparency=0.2,
                )
            )

    # Entry gold molding around opening
    kids.append(part("EntryMold_L", (0.6, 18.5, 1.0), (-12.4, 9.5, 66.8), GOLD, material="Metal", can_collide=False))
    kids.append(part("EntryMold_R", (0.6, 18.5, 1.0), (12.4, 9.5, 66.8), GOLD, material="Metal", can_collide=False))
    kids.append(part("EntryMold_Top", (25.4, 0.7, 1.0), (0.0, 18.9, 66.8), GOLD, material="Metal", can_collide=False))

    # --- Iconic marquee board (BrandSign sits in front of this) ---
    kids.append(
        part("MarqueeBoard", (52.0, 9.0, 2.0), (0.0, 28.5, 69.0), MARBLE, material="Slate", can_collide=True)
    )
    kids.append(
        part("MarqueeNeonOuter", (54.0, 10.0, 0.45), (0.0, 28.5, 70.15), CYAN, material="Neon", can_collide=False, transparency=0.15)
    )
    kids.append(
        part("MarqueeNeonInner", (50.0, 7.6, 0.35), (0.0, 28.5, 70.25), MAGENTA, material="Neon", can_collide=False, transparency=0.25)
    )
    kids.append(light_part("MarqueeWash", (0.0, 28.5, 72.0), CYAN, brightness=3.5, range_=55.0, size=(1.0, 1.0, 1.0)))

    # Diamond / crown rooftop silhouette (original geometry, not Rockstar IP)
    kids.append(
        part(
            "CrownDiamond",
            (10.0, 10.0, 2.5),
            (0.0, 36.0, 66.5),
            GOLD,
            material="Metal",
            can_collide=False,
            orientation=(0.0, 0.0, 45.0),
        )
    )
    kids.append(
        part(
            "CrownDiamondCore",
            (5.5, 5.5, 2.0),
            (0.0, 36.0, 66.8),
            CYAN,
            material="Neon",
            can_collide=False,
            orientation=(0.0, 0.0, 45.0),
            transparency=0.1,
        )
    )
    kids.append(part("CrownSpire", (1.6, 8.0, 1.6), (0.0, 43.0, 66.5), GOLD, material="Metal", can_collide=False))
    kids.append(part("CrownSpireTip", (0.9, 2.2, 0.9), (0.0, 48.0, 66.5), MAGENTA, material="Neon", can_collide=False))
    kids.append(light_part("CrownLight", (0.0, 40.0, 68.0), GOLD, brightness=2.8, range_=45.0))

    # Side elevation pilasters + window bands (readable from afar)
    for side, x in (("W", -93.2), ("E", 93.2)):
        for i, z in enumerate(range(-120, 60, 22)):
            kids.append(
                part(
                    f"Pilaster_{side}_{i}",
                    (2.2, 22.0, 2.8),
                    (x, 11.0, float(z)),
                    MARBLE,
                    material="Slate",
                    can_collide=False,
                )
            )
            kids.append(
                part(
                    f"PilasterCap_{side}_{i}",
                    (2.6, 0.5, 3.2),
                    (x, 22.2, float(z)),
                    GOLD,
                    material="Metal",
                    can_collide=False,
                )
            )
        # Horizontal window glow band mid-height
        kids.append(
            part(
                f"SideWindowBand_{side}",
                (0.3, 1.2, 180.0),
                (x + (0.6 if side == "W" else -0.6), 14.0, -37.0),
                WARM,
                material="Neon",
                can_collide=False,
                transparency=0.3,
            )
        )
        kids.append(
            part(
                f"SideGoldRail_{side}",
                (0.25, 0.35, 190.0),
                (x + (0.5 if side == "W" else -0.5), 21.0, -37.0),
                GOLD,
                material="Metal",
                can_collide=False,
            )
        )

    # Facade flood spots from plaza looking north
    for i, x in enumerate((-40.0, -15.0, 15.0, 40.0)):
        kids.append(spot_part(f"FacadeFlood_{i}", (x, 6.0, 90.0), WARM, brightness=4.0, range_=55.0, angle=65.0))

    return kids


def build_plaza() -> list:
    kids: list = []

    # Ground (collidable) - south of envelope
    kids.append(
        part(
            "PlazaFloor",
            (160.0, 1.0, 52.0),
            (0.0, 0.0, 92.0),
            ASPHALT,
            material="Asphalt",
            can_collide=True,
        )
    )
    # Stone apron near doors
    kids.append(
        part(
            "PlazaApron",
            (80.0, 0.14, 16.0),
            (0.0, 0.58, 74.0),
            STONE,
            material="Slate",
            can_collide=False,
        )
    )
    # Red carpet approach in two segments around the fountain medallion
    # (height ladder: above apron / plaza stone).
    for seg, z, depth in (("N", 78.0, 20.0), ("S", 108.0, 16.0)):
        kids.append(
            part(
                f"PlazaCarpet_{seg}",
                (12.0, 0.14, depth),
                (0.0, 0.66, z),
                RED_CARPET,
                material="Fabric",
                can_collide=False,
            )
        )
        kids.append(
            part(
                f"PlazaCarpetGoldL_{seg}",
                (0.35, 0.08, depth),
                (-6.2, 0.74, z),
                GOLD,
                material="Metal",
                can_collide=False,
            )
        )
        kids.append(
            part(
                f"PlazaCarpetGoldR_{seg}",
                (0.35, 0.08, depth),
                (6.2, 0.74, z),
                GOLD,
                material="Metal",
                can_collide=False,
            )
        )
    # Side bypass carpets around fountain (queue split energy)
    for side, x in (("L", -10.0), ("R", 10.0)):
        kids.append(
            part(
                f"PlazaCarpetBypass_{side}",
                (6.0, 0.14, 14.0),
                (x, 0.66, 95.0),
                RED_CARPET,
                material="Fabric",
                can_collide=False,
            )
        )

    # Valet drive loop suggestion (curb ring)
    for i in range(16):
        ang = (i / 16.0) * math.tau
        rx, rz = 38.0, 22.0
        x = rx * math.cos(ang)
        z = 95.0 + rz * math.sin(ang)
        kids.append(
            part(
                f"ValetCurb_{i}",
                (5.5, 0.55, 1.4),
                (x, 0.55, z),
                GOLD_DIM,
                material="Concrete",
                can_collide=True,
                orientation=(0.0, -math.degrees(ang), 0.0),
            )
        )
    kids.append(
        part("ValetPad", (18.0, 0.12, 10.0), (0.0, 0.52, 108.0), [0.18, 0.18, 0.2], material="Asphalt", can_collide=False)
    )
    kids.append(
        part("ValetSignPost", (0.5, 4.0, 0.5), (-22.0, 2.2, 108.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part(
            "ValetSign",
            (3.5, 1.4, 0.3),
            (-22.0, 4.4, 108.0),
            MARBLE,
            material="Slate",
            can_collide=False,
            orientation=(0.0, 180.0, 0.0),
        )
    )
    kids.append(
        part(
            "ValetSignNeon",
            (3.7, 1.6, 0.15),
            (-22.0, 4.4, 108.25),
            CYAN,
            material="Neon",
            can_collide=False,
            transparency=0.2,
            orientation=(0.0, 180.0, 0.0),
        )
    )

    # Fountain / art feature
    kids.append(
        part("FountainBase", (14.0, 1.2, 14.0), (0.0, 0.9, 95.0), STONE, material="Slate", can_collide=True, shape="Cylinder")
    )
    kids.append(
        part("FountainRim", (15.2, 0.45, 15.2), (0.0, 1.55, 95.0), GOLD, material="Metal", can_collide=False, shape="Cylinder")
    )
    kids.append(
        part(
            "FountainWater",
            (12.0, 0.7, 12.0),
            (0.0, 1.35, 95.0),
            WATER,
            material="Glass",
            can_collide=False,
            shape="Cylinder",
            transparency=0.35,
        )
    )
    kids.append(
        part("FountainSpire", (1.8, 5.5, 1.8), (0.0, 4.2, 95.0), MARBLE, material="Slate", can_collide=False, shape="Cylinder")
    )
    kids.append(
        part("FountainOrb", (2.8, 2.8, 2.8), (0.0, 7.4, 95.0), CYAN, material="Neon", can_collide=False, shape="Ball", transparency=0.15)
    )
    kids.append(light_part("FountainLight", (0.0, 5.0, 95.0), CYAN, brightness=3.0, range_=35.0))

    # Lit planters
    planter_spots = [
        (-28.0, 78.0),
        (28.0, 78.0),
        (-28.0, 102.0),
        (28.0, 102.0),
        (-45.0, 90.0),
        (45.0, 90.0),
    ]
    for i, (px, pz) in enumerate(planter_spots):
        kids.append(
            part(f"Planter_{i}", (4.5, 1.6, 4.5), (px, 1.0, pz), STONE, material="Concrete", can_collide=True)
        )
        kids.append(
            part(f"PlanterGold_{i}", (4.8, 0.25, 4.8), (px, 1.85, pz), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(f"Plant_{i}", (2.2, 3.2, 2.2), (px, 3.5, pz), GREEN_PLANT, material="Grass", can_collide=False, shape="Cylinder")
        )
        kids.append(
            part(f"PlantTop_{i}", (3.2, 1.6, 3.2), (px, 5.2, pz), [0.1, 0.5, 0.25], material="Grass", can_collide=False, shape="Ball")
        )
        kids.append(light_part(f"PlanterLight_{i}", (px, 2.2, pz), WARM, brightness=1.6, range_=18.0, size=(0.3, 0.3, 0.3)))

    # Rope stanchions along carpet edges (queue energy, decorative only).
    # Skip fountain band so ropes do not cut the medallion.
    queue_zs = list(range(70, 88, 5)) + list(range(104, 116, 5))
    for i, z in enumerate(queue_zs):
        for side, x in (("L", -6.5), ("R", 6.5)):
            kids.append(
                part(f"QueueStanchion_{side}_{i}", (0.4, 2.2, 0.4), (x, 1.3, float(z)), GOLD, material="Metal", can_collide=False)
            )
            kids.append(
                part(
                    f"QueueTip_{side}_{i}",
                    (0.55, 0.25, 0.55),
                    (x, 2.5, float(z)),
                    GOLD,
                    material="Metal",
                    can_collide=False,
                    shape="Cylinder",
                )
            )
        kids.append(
            part(
                f"QueueRope_{i}",
                (12.6, 0.12, 0.12),
                (0.0, 2.15, float(z)),
                RED,
                material="Fabric",
                can_collide=False,
            )
        )

    # Plaza fill wash
    kids.append(light_part("PlazaWash_Center", (0.0, 12.0, 95.0), WARM, brightness=2.2, range_=50.0, size=(1.2, 1.2, 1.2)))
    kids.append(light_part("PlazaWash_S", (0.0, 8.0, 112.0), PURPLE, brightness=1.8, range_=35.0))

    return kids


# ---------------------------------------------------------------------------
# Phase B - Vestibule / entrance sequence
# ---------------------------------------------------------------------------


def build_vestibule() -> list:
    kids: list = []

    # Grand double doors (swung open, walkable center)
    kids.append(
        part(
            "Door_L",
            (5.5, 14.0, 0.45),
            (-8.5, 7.2, 65.2),
            MARBLE,
            material="Slate",
            can_collide=False,
            orientation=(0.0, 55.0, 0.0),
        )
    )
    kids.append(
        part(
            "Door_R",
            (5.5, 14.0, 0.45),
            (8.5, 7.2, 65.2),
            MARBLE,
            material="Slate",
            can_collide=False,
            orientation=(0.0, -55.0, 0.0),
        )
    )
    kids.append(
        part("DoorGold_L", (5.7, 14.3, 0.2), (-8.5, 7.2, 65.0), GOLD, material="Metal", can_collide=False, orientation=(0.0, 55.0, 0.0))
    )
    kids.append(
        part("DoorGold_R", (5.7, 14.3, 0.2), (8.5, 7.2, 65.0), GOLD, material="Metal", can_collide=False, orientation=(0.0, -55.0, 0.0))
    )
    # Glass panels on doors
    kids.append(
        part(
            "DoorGlass_L",
            (4.0, 10.0, 0.15),
            (-8.5, 7.5, 65.35),
            GLASS,
            material="Glass",
            can_collide=False,
            transparency=0.4,
            orientation=(0.0, 55.0, 0.0),
        )
    )
    kids.append(
        part(
            "DoorGlass_R",
            (4.0, 10.0, 0.15),
            (8.5, 7.5, 65.35),
            GLASS,
            material="Glass",
            can_collide=False,
            transparency=0.4,
            orientation=(0.0, -55.0, 0.0),
        )
    )

    # Door threshold + gold sill
    kids.append(part("Threshold", (22.0, 0.2, 2.5), (0.0, 0.62, 65.5), STONE, material="Slate", can_collide=False))
    kids.append(part("ThresholdGold", (22.5, 0.08, 0.4), (0.0, 0.74, 64.4), GOLD, material="Metal", can_collide=False))

    # Reception desk (east of aisle - keeps center sightline clear)
    kids.append(
        part("ReceptionDesk", (10.0, 3.2, 3.2), (18.0, 1.8, 56.0), MARBLE, material="Slate", can_collide=True)
    )
    kids.append(
        part("ReceptionTop", (10.4, 0.25, 3.5), (18.0, 3.5, 56.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("ReceptionFront", (10.0, 2.4, 0.25), (18.0, 2.0, 57.7), MARBLE_VEIN, material="Marble", can_collide=False)
    )
    kids.append(
        part("ReceptionNeon", (9.5, 0.2, 0.15), (18.0, 3.2, 57.85), CYAN, material="Neon", can_collide=False)
    )
    kids.append(light_part("ReceptionLight", (18.0, 5.5, 56.0), WARM, brightness=2.0, range_=22.0))

    # VIP rope cue west of aisle (mirrors reception)
    for i, z in enumerate((58.0, 54.0, 50.0)):
        kids.append(part(f"VipStanchion_{i}", (0.45, 2.3, 0.45), (-10.0, 1.35, z), GOLD, material="Metal", can_collide=False))
        kids.append(
            part(f"VipTip_{i}", (0.6, 0.28, 0.6), (-10.0, 2.6, z), GOLD, material="Metal", can_collide=False, shape="Cylinder")
        )
    kids.append(part("VipRope_0", (0.12, 0.12, 4.2), (-10.0, 2.2, 56.0), RED, material="Fabric", can_collide=False))
    kids.append(part("VipRope_1", (0.12, 0.12, 4.2), (-10.0, 2.2, 52.0), RED, material="Fabric", can_collide=False))
    kids.append(
        part(
            "VipSign",
            (3.2, 1.2, 0.25),
            (-10.0, 3.4, 54.0),
            MARBLE,
            material="Slate",
            can_collide=False,
            orientation=(0.0, -90.0, 0.0),
        )
    )
    kids.append(
        part(
            "VipSignNeon",
            (3.4, 1.4, 0.12),
            (-9.8, 3.4, 54.0),
            MAGENTA,
            material="Neon",
            can_collide=False,
            transparency=0.2,
            orientation=(0.0, -90.0, 0.0),
        )
    )

    # Foyer chandelier accent ring (extra presence near entry)
    kids.append(
        part("FoyerRing", (8.0, 0.4, 8.0), (0.0, 18.5, 58.0), GOLD, material="Metal", can_collide=False, shape="Cylinder")
    )
    kids.append(
        part("FoyerCrystal", (3.5, 2.5, 3.5), (0.0, 17.2, 58.0), WHITE, material="Glass", can_collide=False, transparency=0.25)
    )
    kids.append(light_part("FoyerChandelierLight", (0.0, 17.0, 58.0), WARM, brightness=3.2, range_=40.0, size=(1.0, 1.0, 1.0)))

    # Mirrored accent panels flanking entry inside
    for side, x in (("L", -20.0), ("R", 20.0)):
        kids.append(
            part(
                f"FoyerMirror_{side}",
                (0.25, 10.0, 8.0),
                (x, 7.0, 58.0),
                GLASS,
                material="Glass",
                can_collide=False,
                transparency=0.35,
                reflectance=0.4,
            )
        )
        kids.append(
            part(f"FoyerMirrorFrame_{side}", (0.35, 10.5, 8.5), (x + (-0.15 if side == "L" else 0.15), 7.0, 58.0), GOLD, material="Metal", can_collide=False)
        )

    return kids


# ---------------------------------------------------------------------------
# Phase C - Interior luxury
# ---------------------------------------------------------------------------


def build_luxury_trim() -> list:
    kids: list = []

    # Interior baseboards along pit long walls (inside face)
    kids.append(
        part("Baseboard_W", (0.35, 1.1, 118.0), (-90.5, 0.85, 0.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("Baseboard_E", (0.35, 1.1, 118.0), (90.5, 0.85, 0.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("Baseboard_S_L", (70.0, 1.1, 0.35), (-48.0, 0.85, 64.5), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("Baseboard_S_R", (70.0, 1.1, 0.35), (48.0, 0.85, 64.5), GOLD, material="Metal", can_collide=False)
    )

    # Dark marble wall veneers (thin, inset from exterior walls)
    kids.append(
        part("MarbleWall_W", (0.4, 18.0, 110.0), (-90.2, 10.0, 0.0), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("MarbleWall_E", (0.4, 18.0, 110.0), (90.2, 10.0, 0.0), MARBLE, material="Marble", can_collide=False)
    )
    # Mid cornice gold line
    kids.append(
        part("Cornice_W", (0.3, 0.35, 110.0), (-90.0, 18.5, 0.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("Cornice_E", (0.3, 0.35, 110.0), (90.0, 18.5, 0.0), GOLD, material="Metal", can_collide=False)
    )

    # Carpet border gold runners along main aisle edges (above red layer)
    for i, z in enumerate((-40.0, -20.0, 0.0, 20.0, 40.0)):
        kids.append(
            part(f"AisleGold_L_{i}", (0.3, 0.06, 16.0), (-8.2, 0.72, z), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(f"AisleGold_R_{i}", (0.3, 0.06, 16.0), (8.2, 0.72, z), GOLD, material="Metal", can_collide=False)
        )

    # VIP door frames for game rooms (additive gold around existing neon posts)
    door_specs = [
        ("Mines", -55.0, MAGENTA),
        ("Rocket", 0.0, CYAN),
        ("Plinko", 55.0, PURPLE),
    ]
    for name, x, accent in door_specs:
        kids.append(
            part(f"VipDoorFrame_{name}_L", (0.55, 14.0, 0.55), (x - 6.5, 7.2, -81.0), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(f"VipDoorFrame_{name}_R", (0.55, 14.0, 0.55), (x + 6.5, 7.2, -81.0), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(f"VipDoorFrame_{name}_Top", (13.5, 0.55, 0.55), (x, 14.4, -81.0), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(
                f"VipDoorAccent_{name}",
                (12.5, 0.3, 0.3),
                (x, 14.9, -80.7),
                accent,
                material="Neon",
                can_collide=False,
            )
        )

    # Game-hall wayfinding bar
    kids.append(
        part("WayfindingBar", (90.0, 1.8, 0.4), (0.0, 16.5, -68.0), MARBLE, material="Slate", can_collide=False)
    )
    kids.append(
        part("WayfindingNeon", (92.0, 2.1, 0.2), (0.0, 16.5, -67.7), PURPLE, material="Neon", can_collide=False, transparency=0.25)
    )

    # Wall art panels (abstract luxury, not logos)
    art_spots = [(-70.0, 30.0), (70.0, 30.0), (-70.0, -20.0), (70.0, -20.0)]
    accents = [CYAN, MAGENTA, PURPLE, GOLD]
    for i, ((ax, az), col) in enumerate(zip(art_spots, accents)):
        x = -89.6 if ax < 0 else 89.6
        kids.append(
            part(f"WallArt_{i}", (0.3, 6.0, 8.0), (x, 10.0, az), MARBLE_VEIN, material="Marble", can_collide=False)
        )
        kids.append(
            part(f"WallArtFrame_{i}", (0.35, 6.5, 8.5), (x + (-0.1 if ax < 0 else 0.1), 10.0, az), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(f"WallArtNeon_{i}", (0.2, 4.0, 5.0), (x + (-0.25 if ax < 0 else 0.25), 10.0, az), col, material="Neon", can_collide=False, transparency=0.3)
        )

    return kids


def build_coffers() -> list:
    kids: list = []
    # Grid of ceiling coffer frames under pit ceiling (y ~ 21)
    idx = 0
    for x in range(-60, 61, 30):
        for z in range(-40, 41, 25):
            kids.append(
                part(
                    f"Coffer_{idx}",
                    (22.0, 0.35, 18.0),
                    (float(x), 21.2, float(z)),
                    GOLD_DIM,
                    material="Metal",
                    can_collide=False,
                )
            )
            kids.append(
                part(
                    f"CofferInset_{idx}",
                    (18.0, 0.25, 14.0),
                    (float(x), 21.05, float(z)),
                    MARBLE,
                    material="Slate",
                    can_collide=False,
                )
            )
            idx += 1
    return kids


def build_cove_lights() -> list:
    kids: list = []
    # Perimeter cove neon under ceiling edge
    kids.append(
        part("Cove_N", (160.0, 0.3, 0.4), (0.0, 20.8, -52.0), WARM, material="Neon", can_collide=False, transparency=0.2)
    )
    kids.append(
        part("Cove_S", (160.0, 0.3, 0.4), (0.0, 20.8, 52.0), WARM, material="Neon", can_collide=False, transparency=0.2)
    )
    kids.append(
        part("Cove_W", (0.4, 0.3, 100.0), (-85.0, 20.8, 0.0), CYAN, material="Neon", can_collide=False, transparency=0.25)
    )
    kids.append(
        part("Cove_E", (0.4, 0.3, 100.0), (85.0, 20.8, 0.0), MAGENTA, material="Neon", can_collide=False, transparency=0.25)
    )
    kids.append(light_part("CoveWash_W", (-70.0, 18.0, 10.0), CYAN, brightness=1.4, range_=40.0))
    kids.append(light_part("CoveWash_E", (70.0, 18.0, 10.0), MAGENTA, brightness=1.4, range_=40.0))
    return kids


def build_pit_dressing() -> list:
    """Non-playable pit polish near known table bases - chip trays + dealer rails."""
    kids: list = []
    # Blackjack dealer-side chip trays (local +Z toward dealer on yaw0 tables)
    bj = [
        ("BJ_W1", -36.0, -8.0, 0.0),
        ("BJ_E1", 36.0, -8.0, 0.0),
        ("BJ_Entry_L", -26.0, 46.0, 0.0),
        ("BJ_Entry_R", 26.0, 46.0, 0.0),
        ("BJ_W2", -56.0, 28.0, 12.0),
        ("BJ_E2", 56.0, 28.0, -12.0),
    ]
    for name, cx, cz, yaw in bj:
        t = math.radians(yaw)
        # Dealer side offset in local -Z
        lx, lz = 0.0, -3.2
        x = cx + lx * math.cos(t) + lz * math.sin(t)
        z = cz - lx * math.sin(t) + lz * math.cos(t)
        kids.append(
            part(
                f"ChipTray_{name}",
                (2.4, 0.25, 1.1),
                (x, 2.35, z),
                GOLD_DIM,
                material="Metal",
                can_collide=False,
                orientation=(0.0, yaw, 0.0),
            )
        )
        kids.append(
            part(
                f"ChipTrayWell_{name}",
                (2.0, 0.2, 0.8),
                (x, 2.48, z),
                DARK,
                material="SmoothPlastic",
                can_collide=False,
                orientation=(0.0, yaw, 0.0),
            )
        )

    # Pit rail end caps near aisle (cleaner pit edge)
    for i, z in enumerate((-45.0, -25.0, -5.0, 15.0, 35.0)):
        for side, x in (("L", -8.0), ("R", 8.0)):
            kids.append(
                part(
                    f"PitRailCap_{side}_{i}",
                    (0.7, 1.35, 0.7),
                    (x, 1.2, z),
                    GOLD,
                    material="Metal",
                    can_collide=False,
                )
            )

    return kids


def build_bar_glow() -> list:
    """Additive lounge glow - does not replace LoungeBar core parts."""
    kids: list = []
    kids.append(
        part("BarCanopy", (3.5, 0.4, 28.0), (-84.0, 9.2, 18.0), MARBLE, material="Slate", can_collide=False)
    )
    kids.append(
        part("BarCanopyNeon", (3.0, 0.2, 26.0), (-83.7, 8.95, 18.0), MAGENTA, material="Neon", can_collide=False, transparency=0.2)
    )
    kids.append(
        part("BarBackGlow", (0.25, 6.0, 24.0), (-85.7, 6.0, 18.0), PURPLE, material="Neon", can_collide=False, transparency=0.45)
    )
    # Extra bottle row higher
    for i, bz in enumerate([7.0 + i * 2.6 for i in range(9)]):
        h = 1.0 + (i % 3) * 0.3
        kids.append(
            part(
                f"BarGlowBottle_{i}",
                (0.3, h, 0.3),
                (-85.4, 8.6 + h / 2, bz),
                [0.7, 0.2 + (i % 3) * 0.2, 0.35],
                material="Glass",
                can_collide=False,
                transparency=0.2,
            )
        )
    kids.append(light_part("BarWash", (-82.0, 7.0, 18.0), MAGENTA, brightness=2.4, range_=30.0))
    return kids


def relocate_brand_sign(lobby: dict) -> None:
    """Move BrandSign onto exterior marquee, facing south approach."""
    remove_named(lobby, "BrandSign")
    sign = {
        "name": "BrandSign",
        "className": "Part",
        "properties": {
            "Anchored": True,
            "Size": [46.0, 7.5, 1.4],
            "Position": [0.0, 28.5, 71.2],
            "Color": MARBLE,
            "Material": "Slate",
            # Face Front (+ approach from south): yaw 180 so local -Z -> world +Z
            "Orientation": [0.0, 180.0, 0.0],
        },
        "children": [
            part(
                "SignFrame",
                (48.0, 8.5, 0.45),
                (0.0, 28.5, 70.3),
                CYAN,
                material="Neon",
                can_collide=False,
                transparency=0.15,
            ),
            {
                "name": "SignLight",
                "className": "PointLight",
                "properties": {
                    "Brightness": 3.5,
                    "Range": 60.0,
                    "Color": CYAN,
                },
            },
        ],
    }
    lobby.setdefault("children", []).append(sign)


def update_spawn(lobby: dict) -> None:
    hub = find(lobby, "HubSpawn")
    if hub and hub.get("properties"):
        hub["properties"]["Position"] = list(SPAWN_POS)
        # Face north (-Z) into the casino. Spawn Front is local -Z.
        hub["properties"]["Orientation"] = [0.0, 0.0, 0.0]
    # Keep spawn ring / light as children; nudge if present
    if hub:
        for child in hub.get("children") or []:
            props = child.get("properties") or {}
            if "Position" in props and child.get("name") == "SpawnRing":
                props["Position"] = [SPAWN_POS[0], 0.7, SPAWN_POS[2]]
            if child.get("name") == "SpawnLight" and child.get("className") == "PointLight":
                pass


def upgrade_entry_columns(walls: dict) -> None:
    """Enrich existing entry columns with gold capitals (mutate in place)."""
    for child in walls.get("children") or []:
        name = child.get("name") or ""
        props = child.get("properties") or {}
        if name in ("Entry_Column_L", "Entry_Column_R"):
            props["Material"] = "Slate"
            props["Color"] = MARBLE
            # Taller presence
            props["Size"] = [3.8, 28.0, 3.8]
            pos = props.get("Position") or [0, 13, 64.5]
            props["Position"] = [pos[0], 14.0, 64.2]
        if name in ("Entry_ColNeon_L", "Entry_ColNeon_R"):
            props["Size"] = [0.5, 26.0, 0.5]
            pos = props.get("Position") or [0, 13, 66.3]
            props["Position"] = [pos[0], 14.0, 66.5]
            props["Color"] = GOLD
        if name == "Entry_Marquee":
            # Superseded by Exterior marquee; hide old thin strip by shrinking / pushing
            props["Transparency"] = 1.0
            props["CanCollide"] = False


def upgrade_existing_stanchions(stanchions: dict) -> None:
    """Repurpose interior Structure.Stanchions as VIP foyer set (clear of plaza queue)."""
    clear_folder(stanchions)
    # Kept empty - vestibule owns VIP rope now to avoid duplicate props.


def add_fill_lights(lobby: dict) -> None:
    fill = find(lobby, "FillLights")
    if not fill:
        return
    # Remove prior polish washes if re-run
    kids = fill.setdefault("children", [])
    fill["children"] = [c for c in kids if not str(c.get("name") or "").startswith("Wash_Plaza") and not str(c.get("name") or "").startswith("Wash_Facade") and not str(c.get("name") or "").startswith("Wash_Foyer")]
    fill["children"].append(light_part("Wash_Plaza", (0.0, 10.0, 95.0), WARM, brightness=2.0, range_=55.0, size=(2.0, 2.0, 2.0)))
    fill["children"].append(light_part("Wash_Facade", (0.0, 22.0, 78.0), CYAN, brightness=2.5, range_=50.0, size=(2.0, 2.0, 2.0)))
    fill["children"].append(light_part("Wash_Foyer", (0.0, 12.0, 58.0), WARM, brightness=2.2, range_=35.0, size=(1.5, 1.5, 1.5)))


def main() -> None:
    data = json.loads(LOBBY.read_text())
    lobby = data  # root Folder is Lobby contents (unnamed in file)
    structure = find(data, "Structure")
    atmosphere = find(data, "Atmosphere")
    walls = find(data, "Walls")
    stanchions = find(data, "Stanchions")
    assert structure and atmosphere and walls

    # Idempotent cleanup of polish folders
    for parent in (structure, atmosphere):
        for name in POLISH_FOLDERS:
            remove_named(parent, name)

    # Phase A
    exterior = ensure_folder(structure, "Exterior")
    clear_folder(exterior)
    exterior["children"] = build_exterior()

    plaza = ensure_folder(atmosphere, "Plaza")
    clear_folder(plaza)
    plaza["children"] = build_plaza()

    relocate_brand_sign(lobby)
    update_spawn(lobby)
    upgrade_entry_columns(walls)
    if stanchions:
        upgrade_existing_stanchions(stanchions)

    # Phase B
    vestibule = ensure_folder(atmosphere, "Vestibule")
    clear_folder(vestibule)
    vestibule["children"] = build_vestibule()

    # Phase C
    luxury = ensure_folder(structure, "LuxuryTrim")
    clear_folder(luxury)
    luxury["children"] = build_luxury_trim()

    coffers = ensure_folder(structure, "Coffers")
    clear_folder(coffers)
    coffers["children"] = build_coffers()

    cove = ensure_folder(structure, "CoveLights")
    clear_folder(cove)
    cove["children"] = build_cove_lights()

    pit = ensure_folder(atmosphere, "PitDressing")
    clear_folder(pit)
    pit["children"] = build_pit_dressing()

    bar_glow = ensure_folder(atmosphere, "BarGlow")
    clear_folder(bar_glow)
    bar_glow["children"] = build_bar_glow()

    add_fill_lights(lobby)

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Wrote {LOBBY}")
    print(f"  Exterior parts: {len(exterior['children'])}")
    print(f"  Plaza parts: {len(plaza['children'])}")
    print(f"  Vestibule parts: {len(vestibule['children'])}")
    print(f"  LuxuryTrim parts: {len(luxury['children'])}")
    print(f"  Spawn -> {SPAWN_POS}")


if __name__ == "__main__":
    main()
