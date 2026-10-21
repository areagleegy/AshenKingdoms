import unittest
from test_lab import load_catalog, COMMANDS

class TestLabTests(unittest.TestCase):
    def test_catalog_has_known_commands(self):
        catalog = load_catalog()
        for item in catalog['scenarios']:
            if item['kind'] == 'automated':
                self.assertIn(item['command'], COMMANDS)

    def test_manual_scenarios_exist(self):
        catalog = load_catalog()
        self.assertTrue(any(item['id'] == 'android_device' and item['kind'] == 'manual' for item in catalog['scenarios']))

if __name__ == '__main__':
    unittest.main()
