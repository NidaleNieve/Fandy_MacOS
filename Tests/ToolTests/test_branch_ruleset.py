import json
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[2]


class BranchRulesetTests(unittest.TestCase):
    def test_main_requires_pull_requests_and_real_github_actions_checks(self):
        ruleset = json.loads((ROOT / '.github/main-ruleset.json').read_text())
        self.assertEqual(ruleset['target'], 'branch')
        self.assertEqual(ruleset['enforcement'], 'active')
        self.assertEqual(ruleset['conditions']['ref_name'], {'include': ['refs/heads/main'], 'exclude': []})
        self.assertEqual(ruleset['bypass_actors'], [])
        rules = {rule['type']: rule for rule in ruleset['rules']}
        self.assertIn('deletion', rules)
        self.assertIn('non_fast_forward', rules)
        pr = rules['pull_request']['parameters']
        self.assertTrue(pr['required_review_thread_resolution'])
        self.assertEqual(pr['required_approving_review_count'], 0)
        self.assertIn('merge', pr['allowed_merge_methods'])
        checks = rules['required_status_checks']['parameters']
        self.assertTrue(checks['strict_required_status_checks_policy'])
        self.assertEqual({entry['context'] for entry in checks['required_status_checks']},
                         {'tests', 'sanitizers', 'native-release (macos-15)', 'native-release (macos-latest)'})
        self.assertTrue(all(entry['integration_id'] == 15368 for entry in checks['required_status_checks']))


if __name__ == '__main__':
    unittest.main()
