"""Regression tests for the Ashen Kingdoms world catalog."""
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.validate_world_catalog import WORLD_PATH, validate_world


class WorldCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.world = json.loads(WORLD_PATH.read_text(encoding="utf-8"))

    def test_bundled_world_catalog_is_valid(self) -> None:
        self.assertEqual(validate_world(self.world), [])

    def test_duplicate_region_ids_are_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["regions"].append(copy.deepcopy(world["regions"][0]))
        self.assertTrue(any("duplicate id" in error for error in validate_world(world)))

    def test_unknown_settlement_region_is_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["settlements"][0]["region"] = "missing_region"
        self.assertTrue(any("unknown region" in error for error in validate_world(world)))

    def test_unknown_quest_npc_is_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["quest_chains"][0]["start_npc"] = "missing_character"
        self.assertTrue(any("unknown NPC" in error for error in validate_world(world)))

    def test_negative_weapon_damage_is_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["equipment"]["weapons"][0]["damage"] = -1
        self.assertTrue(any("invalid damage" in error for error in validate_world(world)))


if __name__ == "__main__":
    unittest.main()
