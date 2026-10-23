import unittest
from test_lab import load_catalog, COMMANDS, make_report

class TestLabTests(unittest.TestCase):
    def test_catalog_has_known_commands(self):
        catalog = load_catalog()
        for item in catalog['scenarios']:
            if item['kind'] == 'automated':
                self.assertIn(item['command'], COMMANDS)

    def test_manual_scenarios_exist(self):
        catalog = load_catalog()
        self.assertTrue(any(item['id'] == 'android_device' and item['kind'] == 'manual' for item in catalog['scenarios']))

    def test_failed_scenario_fails_report(self):
        catalog = load_catalog()
        ids = catalog['profiles']['python']
        results = [{'id': sid, 'status': 'passed'} for sid in ids]
        results[0]['status'] = 'failed'
        self.assertEqual(make_report(catalog, 'python', results)['overall_status'], 'failed')

    def test_missing_scenario_fails_report(self):
        catalog = load_catalog()
        ids = catalog['profiles']['python']
        results = [{'id': sid, 'status': 'passed'} for sid in ids[:-1]]
        self.assertEqual(make_report(catalog, 'python', results)['overall_status'], 'failed')

if __name__ == '__main__':
    unittest.main()
