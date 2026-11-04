import json
from pathlib import Path
import os
import subprocess
import unittest

ROOT = Path(__file__).parents[2]


class BranchRulesetTests(unittest.TestCase):
    def test_feature_branch_push_and_pull_request_do_not_run_duplicate_checks(self):
        parsed = subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e',
            'puts JSON.generate(YAML.load_file(ARGV[0]))',
            str(ROOT / '.github/workflows/verification.yml')], text=True)
        workflow = json.loads(parsed)
        events = workflow.get('on', workflow.get('true'))
        self.assertIn('pull_request', events)
        self.assertEqual(events['push']['branches'], ['main'])

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

    def test_required_jobs_fail_when_scope_fails_but_allow_obsolete_run_cancellation(self):
        parsed = subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e',
            'puts JSON.generate(YAML.load_file(ARGV[0]))',
            str(ROOT / '.github/workflows/verification.yml')], text=True)
        workflow = json.loads(parsed)
        for name in ['tests', 'sanitizers', 'native-release']:
            job = workflow['jobs'][name]
            with self.subTest(job=name):
                self.assertEqual(job['needs'], 'scope')
                self.assertIn('!cancelled()', job['if'])
                gate = job['steps'][0]['run']
                for result, app, accepted in [('success', 'true', True), ('success', 'false', True),
                                              ('failure', 'false', False), ('skipped', '', False),
                                              ('success', 'unknown', False)]:
                    status = subprocess.run(['sh', '-c', gate],
                        env={**os.environ, 'RESULT': result, 'APP': app}, capture_output=True)
                    self.assertEqual(status.returncode == 0, accepted, (name, result, app))


if __name__ == '__main__':
    unittest.main()
