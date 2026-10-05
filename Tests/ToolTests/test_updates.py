import importlib.util
from pathlib import Path
import plistlib
import re
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location('release_updates', ROOT / 'Scripts/distribute.py')
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)

class UpdateReleaseTests(unittest.TestCase):
    def test_release_and_helper_build_identity_match(self):
        info = plistlib.loads((ROOT / 'Config/App-Info.plist').read_bytes())
        policy = (ROOT / 'Sources/FandyCore/UpdatePolicy.swift').read_text()
        self.assertEqual(info['CFBundleVersion'], re.search(r'identifier = "([0-9]+)"', policy)[1])
        self.assertEqual(info['CFBundleShortVersionString'], re.search(r'version = "([0-9.]+)"', policy)[1])
        self.assertEqual(info['SUScheduledCheckInterval'], 7*24*3600)
        self.assertEqual(info['SUScheduledImpatientCheckInterval'], 14*24*3600)
        self.assertFalse(info['SUEnableSystemProfiling'])
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
        self.assertTrue(info['SUFeedURL'].startswith('https://raw.githubusercontent.com/'))
        self.assertEqual(len(info['SUPublicEDKey']), 44)
        self.assertIn('exact: "2.10.0"', (ROOT / 'Package.swift').read_text())
    def test_helper_has_explicit_argument_vector(self):
        helper = plistlib.loads((ROOT / 'Config/is.dsr.fandy.fan-service.plist').read_bytes())
        self.assertEqual(helper['BundleProgram'], 'Contents/Library/HelperTools/FandyFanHelper')
        self.assertEqual(helper['ProgramArguments'], ['FandyFanHelper'])
        self.assertNotIn('Program', helper)
    def test_framework_signing_is_inside_out(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)/'Fandy.app'
            framework = app/'Contents/Frameworks/Sparkle.framework'
            current = framework/'Versions/B'; current.mkdir(parents=True)
            (framework/'Versions/Current').symlink_to('B')
            for name in ['Autoupdate', 'Updater.app', 'XPCServices/Downloader.xpc', 'XPCServices/Installer.xpc']:
                path = current/name; path.parent.mkdir(exist_ok=True); path.touch()
            with patch.object(RELEASE, 'sign') as sign:
                RELEASE.sign_updater(app, 'fixture')
                paths = [call.args[0] for call in sign.call_args_list]
                self.assertEqual(paths[-1], framework)
                self.assertEqual(len(paths), 5)
                self.assertEqual(sign.call_args_list[2].args[2], 'org.sparkle-project.DownloaderService')
                self.assertEqual(sign.call_args_list[3].args[2], 'org.sparkle-project.InstallerLauncher')
    def test_missing_updater_cannot_be_packaged(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError): RELEASE.sign_updater(Path(directory)/'Fandy.app', 'fixture')
