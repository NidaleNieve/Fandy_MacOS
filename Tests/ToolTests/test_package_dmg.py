import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location('package_dmg', ROOT / 'Scripts/package-dmg.py')
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class PackagingTests(unittest.TestCase):
    def metadata(self):
        return ({'CFBundleIdentifier': 'is.dsr.fandy', 'CFBundleExecutable': 'Fandy',
                 'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '15.0'},
                {'Label': 'is.dsr.fandy.fan-service', 'BundleProgram': str(PACKAGE.HELPER),
                 'MachServices': {'is.dsr.fandy.fan-helper': True}, 'ProgramArguments': ['FandyFanHelper']})

    def test_wrong_identity_helper_path_and_service_are_rejected(self):
        info, service = self.metadata()
        PACKAGE.validate_metadata(info, service)
        for field, value in [('CFBundleIdentifier', 'example.fake'), ('CFBundleExecutable', '/bin/sh'),
                             ('CFBundleVersion', '../escape'), ('LSMinimumSystemVersion', '14.0')]:
            invalid = dict(info, **{field: value})
            with self.assertRaises(ValueError):
                PACKAGE.validate_metadata(invalid, service)
        for field, value in [('BundleProgram', '/bin/sh'), ('Label', 'example.fake'),
                             ('MachServices', {'example.fake': True}), ('ProgramArguments', ['/bin/sh'])]:
            with self.assertRaises(ValueError):
                PACKAGE.validate_metadata(info, dict(service, **{field: value}))

    def test_private_files_and_source_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Fandy.app'
            app.mkdir()
            resource = app / 'resource.txt'
            resource.write_text('/Fandy/Sources/model.swift')
            PACKAGE.check_payload(app)
            resource.write_bytes(b'prefix ' + b'/Users/' + b'example/Projects/model.swift\x00')
            with self.assertRaises(ValueError):
                PACKAGE.check_payload(app)
            resource.unlink()
            for suffix in ['.csv', '.log', '.xcconfig', '.p12', '.key']:
                private = app / ('private' + suffix)
                private.write_text('private fixture')
                with self.assertRaises(ValueError):
                    PACKAGE.check_payload(app)
                private.unlink()

    def test_external_links_and_debug_symbol_bundles_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Fandy.app'
            app.mkdir()
            external = app / 'external'
            external.symlink_to('/Applications')
            with self.assertRaises(ValueError):
                PACKAGE.check_payload(app)
            external.unlink()
            symbols = app / 'Fandy.dSYM'
            symbols.mkdir()
            (symbols / 'symbols').write_text('private debug data')
            with self.assertRaises(ValueError):
                PACKAGE.check_payload(app)

    def test_failed_preflight_cannot_create_an_image(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'output'
            with patch.object(PACKAGE, 'verify_app', side_effect=ValueError('unsigned')):
                with self.assertRaises(ValueError):
                    PACKAGE.package(Path(directory) / 'Fandy.app', output)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
