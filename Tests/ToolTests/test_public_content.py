import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('public_content', Path(__file__).parents[2] / 'Scripts/check-public-content.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicContentTests(unittest.TestCase):
    def test_raw_logs_and_local_configuration_are_rejected(self):
        for path in ['build/data.swift', 'sample.csv', 'capture.jsonl', 'Config/Signing.local.xcconfig',
                     'docs/BUILD_VERIFICATION.md', '.env', 'docs/local/evidence.md']:
            self.assertIn('private artifact', module.scan(path, b'ordinary text'))

    def test_identity_and_credentials_are_reported_without_echoing_values(self):
        values = ['/' + 'Users/privateaccount/Documents', 'person' + '@mail.test', 'ghp_' + 'x' * 36,
                  'DEVELOPMENT_' + 'TEAM = ABCDE12345', '-----BEGIN ' + 'PRIVATE KEY-----']
        for value in values:
            issues = module.scan('README.md', value.encode())
            self.assertTrue(issues)
            self.assertTrue(all(value not in issue for issue in issues))

    def test_required_license_attribution_is_preserved(self):
        text = ('Copyright External Author <author' + '@thirdparty.test>').encode()
        self.assertFalse(module.scan('docs/licenses/reference.txt', text))
        self.assertTrue(module.scan('README.md', text))

    def test_comparison_against_local_identity_does_not_embed_it_in_policy(self):
        self.assertIn('local signing identifier', module.scan('source.swift', b'ABCDE12345', ['ABCDE12345']))
        self.assertIn('local account name', module.scan('source.swift', b'privateaccount', username='privateaccount'))

    def test_source_with_public_identities_and_placeholders_is_allowed(self):
        text = ('is.dsr.fandy\nis.dsr.fandy.fan-helper\n#include? "Signing.local.xcconfig"\ncontact' + '@example.invalid').encode()
        self.assertFalse(module.scan('Config/Signing.xcconfig', text))

    def test_binary_artifacts_are_rejected(self):
        self.assertIn('binary or oversized artifact', module.scan('capture.dat', b'\0private'))


if __name__ == '__main__':
    unittest.main()
