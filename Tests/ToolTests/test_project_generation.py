import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[2]


def project_objects(path):
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)['objects']


class ProjectGenerationTests(unittest.TestCase):
    def make_workspace(self, directory):
        root = Path(directory)
        (root / 'Scripts').mkdir()
        (root / 'Fandy.xcodeproj').mkdir()
        shutil.copy(ROOT / 'Scripts/generate-project.py', root / 'Scripts/generate-project.py')
        return root

    def test_xcode_signing_choices_survive_regeneration(self):
        # The real project is never edited. Model another developer's Xcode selections in a copy.
        objects = project_objects(ROOT / 'Fandy.xcodeproj/project.pbxproj')
        configurations = {key: value for key, value in objects.items() if value['isa'] == 'XCBuildConfiguration'}
        for config in configurations.values():
            settings = config['buildSettings']
            settings['DEVELOPMENT_TEAM'] = 'TESTTEAM12'
            settings['CODE_SIGN_IDENTITY'] = 'Custom developer selection'
            settings['CODE_SIGN_STYLE'] = 'Manual'
            settings['PROVISIONING_PROFILE_SPECIFIER'] = 'Chosen profile'
            settings['CODE_SIGN_IDENTITY[sdk=macosx*]'] = 'Conditional selection'
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_workspace(directory)
            path = root / 'Fandy.xcodeproj/project.pbxproj'
            path.write_bytes(plistlib.dumps({'objects': objects}))
            subprocess.run(['python3', str(root / 'Scripts/generate-project.py')], check=True, capture_output=True)
            updated = project_objects(path)
            for key, config in configurations.items():
                self.assertFalse(any(field.split('[')[0] in {'DEVELOPMENT_TEAM', 'CODE_SIGN_IDENTITY', 'CODE_SIGN_STYLE',
                    'PROVISIONING_PROFILE', 'PROVISIONING_PROFILE_SPECIFIER', 'CODE_SIGN_ENTITLEMENTS'}
                    for field in updated[key]['buildSettings']))
                reference = updated[updated[key]['baseConfigurationReference']]['path']
                local = (root / reference).with_suffix('.local.xcconfig')
                private_settings = dict(line.split(' = ', 1) for line in local.read_text().splitlines() if ' = ' in line)
                for field in ['DEVELOPMENT_TEAM', 'CODE_SIGN_IDENTITY', 'CODE_SIGN_STYLE', 'PROVISIONING_PROFILE_SPECIFIER', 'CODE_SIGN_IDENTITY[sdk=macosx*]']:
                    self.assertEqual(private_settings[field], config['buildSettings'][field])
            self.assertNotIn('TESTTEAM12', path.read_text())
            before = {p.name: p.read_text() for p in (root / 'Config/Signing').glob('*.local.xcconfig')}
            subprocess.run(['python3', str(root / 'Scripts/generate-project.py')], check=True, capture_output=True)
            self.assertEqual(before, {p.name: p.read_text() for p in (root / 'Config/Signing').glob('*.local.xcconfig')})

    def test_generated_helper_and_app_use_domain_identities(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_workspace(directory)
            subprocess.run(['python3', str(root / 'Scripts/generate-project.py')], check=True, capture_output=True)
            objects = project_objects(root / 'Fandy.xcodeproj/project.pbxproj')
            identifiers = {value['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER'] for value in objects.values()
                           if value['isa'] == 'XCBuildConfiguration' and 'PRODUCT_BUNDLE_IDENTIFIER' in value['buildSettings']}
            self.assertEqual(identifiers, {'is.dsr.fandy', 'is.dsr.fandy.fan-helper'})
            helpers = [value['buildSettings'] for value in objects.values() if value['isa'] == 'XCBuildConfiguration'
                       and value['buildSettings'].get('PRODUCT_BUNDLE_IDENTIFIER') == 'is.dsr.fandy.fan-helper']
            self.assertTrue(all(settings['OTHER_CODE_SIGN_FLAGS'] == '--identifier is.dsr.fandy.fan-helper' for settings in helpers))
            references = [value.get('path') for value in objects.values() if value['isa'] == 'PBXFileReference']
            self.assertIn('Config/is.dsr.fandy.fan-helper.plist', references)
            self.assertNotIn('Config/local.fandy.fan-helper.plist', references)
            self.assertTrue(all('DEVELOPMENT_TEAM' not in value['buildSettings'] for value in objects.values()
                                if value['isa'] == 'XCBuildConfiguration'))
            self.assertFalse(list((root / 'Config/Signing').glob('*.local.xcconfig')))


if __name__ == '__main__':
    unittest.main()
