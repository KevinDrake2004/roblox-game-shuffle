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
GRASS = [0.18, 0.42, 0.16]
GLASS = [0.55, 0.75, 0.85]
WHITE = [0.95, 0.93, 0.88]
WARM = [1.0, 0.85, 0.55]

# Envelope (unchanged)
WALL_Z_S = 66.0
WALL_X = 92.0
ENTRY_HALF = 12.0  # clear opening roughly |x| < 12

# Plaza / facade extents (south of building)
PLAZA_Z0 = 66.5
PLAZA_Z1 = 124.0
SPAWN_POS = [0.0, 3.0, 112.0]
# Continuous approach carpet (half-width); stanchions sit just outside edges.
CARPET_HALF = 5.0
STANCHION_X = 5.6
FOUNTAIN_POS = (28.0, 92.0)  # east of carpet so the walk line stays clear

POLISH_FOLDERS = (
    "Exterior",
    "Plaza",
    "Vestibule",
    "Ground",
    "SiteLighting",
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


def light_part(name: str, pos, color, *, brightness=2.0, range_=28.0) -> dict:
    """Fully invisible PointLight host - never leave neon cubes floating in world."""
    p = part(name, (0.2, 0.2, 0.2), pos, color, material="SmoothPlastic", can_collide=False, transparency=1.0)
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


def spot_part(
    name: str,
    pos,
    color,
    *,
    brightness=3.0,
    range_=40.0,
    angle=70.0,
    orientation=(0.0, 0.0, 0.0),
) -> dict:
    """Invisible SpotLight host. Face=Front (-Z local). Use orientation to aim.

    Downward wash: orientation=(-90, yaw, 0) so Front points world -Y.
    Facade wash from plaza: orientation=(0, 0, 0) aims world -Z (north).
    """
    p = part(name, (0.2, 0.2, 0.2), pos, color, material="SmoothPlastic", can_collide=False, transparency=1.0)
    p["properties"]["Orientation"] = [float(o) for o in orientation]
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
    return p


def street_lamp(name: str, x: float, z: float, *, yaw: float = 0.0) -> list:
    """Visible lamp post with warm PointLight. Does not collide with players."""
    kids: list = []
    # Base + pole
    kids.append(part(f"{name}_Base", (1.2, 0.35, 1.2), (x, 0.4, z), STONE, material="Concrete", can_collide=False))
    kids.append(
        part(f"{name}_Pole", (0.35, 12.0, 0.35), (x, 6.4, z), [0.12, 0.12, 0.14], material="Metal", can_collide=False)
    )
    kids.append(part(f"{name}_Collar", (0.55, 0.25, 0.55), (x, 12.2, z), GOLD, material="Metal", can_collide=False))
    # Arm reaches toward plaza/path (local +Z after yaw)
    t = math.radians(yaw)
    arm_len = 2.4
    ax = x + arm_len * 0.5 * math.sin(t)
    az = z + arm_len * 0.5 * math.cos(t)
    kids.append(
        part(
            f"{name}_Arm",
            (0.25, 0.25, arm_len),
            (ax, 12.35, az),
            [0.12, 0.12, 0.14],
            material="Metal",
            can_collide=False,
            orientation=(0.0, yaw, 0.0),
        )
    )
    hx = x + arm_len * math.sin(t)
    hz = z + arm_len * math.cos(t)
    kids.append(
        part(f"{name}_Head", (1.1, 0.55, 1.1), (hx, 12.1, hz), [0.08, 0.08, 0.1], material="Metal", can_collide=False)
    )
    # Soft visible lamp glass (small, intentional - not a floating wash cube)
    kids.append(
        part(
            f"{name}_Glow",
            (0.7, 0.35, 0.7),
            (hx, 11.85, hz),
            WARM,
            material="Neon",
            can_collide=False,
            transparency=0.15,
        )
    )
    kids.append(light_part(f"{name}_Light", (hx, 11.5, hz), WARM, brightness=2.8, range_=48.0))
    return kids


def roof_down_spot(name: str, x: float, y: float, z: float, *, yaw: float = 0.0) -> dict:
    """Roof-mounted spotlight aimed straight down onto walkable ground."""
    return spot_part(
        name,
        (x, y, z),
        WARM,
        brightness=5.0,
        range_=70.0,
        angle=80.0,
        orientation=(-90.0, yaw, 0.0),
    )


def build_site_lighting() -> list:
    """Street lamps + roof-down spots covering plaza and grass perimeter."""
    kids: list = []

    # --- Street lamps along plaza approach (arms face inward toward carpet) ---
    plaza_lamps = [
        # west row (yaw 90 → arm toward +X / carpet)
        ("PlazaW0", -18.0, 72.0, 90.0),
        ("PlazaW1", -18.0, 88.0, 90.0),
        ("PlazaW2", -18.0, 104.0, 90.0),
        ("PlazaW3", -18.0, 120.0, 90.0),
        # east row (yaw -90 → arm toward -X / carpet)
        ("PlazaE0", 18.0, 72.0, -90.0),
        ("PlazaE1", 18.0, 88.0, -90.0),
        ("PlazaE2", 18.0, 104.0, -90.0),
        ("PlazaE3", 18.0, 120.0, -90.0),
    ]
    for name, x, z, yaw in plaza_lamps:
        kids.extend(street_lamp(name, x, z, yaw=yaw))

    # --- Perimeter lamps for walking around the building ---
    # South grass / path (arms face north toward building)
    for i, x in enumerate((-90.0, -45.0, 0.0, 45.0, 90.0)):
        kids.extend(street_lamp(f"PerimS{i}", x, 138.0, yaw=180.0))
    # North grass / path (arms face south)
    for i, x in enumerate((-90.0, -45.0, 0.0, 45.0, 90.0)):
        kids.extend(street_lamp(f"PerimN{i}", x, -158.0, yaw=0.0))
    # West path (arms face east)
    for i, z in enumerate((-120.0, -60.0, 0.0, 40.0, 100.0)):
        kids.extend(street_lamp(f"PerimW{i}", -120.0, z, yaw=90.0))
    # East path (arms face west)
    for i, z in enumerate((-120.0, -60.0, 0.0, 40.0, 100.0)):
        kids.extend(street_lamp(f"PerimE{i}", 120.0, z, yaw=-90.0))

    # --- Roof-edge spotlights aimed straight down ---
    # South parapet / canopy line over plaza
    for i, x in enumerate((-70.0, -35.0, 0.0, 35.0, 70.0)):
        kids.append(roof_down_spot(f"RoofSpot_S{i}", x, 24.5, 68.5))
    # Canopy underside extras over porte-cochere
    for i, x in enumerate((-12.0, 12.0)):
        kids.append(roof_down_spot(f"RoofSpot_Canopy{i}", x, 18.2, 78.0))
    # East / west pit-roof edges
    for i, z in enumerate((-40.0, -10.0, 20.0, 50.0)):
        kids.append(roof_down_spot(f"RoofSpot_W{i}", -90.0, 23.5, z))
        kids.append(roof_down_spot(f"RoofSpot_E{i}", 90.0, 23.5, z))
    # North game-room roof edge over north path
    for i, x in enumerate((-70.0, -35.0, 0.0, 35.0, 70.0)):
        kids.append(roof_down_spot(f"RoofSpot_N{i}", x, 54.0, -138.0))
    # Corner down-spots for apron coverage
    for i, (x, z) in enumerate(((-100.0, 70.0), (100.0, 70.0), (-100.0, -130.0), (100.0, -130.0))):
        kids.append(roof_down_spot(f"RoofSpot_Corner{i}", x, 24.0, z))

    # Soft ambient fills over open grass (invisible hosts only)
    for i, (x, z) in enumerate(
        (
            (0.0, 130.0),
            (0.0, -155.0),
            (-115.0, -20.0),
            (115.0, -20.0),
            (-60.0, 110.0),
            (60.0, 110.0),
            (-60.0, -100.0),
            (60.0, -100.0),
        )
    ):
        kids.append(light_part(f"GrassFill_{i}", (x, 14.0, z), WARM, brightness=1.6, range_=55.0))

    return kids



def stanchion_pair(prefix: str, x: float, z: float) -> list:
    """Gold post + tip at one carpet edge."""
    return [
        part(f"{prefix}", (0.35, 2.4, 0.35), (x, 1.4, z), GOLD, material="Metal", can_collide=False),
        part(
            f"{prefix}Tip",
            (0.5, 0.22, 0.5),
            (x, 2.7, z),
            GOLD,
            material="Metal",
            can_collide=False,
            shape="Cylinder",
        ),
    ]


def side_rope(name: str, x: float, z0: float, z1: float) -> dict:
    """Velvet rope along one carpet edge between two Z posts (not across the walk)."""
    z_mid = (z0 + z1) * 0.5
    depth = abs(z1 - z0)
    return part(name, (0.1, 0.1, depth), (x, 2.25, z_mid), RED, material="Fabric", can_collide=False)


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
    kids.append(light_part("MarqueeWash", (0.0, 26.0, 74.0), CYAN, brightness=3.5, range_=55.0))

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
    fx, fz = FOUNTAIN_POS

    # Hard plaza pad under porte-cochere / approach (sits above world grass)
    kids.append(
        part(
            "PlazaFloor",
            (120.0, 1.0, 58.0),
            (0.0, 0.0, 95.0),
            ASPHALT,
            material="Asphalt",
            can_collide=True,
        )
    )
    kids.append(
        part(
            "PlazaApron",
            (56.0, 0.14, 18.0),
            (0.0, 0.58, 74.0),
            STONE,
            material="Slate",
            can_collide=False,
        )
    )

    # Continuous red carpet from spawn to doors (clear center walk)
    carpet_z0, carpet_z1 = 67.0, 118.0
    carpet_depth = carpet_z1 - carpet_z0
    carpet_cz = (carpet_z0 + carpet_z1) * 0.5
    kids.append(
        part(
            "PlazaCarpet",
            (CARPET_HALF * 2, 0.14, carpet_depth),
            (0.0, 0.66, carpet_cz),
            RED_CARPET,
            material="Fabric",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PlazaCarpetGoldL",
            (0.3, 0.08, carpet_depth),
            (-CARPET_HALF - 0.05, 0.74, carpet_cz),
            GOLD,
            material="Metal",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PlazaCarpetGoldR",
            (0.3, 0.08, carpet_depth),
            (CARPET_HALF + 0.05, 0.74, carpet_cz),
            GOLD,
            material="Metal",
            can_collide=False,
        )
    )

    # Side-only velvet ropes (connect posts along Z - never across the walk)
    queue_zs = [68.0, 76.0, 84.0, 92.0, 100.0, 108.0, 116.0]
    for i, z in enumerate(queue_zs):
        kids.extend(stanchion_pair(f"QueueStanchion_L_{i}", -STANCHION_X, z))
        kids.extend(stanchion_pair(f"QueueStanchion_R_{i}", STANCHION_X, z))
        if i > 0:
            kids.append(side_rope(f"QueueRope_L_{i}", -STANCHION_X, queue_zs[i - 1], z))
            kids.append(side_rope(f"QueueRope_R_{i}", STANCHION_X, queue_zs[i - 1], z))

    # Valet drop-off pad south of fountain (simple curb, not a noisy ring)
    kids.append(
        part("ValetPad", (28.0, 0.12, 14.0), (0.0, 0.52, 118.0), [0.16, 0.16, 0.18], material="Asphalt", can_collide=False)
    )
    kids.append(part("ValetCurbN", (30.0, 0.45, 0.7), (0.0, 0.45, 125.0), GOLD_DIM, material="Concrete", can_collide=True))
    kids.append(part("ValetCurbS", (30.0, 0.45, 0.7), (0.0, 0.45, 111.0), GOLD_DIM, material="Concrete", can_collide=True))
    kids.append(part("ValetCurbL", (0.7, 0.45, 14.0), (-15.0, 0.45, 118.0), GOLD_DIM, material="Concrete", can_collide=True))
    kids.append(part("ValetCurbR", (0.7, 0.45, 14.0), (15.0, 0.45, 118.0), GOLD_DIM, material="Concrete", can_collide=True))
    kids.append(
        part("ValetSignPost", (0.5, 4.0, 0.5), (-18.0, 2.2, 118.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part(
            "ValetSign",
            (3.5, 1.4, 0.3),
            (-18.0, 4.4, 118.0),
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
            (-18.0, 4.4, 118.25),
            CYAN,
            material="Neon",
            can_collide=False,
            transparency=0.2,
            orientation=(0.0, 180.0, 0.0),
        )
    )

    # Grand plaza fountain (east of carpet - always visible from approach)
    kids.append(
        part(
            "FountainPlaza",
            (18.0, 0.6, 18.0),
            (fx, 0.55, fz),
            STONE,
            material="Slate",
            can_collide=True,
            shape="Cylinder",
        )
    )
    kids.append(
        part(
            "FountainBase",
            (14.0, 1.4, 14.0),
            (fx, 1.1, fz),
            MARBLE,
            material="Marble",
            can_collide=True,
            shape="Cylinder",
        )
    )
    kids.append(
        part(
            "FountainRim",
            (15.5, 0.5, 15.5),
            (fx, 1.85, fz),
            GOLD,
            material="Metal",
            can_collide=False,
            shape="Cylinder",
        )
    )
    kids.append(
        part(
            "FountainWater",
            (12.5, 0.85, 12.5),
            (fx, 1.55, fz),
            WATER,
            material="Glass",
            can_collide=False,
            shape="Cylinder",
            transparency=0.3,
        )
    )
    kids.append(
        part(
            "FountainTier",
            (7.0, 1.0, 7.0),
            (fx, 2.6, fz),
            MARBLE,
            material="Marble",
            can_collide=False,
            shape="Cylinder",
        )
    )
    kids.append(
        part(
            "FountainSpire",
            (1.6, 6.0, 1.6),
            (fx, 5.5, fz),
            GOLD,
            material="Metal",
            can_collide=False,
            shape="Cylinder",
        )
    )
    kids.append(
        part(
            "FountainOrb",
            (3.2, 3.2, 3.2),
            (fx, 9.0, fz),
            CYAN,
            material="Neon",
            can_collide=False,
            shape="Ball",
            transparency=0.12,
        )
    )
    kids.append(light_part("FountainLight", (fx, 6.0, fz), CYAN, brightness=3.2, range_=40.0))
    # Matching west planter island so the approach stays balanced
    wx = -fx
    kids.append(
        part("WestIsland", (14.0, 0.55, 14.0), (wx, 0.5, fz), STONE, material="Slate", can_collide=True, shape="Cylinder")
    )
    kids.append(
        part("WestPlanter", (8.0, 1.8, 8.0), (wx, 1.2, fz), STONE, material="Concrete", can_collide=True, shape="Cylinder")
    )
    kids.append(
        part("WestPlant", (5.0, 4.5, 5.0), (wx, 4.2, fz), GREEN_PLANT, material="Grass", can_collide=False, shape="Cylinder")
    )
    kids.append(
        part("WestPlantTop", (6.5, 3.0, 6.5), (wx, 6.8, fz), [0.12, 0.48, 0.22], material="Grass", can_collide=False, shape="Ball")
    )
    kids.append(light_part("WestIslandLight", (wx, 3.0, fz), WARM, brightness=1.8, range_=22.0))

    # Lit planters flanking canopy
    planter_spots = [(-22.0, 78.0), (22.0, 78.0), (-22.0, 105.0), (22.0, 105.0)]
    for i, (px, pz) in enumerate(planter_spots):
        kids.append(part(f"Planter_{i}", (4.2, 1.5, 4.2), (px, 1.0, pz), STONE, material="Concrete", can_collide=True))
        kids.append(part(f"PlanterGold_{i}", (4.5, 0.22, 4.5), (px, 1.8, pz), GOLD, material="Metal", can_collide=False))
        kids.append(
            part(f"Plant_{i}", (2.0, 3.0, 2.0), (px, 3.4, pz), GREEN_PLANT, material="Grass", can_collide=False, shape="Cylinder")
        )
        kids.append(
            part(
                f"PlantTop_{i}",
                (3.0, 1.5, 3.0),
                (px, 5.0, pz),
                [0.1, 0.5, 0.25],
                material="Grass",
                can_collide=False,
                shape="Ball",
            )
        )
        kids.append(light_part(f"PlanterLight_{i}", (px, 2.4, pz), WARM, brightness=1.5, range_=16.0))

    kids.append(light_part("PlazaWash_Center", (0.0, 12.0, 95.0), WARM, brightness=2.0, range_=50.0))
    kids.append(light_part("PlazaWash_S", (0.0, 8.0, 118.0), PURPLE, brightness=1.6, range_=35.0))

    return kids


def build_ground() -> list:
    """Walkable grass apron around the whole casino footprint."""
    kids: list = []
    # Large collide grass under/around everything. Building MainFloor + PlazaFloor sit on top.
    kids.append(
        part(
            "WorldGrass",
            (420.0, 1.0, 420.0),
            (0.0, -0.55, -20.0),
            GRASS,
            material="Grass",
            can_collide=True,
        )
    )
    # Soft path ring outside plaza asphalt so players can circle the building
    kids.append(
        part(
            "PerimeterPath_S",
            (220.0, 0.2, 18.0),
            (0.0, 0.05, 130.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PerimeterPath_N",
            (220.0, 0.2, 18.0),
            (0.0, 0.05, -155.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PerimeterPath_W",
            (18.0, 0.2, 280.0),
            (-115.0, 0.05, -20.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PerimeterPath_E",
            (18.0, 0.2, 280.0),
            (115.0, 0.05, -20.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )
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

    kids.append(part("Threshold", (22.0, 0.2, 2.5), (0.0, 0.62, 65.5), STONE, material="Slate", can_collide=False))
    kids.append(part("ThresholdGold", (22.5, 0.08, 0.4), (0.0, 0.74, 64.4), GOLD, material="Metal", can_collide=False))

    # Reception desk - just inside doors, east of carpet, tall + labeled
    rx, rz = 15.0, 60.0
    kids.append(part("ReceptionDesk", (9.0, 3.6, 3.6), (rx, 2.0, rz), MARBLE, material="Slate", can_collide=True))
    kids.append(part("ReceptionTop", (9.5, 0.3, 4.0), (rx, 3.9, rz), GOLD, material="Metal", can_collide=False))
    kids.append(part("ReceptionFront", (9.0, 2.8, 0.3), (rx, 2.2, rz + 1.95), MARBLE_VEIN, material="Marble", can_collide=False))
    kids.append(part("ReceptionNeon", (8.5, 0.25, 0.18), (rx, 3.55, rz + 2.1), CYAN, material="Neon", can_collide=False))
    kids.append(part("ReceptionBack", (0.35, 5.5, 3.6), (rx + 4.7, 4.0, rz), MARBLE, material="Slate", can_collide=False))
    # Billboard-facing sign toward the aisle (Front = +X toward carpet after yaw -90)
    kids.append(
        part(
            "ReceptionSign",
            (4.5, 1.4, 0.3),
            (rx - 0.2, 5.2, rz + 2.3),
            MARBLE,
            material="Slate",
            can_collide=False,
            orientation=(0.0, 180.0, 0.0),
        )
    )
    kids.append(
        part(
            "ReceptionSignNeon",
            (4.8, 1.65, 0.15),
            (rx - 0.2, 5.2, rz + 2.45),
            CYAN,
            material="Neon",
            can_collide=False,
            transparency=0.2,
            orientation=(0.0, 180.0, 0.0),
        )
    )
    kids.append(light_part("ReceptionLight", (rx, 6.0, rz), WARM, brightness=2.4, range_=24.0))

    # VIP lounge cue - west of carpet, opposite reception (clear podium + rope pen)
    vx, vz = -15.0, 60.0
    kids.append(part("VipPodium", (8.0, 0.45, 10.0), (vx, 0.75, vz), MARBLE, material="Slate", can_collide=True))
    kids.append(part("VipPodiumGold", (8.4, 0.12, 10.4), (vx, 1.0, vz), GOLD, material="Metal", can_collide=False))
    vip_posts = [(-18.5, 64.5), (-11.5, 64.5), (-18.5, 55.5), (-11.5, 55.5)]
    for i, (px, pz) in enumerate(vip_posts):
        kids.extend(stanchion_pair(f"VipStanchion_{i}", px, pz))
    # Ropes around the VIP pen (rectangle)
    kids.append(part("VipRope_N", (7.0, 0.1, 0.1), (vx, 2.25, 64.5), RED, material="Fabric", can_collide=False))
    kids.append(part("VipRope_S", (7.0, 0.1, 0.1), (vx, 2.25, 55.5), RED, material="Fabric", can_collide=False))
    kids.append(part("VipRope_W", (0.1, 0.1, 9.0), (-18.5, 2.25, vz), RED, material="Fabric", can_collide=False))
    kids.append(part("VipRope_E", (0.1, 0.1, 9.0), (-11.5, 2.25, vz), RED, material="Fabric", can_collide=False))
    kids.append(
        part(
            "VipSign",
            (4.0, 1.5, 0.3),
            (vx, 4.0, 65.0),
            MARBLE,
            material="Slate",
            can_collide=False,
            orientation=(0.0, 180.0, 0.0),
        )
    )
    kids.append(
        part(
            "VipSignNeon",
            (4.3, 1.75, 0.15),
            (vx, 4.0, 65.2),
            MAGENTA,
            material="Neon",
            can_collide=False,
            transparency=0.15,
            orientation=(0.0, 180.0, 0.0),
        )
    )
    kids.append(light_part("VipLight", (vx, 5.0, vz), MAGENTA, brightness=2.0, range_=20.0))

    # Foyer chandelier accent
    kids.append(
        part("FoyerRing", (8.0, 0.4, 8.0), (0.0, 18.5, 58.0), GOLD, material="Metal", can_collide=False, shape="Cylinder")
    )
    kids.append(
        part("FoyerCrystal", (3.5, 2.5, 3.5), (0.0, 17.2, 58.0), WHITE, material="Glass", can_collide=False, transparency=0.25)
    )
    kids.append(light_part("FoyerChandelierLight", (0.0, 17.0, 58.0), WARM, brightness=3.2, range_=40.0))

    # Mirrored accent panels flanking entry inside
    for side, x in (("L", -22.0), ("R", 22.0)):
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
            part(
                f"FoyerMirrorFrame_{side}",
                (0.35, 10.5, 8.5),
                (x + (-0.15 if side == "L" else 0.15), 7.0, 58.0),
                GOLD,
                material="Metal",
                can_collide=False,
            )
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
    """Enrich existing entry columns; drop superseded Entry_Marquee strip."""
    kept = []
    for child in walls.get("children") or []:
        name = child.get("name") or ""
        props = child.get("properties") or {}
        if name == "Entry_Marquee":
            continue  # replaced by Structure.Exterior marquee
        if name in ("Entry_Column_L", "Entry_Column_R"):
            props["Material"] = "Slate"
            props["Color"] = MARBLE
            props["Size"] = [3.8, 28.0, 3.8]
            pos = props.get("Position") or [0, 13, 64.5]
            props["Position"] = [pos[0], 14.0, 64.2]
        if name in ("Entry_ColNeon_L", "Entry_ColNeon_R"):
            props["Size"] = [0.5, 26.0, 0.5]
            pos = props.get("Position") or [0, 13, 66.3]
            props["Position"] = [pos[0], 14.0, 66.5]
            props["Color"] = GOLD
        kept.append(child)
    walls["children"] = kept


def upgrade_existing_stanchions(stanchions: dict) -> None:
    """Clear legacy Structure.Stanchions - vestibule/plaza own rope props now."""
    clear_folder(stanchions)


def scrub_light_hosts(node: dict) -> None:
    """Force pure PointLight/SpotLight host parts fully invisible (no floating cubes).

    Skips parts that also parent geometry (e.g. BrandSign -> SignFrame + SignLight).
    """
    kids = node.get("children") or []
    light_kids = [c for c in kids if c.get("className") in ("PointLight", "SpotLight")]
    geo_kids = [c for c in kids if c.get("className") not in ("PointLight", "SpotLight", None) or c.get("className") == "Part"]
    # Only lights as children (ignore empty) -> host part
    only_lights = bool(light_kids) and all(c.get("className") in ("PointLight", "SpotLight") for c in kids)
    props = node.get("properties")
    if only_lights and props is not None and node.get("className") == "Part":
        props["Transparency"] = 1.0
        props["CanCollide"] = False
        props["Material"] = "SmoothPlastic"
        props["Size"] = [0.2, 0.2, 0.2]
    for child in kids:
        scrub_light_hosts(child)


def add_fill_lights(lobby: dict) -> None:
    fill = find(lobby, "FillLights")
    if not fill:
        return
    kids = fill.setdefault("children", [])
    fill["children"] = [
        c
        for c in kids
        if not str(c.get("name") or "").startswith("Wash_Plaza")
        and not str(c.get("name") or "").startswith("Wash_Facade")
        and not str(c.get("name") or "").startswith("Wash_Foyer")
    ]
    fill["children"].append(light_part("Wash_Plaza", (0.0, 10.0, 95.0), WARM, brightness=2.0, range_=55.0))
    fill["children"].append(light_part("Wash_Facade", (0.0, 22.0, 78.0), CYAN, brightness=2.5, range_=50.0))
    fill["children"].append(light_part("Wash_Foyer", (0.0, 12.0, 58.0), WARM, brightness=2.2, range_=35.0))
    scrub_light_hosts(fill)


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

    ground = ensure_folder(atmosphere, "Ground")
    clear_folder(ground)
    ground["children"] = build_ground()

    site_lights = ensure_folder(atmosphere, "SiteLighting")
    clear_folder(site_lights)
    site_lights["children"] = build_site_lighting()

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
    scrub_light_hosts(data)

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Wrote {LOBBY}")
    print(f"  Exterior parts: {len(exterior['children'])}")
    print(f"  Plaza parts: {len(plaza['children'])}")
    print(f"  Ground parts: {len(ground['children'])}")
    print(f"  SiteLighting parts: {len(site_lights['children'])}")
    print(f"  Vestibule parts: {len(vestibule['children'])}")
    print(f"  LuxuryTrim parts: {len(luxury['children'])}")
    print(f"  Spawn -> {SPAWN_POS}")


if __name__ == "__main__":
    main()
