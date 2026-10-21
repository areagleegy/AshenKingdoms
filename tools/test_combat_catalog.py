"""Unit tests for prototype weapon and armor catalog validation."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from validate_combat_catalog import validate


def sample_weapon() -> dict:
    return {
        "id": "test_blade",
        "name_ar": "نصل اختبار",
        "category": "light_melee",
        "damage": 10,
        "range": 1.5,
        "windup_seconds": 0.2,
        "active_seconds": 0.1,
        "recovery_seconds": 0.3,
        "stamina_cost": 4,
        "poise_damage": 2,
        "ammo_capacity": 0,
        "charges": 0,
        "cooldown_seconds": 0.0,
        "charge_seconds": 0.0,
        "interruptible": False,
        "durability_max": 80,
        "weight": 2.0,
    }


def sample_armor() -> dict:
    return {
        "id": "test_armor",
        "name_ar": "درع اختبار",
        "weight": 5.0,
        "damage_reduction": 0.2,
        "movement_speed_multiplier": 0.95,
        "dodge_distance_multiplier": 0.9,
        "poise_resistance": 3.0,
        "durability_max": 90,
    }


class CombatCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        combat = self.root / "data" / "combat"
        combat.mkdir(parents=True)
        self.weapons = {
            "schema_version": 1, "balance_status": "prototype",
            "weapons": [sample_weapon()],
        }
        self.armor = {
            "schema_version": 1, "balance_status": "prototype",
            "max_carry_weight": 30.0,
            "encumbrance_thresholds_percent": [50, 80, 100],
            "armor": [sample_armor()],
        }
        self._write()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write(self) -> None:
        (self.root / "data" / "combat" / "weapons.json").write_text(
            json.dumps(self.weapons), encoding="utf-8"
        )
        (self.root / "data" / "combat" / "armor.json").write_text(
            json.dumps(self.armor), encoding="utf-8"
        )

    def test_valid_catalogs_pass(self) -> None:
        self.assertEqual(validate(self.root), [])

    def test_negative_damage_is_rejected(self) -> None:
        self.weapons["weapons"][0]["damage"] = -1
        self._write()
        self.assertTrue(any("damage" in error for error in validate(self.root)))

    def test_nan_is_rejected(self) -> None:
        self.weapons["weapons"][0]["range"] = float("nan")
        self._write()
        self.assertTrue(any("finite number" in error for error in validate(self.root)))

    def test_duplicate_ids_are_rejected(self) -> None:
        self.weapons["weapons"].append(sample_weapon())
        self._write()
        self.assertTrue(any("duplicate id" in error for error in validate(self.root)))

    def test_charged_skill_requires_charges_and_cooldown(self) -> None:
        weapon = self.weapons["weapons"][0]
        weapon.update({
            "category": "charged_skill", "charges": 0,
            "charge_seconds": 0, "cooldown_seconds": 0,
        })
        self._write()
        self.assertTrue(any("charged_skill requires" in error for error in validate(self.root)))

    def test_damage_reduction_must_not_exceed_one(self) -> None:
        self.armor["armor"][0]["damage_reduction"] = 1.2
        self._write()
        self.assertTrue(any("damage_reduction" in error for error in validate(self.root)))

    def test_encumbrance_thresholds_must_increase(self) -> None:
        self.armor["encumbrance_thresholds_percent"] = [50, 50, 20]
        self._write()
        self.assertTrue(any("strictly increasing" in error for error in validate(self.root)))


if __name__ == "__main__":
    unittest.main()
