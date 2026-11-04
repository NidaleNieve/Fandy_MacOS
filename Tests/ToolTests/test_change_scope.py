import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[2]
SCRIPT = ROOT / 'Scripts/check-change-scope.py'


class ChangeScopeTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('change_scope', SCRIPT)
        self.scope = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.scope)

    def test_only_public_documentation_and_gitignore_use_the_lightweight_path(self):
        for path in ['README.md', 'SAFETY.md', 'ARCHITECTURE.md', 'SECURITY.md', 'AGENTS.md',
                     '.gitignore', 'docs/INSTALLATION.md', 'docs/nested/guide.md',
                     'docs/images/menu.png', 'docs/images/fandy-icon.svg']:
            with self.subTest(path=path):
                self.assertTrue(self.scope.documentation_path(path))
        for path in ['Sources/FandyApp/FandyApp.swift', 'Tests/FandyCoreTests/CoreTests.swift',
                     'Scripts/build.sh', 'Config/App-Info.plist', 'Package.swift',
                     'Fandy.xcodeproj/project.pbxproj', '.github/workflows/verification.yml',
                     '.github/main-ruleset.json', 'LICENSE', 'THIRD_PARTY_NOTICES.md',
                     'docs/licenses/Sparkle.txt', 'docs/licenses/readme.md',
                     'docs/tool.py', 'new-file', '../README.md']:
            with self.subTest(path=path):
                self.assertFalse(self.scope.documentation_path(path))

    def test_real_git_ranges_include_earlier_code_changes_deletions_and_renames(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args, check=True):
                return subprocess.run(['git', '-C', directory, *args], check=check,
                                      capture_output=True, text=True).stdout.strip()
            def write(path, content):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content)
            def commit(message):
                git('add', '-A')
                git('-c', 'user.name=Scope Test', '-c', 'user.email=scope@example.invalid',
                    '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
                    'commit', '-m', message)
                return git('rev-parse', 'HEAD')
            git('init')
            write('README.md', 'Introduction\n')
            write('Sources/main.swift', 'print("app")\n')
            baseline = commit('baseline')
            write('README.md', 'Updated introduction\n')
            docs = commit('docs')
            self.assertFalse(self.scope.requires_app_checks(root, baseline, docs))
            write('Sources/main.swift', 'print("changed app")\n')
            commit('app change')
            write('README.md', 'Another documentation edit\n')
            tip = commit('later docs')
            self.assertTrue(self.scope.requires_app_checks(root, baseline, tip))
            git('reset', '--hard', baseline)
            git('rm', 'Sources/main.swift')
            deleted = commit('remove code')
            self.assertTrue(self.scope.requires_app_checks(root, baseline, deleted))
            git('reset', '--hard', baseline)
            (root / 'docs').mkdir()
            git('mv', 'Sources/main.swift', 'docs/renamed.md')
            renamed = commit('rename code into docs')
            self.assertTrue(self.scope.requires_app_checks(root, baseline, renamed))
            git('reset', '--hard', baseline)
            git('rm', 'README.md')
            removed_docs = commit('remove docs')
            self.assertFalse(self.scope.requires_app_checks(root, baseline, removed_docs))
            git('reset', '--hard', baseline)
            (root / 'README.md').unlink()
            os.symlink('Sources/main.swift', root / 'README.md')
            symlink = commit('replace docs with symlink')
            self.assertTrue(self.scope.requires_app_checks(root, baseline, symlink))
            with self.assertRaises(subprocess.CalledProcessError):
                self.scope.requires_app_checks(root, 'missing-ref', tip)
            output = root / 'workflow-output'
            failed = subprocess.run(['python3', str(SCRIPT), '--base', 'missing-ref', '--head', tip],
                                    cwd=root, env={**os.environ, 'GITHUB_OUTPUT': str(output)},
                                    capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse(output.exists())
            self.assertTrue(self.scope.requires_app_checks(root, baseline, baseline))
            self.assertTrue(self.scope.requires_app_checks(root, '0' * 40, tip))


if __name__ == '__main__':
    unittest.main()
