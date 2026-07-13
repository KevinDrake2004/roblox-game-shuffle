#!/usr/bin/env python3
"""Rebuild roulette tables as real rectangular tables (wheel at one end, betting
layout across the rest) and rebuild the lounge bar so it reads clearly as a bar."""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOBBY = ROOT / "src/map/Lobby.model.json"

WOOD = [0.16, 0.08, 0.04]
WOOD_RAIL = [0.3, 0.14, 0.07]
GOLD = [0.92, 0.75, 0.32]
FELT = [0.04, 0.42, 0.22]
FELT_DARK = [0.03, 0.32, 0.17]
DARK = [0.06, 0.06, 0.08]
RED = [0.78, 0.08, 0.1]
BLACK = [0.05, 0.05, 0.07]
GREEN = [0.1, 0.55, 0.3]

# European single-zero red numbers.
RED_NUMS = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}


def find(node: dict, name: str):
    if node.get("name") == name:
        return node
    for child in node.get("children") or []:
        found = find(child, name)
        if found:
            return found
    return None


def rot(cx: float, cz: float, lx: float, lz: float, yaw_deg: float):
    t = math.radians(yaw_deg)
    c, s = math.cos(t), math.sin(t)
    return (cx + lx * c - lz * s, cz + lx * s + lz * c)


def part(name, size, pos, color, *, material="SmoothPlastic", orientation=None, shape=None, can_collide=True):
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
    if shape is not None:
        props["Shape"] = shape
    return {"name": name, "className": "Part", "properties": props}


def build_roulette(name: str, cx: float, cz: float, yaw: float) -> dict:
    """Rectangular roulette table. Long axis = local X. Wheel at -X end,
    betting layout across the +X portion (rendered by SurfaceGui on FeltLayout).

    Every stacked part gets a UNIQUE top-Y (and a distinct footprint / radius when
    coaxial) so no two visible faces are coplanar -> no z-fighting."""
    children = []

    # --- Table body + felt (clean ladder, no coplanar tops) ---
    # Base is smaller than felt so its top is fully hidden under the felt slab.
    children.append(part("Base", (12.4, 1.9, 5.4), rot3(cx, cz, 0, 0.95, 0, yaw), WOOD, material="Wood", orientation=(0, yaw, 0)))
    # Felt: full table top, play surface at y=2.2.
    children.append(part("Felt", (13.0, 0.3, 6.0), rot3(cx, cz, 0, 2.05, 0, yaw), FELT, material="Fabric", orientation=(0, yaw, 0)))

    # Raised wood bumper border (perimeter bars only; they abut, never overlap).
    children.append(part("BorderN", (13.6, 0.5, 0.6), rot3(cx, cz, 0, 2.15, 3.3, yaw), WOOD_RAIL, material="Wood", orientation=(0, yaw, 0)))
    children.append(part("BorderS", (13.6, 0.5, 0.6), rot3(cx, cz, 0, 2.15, -3.3, yaw), WOOD_RAIL, material="Wood", orientation=(0, yaw, 0)))
    children.append(part("BorderE", (0.6, 0.5, 6.0), rot3(cx, cz, 6.8, 2.15, 0, yaw), WOOD_RAIL, material="Wood", orientation=(0, yaw, 0)))
    children.append(part("BorderW", (0.6, 0.5, 6.0), rot3(cx, cz, -6.8, 2.15, 0, yaw), WOOD_RAIL, material="Wood", orientation=(0, yaw, 0)))
    # Gold caps sit on top of the wood border (cover it fully -> wood top hidden).
    children.append(part("GoldN", (13.6, 0.08, 0.6), rot3(cx, cz, 0, 2.44, 3.3, yaw), GOLD, material="Metal", orientation=(0, yaw, 0)))
    children.append(part("GoldS", (13.6, 0.08, 0.6), rot3(cx, cz, 0, 2.44, -3.3, yaw), GOLD, material="Metal", orientation=(0, yaw, 0)))
    children.append(part("GoldE", (0.6, 0.08, 6.0), rot3(cx, cz, 6.8, 2.44, 0, yaw), GOLD, material="Metal", orientation=(0, yaw, 0)))
    children.append(part("GoldW", (0.6, 0.08, 6.0), rot3(cx, cz, -6.8, 2.44, 0, yaw), GOLD, material="Metal", orientation=(0, yaw, 0)))

    # Betting layout felt (SurfaceGui target). Floats just above the felt top.
    layout_cx, layout_cz = rot(cx, cz, 2.7, 0.0, yaw)
    children.append(
        {
            "name": "FeltLayout",
            "className": "Part",
            "properties": {
                "Anchored": True,
                "Size": [7.3, 0.1, 4.9],
                "Position": [layout_cx, 2.28, layout_cz],
                "Color": FELT_DARK,
                "Material": "Fabric",
                "Orientation": [0.0, yaw, 0.0],
                "TopSurface": "Smooth",
                "BottomSurface": "Smooth",
                "CanCollide": True,
            },
        }
    )

    # --- Wheel at -X end. Coaxial cylinders, each a UNIQUE top-Y + radius. ---
    wheel_lx = -4.1
    wcx, wcz = rot(cx, cz, wheel_lx, 0.0, yaw)
    # (name, diameter, top_y, color, material)
    disks = [
        ("WheelHousing", 5.2, 2.42, GOLD, "Metal"),
        ("WheelWell", 4.6, 2.50, [0.1, 0.05, 0.03], "Wood"),
        ("WheelBowl", 3.9, 2.58, [0.08, 0.04, 0.03], "Wood"),
        ("WheelDisk", 3.3, 2.66, DARK, "Metal"),
    ]
    for nm, dia, top, col, mat in disks:
        thick = 0.5
        children.append(
            part(nm, (thick, dia, dia), (wcx, top - thick / 2, wcz), col, material=mat, orientation=(0, 0, 90), shape="Cylinder")
        )

    # Pocket ring on the disk (boxes; separated radially -> no coplanar overlap).
    pocket_r = 1.35
    count = 18
    for i in range(count):
        a = i * (360.0 / count)
        rad = math.radians(a)
        plx = wheel_lx + pocket_r * math.sin(rad)
        plz = 0.0 + pocket_r * math.cos(rad)
        pwx, pwz = rot(cx, cz, plx, plz, yaw)
        if i == 0:
            col = GREEN
        elif i % 2 == 1:
            col = RED
        else:
            col = BLACK
        children.append(
            part(
                f"Pocket_{i}",
                (0.42, 0.16, 0.7),
                (pwx, 2.66, pwz),  # top 2.74, embedded in disk (top 2.66) -> bottom hidden
                col,
                material="SmoothPlastic",
                orientation=(0, yaw + a, 0),
            )
        )

    children.append(part("WheelHubRing", (0.3, 1.4, 1.4), (wcx, 2.65, wcz), GOLD, material="Metal", orientation=(0, 0, 90), shape="Cylinder"))
    children.append(part("WheelHub", (0.5, 0.8, 0.8), (wcx, 2.70, wcz), GOLD, material="Metal", orientation=(0, 0, 90), shape="Cylinder"))
    children.append(part("Spindle", (1.0, 0.2, 0.2), (wcx, 3.05, wcz), GOLD, material="Neon", orientation=(0, yaw, 40)))
    children.append(part("SpindleCross", (1.0, 0.2, 0.2), (wcx, 3.12, wcz), GOLD, material="Neon", orientation=(0, yaw + 90, 40)))

    return {
        "name": name,
        "className": "Folder",
        "attributes": {"TableType": "Roulette", "TableYaw": float(yaw)},
        "children": children,
    }


def rot3(cx, cz, lx, y, lz, yaw):
    wx, wz = rot(cx, cz, lx, lz, yaw)
    return (wx, y, wz)


def build_bar() -> dict:
    """Bar along the west wall (x=-90), running in Z (parallel to wall), facing +X."""
    back_x = -87.0  # cabinet against wall
    counter_x = -83.0  # marble counter front edge toward room
    z0, z1 = 4.0, 32.0  # span along wall
    length = z1 - z0
    cz = (z0 + z1) / 2

    children = []
    # Back-bar cabinet + mirror (bottles visible, facing +X into room)
    children.append(part("BackCabinet", (2.2, 8.5, length), (back_x, 4.4, cz), WOOD, material="Wood"))
    children.append(part("BackMirror", (0.2, 5.2, length - 3.0), (back_x + 1.15, 6.2, cz), [0.2, 0.24, 0.3], material="Glass"))
    children.append(part("BackMirrorFrame", (0.35, 5.8, length - 2.4), (back_x + 1.0, 6.2, cz), GOLD, material="Metal"))
    # Two visible bottle shelves in front of the mirror
    for shelf_i, shelf_y in enumerate((5.0, 7.2)):
        children.append(part(f"Shelf_{shelf_i}", (0.9, 0.2, length - 3.0), (back_x + 1.5, shelf_y - 0.6, cz), [0.12, 0.06, 0.03], material="Wood"))
        children.append(part(f"ShelfNeon_{shelf_i}", (0.5, 0.1, length - 3.0), (back_x + 1.7, shelf_y - 0.72, cz), [0.133, 0.827, 0.933] if shelf_i == 0 else [0.925, 0.282, 0.6], material="Neon", can_collide=False))
        bottle_colors = [[0.3, 0.7, 0.75], [0.7, 0.35, 0.2], [0.85, 0.85, 0.7], [0.55, 0.2, 0.5]]
        n = 10
        for b in range(n):
            bz = z0 + 2.0 + b * ((length - 4.0) / (n - 1))
            h = 1.1 + (b % 3) * 0.32
            children.append(
                part(
                    f"Bottle_{shelf_i}_{b}",
                    (0.34, h, 0.34),
                    (back_x + 1.55, shelf_y + h / 2 - 0.5, bz),
                    bottle_colors[b % len(bottle_colors)],
                    material="Glass",
                    can_collide=False,
                )
            )

    # Bar sign
    children.append(part("BarSignBack", (0.4, 1.8, 7.0), (back_x + 1.2, 10.4, cz), [0.1, 0.05, 0.03], material="Wood"))
    children.append(part("BarSign", (0.25, 1.4, 6.4), (back_x + 1.5, 10.4, cz), [0.05, 0.02, 0.08], material="SmoothPlastic"))

    # Counter (marble top + body) facing +X
    children.append(part("CounterBody", (2.6, 3.4, length), (counter_x, 1.7, cz), [0.14, 0.07, 0.03], material="Wood"))
    children.append(part("CounterFront", (0.3, 3.0, length), (counter_x + 1.35, 1.6, cz), [0.24, 0.04, 0.08], material="Wood"))
    children.append(part("CounterTop", (3.2, 0.4, length + 0.6), (counter_x + 0.1, 3.55, cz), [0.88, 0.85, 0.8], material="Marble"))
    children.append(part("CounterNeon", (0.2, 0.2, length), (counter_x + 1.5, 3.3, cz), [0.925, 0.282, 0.6], material="Neon", can_collide=False))
    children.append(part("FootRail", (0.25, 0.25, length), (counter_x + 1.7, 0.55, cz), GOLD, material="Metal", can_collide=False))
    # subtle warm light source
    children.append(
        {
            "name": "BarWash",
            "className": "Part",
            "properties": {
                "Anchored": True,
                "Size": [0.3, 0.3, 0.3],
                "Position": [back_x + 2.0, 8.5, cz],
                "Transparency": 1.0,
                "CanCollide": False,
            },
        }
    )
    return {"name": "LoungeBar", "className": "Folder", "children": children}


def main() -> None:
    data = json.loads(LOBBY.read_text())
    atmosphere = find(data, "Atmosphere")
    tables = find(atmosphere, "Tables")
    assert atmosphere and tables

    roulette_specs = {}
    for t in tables["children"]:
        if (t.get("attributes") or {}).get("TableType") == "Roulette":
            felt = next(c for c in t["children"] if c["name"] == "Felt")
            pos = felt["properties"]["Position"]
            yaw = (t.get("attributes") or {}).get("TableYaw", 0.0)
            roulette_specs[t["name"]] = (pos[0], pos[2], yaw)

    new_children = []
    for t in tables["children"]:
        if (t.get("attributes") or {}).get("TableType") == "Roulette":
            cx, cz, yaw = roulette_specs[t["name"]]
            new_children.append(build_roulette(t["name"], cx, cz, yaw))
        else:
            new_children.append(t)
    tables["children"] = new_children

    # Replace bar
    for i, c in enumerate(atmosphere["children"]):
        if c.get("name") == "LoungeBar":
            atmosphere["children"][i] = build_bar()
            break

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"rebuilt {len(roulette_specs)} roulette tables + bar")
    for n, (x, z, y) in roulette_specs.items():
        print(f"  {n}: center=({x},{z}) yaw={y}")


if __name__ == "__main__":
    main()
