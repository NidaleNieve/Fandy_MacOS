import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location('distribute', ROOT / 'Scripts/distribute.py')
DISTRIBUTE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DISTRIBUTE)


class DistributionTests(unittest.TestCase):
    def test_release_metadata_comes_from_compiled_roster_and_pinned_source(self):
        report = DISTRIBUTE.PACKAGE.compatibility_manifest()
        self.assertEqual(set(report['referenceSupportedFamilies']), {'M1', 'M2', 'M3', 'M4', 'M5'})
        self.assertEqual(report['locallyTested'], ['Mac17,9'])
        self.assertIn('Mac16,8', report['referenceSupportedFamilies']['M4'])
        self.assertFalse(report['otherHardwarePhysicallyTested'])
        self.assertTrue(report['runtimeChecksRequired'])

    def test_development_identity_cannot_be_used_for_distribution(self):
        result = subprocess.CompletedProcess([], 0, b'1) ' + b'A' * 40 + b' "Apple Development: Example"', b'')
        with patch.object(DISTRIBUTE.PACKAGE, 'run', return_value=result):
            with self.assertRaises(ValueError):
                DISTRIBUTE.developer_identity()

    def test_identity_owner_is_not_returned_or_logged(self):
        result = subprocess.CompletedProcess([], 0, b'1) ' + b'A' * 40 + b' "Developer ID Application: Private Owner"', b'')
        with patch.object(DISTRIBUTE.PACKAGE, 'run', return_value=result):
            self.assertEqual(DISTRIBUTE.developer_identity(), 'A' * 40)

    def test_notarization_requires_accepted_status_and_successful_command(self):
        for status, code in [('Invalid', 0), ('Accepted', 1), ('In Progress', 0)]:
            result = subprocess.CompletedProcess([], code, json.dumps({'status': status}).encode(), b'private')
            with patch.object(DISTRIBUTE.subprocess, 'run', return_value=result):
                with self.assertRaises(ValueError):
                    DISTRIBUTE.notarize(Path('candidate.dmg'), 'local-profile')
        result = subprocess.CompletedProcess([], 0, b'{"status":"Accepted"}', b'')
        with patch.object(DISTRIBUTE.subprocess, 'run', return_value=result) as run:
            DISTRIBUTE.notarize(Path('candidate.dmg'), 'local-profile')
            self.assertIn('--keychain-profile', run.call_args.args[0])
            self.assertNotIn('--password', run.call_args.args[0])

    def test_missing_distribution_identity_cannot_publish_release(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'output'
            with patch.object(DISTRIBUTE.PACKAGE, 'verify_app', return_value=({}, 'Apple Development')), \
                 patch.object(DISTRIBUTE.PACKAGE, 'signature', return_value=('fixture', 'Apple Development')), \
                 patch.object(DISTRIBUTE, 'developer_identity', side_effect=ValueError('missing')):
                with self.assertRaises(ValueError):
                    DISTRIBUTE.distribute(Path(directory) / 'Fandy.app', output, 'local-profile')
            self.assertFalse(output.exists())

    def test_release_staging_rejects_development_signature_before_image_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'output'
            with patch.object(DISTRIBUTE.PACKAGE, 'verify_app', return_value=({}, 'Apple Development')):
                with self.assertRaises(ValueError):
                    DISTRIBUTE.PACKAGE.package(Path(directory) / 'Fandy.app', output, release_staging=True)
            self.assertFalse(output.exists())

    def test_distribution_resigning_uses_explicit_authenticated_identifier(self):
        with patch.object(DISTRIBUTE.PACKAGE, 'run') as run:
            DISTRIBUTE.sign(Path('FandyFanHelper'), 'fixture-hash', 'is.dsr.fandy.fan-helper')
            args = run.call_args.args[0]
            self.assertEqual(args[args.index('--identifier') + 1], 'is.dsr.fandy.fan-helper')
            self.assertIn('--timestamp', args)
            self.assertIn('runtime', args)

    def test_nonobject_notary_response_is_rejected_without_tool_output(self):
        for output in [b'null', b'[]', b'false', b'private invalid tool output']:
            result = subprocess.CompletedProcess([], 0, output, b'private')
            with patch.object(DISTRIBUTE.subprocess, 'run', return_value=result):
                with self.assertRaises(ValueError) as error:
                    DISTRIBUTE.notarize(Path('candidate.dmg'), 'local-profile')
                self.assertNotIn('private invalid', str(error.exception))

    def test_blank_or_multiline_profile_is_rejected_before_signing(self):
        for profile in ['', ' ', 'a\nb']:
            with self.assertRaises(ValueError):
                DISTRIBUTE.distribute(Path('Fandy.app'), Path('output'), profile)


if __name__ == '__main__':
    unittest.main()
