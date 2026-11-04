from pathlib import Path
import plistlib
import re
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).parents[2]
PUBLIC_DOCS = ['README.md', 'ARCHITECTURE.md', 'SAFETY.md', 'THIRD_PARTY_NOTICES.md',
               'docs/INSTALLATION.md', 'docs/LOCAL_CONFIGURATION.md',
               'docs/HARDWARE_GATES.md', 'docs/COMPATIBILITY.md']


class DocumentationTests(unittest.TestCase):
    def test_installation_download_matches_the_current_app_version(self):
        info = plistlib.loads((ROOT / 'Config/App-Info.plist').read_bytes())
        version = info['CFBundleShortVersionString']
        installation = (ROOT / 'docs/INSTALLATION.md').read_text()
        self.assertIn(f'/releases/latest/download/Fandy-{version}-arm64.dmg', installation)
        self.assertNotIn('checks weekly by default', installation)

    def test_support_docs_record_both_owner_tested_chip_variants(self):
        for path in ['SAFETY.md', 'docs/COMPATIBILITY.md']:
            text = (ROOT / path).read_text()
            with self.subTest(path=path):
                self.assertRegex(text, r'(?:tested[^\n]*M2 Pro[^\n]*M5 Pro|M2 Pro[^\n]*M5 Pro[^\n]*tested)')
                self.assertNotRegex(text, r'M2[^\n]*(?:remains pending|still pending|acceptance remains necessary)')

    def test_public_document_links_work_in_a_fresh_checkout(self):
        # Local archive files must never make a broken public link appear valid.
        import subprocess
        public = set(subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines())
        public = {path for path in public if (ROOT / path).is_file()}
        for path in PUBLIC_DOCS:
            text = (ROOT / path).read_text()
            targets = re.findall(r'\]\(([^\s)]+)\)|(?:src|href)="([^"]+)"', text)
            for markdown, html in targets:
                target = markdown or html
                parsed = urlsplit(target)
                if parsed.scheme or parsed.netloc or not parsed.path:
                    continue
                absolute = (ROOT / path).parent / unquote(parsed.path)
                with self.subTest(source=path, target=target):
                    relative = absolute.resolve().relative_to(ROOT)
                    self.assertIn(relative.as_posix(), public)

    def test_sensor_explanations_do_not_reference_retired_reports_or_fan_guard(self):
        source = (ROOT / 'Sources/FandyHardware/SensorRegistry.swift').read_text()
        self.assertNotIn('CHIP_ENVELOPE / TEMPERATURE_PROFILE_STATUS', source)
        self.assertNotIn('Independent guard always', source)


if __name__ == '__main__':
    unittest.main()
