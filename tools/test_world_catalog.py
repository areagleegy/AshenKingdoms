"""Regression tests for the Ashen Kingdoms world catalog."""
from __future__ import annotations

import copy
import json
import unittest

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

    def test_character_home_may_reference_a_region_landmark(self) -> None:
        self.assertEqual(validate_world(self.world), [])
        uncrowned = next(item for item in self.world["characters"] if item["id"] == "the_uncrowned")
        self.assertEqual(uncrowned["home"], "throne_without_a_king")

    def test_every_character_questline_resolves_to_a_quest_chain(self) -> None:
        quest_titles = {quest["title"]["en"] for quest in self.world["quest_chains"]}
        self.assertTrue(all(character["questline"] in quest_titles for character in self.world["characters"]))

    def test_unknown_character_questline_is_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["characters"][0]["questline"] = "Missing Questline"
        self.assertTrue(any("unknown questline" in error for error in validate_world(world)))

    def test_unknown_creature_habitat_is_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["creatures"][0]["habitats"] = ["missing_region"]
        self.assertTrue(any("unknown habitat" in error for error in validate_world(world)))

    def test_unknown_waterway_region_is_rejected(self) -> None:
        world = copy.deepcopy(self.world)
        world["waterways"][0]["connects"] = ["missing_region"]
        self.assertTrue(any("references unknown region" in error for error in validate_world(world)))

    def test_malformed_faction_relations_are_reported(self) -> None:
        world = copy.deepcopy(self.world)
        world["factions"][0]["relations"] = ["not", "an", "object"]
        errors = validate_world(world)
        self.assertTrue(any("relations must be an object" in error for error in errors))

    def test_malformed_region_threats_are_reported_without_crashing(self) -> None:
        world = copy.deepcopy(self.world)
        world["regions"][0]["threats"] = {"unexpected": "object"}
        errors = validate_world(world)
        self.assertTrue(any("threats must be an array" in error for error in errors))

    def test_malformed_transport_terrain_bonus_is_reported(self) -> None:
        world = copy.deepcopy(self.world)
        world["transport"]["mounts"][0]["terrain_bonus"] = {"ashen_basin": True}
        errors = validate_world(world)
        self.assertTrue(any("terrain_bonus must be an array" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
