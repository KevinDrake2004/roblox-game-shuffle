#!/usr/bin/env python3
"""Re-align blackjack table props on angled tables.

The two angled blackjack tables (yaw +-12) had their off-centre props (Shoe,
Discard, DealerPad, BetSpot_*, BetRing_*) placed with the wrong rotation, so
they landed off the rotated felt - the same parallelogram bug that hit the
roulette tables.

Fix: take the canonical local offset of every part from a straight (yaw 0)
table, then recompute each part's world X/Z on every table as
    world = feltCenter + Rot(yaw) * localOffset
using Roblox's Orientation(0, yaw, 0) convention
(wx = cx + lx*cos + lz*sin, wz = cz - lx*sin + lz*cos), matching the felt.

Y heights are preserved (the height/flush fix stays intact). Idempotent and a
no-op on the already-correct straight tables."""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOBBY = ROOT / "src/map/Lobby.model.json"


def walk(node: dict):
    yield node
    for child in node.get("children") or []:
        yield from walk(child)


def felt_center(table: dict) -> tuple[float, float]:
    felt = next(c for c in table["children"] if c["name"] == "Felt")
    pos = felt["properties"]["Position"]
    return pos[0], pos[2]


def main() -> None:
    data = json.loads(LOBBY.read_text())
    tables = next(n for n in walk(data) if n.get("name") == "Tables")
    blackjack = [
        t for t in tables["children"] if (t.get("attributes") or {}).get("TableType") == "Blackjack"
    ]
    if not blackjack:
        print("no blackjack tables found")
        return

    template = next(
        t for t in blackjack if abs((t.get("attributes") or {}).get("TableYaw", 0.0)) < 1e-6
    )
    tcx, tcz = felt_center(template)
    canon: dict[str, tuple[float, float]] = {}
    for c in template["children"]:
        p = c.get("properties") or {}
        if "Position" not in p:
            continue
        canon[c["name"]] = (p["Position"][0] - tcx, p["Position"][2] - tcz)

    changed = 0
    for table in blackjack:
        yaw = float((table.get("attributes") or {}).get("TableYaw", 0.0))
        cx, cz = felt_center(table)
        rad = math.radians(yaw)
        cos_y, sin_y = math.cos(rad), math.sin(rad)
        for c in table["children"]:
            p = c.get("properties") or {}
            if "Position" not in p:
                continue
            offset = canon.get(c["name"])
            if offset is None:
                continue
            lx, lz = offset
            p["Position"][0] = round(cx + lx * cos_y + lz * sin_y, 4)
            p["Position"][2] = round(cz - lx * sin_y + lz * cos_y, 4)
            p["Orientation"] = [0.0, yaw, 0.0]
            changed += 1

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"aligned {changed} parts across {len(blackjack)} blackjack tables")


if __name__ == "__main__":
    main()
