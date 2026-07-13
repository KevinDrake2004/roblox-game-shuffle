#!/usr/bin/env python3
"""Rebuild lobby floors/carpets/walls to kill z-fighting and seal envelope gaps."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOBBY = ROOT / "src/map/Lobby.model.json"

GREEN = [0.05, 0.26, 0.15]
GREEN_DEEP = [0.04, 0.2, 0.12]
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


def find(node: dict, name: str):
    if node.get("name") == name:
        return node
    for child in node.get("children") or []:
        found = find(child, name)
        if found:
            return found
    return None


def part(
    name: str,
    size,
    pos,
    color,
    *,
    material: str = "Fabric",
    can_collide: bool = False,
    orientation=None,
    transparency=None,
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
    return {"name": name, "className": "Part", "properties": props}


def main() -> None:
    data = json.loads(LOBBY.read_text())
    floors = find(data, "Floors")
    carpets = find(data, "Carpets")
    walls = find(data, "Walls")
    assert floors and carpets and walls

    # --- Floors: collide base + non-overlapping green fields (strict Y ladder) ---
    # Y=0 collide base; green veneer Y=0.52; no stacked same-plane fabrics.
    floors["children"] = [
        part(
            "MainFloor",
            (184.0, 1.0, 206.0),
            (0.0, 0.0, -37.0),
            [0.04, 0.1, 0.08],
            material="SmoothPlastic",
            can_collide=True,
        ),
        # Pit west / east (leave center aisle bare for red carpet)
        part("CasinoField_W", (78.0, 0.12, 112.0), (-49.0, 0.52, 2.0), GREEN),
        part("CasinoField_E", (78.0, 0.12, 112.0), (49.0, 0.52, 2.0), GREEN),
        # North/south of aisle medallion zone (still green, not overlapping red)
        part("CasinoField_EntryW", (34.0, 0.12, 28.0), (-49.0, 0.52, 48.0), GREEN),
        part("CasinoField_EntryE", (34.0, 0.12, 28.0), (49.0, 0.52, 48.0), GREEN),
        # Game hall sides + rooms
        part("CasinoField_HallW", (78.0, 0.12, 28.0), (-49.0, 0.52, -68.0), GREEN_DEEP),
        part("CasinoField_HallE", (78.0, 0.12, 28.0), (49.0, 0.52, -68.0), GREEN_DEEP),
        part("CasinoField_Rooms", (178.0, 0.12, 54.0), (0.0, 0.52, -111.0), GREEN_DEEP),
        # Soft diamond accents ABOVE green only (unique Y, no red overlap)
        part(
            "FieldAccent_W1",
            (16.0, 0.08, 16.0),
            (-52.0, 0.58, 24.0),
            [0.07, 0.32, 0.18],
            orientation=(0, 45, 0),
        ),
        part(
            "FieldAccent_W2",
            (16.0, 0.08, 16.0),
            (-52.0, 0.58, -16.0),
            [0.07, 0.32, 0.18],
            orientation=(0, 45, 0),
        ),
        part(
            "FieldAccent_E1",
            (16.0, 0.08, 16.0),
            (52.0, 0.58, 24.0),
            [0.07, 0.32, 0.18],
            orientation=(0, 45, 0),
        ),
        part(
            "FieldAccent_E2",
            (16.0, 0.08, 16.0),
            (52.0, 0.58, -16.0),
            [0.07, 0.32, 0.18],
            orientation=(0, 45, 0),
        ),
    ]

    # --- Red carpet: aisle walkways only (keeps chairs on green) ---
    # Aisle width 14; tables sit at |x|>=22 so chairs stay off red.
    aisle_w = 14.0
    edge = 0.4
    carpets["children"] = [
        part("Carpet_Entry", (aisle_w, 0.14, 30.0), (0.0, 0.64, 42.0), RED),
        part("CarpetEdge_Entry_L", (edge, 0.16, 30.0), (-aisle_w / 2 - 0.15, 0.7, 42.0), GOLD, material="Neon"),
        part("CarpetEdge_Entry_R", (edge, 0.16, 30.0), (aisle_w / 2 + 0.15, 0.7, 42.0), GOLD, material="Neon"),
        part("Carpet_Main", (aisle_w, 0.14, 96.0), (0.0, 0.64, -10.0), RED),
        part("CarpetEdge_Main_L", (edge, 0.16, 96.0), (-aisle_w / 2 - 0.15, 0.7, -10.0), GOLD, material="Neon"),
        part("CarpetEdge_Main_R", (edge, 0.16, 96.0), (aisle_w / 2 + 0.15, 0.7, -10.0), GOLD, material="Neon"),
        # Short cross at junction only (not under tables)
        part("Carpet_Cross_N", (aisle_w + 8.0, 0.14, 10.0), (0.0, 0.64, 12.0), RED),
        part("Carpet_Cross_S", (aisle_w + 8.0, 0.14, 10.0), (0.0, 0.64, -26.0), RED),
        # Game hall corridor - inset from side walls (±90)
        part("Carpet_GameHall", (160.0, 0.14, 14.0), (0.0, 0.64, -70.0), RED),
        part("CarpetEdge_GameHall_N", (160.0, 0.16, edge), (0.0, 0.7, -77.0), GOLD, material="Neon"),
        part("CarpetEdge_GameHall_S", (160.0, 0.16, edge), (0.0, 0.7, -63.0), GOLD, material="Neon"),
        part("Carpet_ToMines", (12.0, 0.14, 12.0), (-55.0, 0.64, -82.0), RED),
        part("Carpet_ToRocket", (12.0, 0.14, 12.0), (0.0, 0.64, -82.0), RED),
        part("Carpet_ToPlinko", (12.0, 0.14, 12.0), (55.0, 0.64, -82.0), RED),
        part("Medallion", (10.0, 0.12, 10.0), (0.0, 0.68, 12.0), [0.62, 0.08, 0.14]),
        part("MedallionRing", (8.5, 0.08, 8.5), (0.0, 0.74, 12.0), GOLD, material="Neon"),
    ]

    # Floor chips only on green pit (not on red aisle). Unique Y above accents.
    chip_spots = [
        (-60, 30),
        (-48, 12),
        (-52, -8),
        (-38, -48),
        (-65, -30),
        (-45, -18),
        (60, 30),
        (48, 12),
        (52, -8),
        (38, -48),
        (65, -30),
        (45, -18),
        (-55, 40),
        (55, 40),
        (-70, 8),
        (70, 8),
        (-42, -58),
        (42, -58),
        (-30, -40),
        (30, -40),
    ]
    for i, (x, z) in enumerate(chip_spots):
        color = CHIP_COLORS[i % len(CHIP_COLORS)]
        carpets["children"].append(
            part(f"FloorChip_{i}", (1.35, 0.08, 1.35), (x, 0.72, z), color, material="SmoothPlastic")
        )
        carpets["children"].append(
            part(
                f"FloorChipRim_{i}",
                (1.55, 0.04, 1.55),
                (x, 0.76, z),
                GOLD,
                material="Neon",
            )
        )
        carpets["children"].append(
            part(
                f"FloorChipPip_{i}",
                (0.45, 0.03, 0.45),
                (x, 0.78, z),
                [0.95, 0.95, 0.98],
                material="SmoothPlastic",
            )
        )

    # --- Walls: seal envelope to floor edges X±92, Z +66 / -140 ---
    wall_updates = {
        # Side walls cover full depth including entry apron
        "Ext_West": {"Size": [2.5, 54.0, 210.0], "Position": [-92.0, 27.0, -37.0]},
        "Ext_East": {"Size": [2.5, 54.0, 210.0], "Position": [92.0, 27.0, -37.0]},
        "Ext_North": {"Size": [186.5, 54.0, 2.5], "Position": [0.0, 27.0, -140.0]},
        # South facade meets side walls (±92)
        "Ext_South_L": {"Size": [80.0, 22.0, 2.5], "Position": [-52.0, 11.0, 66.0]},
        "Ext_South_R": {"Size": [80.0, 22.0, 2.5], "Position": [52.0, 11.0, 66.0]},
        "Ext_South_Lint": {"Size": [24.0, 4.0, 2.5], "Position": [0.0, 20.0, 66.0]},
        "Entry_Marquee": {"Position": [0.0, 21.0, 67.4]},
        "Entry_Column_L": {"Position": [-13.0, 11.0, 64.5]},
        "Entry_Column_R": {"Position": [13.0, 11.0, 64.5]},
        "Entry_ColNeon_L": {"Position": [-13.0, 11.0, 66.3]},
        "Entry_ColNeon_R": {"Position": [13.0, 11.0, 66.3]},
        # Room south walls reach outer envelope
        "MinesRoom_South_L": {"Size": [26.0, 54.0, 1.5], "Position": [-79.0, 27.0, -82.0]},
        "MinesRoom_South_R": {"Size": [19.0, 54.0, 1.5], "Position": [-39.5, 27.0, -82.0]},
        "PlinkoRoom_South_L": {"Size": [22.0, 54.0, 1.5], "Position": [38.0, 27.0, -82.0]},
        "PlinkoRoom_South_R": {"Size": [26.0, 54.0, 1.5], "Position": [79.0, 27.0, -82.0]},
        # Pit divider meets side walls better
        "Pit_North_L": {"Size": [70.0, 22.0, 1.5], "Position": [-47.0, 11.0, -55.0]},
        "Pit_North_R": {"Size": [70.0, 22.0, 1.5], "Position": [47.0, 11.0, -55.0]},
    }

    for child in walls["children"]:
        name = child.get("name")
        if name in wall_updates and "properties" in child:
            child["properties"].update(wall_updates[name])

    existing = {c.get("name") for c in walls["children"]}
    # Corner seals where south meets east/west
    extras = [
        part(
            "Corner_SW",
            (3.0, 22.0, 3.0),
            (-91.0, 11.0, 65.0),
            [0.12, 0.05, 0.18],
            material="SmoothPlastic",
            can_collide=True,
        ),
        part(
            "Corner_SE",
            (3.0, 22.0, 3.0),
            (91.0, 11.0, 65.0),
            [0.12, 0.05, 0.18],
            material="SmoothPlastic",
            can_collide=True,
        ),
        part(
            "Corner_NW",
            (3.0, 54.0, 3.0),
            (-91.0, 27.0, -139.0),
            [0.12, 0.05, 0.18],
            material="SmoothPlastic",
            can_collide=True,
        ),
        part(
            "Corner_NE",
            (3.0, 54.0, 3.0),
            (91.0, 27.0, -139.0),
            [0.12, 0.05, 0.18],
            material="SmoothPlastic",
            can_collide=True,
        ),
    ]
    for extra in extras:
        if extra["name"] not in existing:
            walls["children"].append(extra)

    # Crown molding follow new west/east x
    for child in walls["children"]:
        name = child.get("name") or ""
        if name.startswith("Crown_W_") and "properties" in child:
            child["properties"]["Position"][0] = -90.5
        if name.startswith("Crown_E_") and "properties" in child:
            child["properties"]["Position"][0] = 90.5

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"floors={len(floors['children'])} carpets={len(carpets['children'])} walls={len(walls['children'])}")


if __name__ == "__main__":
    main()
