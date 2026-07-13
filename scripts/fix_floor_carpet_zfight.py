#!/usr/bin/env python3
"""Rebuild floors + carpets as strictly non-overlapping slabs (per height layer)
and nudge wall corner/lintel tops so nothing is coplanar -> no z-fighting."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOBBY = ROOT / "src/map/Lobby.model.json"

GREEN = [0.05, 0.26, 0.15]
GREEN_DEEP = [0.04, 0.2, 0.12]
GREEN_ACCENT = [0.07, 0.32, 0.18]
RED = [0.55, 0.04, 0.1]
GOLD = [0.92, 0.75, 0.32]
CHIP_COLORS = [
    [0.85, 0.12, 0.15],
    [0.15, 0.28, 0.8],
    [0.95, 0.95, 0.98],
    [0.1, 0.55, 0.3],
    [0.08, 0.08, 0.1],
    [0.92, 0.75, 0.32],
]

# Height layers (top-Y). Each layer strictly above the previous; within a layer
# the parts never overlap in XZ.
Y_GREEN = 0.55
Y_ACCENT = 0.6
Y_RED = 0.66
Y_MEDALLION = 0.7
Y_EDGE = 0.74
Y_CHIP = 0.8
Y_CHIP_RIM = 0.84
Y_CHIP_PIP = 0.87


def find(node: dict, name: str):
    if node.get("name") == name:
        return node
    for child in node.get("children") or []:
        found = find(child, name)
        if found:
            return found
    return None


def part(name, size, top_y, cx, cz, color, *, material="Fabric", orientation=None, can_collide=False):
    props = {
        "Anchored": True,
        "Size": [float(size[0]), float(size[1]), float(size[2])],
        "Position": [float(cx), float(top_y - size[1] / 2), float(cz)],
        "Color": [float(c) for c in color],
        "Material": material,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
        "CanCollide": can_collide,
    }
    if orientation is not None:
        props["Orientation"] = [float(o) for o in orientation]
    return {"name": name, "className": "Part", "properties": props}


def build_floors() -> list:
    out = []
    # Collide base under everything.
    out.append(
        {
            "name": "MainFloor",
            "className": "Part",
            "properties": {
                "Anchored": True,
                "Size": [184.0, 1.0, 206.0],
                "Position": [0.0, 0.0, -37.0],
                "Color": [0.04, 0.1, 0.08],
                "Material": "SmoothPlastic",
                "TopSurface": "Smooth",
                "BottomSurface": "Smooth",
                "CanCollide": True,
            },
        }
    )
    # Two non-overlapping green slabs (pit + rooms), abutting at z=-80.
    out.append(part("GreenPit", (176.0, 0.12, 144.0), Y_GREEN, 0.0, -8.0, GREEN))  # z -80..64
    out.append(part("GreenRooms", (176.0, 0.12, 60.0), Y_GREEN, 0.0, -110.0, GREEN_DEEP))  # z -140..-80
    # Diamond accents (spaced so they never overlap each other), one layer up.
    accents = [(-52, 24), (-52, -16), (52, 24), (52, -16), (0, 40), (-30, -46), (30, -46)]
    for i, (x, z) in enumerate(accents):
        out.append(part(f"FieldAccent_{i}", (15.0, 0.08, 15.0), Y_ACCENT, x, z, GREEN_ACCENT, orientation=(0, 45, 0)))
    return out


def build_carpets() -> list:
    out = []
    # --- Red carpet: non-overlapping rectangles forming aisle + cross + hall. ---
    # Main aisle (x -7..7), runs z -63..57.
    out.append(part("Carpet_Main", (14.0, 0.14, 120.0), Y_RED, 0.0, -3.0, RED))
    # Cross arms abut the aisle at x=+-7 (never cross over it).
    out.append(part("Carpet_CrossN_W", (40.0, 0.14, 14.0), Y_RED, -27.0, 12.0, RED))
    out.append(part("Carpet_CrossN_E", (40.0, 0.14, 14.0), Y_RED, 27.0, 12.0, RED))
    out.append(part("Carpet_CrossS_W", (40.0, 0.14, 14.0), Y_RED, -27.0, -26.0, RED))
    out.append(part("Carpet_CrossS_E", (40.0, 0.14, 14.0), Y_RED, 27.0, -26.0, RED))
    # Game hall corridor, abuts aisle at z=-63.
    out.append(part("Carpet_GameHall", (160.0, 0.14, 14.0), Y_RED, 0.0, -70.0, RED))
    # Room approach pads abut the hall at z=-77.
    for label, x in (("ToMines", -55.0), ("ToRocket", 0.0), ("ToPlinko", 55.0)):
        out.append(part(f"Carpet_{label}", (12.0, 0.14, 12.0), Y_RED, x, -83.0, RED))
    # Entry apron pad (south of aisle start), abuts aisle at z=57.
    out.append(part("Carpet_Entry", (24.0, 0.14, 10.0), Y_RED, 0.0, 62.0, RED))

    # Medallion at the crossing (clearly above the aisle; ring below the disc).
    out.append(part("MedallionRing", (11.0, 0.1, 11.0), Y_MEDALLION, 0.0, 12.0, GOLD, material="Neon"))
    out.append(part("Medallion", (10.0, 0.12, 10.0), Y_MEDALLION + 0.06, 0.0, 12.0, [0.62, 0.08, 0.14]))

    # --- Gold neon edges (thin, one layer up; placed so they don't overlap). ---
    # Hall edges sit a touch higher so they don't cross the aisle edges coplanar.
    edges = [
        ("Edge_Main_L", (0.5, 0.16, 120.0), -7.3, -3.0, Y_EDGE),
        ("Edge_Main_R", (0.5, 0.16, 120.0), 7.3, -3.0, Y_EDGE),
        ("Edge_Hall_N", (160.0, 0.16, 0.5), 0.0, -62.7, Y_EDGE + 0.04),
        ("Edge_Hall_S", (160.0, 0.16, 0.5), 0.0, -77.3, Y_EDGE + 0.04),
    ]
    for name, size, x, z, y in edges:
        out.append(part(name, size, y, x, z, GOLD, material="Neon"))

    # --- Floor chips on the green pit (spaced; never overlap; 3 unique tops). ---
    chip_spots = [
        (-60, 30), (-48, 12), (-52, -8), (-38, -48), (-65, -30), (-45, -18),
        (60, 30), (48, 12), (52, -8), (38, -48), (65, -30), (45, -18),
        (-55, 44), (55, 44), (-72, 8), (72, 8), (-42, -58), (42, -58),
        (-30, -40), (30, -40),
    ]
    for i, (x, z) in enumerate(chip_spots):
        col = CHIP_COLORS[i % len(CHIP_COLORS)]
        out.append(part(f"FloorChip_{i}", (1.35, 0.08, 1.35), Y_CHIP, x, z, col, material="SmoothPlastic"))
        out.append(part(f"FloorChipRim_{i}", (1.55, 0.06, 1.55), Y_CHIP_RIM, x, z, GOLD, material="Neon"))
        out.append(part(f"FloorChipPip_{i}", (0.45, 0.04, 0.45), Y_CHIP_PIP, x, z, [0.95, 0.95, 0.98], material="SmoothPlastic"))
    return out


def nudge_walls(walls: dict) -> None:
    """Adjust wall tops at corners/junctions so meeting walls are never coplanar."""
    # deltaTop: change applied to each part's top-Y (keeps the base fixed).
    tweaks = {
        "Corner_SW": -1.0,
        "Corner_SE": -1.0,
        "Corner_NW": -1.0,
        "Corner_NE": -1.0,
        "Pit_North_Lint": -0.6,
        "MinesRoom_South_Lint": -0.6,
        "RocketRoom_South_Lint": -0.6,
        "PlinkoRoom_South_Lint": -0.6,
        "Ext_South_Lint": -0.6,
        # North wall + room interior walls sit 0.6 below the side walls so the
        # corners/junctions aren't coplanar (roof hides the tiny gap).
        "Ext_North": -0.6,
        "MinesRoom_South_L": -0.6,
        "MinesRoom_South_R": -0.6,
        "RocketRoom_South_L": -0.6,
        "RocketRoom_South_R": -0.6,
        "PlinkoRoom_South_L": -0.6,
        "PlinkoRoom_South_R": -0.6,
    }
    # Entry columns grow taller so their tops clear the south facade.
    raises = {"Entry_Column_L": 2.0, "Entry_Column_R": 2.0, "Entry_ColNeon_L": 2.0, "Entry_ColNeon_R": 2.0}
    for child in walls.get("children") or []:
        name = child.get("name")
        p = child.get("properties")
        if not p or "Size" not in p:
            continue
        if name in tweaks:
            delta = tweaks[name]
            top = p["Position"][1] + p["Size"][1] / 2 + delta
            p["Size"][1] = max(0.5, p["Size"][1] + delta)
            p["Position"][1] = top - p["Size"][1] / 2
        elif name in raises:
            delta = raises[name]
            base = p["Position"][1] - p["Size"][1] / 2
            p["Size"][1] += delta
            p["Position"][1] = base + p["Size"][1] / 2


def main() -> None:
    data = json.loads(LOBBY.read_text())
    floors = find(data, "Floors")
    carpets = find(data, "Carpets")
    walls = find(data, "Walls")
    assert floors and carpets and walls

    floors["children"] = build_floors()
    carpets["children"] = build_carpets()
    nudge_walls(walls)

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"floors={len(floors['children'])} carpets={len(carpets['children'])}")


if __name__ == "__main__":
    main()
