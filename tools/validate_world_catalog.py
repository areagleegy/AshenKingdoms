#!/usr/bin/env python3
"""Validate structural integrity and cross-references in Ashen Kingdoms world data."""
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
    schema_version = world.get("schema_version")
    if isinstance(schema_version, bool) or not isinstance(schema_version, int) or schema_version != 1:
        errors.append("schema_version must be integer 1")
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

    def string_list(record: dict[str, Any], field: str, label: str) -> list[str]:
        value = record.get(field, [])
        if not isinstance(value, list):
            errors.append(f"{label}.{field} must be an array")
            return []
        result: list[str] = []
        for index, item in enumerate(value):
            if not isinstance(item, str) or not item:
                errors.append(f"{label}.{field}[{index}] must be a non-empty string")
            else:
                result.append(item)
        return result

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

    regions = records(("regions",), "regions")
    settlements = records(("settlements",), "settlements")
    factions = records(("factions",), "factions")
    characters = records(("characters",), "characters")
    creatures = records(("creatures",), "creatures")
    quests = records(("quest_chains",), "quest_chains")
    waterways = records(("waterways",), "waterways")
    world_events = records(("world_events",), "world_events")

    region_ids = unique_ids(regions, "regions")
    settlement_ids = unique_ids(settlements, "settlements")
    faction_ids = unique_ids(factions, "factions")
    character_ids = unique_ids(characters, "characters")
    creature_ids = unique_ids(creatures, "creatures")
    quest_ids = unique_ids(quests, "quest_chains")
    unique_ids(waterways, "waterways")
    unique_ids(world_events, "world_events")

    landmark_ids: set[str] = set()
    for region in regions:
        label = f"region {region.get('id')}"
        names = region.get("name")
        if not isinstance(names, dict) or not isinstance(names.get("ar"), str) or not names.get("ar") or not isinstance(names.get("en"), str) or not names.get("en"):
            errors.append(f"{label} must have Arabic and English names")
        for landmark in string_list(region, "landmarks", label):
            if landmark in landmark_ids:
                errors.append(f"duplicate landmark id: {landmark}")
            landmark_ids.add(landmark)
        for creature_id in string_list(region, "threats", label):
            if creature_id not in creature_ids:
                errors.append(f"{label} references unknown creature {creature_id}")

    for settlement in settlements:
        if settlement.get("region") not in region_ids:
            errors.append(f"settlement {settlement.get('id')} references unknown region")

    for creature in creatures:
        label = f"creature {creature.get('id')}"
        for region_id in string_list(creature, "habitats", label):
            if region_id not in region_ids:
                errors.append(f"{label} references unknown habitat {region_id}")

    for character in characters:
        home = character.get("home")
        if not isinstance(home, str) or (home not in settlement_ids and home not in landmark_ids):
            errors.append(f"character {character.get('id')} references unknown home {home}")

    for quest in quests:
        if quest.get("start_npc") not in character_ids:
            errors.append(f"quest {quest.get('id')} references unknown NPC")
        if quest.get("region") not in region_ids:
            errors.append(f"quest {quest.get('id')} references unknown region")
        title = quest.get("title")
        if not isinstance(title, dict) or not isinstance(title.get("en"), str) or not title.get("en") or not isinstance(title.get("ar"), str) or not title.get("ar"):
            errors.append(f"quest {quest.get('id')} must have Arabic and English titles")

    for faction in factions:
        relations = faction.get("relations", {})
        if not isinstance(relations, dict):
            errors.append(f"faction {faction.get('id')} relations must be an object")
            continue
        for related_faction in relations:
            if related_faction not in faction_ids:
                errors.append(f"faction {faction.get('id')} references unknown faction {related_faction}")

    for waterway in waterways:
        label = f"waterway {waterway.get('id')}"
        for region_id in string_list(waterway, "connects", label):
            if region_id not in region_ids:
                errors.append(f"{label} references unknown region {region_id}")

    equipment = world.get("equipment", {})
    if not isinstance(equipment, dict):
        errors.append("equipment must be an object")
    else:
        for category in ("weapons", "armor", "shields"):
            items = equipment.get(category)
            if not isinstance(items, list):
                errors.append(f"equipment.{category} must be an array")
                continue
            valid_items = [item for item in items if isinstance(item, dict)]
            if len(valid_items) != len(items):
                errors.append(f"equipment.{category} entries must be objects")
            unique_ids(valid_items, f"equipment.{category}")
            numeric_fields = (
                "damage", "reach_m", "windup_s", "recovery_s", "stamina_cost",
                "durability", "physical_resist", "elemental_resist", "guard",
                "stability", "mobility", "noise", "weight", "ammo_capacity",
                "charge_s", "charges",
            )
            for item in valid_items:
                for field in numeric_fields:
                    if field not in item:
                        continue
                    value = item[field]
                    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
                        errors.append(f"{item.get('id')} has invalid {field}")

    transport = world.get("transport", {})
    if not isinstance(transport, dict):
        errors.append("transport must be an object")
    else:
        for category in ("mounts", "vehicles", "ships"):
            items = transport.get(category)
            if not isinstance(items, list):
                errors.append(f"transport.{category} must be an array")
                continue
            valid_items = [item for item in items if isinstance(item, dict)]
            if len(valid_items) != len(items):
                errors.append(f"transport.{category} entries must be objects")
            unique_ids(valid_items, f"transport.{category}")
            numeric_fields = ("speed", "stamina", "cargo_slots", "capacity", "crew", "defense", "cargo", "weapons")
            for item in valid_items:
                for field in numeric_fields:
                    if field not in item:
                        continue
                    value = item[field]
                    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
                        errors.append(f"transport {item.get('id')} has invalid {field}")
                for region_id in string_list(item, "terrain_bonus", f"transport {item.get('id')}"):
                    if region_id not in region_ids:
                        errors.append(f"transport {item.get('id')} references unknown region {region_id}")

    progression = world.get("progression", {})
    if not isinstance(progression, dict):
        errors.append("progression must be an object")
    else:
        order = progression.get("recommended_region_order", [])
        if not isinstance(order, list):
            errors.append("progression.recommended_region_order must be an array")
        else:
            for region_id in order:
                if not isinstance(region_id, str) or region_id not in region_ids:
                    errors.append(f"progression references unknown region {region_id}")
        bands = progression.get("level_bands", [])
        if not isinstance(bands, list):
            errors.append("progression.level_bands must be an array")
        else:
            for index, band in enumerate(bands):
                if not isinstance(band, dict):
                    errors.append(f"progression.level_bands[{index}] must be an object")
                    continue
                minimum, maximum = band.get("min"), band.get("max")
                if (
                    isinstance(minimum, bool) or not isinstance(minimum, (int, float))
                    or isinstance(maximum, bool) or not isinstance(maximum, (int, float))
                    or minimum < 0 or maximum < minimum
                ):
                    errors.append(f"progression.level_bands[{index}] has an invalid range")
                if band.get("region") not in region_ids:
                    errors.append(f"progression.level_bands[{index}] references unknown region")

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
