import importlib.util
from pathlib import Path
import unittest
import struct
import zlib

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

    @staticmethod
    def png(extra=b''):
        def chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) + extra
                + chunk(b'IDAT', zlib.compress(b'\0\xff\xff\xff\xff')) + chunk(b'IEND', b''))

    def test_only_reviewed_metadata_free_app_image_is_allowed(self):
        png = self.png()
        self.assertFalse(module.scan('docs/images/profiles.png', png))
        self.assertTrue(module.scan('docs/images/unreviewed.png', png))
        self.assertTrue(module.scan('docs/images/profiles.png', b'not a PNG'))
        self.assertTrue(module.scan('docs/images/profiles.png', png + b'trailing private data'))
        corrupt = bytearray(png); corrupt[-1] ^= 1
        self.assertTrue(module.scan('docs/images/profiles.png', bytes(corrupt)))

    def test_png_text_metadata_is_rejected_without_echoing_it(self):
        text = b'tEXt' + b'private metadata'
        extra = struct.pack('>I', len(text) - 4) + text + struct.pack('>I', zlib.crc32(text))
        self.assertEqual(module.scan('docs/images/profiles.png', self.png(extra)), ['unreviewed PNG metadata'])


if __name__ == '__main__':
    unittest.main()
