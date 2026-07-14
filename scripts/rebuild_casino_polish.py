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


def wedge_part(
    name: str,
    size,
    pos,
    color,
    *,
    material: str = "Grass",
    can_collide: bool = True,
    orientation=None,
    transparency=None,
) -> dict:
    """WedgePart for terrain berms / slopes (same props as part)."""
    node = part(
        name,
        size,
        pos,
        color,
        material=material,
        can_collide=can_collide,
        orientation=orientation,
        transparency=transparency,
    )
    node["className"] = "WedgePart"
    return node


# Mesh accent helpers. Prefer SpecialMesh MeshType (always loads). FileMesh IDs
# below are optional catalog accents - swap freely and document in docs/CASINO.md.
MESH_DIAMOND = "rbxassetid://67524904"  # optional gem mesh; Sphere fallback used if unavailable


def mesh_part(
    name: str,
    size,
    pos,
    color,
    mesh_id: str,
    *,
    material: str = "SmoothPlastic",
    can_collide: bool = False,
    orientation=None,
    transparency=None,
    texture_id: str | None = None,
) -> dict:
    """MeshPart authored for Rojo sync (MeshId set at load time, not runtime scripts)."""
    props = {
        "Anchored": True,
        "Size": [float(size[0]), float(size[1]), float(size[2])],
        "Position": [float(pos[0]), float(pos[1]), float(pos[2])],
        "Color": [float(c) for c in color],
        "Material": material,
        "CanCollide": can_collide,
        "MeshId": mesh_id,
    }
    if orientation is not None:
        props["Orientation"] = [float(o) for o in orientation]
    if transparency is not None:
        props["Transparency"] = float(transparency)
    if texture_id is not None:
        props["TextureID"] = texture_id
    return {"name": name, "className": "MeshPart", "properties": props}


def special_mesh_part(
    name: str,
    size,
    pos,
    color,
    *,
    mesh_type: str = "Cylinder",
    mesh_id: str | None = None,
    mesh_scale=None,
    material: str = "SmoothPlastic",
    can_collide: bool = False,
    orientation=None,
    transparency=None,
) -> dict:
    """Part + SpecialMesh (reliable Rojo path for FileMesh / Cylinder / Sphere)."""
    p = part(
        name,
        size,
        pos,
        color,
        material=material,
        can_collide=can_collide,
        orientation=orientation,
        transparency=transparency,
    )
    mesh_props: dict = {"MeshType": mesh_type}
    if mesh_id is not None:
        mesh_props["MeshType"] = "FileMesh"
        mesh_props["MeshId"] = mesh_id
    if mesh_scale is not None:
        mesh_props["Scale"] = [float(mesh_scale[0]), float(mesh_scale[1]), float(mesh_scale[2])]
    p["children"] = [{"name": "Mesh", "className": "SpecialMesh", "properties": mesh_props}]
    return p


def classical_column(name: str, x: float, z: float, *, height: float = 18.0, yaw: float = 0.0) -> list:
    """Hotel-casino column: fluted shaft, gold base/capital. Walk channel stays clear."""
    kids: list = []
    y_mid = height * 0.5
    # Pedestal
    kids.append(part(f"{name}_Plinth", (3.4, 0.7, 3.4), (x, 0.45, z), STONE, material="Concrete", can_collide=True))
    kids.append(part(f"{name}_Base", (2.9, 0.55, 2.9), (x, 1.0, z), GOLD, material="Metal", can_collide=False))
    kids.append(
        part(f"{name}_BaseRing", (3.1, 0.2, 3.1), (x, 1.35, z), GOLD, material="Metal", can_collide=False, shape="Cylinder")
    )
    # Main shaft (cylinder)
    shaft_h = height - 3.2
    kids.append(
        part(
            f"{name}_Shaft",
            (2.1, shaft_h, 2.1),
            (x, 1.6 + shaft_h * 0.5, z),
            MARBLE,
            material="Marble",
            can_collide=True,
            shape="Cylinder",
        )
    )
    # Flute ribs
    for i in range(8):
        ang = i * (math.tau / 8)
        rx = x + 1.05 * math.cos(ang)
        rz = z + 1.05 * math.sin(ang)
        kids.append(
            part(
                f"{name}_Flute_{i}",
                (0.28, shaft_h * 0.92, 0.28),
                (rx, 1.6 + shaft_h * 0.5, rz),
                MARBLE_VEIN,
                material="Marble",
                can_collide=False,
                shape="Cylinder",
            )
        )
    # Capital
    cap_y = height - 0.9
    kids.append(part(f"{name}_Neck", (2.3, 0.35, 2.3), (x, cap_y - 0.5, z), GOLD, material="Metal", can_collide=False, shape="Cylinder"))
    kids.append(part(f"{name}_Capital", (3.2, 0.7, 3.2), (x, cap_y, z), GOLD, material="Metal", can_collide=False))
    kids.append(part(f"{name}_Abacus", (3.6, 0.35, 3.6), (x, cap_y + 0.45, z), GOLD, material="Metal", can_collide=False))
    # Neon pin on outer face (south-facing for canopy cols)
    kids.append(
        part(f"{name}_Neon", (0.25, shaft_h * 0.7, 0.25), (x, 1.6 + shaft_h * 0.5, z + 1.25), GOLD, material="Neon", can_collide=False)
    )
    return kids


def window_bay(name: str, cx: float, cy: float, cz: float, *, width: float = 8.0, height: float = 9.0) -> list:
    """Single hotel window module facing south (+Z): gold frame, glass, warm glow."""
    kids: list = []
    depth = 0.55
    kids.append(
        part(f"{name}_Frame", (width, height, depth), (cx, cy, cz), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part(
            f"{name}_Glass",
            (width - 0.7, height - 0.7, 0.2),
            (cx, cy, cz + 0.15),
            GLASS,
            material="Glass",
            can_collide=False,
            transparency=0.4,
            reflectance=0.3,
        )
    )
    kids.append(
        part(
            f"{name}_Glow",
            (width - 1.2, height - 1.2, 0.12),
            (cx, cy, cz + 0.28),
            WARM,
            material="Neon",
            can_collide=False,
            transparency=0.25,
        )
    )
    kids.append(part(f"{name}_MullionV", (0.2, height - 0.9, 0.22), (cx, cy, cz + 0.2), GOLD, material="Metal", can_collide=False))
    kids.append(part(f"{name}_MullionH", (width - 0.9, 0.2, 0.22), (cx, cy, cz + 0.2), GOLD, material="Metal", can_collide=False))
    return kids


def window_bay_ew(name: str, cx: float, cy: float, cz: float, *, outward: float, width: float = 5.5, height: float = 8.0) -> list:
    """Window module on east/west elevation (thin axis along X, facing outward)."""
    kids: list = []
    sign = 1.0 if outward > 0 else -1.0
    kids.append(part(f"{name}_Frame", (0.55, height, width), (cx, cy, cz), GOLD, material="Metal", can_collide=False))
    kids.append(
        part(
            f"{name}_Glass",
            (0.2, height - 0.7, width - 0.7),
            (cx + sign * 0.15, cy, cz),
            GLASS,
            material="Glass",
            can_collide=False,
            transparency=0.4,
            reflectance=0.3,
        )
    )
    kids.append(
        part(
            f"{name}_Glow",
            (0.12, height - 1.2, width - 1.2),
            (cx + sign * 0.28, cy, cz),
            WARM,
            material="Neon",
            can_collide=False,
            transparency=0.25,
        )
    )
    kids.append(
        part(f"{name}_MullionV", (0.22, height - 0.9, 0.2), (cx + sign * 0.2, cy, cz), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part(f"{name}_MullionH", (0.22, 0.2, width - 0.9), (cx + sign * 0.2, cy, cz), GOLD, material="Metal", can_collide=False)
    )
    return kids


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


def roof_down_spot(
    name: str,
    x: float,
    y: float,
    z: float,
    *,
    yaw: float = 0.0,
    brightness: float = 5.0,
    range_: float = 70.0,
    angle: float = 80.0,
) -> dict:
    """Roof-mounted spotlight aimed straight down onto walkable ground."""
    return spot_part(
        name,
        (x, y, z),
        WARM,
        brightness=brightness,
        range_=range_,
        angle=angle,
        orientation=(-90.0, yaw, 0.0),
    )


def build_site_lighting() -> list:
    """Street lamps on the perimeter + roof-down spots (entrance uses spots only)."""
    kids: list = []

    # --- Perimeter street lamps only (no posts on the entrance approach) ---
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

    # --- Entrance / porte-cochere: downward spots only (softer than perimeter wash) ---
    entry_spots = [
        # Under canopy - walk path
        ("EntrySpot_CanopyL", -8.0, 17.9, 74.0),
        ("EntrySpot_CanopyC", 0.0, 17.9, 76.0),
        ("EntrySpot_CanopyR", 8.0, 17.9, 74.0),
        ("EntrySpot_CanopyFL", -10.0, 17.9, 82.0),
        ("EntrySpot_CanopyFR", 10.0, 17.9, 82.0),
        # South parapet over doors / apron
        ("EntrySpot_DoorL", -10.0, 21.5, 67.5),
        ("EntrySpot_DoorC", 0.0, 21.5, 67.5),
        ("EntrySpot_DoorR", 10.0, 21.5, 67.5),
        # Approach carpet (mounted high on invisible hosts - still "from roof" energy)
        ("EntrySpot_Approach0", -6.0, 22.0, 88.0),
        ("EntrySpot_Approach1", 6.0, 22.0, 88.0),
        ("EntrySpot_Approach2", -6.0, 22.0, 100.0),
        ("EntrySpot_Approach3", 6.0, 22.0, 100.0),
        ("EntrySpot_Approach4", 0.0, 22.0, 112.0),
    ]
    for name, x, y, z in entry_spots:
        kids.append(
            roof_down_spot(name, x, y, z, brightness=2.4, range_=42.0, angle=70.0)
        )

    # --- Roof-edge spotlights for sides / north / corners (not blasting the doors) ---
    # South parapet wings (away from center entry)
    for i, x in enumerate((-70.0, -45.0, 45.0, 70.0)):
        kids.append(roof_down_spot(f"RoofSpot_S{i}", x, 24.5, 68.5, brightness=3.2, range_=55.0))
    # East / west pit-roof edges
    for i, z in enumerate((-40.0, -10.0, 20.0, 50.0)):
        kids.append(roof_down_spot(f"RoofSpot_W{i}", -90.0, 23.5, z, brightness=3.5, range_=60.0))
        kids.append(roof_down_spot(f"RoofSpot_E{i}", 90.0, 23.5, z, brightness=3.5, range_=60.0))
    # North game-room roof edge over north path
    for i, x in enumerate((-70.0, -35.0, 0.0, 35.0, 70.0)):
        kids.append(roof_down_spot(f"RoofSpot_N{i}", x, 54.0, -138.0, brightness=3.5, range_=60.0))
    # Corner down-spots for apron coverage
    for i, (x, z) in enumerate(((-100.0, 70.0), (100.0, 70.0), (-100.0, -130.0), (100.0, -130.0))):
        kids.append(roof_down_spot(f"RoofSpot_Corner{i}", x, 24.0, z, brightness=3.2, range_=55.0))

    # Soft ambient fills over open grass (invisible hosts only) - keep off the door axis
    for i, (x, z) in enumerate(
        (
            (-50.0, 130.0),
            (50.0, 130.0),
            (0.0, -155.0),
            (-115.0, -20.0),
            (115.0, -20.0),
            (-60.0, -100.0),
            (60.0, -100.0),
        )
    ):
        kids.append(light_part(f"GrassFill_{i}", (x, 14.0, z), WARM, brightness=1.4, range_=50.0))

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
    """Hotel-casino south facade + sides: podium, window bays, canopy, marquee, crown."""
    kids: list = []
    wall_z = 66.0
    face_z = 67.35  # cladding just south of collide wall

    # -------------------------------------------------------------------------
    # South podium / water table (wings only - keep door bay walkable)
    # -------------------------------------------------------------------------
    kids.append(
        part("SouthPodium_L", (78.0, 2.0, 3.5), (-53.0, 1.1, 67.5), STONE, material="Slate", can_collide=False)
    )
    kids.append(
        part("SouthPodium_R", (78.0, 2.0, 3.5), (53.0, 1.1, 67.5), STONE, material="Slate", can_collide=False)
    )
    kids.append(
        part("SouthWaterTable_L", (80.0, 0.3, 4.0), (-53.0, 2.2, 67.7), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("SouthWaterTable_R", (80.0, 0.3, 4.0), (53.0, 2.2, 67.7), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("SouthPodiumNeon", (170.0, 0.15, 0.25), (0.0, 2.35, 69.5), CYAN, material="Neon", can_collide=False, transparency=0.2)
    )

    # -------------------------------------------------------------------------
    # Tall center entry bay (hotel-scale around doors)
    # -------------------------------------------------------------------------
    # Tall center entry bay - L/R backs only so the door opening is a real cutout
    # Opening: |x| < 11, y ~ 0..18 (matches Ext_South gap + lint)
    kids.append(
        part("EntryBayBack_L", (4.0, 18.0, 2.0), (-14.0, 9.5, 65.2), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("EntryBayBack_R", (4.0, 18.0, 2.0), (14.0, 9.5, 65.2), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("EntryBayLint", (24.0, 3.0, 2.0), (0.0, 19.5, 65.2), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("EntryBayPilaster_L", (3.2, 24.0, 3.5), (-14.5, 12.5, 65.8), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("EntryBayPilaster_R", (3.2, 24.0, 3.5), (14.5, 12.5, 65.8), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("EntryBayEntablature", (32.0, 2.0, 4.0), (0.0, 25.5, 66.5), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("EntryBayFrieze", (30.0, 1.0, 3.2), (0.0, 24.2, 66.3), MARBLE, material="Slate", can_collide=False)
    )
    kids.append(
        part("EntryBayNeon", (28.0, 0.25, 0.3), (0.0, 24.2, 68.0), MAGENTA, material="Neon", can_collide=False)
    )
    # Gold door surround (outside walk |x|<10)
    kids.append(part("EntryMold_L", (0.7, 20.0, 1.2), (-12.2, 10.5, 66.9), GOLD, material="Metal", can_collide=False))
    kids.append(part("EntryMold_R", (0.7, 20.0, 1.2), (12.2, 10.5, 66.9), GOLD, material="Metal", can_collide=False))
    kids.append(part("EntryMold_Top", (25.8, 0.9, 1.2), (0.0, 20.8, 66.9), GOLD, material="Metal", can_collide=False))
    kids.append(part("EntryMold_Key", (3.5, 1.6, 1.4), (0.0, 22.0, 67.2), GOLD, material="Metal", can_collide=False))

    # -------------------------------------------------------------------------
    # South wing cladding + repeating window bays (replace flat GlassBand)
    # -------------------------------------------------------------------------
    # Dark stone veneer over south wings
    kids.append(
        part("SouthVeneer_L", (78.0, 20.0, 1.2), (-52.0, 12.5, face_z), MARBLE, material="Marble", can_collide=False)
    )
    kids.append(
        part("SouthVeneer_R", (78.0, 20.0, 1.2), (52.0, 12.5, face_z), MARBLE, material="Marble", can_collide=False)
    )
    # Window bay grid on each wing
    bay_xs_l = [-80.0, -70.0, -60.0, -50.0, -40.0, -30.0, -22.0]
    bay_xs_r = [22.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0]
    for row, cy in enumerate((8.5, 17.5)):
        for i, bx in enumerate(bay_xs_l):
            kids.extend(window_bay(f"Win_L_{row}_{i}", bx, cy, face_z + 0.4, width=7.5, height=7.5))
        for i, bx in enumerate(bay_xs_r):
            kids.extend(window_bay(f"Win_R_{row}_{i}", bx, cy, face_z + 0.4, width=7.5, height=7.5))

    # -------------------------------------------------------------------------
    # Cornice / parapet stack (full south)
    # -------------------------------------------------------------------------
    kids.append(
        part("SouthParapet", (186.0, 5.5, 3.8), (0.0, 25.5, 66.4), DARK, material="Slate", can_collide=False)
    )
    kids.append(
        part("SouthCorniceLower", (188.0, 0.55, 4.6), (0.0, 23.0, 66.8), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("SouthCornice", (190.0, 0.85, 5.0), (0.0, 28.5, 66.9), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("SouthCorniceNeon", (176.0, 0.28, 0.35), (0.0, 27.9, 69.0), MAGENTA, material="Neon", can_collide=False)
    )
    kids.append(
        part("SouthAttic", (160.0, 3.0, 2.5), (0.0, 30.8, 66.2), MARBLE, material="Marble", can_collide=False)
    )

    # -------------------------------------------------------------------------
    # Porte-cochere (thicker canopy + coffers + classical columns)
    # -------------------------------------------------------------------------
    kids.append(
        part("CanopyDeck", (44.0, 1.4, 20.0), (0.0, 19.6, 76.0), MARBLE, material="Slate", can_collide=False)
    )
    kids.append(
        part("CanopyFasciaS", (45.0, 1.1, 0.7), (0.0, 20.5, 86.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("CanopyFasciaN", (45.0, 1.1, 0.7), (0.0, 20.5, 66.2), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("CanopyFasciaL", (0.7, 1.1, 20.0), (-22.0, 20.5, 76.0), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("CanopyFasciaR", (0.7, 1.1, 20.0), (22.0, 20.5, 76.0), GOLD, material="Metal", can_collide=False)
    )
    # Strict soffit Y ladder (no coplanar faces -> no z-fight flash):
    # Deck bottom ~18.9 · coffer frame 18.65 · inset 18.45 · neon strip 18.25 · spots 17.9
    kids.append(
        part("CanopyNeon", (36.0, 0.12, 14.0), (0.0, 18.25, 76.0), CYAN, material="Neon", can_collide=False, transparency=0.35)
    )
    # Soffit coffers
    idx = 0
    for cx in (-12.0, 0.0, 12.0):
        for cz in (70.0, 76.0, 82.0):
            kids.append(
                part(
                    f"CanopyCoffer_{idx}",
                    (9.0, 0.18, 4.5),
                    (cx, 18.65, cz),
                    GOLD_DIM,
                    material="Metal",
                    can_collide=False,
                )
            )
            kids.append(
                part(
                    f"CanopyCofferInset_{idx}",
                    (7.5, 0.14, 3.5),
                    (cx, 18.45, cz),
                    MARBLE,
                    material="Slate",
                    can_collide=False,
                )
            )
            idx += 1

    # Columns outside walk channel (|x| >= 16)
    for i, x in enumerate((-17.0, 17.0)):
        for j, z in enumerate((70.0, 83.0)):
            kids.extend(classical_column(f"CanopyCol_{i}_{j}", x, z, height=18.5))

    # -------------------------------------------------------------------------
    # Marquee (deeper board + stepped neon)
    # -------------------------------------------------------------------------
    kids.append(
        part("MarqueeBoard", (56.0, 10.0, 3.2), (0.0, 29.5, 69.5), MARBLE, material="Slate", can_collide=False)
    )
    kids.append(
        part("MarqueeGoldReturn", (58.0, 11.0, 0.6), (0.0, 29.5, 67.8), GOLD, material="Metal", can_collide=False)
    )
    kids.append(
        part("MarqueeNeonOuter", (58.0, 11.2, 0.45), (0.0, 29.5, 71.3), CYAN, material="Neon", can_collide=False, transparency=0.12)
    )
    kids.append(
        part("MarqueeNeonMid", (54.0, 9.0, 0.35), (0.0, 29.5, 71.45), PURPLE, material="Neon", can_collide=False, transparency=0.2)
    )
    kids.append(
        part("MarqueeNeonInner", (50.0, 7.2, 0.3), (0.0, 29.5, 71.55), MAGENTA, material="Neon", can_collide=False, transparency=0.25)
    )
    kids.append(light_part("MarqueeWash", (0.0, 27.0, 74.5), CYAN, brightness=2.8, range_=48.0))

    # -------------------------------------------------------------------------
    # Crown / diamond rooftop silhouette (multi-part + mesh accent)
    # -------------------------------------------------------------------------
    kids.append(
        part("CrownPedestal", (14.0, 2.0, 4.0), (0.0, 33.0, 66.5), MARBLE, material="Slate", can_collide=False)
    )
    kids.append(
        part(
            "CrownDiamond",
            (9.0, 9.0, 2.2),
            (0.0, 38.0, 66.6),
            GOLD,
            material="Metal",
            can_collide=False,
            orientation=(0.0, 0.0, 45.0),
        )
    )
    kids.append(
        part(
            "CrownDiamondCore",
            (5.0, 5.0, 1.8),
            (0.0, 38.0, 66.9),
            CYAN,
            material="Neon",
            can_collide=False,
            orientation=(0.0, 0.0, 45.0),
            transparency=0.12,
        )
    )
    # Mesh gem accent (SpecialMesh Sphere - always loads; FileMesh optional overlay)
    kids.append(
        special_mesh_part(
            "CrownMeshGem",
            (5.5, 5.5, 5.5),
            (0.0, 38.0, 68.5),
            CYAN,
            mesh_type="Sphere",
            material="Neon",
            can_collide=False,
            transparency=0.2,
        )
    )
    kids.append(
        special_mesh_part(
            "CrownMeshGemFile",
            (3.5, 3.5, 3.5),
            (0.0, 41.5, 68.0),
            GOLD,
            mesh_type="FileMesh",
            mesh_id=MESH_DIAMOND,
            mesh_scale=(1.5, 1.5, 1.5),
            material="Neon",
            can_collide=False,
            transparency=0.25,
        )
    )
    kids.append(part("CrownSpire", (1.4, 9.0, 1.4), (0.0, 45.5, 66.5), GOLD, material="Metal", can_collide=False, shape="Cylinder"))
    kids.append(part("CrownSpireTip", (1.0, 2.5, 1.0), (0.0, 51.0, 66.5), MAGENTA, material="Neon", can_collide=False, shape="Ball"))
    kids.append(part("CrownFin_L", (0.6, 6.0, 2.5), (-5.0, 40.0, 66.5), GOLD, material="Metal", can_collide=False, orientation=(0.0, 0.0, 18.0)))
    kids.append(part("CrownFin_R", (0.6, 6.0, 2.5), (5.0, 40.0, 66.5), GOLD, material="Metal", can_collide=False, orientation=(0.0, 0.0, -18.0)))
    kids.append(light_part("CrownLight", (0.0, 42.0, 69.0), GOLD, brightness=2.4, range_=40.0))

    # -------------------------------------------------------------------------
    # Corner towers SW / SE (match south facade height ~22-25)
    for side, x in (("SW", -90.0), ("SE", 90.0)):
        kids.append(
            part(f"Tower_{side}", (7.0, 24.0, 7.0), (x, 12.5, 64.0), MARBLE, material="Marble", can_collide=False)
        )
        kids.append(
            part(f"TowerCap_{side}", (8.2, 1.0, 8.2), (x, 25.0, 64.0), GOLD, material="Metal", can_collide=False)
        )
        kids.append(
            part(f"TowerSpire_{side}", (1.6, 5.0, 1.6), (x, 28.5, 64.0), GOLD, material="Metal", can_collide=False, shape="Cylinder")
        )
        kids.append(
            part(f"TowerNeon_{side}", (0.35, 20.0, 0.35), (x, 11.0, 67.8), CYAN if side == "SW" else MAGENTA, material="Neon", can_collide=False)
        )
        for wi, wy in enumerate((7.0, 14.0)):
            kids.extend(window_bay(f"TowerWin_{side}_{wi}", x, wy, 67.8, width=4.0, height=5.0))

    # East / west side elevations - bay rhythm
    # -------------------------------------------------------------------------
    for side, x, outward in (("W", -93.4, -1.0), ("E", 93.4, 1.0)):
        # Veneer strip (no floating side belts - they read as a cyan outline)
        kids.append(
            part(
                f"SideVeneer_{side}",
                (0.8, 20.0, 120.0),
                (x, 11.0, 5.0),
                MARBLE,
                material="Marble",
                can_collide=False,
            )
        )
        # Side bays only along the pit wing (match south height) - not the tall room wing
        for i, z in enumerate(range(-40, 62, 18)):
            kids.append(
                part(
                    f"Pilaster_{side}_{i}",
                    (2.6, 20.0, 3.2),
                    (x, 10.5, float(z)),
                    MARBLE,
                    material="Marble",
                    can_collide=False,
                )
            )
            kids.append(
                part(
                    f"PilasterCap_{side}_{i}",
                    (3.0, 0.5, 3.6),
                    (x, 20.8, float(z)),
                    GOLD,
                    material="Metal",
                    can_collide=False,
                )
            )
            kids.extend(
                window_bay_ew(
                    f"SideWin_{side}_{i}",
                    x + outward * 0.9,
                    11.0,
                    float(z) + 8.0,
                    outward=outward,
                    width=5.5,
                    height=7.5,
                )
            )

    # Soft facade floods (off door centerline)
    for i, x in enumerate((-52.0, -30.0, 30.0, 52.0)):
        kids.append(spot_part(f"FacadeFlood_{i}", (x, 6.0, 94.0), WARM, brightness=2.0, range_=38.0, angle=50.0))

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

    kids.append(light_part("PlazaWash_Center", (0.0, 12.0, 95.0), WARM, brightness=1.1, range_=36.0))
    kids.append(light_part("PlazaWash_S", (0.0, 8.0, 118.0), PURPLE, brightness=1.0, range_=28.0))

    return kids


ROCK = [0.32, 0.30, 0.28]
ROCK_DARK = [0.22, 0.20, 0.18]
GRASS_DARK = [0.14, 0.34, 0.12]


def build_ground() -> list:
    """Walkable grass apron + hill berms that nest the north game-room wing."""
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
            (0.0, 0.05, -195.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PerimeterPath_W",
            (18.0, 0.2, 280.0),
            (-145.0, 0.05, -20.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )
    kids.append(
        part(
            "PerimeterPath_E",
            (18.0, 0.2, 280.0),
            (145.0, 0.05, -20.0),
            [0.35, 0.32, 0.28],
            material="Ground",
            can_collide=False,
        )
    )

    # -------------------------------------------------------------------------
    # Hill / berms - building stays at Y≈0; terrain rises around the envelope
    # so the tall north room wing reads nestled in a ridge (no ArenaOrigin moves).
    # -------------------------------------------------------------------------
    # North ridge core behind Z≈-140 (room wing north wall)
    kids.append(
        part(
            "Hill_NorthCore",
            (220.0, 42.0, 48.0),
            (0.0, 20.5, -168.0),
            GRASS_DARK,
            material="Grass",
            can_collide=True,
        )
    )
    kids.append(
        part(
            "Hill_NorthRockBand",
            (210.0, 18.0, 22.0),
            (0.0, 8.5, -152.0),
            ROCK,
            material="Slate",
            can_collide=True,
        )
    )
    # Slope from ridge crest down toward the north wall (wedge high edge north)
    kids.append(
        wedge_part(
            "Hill_NorthSlope",
            (200.0, 28.0, 24.0),
            (0.0, 13.5, -146.0),
            GRASS,
            material="Grass",
            can_collide=True,
            orientation=(0.0, 180.0, 0.0),
        )
    )
    # Outer north fallaway so the mass reads as a hill, not a cliff slab
    kids.append(
        wedge_part(
            "Hill_NorthOuter",
            (230.0, 36.0, 36.0),
            (0.0, 17.5, -192.0),
            GRASS,
            material="Grass",
            can_collide=True,
            orientation=(0.0, 0.0, 0.0),
        )
    )

    # East / west flank berms along the tall room wing (z -140..-55)
    for side, sx in (("W", -1.0), ("E", 1.0)):
        x_core = sx * 118.0
        x_outer = sx * 148.0
        kids.append(
            part(
                f"Hill_FlankCore_{side}",
                (36.0, 38.0, 95.0),
                (x_core, 18.5, -97.0),
                GRASS_DARK,
                material="Grass",
                can_collide=True,
            )
        )
        kids.append(
            part(
                f"Hill_FlankRock_{side}",
                (14.0, 22.0, 90.0),
                (sx * 100.0, 10.5, -97.0),
                ROCK,
                material="Slate",
                can_collide=True,
            )
        )
        # Outer flank slope (wedge: high edge toward building)
        yaw = 90.0 if side == "W" else -90.0
        kids.append(
            wedge_part(
                f"Hill_FlankOuter_{side}",
                (40.0, 32.0, 100.0),
                (x_outer, 15.5, -97.0),
                GRASS,
                material="Grass",
                can_collide=True,
                orientation=(0.0, yaw, 0.0),
            )
        )
        # Corner fillers NE / NW so ridge meets flanks
        kids.append(
            part(
                f"Hill_Corner_{side}",
                (48.0, 36.0, 40.0),
                (sx * 120.0, 17.5, -155.0),
                GRASS_DARK,
                material="Grass",
                can_collide=True,
            )
        )

    # Soft mounds on the apron (south/east/west) - keep plaza + spawn clear
    mound_specs = (
        ("Hill_Mound_SW", (-95.0, 4.0, 105.0), (42.0, 8.0, 36.0), GRASS),
        ("Hill_Mound_SE", (100.0, 3.5, 108.0), (38.0, 7.0, 32.0), GRASS),
        ("Hill_Mound_W", (-130.0, 5.0, 20.0), (48.0, 10.0, 55.0), GRASS_DARK),
        ("Hill_Mound_E", (130.0, 5.0, 15.0), (48.0, 10.0, 55.0), GRASS_DARK),
        ("Hill_Mound_FarS", (-40.0, 2.5, 155.0), (50.0, 5.0, 28.0), GRASS),
        ("Hill_Mound_FarSE", (55.0, 2.8, 158.0), (44.0, 5.5, 26.0), GRASS),
    )
    for name, pos, size, color in mound_specs:
        kids.append(
            part(
                name,
                size,
                pos,
                color,
                material="Grass",
                can_collide=True,
            )
        )

    # Rock outcrops near room-wing flanks for cliff read
    for side, sx in (("W", -1.0), ("E", 1.0)):
        kids.append(
            part(
                f"Hill_Outcrop_{side}1",
                (10.0, 14.0, 16.0),
                (sx * 108.0, 6.5, -120.0),
                ROCK_DARK,
                material="Slate",
                can_collide=True,
                orientation=(0.0, 18.0 * sx, 8.0),
            )
        )
        kids.append(
            part(
                f"Hill_Outcrop_{side}2",
                (12.0, 18.0, 12.0),
                (sx * 112.0, 8.5, -75.0),
                ROCK,
                material="Rock",
                can_collide=True,
                orientation=(0.0, -12.0 * sx, -6.0),
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
    # Sized to fill MarqueeNeonOuter (~58x11.2) so SurfaceGui text reads large.
    sign = {
        "name": "BrandSign",
        "className": "Part",
        "properties": {
            "Anchored": True,
            "Size": [56.0, 10.0, 1.5],
            "Position": [0.0, 29.5, 72.2],
            "Color": MARBLE,
            "Material": "Slate",
            # Face Front (+ approach from south): yaw 180 so local -Z -> world +Z
            "Orientation": [0.0, 180.0, 0.0],
        },
        "children": [
            part(
                "SignFrame",
                (58.0, 10.8, 0.45),
                (0.0, 29.5, 71.4),
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
    """Align envelope with south facade height; keep tall walls only on game-room wing.

    Splits Ext_East/West into pit-height (matches south ~22) and room-height (~54).
    Also drops superseded Entry_Marquee and tunes entry columns / SW-SE corners.
    """
    kept = []
    for child in walls.get("children") or []:
        name = child.get("name") or ""
        props = child.get("properties") or {}
        if name in (
            "Entry_Marquee",
            "Ext_East",
            "Ext_West",
            "Ext_E_Pit",
            "Ext_W_Pit",
            "Ext_E_Rooms",
            "Ext_W_Rooms",
        ):
            # Replaced by fresh split segments below (idempotent)
            continue
        if name in ("Entry_Column_L", "Entry_Column_R"):
            # Match south facade height ladder (wall ~22 + parapet), not 32-stud towers
            props["Material"] = "Marble"
            props["Color"] = MARBLE
            props["Size"] = [3.6, 24.0, 3.6]
            pos = props.get("Position") or [0, 13, 64.5]
            props["Position"] = [pos[0], 12.5, 64.2]
        if name in ("Entry_ColNeon_L", "Entry_ColNeon_R"):
            props["Size"] = [0.5, 22.0, 0.5]
            pos = props.get("Position") or [0, 13, 66.3]
            props["Position"] = [pos[0], 12.5, 66.5]
            props["Color"] = GOLD
        if name in ("Corner_SW", "Corner_SE"):
            # Align with south wall top (~22), slightly proud as corner posts
            props["Material"] = "Marble"
            props["Color"] = MARBLE
            props["Size"] = [4.5, 24.0, 4.5]
            pos = props.get("Position") or [0, 10, 65]
            props["Position"] = [pos[0], 12.5, 65.0]
        kept.append(child)

    # Pit-side walls: same height as Ext_South (22). z from -55 (pit north) to +66 (south).
    # depth=121, center z = (-55+66)/2 = 5.5
    for side, x in (("W", -92.0), ("E", 92.0)):
        kept.append(
            part(
                f"Ext_{side}_Pit",
                (2.5, 22.0, 121.0),
                (x, 11.0, 5.5),
                DARK,
                material="SmoothPlastic",
                can_collide=True,
            )
        )
        # Game-room wing stays tall (Plinko board clearance). z -140..-55.
        # depth=85, center z = (-140-55)/2 = -97.5
        kept.append(
            part(
                f"Ext_{side}_Rooms",
                (2.5, 54.0, 85.0),
                (x, 27.0, -97.5),
                DARK,
                material="SmoothPlastic",
                can_collide=True,
            )
        )

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
    fill["children"].append(light_part("Wash_Plaza", (0.0, 10.0, 100.0), WARM, brightness=1.2, range_=40.0))
    fill["children"].append(light_part("Wash_Facade", (0.0, 22.0, 78.0), CYAN, brightness=1.4, range_=36.0))
    fill["children"].append(light_part("Wash_Foyer", (0.0, 12.0, 58.0), WARM, brightness=1.6, range_=28.0))
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
