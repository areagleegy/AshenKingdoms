#!/usr/bin/env python3
"""Validate structural integrity of the bundled Ashen Kingdoms world design data."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

WORLD_PATH = Path(__file__).resolve().parents[1] / "content" / "world" / "world_catalog.json"


def validate_world(world: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(world, dict):
        return ["world root must be an object"]
    if world.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if world.get("world_id") != "ashen_kingdoms":
        errors.append("world_id must be ashen_kingdoms")

    def records(path: tuple[str, ...], label: str) -> list[dict[str, Any]]:
        value: Any = world
        for key in path:
            value = value.get(key) if isinstance(value, dict) else None
        if not isinstance(value, list):
            errors.append(f"{label} must be an array")
            return []
        result: list[dict[str, Any]] = []
        for index, item in enumerate(value):
            if not isinstance(item, dict):
                errors.append(f"{label}[{index}] must be an object")
            else:
                result.append(item)
        return result

    regions = records(("regions",), "regions")
    settlements = records(("settlements",), "settlements")
    factions = records(("factions",), "factions")
    characters = records(("characters",), "characters")
    creatures = records(("creatures",), "creatures")
    quests = records(("quest_chains",), "quest_chains")
    waterways = records(("waterways",), "waterways")

    def unique_ids(items: list[dict[str, Any]], label: str) -> set[str]:
        ids: set[str] = set()
        for item in items:
            item_id = item.get("id")
            if not isinstance(item_id, str) or not item_id:
                errors.append(f"{label} entry has missing or invalid id")
            elif item_id in ids:
                errors.append(f"{label} has duplicate id: {item_id}")
            else:
                ids.add(item_id)
        return ids

    region_ids = unique_ids(regions, "regions")
    settlement_ids = unique_ids(settlements, "settlements")
    faction_ids = unique_ids(factions, "factions")
    character_ids = unique_ids(characters, "characters")
    creature_ids = unique_ids(creatures, "creatures")
    quest_ids = unique_ids(quests, "quest_chains")

    for faction in factions:
        for related_faction in faction.get("relations", {}):
            if related_faction not in faction_ids:
                errors.append(
                    f"faction {faction.get('id')} references unknown faction {related_faction}"
                )
    unique_ids(waterways, "waterways")

    for region in regions:
        if not isinstance(region.get("name"), dict) or not region["name"].get("ar") or not region["name"].get("en"):
            errors.append(f"region {region.get('id')} must have Arabic and English names")
        for creature_id in region.get("threats", []):
            if creature_id not in creature_ids:
                errors.append(f"region {region.get('id')} references unknown creature {creature_id}")

    for settlement in settlements:
        if settlement.get("region") not in region_ids:
            errors.append(f"settlement {settlement.get('id')} references unknown region")
    for creature in creatures:
        for region_id in creature.get("habitats", []):
            if region_id not in region_ids:
                errors.append(f"creature {creature.get('id')} references unknown habitat {region_id}")
    for character in characters:
        home = character.get("home")
        landmark_ids = {
            landmark
            for region in regions
            for landmark in region.get("landmarks", [])
        }
        if home not in settlement_ids and home not in landmark_ids:
            errors.append(f"character {character.get('id')} references unknown home {home}")
    for quest in quests:
        if quest.get("start_npc") not in character_ids:
            errors.append(f"quest {quest.get('id')} references unknown NPC")
        if quest.get("region") not in region_ids:
            errors.append(f"quest {quest.get('id')} references unknown region")

    equipment = world.get("equipment", {})
    if not isinstance(equipment, dict):
        errors.append("equipment must be an object")
    else:
        for category in ("weapons", "armor", "shields"):
            items = equipment.get(category)
            if not isinstance(items, list):
                errors.append(f"equipment.{category} must be an array")
                continue
            item_ids = unique_ids(items, f"equipment.{category}")
            for item in items:
                for field in ("damage", "reach_m", "windup_s", "recovery_s", "stamina_cost"):
                    if field in item and (not isinstance(item[field], (int, float)) or item[field] < 0):
                        errors.append(f"{item.get('id')} has invalid {field}")
                for field in ("durability", "guard", "stability"):
                    if field in item and (not isinstance(item[field], (int, float)) or item[field] < 0):
                        errors.append(f"{item.get('id')} has invalid {field}")

    transport = world.get("transport", {})
    if not isinstance(transport, dict):
        errors.append("transport must be an object")
    else:
        for category in ("mounts", "vehicles", "ships"):
            items = transport.get(category)
            if not isinstance(items, list):
                errors.append(f"transport.{category} must be an array")
            else:
                unique_ids(items, f"transport.{category}")

    progression = world.get("progression", {})
    if isinstance(progression, dict):
        for region_id in progression.get("recommended_region_order", []):
            if region_id not in region_ids:
                errors.append(f"progression references unknown region {region_id}")
    else:
        errors.append("progression must be an object")

    if not factions or not settlements or not characters or not creatures or not quests:
        errors.append("world catalog must include factions, settlements, characters, creatures, and quests")
    if len(quest_ids) != len(quests):
        errors.append("quest ids must be unique")
    return errors


def main() -> int:
    try:
        world = json.loads(WORLD_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"World catalog could not be read: {exc}", file=sys.stderr)
        return 1
    errors = validate_world(world)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "World catalog valid: "
        f"{len(world['regions'])} regions, {len(world['settlements'])} settlements, "
        f"{len(world['factions'])} factions, {len(world['characters'])} characters, "
        f"{len(world['creatures'])} creatures, {len(world['quest_chains'])} quest chains."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
