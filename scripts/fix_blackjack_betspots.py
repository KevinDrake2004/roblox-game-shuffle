#!/usr/bin/env python3
"""Layer blackjack bet spots so the numbered tile sits flush ON the felt (not a
floating puck) while its number stays un-occluded (no flicker).

- BetSpot: numbered disc, bottom flush with the felt top, only slightly proud.
- BetRing: wider gold halo that sits basically flush around it, clearly lower
  than the spot's top face so it never covers the number.

Idempotent (sets absolute heights derived from each table's felt)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOBBY = ROOT / "src/map/Lobby.model.json"


def find(node: dict, name: str):
    if node.get("name") == name:
        return node
    for child in node.get("children") or []:
        found = find(child, name)
        if found:
            return found
    return None


def set_top(props: dict, top: float) -> None:
    props["Position"][1] = top - props["Size"][1] / 2


def main() -> None:
    data = json.loads(LOBBY.read_text())
    atmosphere = find(data, "Atmosphere")
    tables = find(atmosphere, "Tables")
    assert tables

    changed = 0
    for t in tables["children"]:
        if (t.get("attributes") or {}).get("TableType") != "Blackjack":
            continue
        felt = next((c for c in t["children"] if c["name"] == "Felt"), None)
        if not felt:
            continue
        felt_top = felt["properties"]["Position"][1] + felt["properties"]["Size"][1] / 2
        for c in t["children"]:
            name = c.get("name", "")
            p = c.get("properties")
            if not p or "Size" not in p:
                continue
            if name.startswith("BetRing_"):
                # Wide gold halo, nearly flush with the felt and well below the
                # spot's top face so it never covers the number.
                p["Size"] = [1.2, 0.05, 1.2]
                set_top(p, felt_top + 0.02)
                p["CanCollide"] = False
                changed += 1
            elif name.startswith("BetSpot_"):
                # Numbered tile planted ON the felt (bottom flush), only slightly
                # proud so it reads as painted-on, not a floating puck.
                p["Size"] = [0.9, 0.08, 0.9]
                set_top(p, felt_top + 0.08)
                p["CanCollide"] = False
                changed += 1

    LOBBY.write_text(json.dumps(data, indent=2) + "\n")
    print(f"adjusted {changed} bet-spot parts")


if __name__ == "__main__":
    main()
