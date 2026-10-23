#!/usr/bin/env python3
"""Validate prototype weapon and armor catalogs using only the Python stdlib."""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]{1,47}$")
WEAPON_NUMBERS = (
    "damage", "range", "windup_seconds", "active_seconds",
    "recovery_seconds", "stamina_cost", "poise_damage",
    "cooldown_seconds", "charge_seconds", "weight",
)
ARMOR_NUMBERS = (
    "weight", "damage_reduction", "movement_speed_multiplier",
    "dodge_distance_multiplier", "poise_resistance",
)
WEAPON_CATEGORIES = {
    "light_melee", "medium_melee", "heavy_melee",
    "ranged", "charged_skill", "limited_throw",
}


def _number(record: dict[str, Any], key: str, prefix: str, errors: list[str],
            *, minimum: float = 0.0, maximum: float | None = None) -> None:
    value = record.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        errors.append(f"{prefix}.{key} must be a finite number.")
        return
    if value < minimum or (maximum is not None and value > maximum):
        bound = f"{minimum}..{maximum}" if maximum is not None else f">= {minimum}"
        errors.append(f"{prefix}.{key} must be in range {bound}.")


def _positive_number(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value) and value > 0


def _integer(record: dict[str, Any], key: str, prefix: str, errors: list[str]) -> None:
    value = record.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        errors.append(f"{prefix}.{key} must be a non-negative integer.")


def _catalog(path: Path, collection: str, errors: list[str]) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{path}: cannot read valid JSON ({exc}).")
        return None
    if not isinstance(data, dict):
        errors.append(f"{path}: root must be a JSON object.")
        return None
    if data.get("schema_version") != 1:
        errors.append(f"{path}: schema_version must equal 1.")
    if data.get("balance_status") != "prototype":
        errors.append(f"{path}: balance_status must be 'prototype'.")
    records = data.get(collection)
    if not isinstance(records, list) or not records:
        errors.append(f"{path}: {collection} must be a non-empty array.")
        return data
    seen: set[str] = set()
    for index, record in enumerate(records):
        prefix = f"{path}:{collection}[{index}]"
        if not isinstance(record, dict):
            errors.append(f"{prefix} must be an object.")
            continue
        item_id = record.get("id")
        if not isinstance(item_id, str) or not ID_PATTERN.fullmatch(item_id):
            errors.append(f"{prefix}.id has an invalid format.")
        elif item_id in seen:
            errors.append(f"{prefix}: duplicate id {item_id!r}.")
        else:
            seen.add(item_id)
        if not isinstance(record.get("name_ar"), str) or not record["name_ar"].strip():
            errors.append(f"{prefix}.name_ar must be a non-empty string.")
        if collection == "weapons":
            category = record.get("category")
            if not isinstance(category, str) or category not in WEAPON_CATEGORIES:
                errors.append(f"{prefix}.category is unsupported.")
            for key in WEAPON_NUMBERS:
                _number(record, key, prefix, errors)
            for key in ("ammo_capacity", "charges", "durability_max"):
                _integer(record, key, prefix, errors)
            if not isinstance(record.get("interruptible"), bool):
                errors.append(f"{prefix}.interruptible must be boolean.")
            if isinstance(record.get("active_seconds"), (int, float)) and not isinstance(record.get("active_seconds"), bool) and record["active_seconds"] <= 0:
                errors.append(f"{prefix}.active_seconds must be greater than zero.")
            if category == "charged_skill":
                if not _positive_number(record.get("charges")) or not _positive_number(record.get("charge_seconds")) or not _positive_number(record.get("cooldown_seconds")):
                    errors.append(f"{prefix}: charged_skill requires charges, charge time, and cooldown.")
            if category in {"ranged", "limited_throw"} and not _positive_number(record.get("ammo_capacity")):
                errors.append(f"{prefix}: ranged/limited_throw requires positive ammo_capacity.")
            if not _positive_number(record.get("durability_max")):
                errors.append(f"{prefix}.durability_max must be at least 1.")
        else:
            for key in ARMOR_NUMBERS:
                _number(record, key, prefix, errors)
            _integer(record, "durability_max", prefix, errors)
            _number(record, "damage_reduction", prefix, errors, maximum=1.0)
            for key in ("movement_speed_multiplier", "dodge_distance_multiplier"):
                _number(record, key, prefix, errors, minimum=0.01, maximum=2.0)
            if record.get("durability_max", 0) < 1:
                errors.append(f"{prefix}.durability_max must be at least 1.")
    return data


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    weapons_path = root / "data" / "combat" / "weapons.json"
    armor_path = root / "data" / "combat" / "armor.json"
    weapons_data = _catalog(weapons_path, "weapons", errors)
    armor_data = _catalog(armor_path, "armor", errors)
    if armor_data is not None:
        _number(armor_data, "max_carry_weight", str(armor_path), errors, minimum=0.01)
        thresholds = armor_data.get("encumbrance_thresholds_percent")
        if not isinstance(thresholds, list) or not thresholds or any(
            isinstance(value, bool) or not isinstance(value, (int, float))
            or not math.isfinite(value) or value <= 0 or value > 100
            for value in thresholds
        ):
            errors.append(f"{armor_path}: encumbrance thresholds must be finite percentages in (0, 100].")
        elif thresholds != sorted(set(thresholds)):
            errors.append(f"{armor_path}: encumbrance thresholds must be strictly increasing.")
    if weapons_data is not None and armor_data is not None:
        if weapons_data.get("schema_version") != armor_data.get("schema_version"):
            errors.append("Weapon and armor schema versions must match.")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = validate(args.root.resolve())
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"Combat catalog validation failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1
    print("Combat catalogs OK: weapon and armor prototype data validated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
