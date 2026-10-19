"""Exercise release metadata with real local Git objects, never signing or publishing."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'fastlane/release_metadata.rb'
FASTFILE = ROOT / 'fastlane/Fastfile'


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='minitools metadata ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'source'
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')
        self.git(self.repo, 'init', '-q')
        self.commit('source')
        self.parent = self.git(self.repo, 'rev-parse', 'HEAD').stdout.strip()
        self.commit('candidate')
        self.candidate = self.git(self.repo, 'rev-parse', 'HEAD').stdout.strip()

    def git(self, repo, *args, check=True):
        return subprocess.run(['git', '-c', 'user.name=Metadata Tests',
                               '-c', 'user.email=tests@example.invalid',
                               '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args],
                              env=self.env, text=True, capture_output=True, check=check)

    def commit(self, message):
        self.git(self.repo, 'commit', '-q', '--no-gpg-sign', '--allow-empty', '-m', message)

    def shallow_clone(self):
        clone = self.root / 'shallow clone'
        self.git(self.root, 'clone', '-q', '--depth=1', self.repo.as_uri(), str(clone))
        self.assertEqual(self.git(clone, 'rev-parse', '--is-shallow-repository').stdout.strip(), 'true')
        self.assertNotEqual(self.git(clone, 'rev-parse', '--verify', 'HEAD^', check=False).returncode, 0)
        self.assertNotEqual(self.git(clone, 'cat-file', '-e', self.parent, check=False).returncode, 0)
        return clone

    def metadata(self, repo, sha):
        return subprocess.run(['ruby', '-r', str(HELPER), '-e',
                               'print MiniToolsReleaseMetadata.source_commit(root: ARGV[0], candidate_commit: ARGV[1])',
                               str(repo), sha], env=self.env, text=True, capture_output=True)

    def test_full_checkout_reports_exact_parent(self):
        result = self.metadata(self.repo, self.candidate)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.parent)

    def test_depth_one_checkout_works_without_parent_object(self):
        result = self.metadata(self.shallow_clone(), self.candidate)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.parent)

    def test_mismatched_checkout_is_rejected(self):
        result = self.metadata(self.repo, self.parent)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Checkout does not match', result.stderr)

    def test_non_exact_candidate_is_rejected(self):
        result = self.metadata(self.repo, 'HEAD')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exact SHA', result.stderr)

    def test_root_commit_is_rejected(self):
        self.git(self.repo, 'checkout', '-q', '--detach', self.parent)
        result = self.metadata(self.repo, self.parent)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exactly one parent', result.stderr)

    def test_merge_commit_is_rejected(self):
        tree = self.git(self.repo, 'rev-parse', 'HEAD^{tree}').stdout.strip()
        merge = self.git(self.repo, 'commit-tree', tree, '-p', self.candidate,
                         '-p', self.parent, '-m', 'merge').stdout.strip()
        self.git(self.repo, 'checkout', '-q', '--detach', merge)
        result = self.metadata(self.repo, merge)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exactly one parent', result.stderr)

    def test_fastfile_notes_generation_with_shallow_checkout(self):
        clone = self.shallow_clone()
        # Stub only Fastlane orchestration: no imports, credentials, builds or releases.
        code = '''
def import_from_git(**options); end
def default_platform(*args); end
def platform(*args); end
def shared_macos_developer_id(**options); end
load ARGV[0]
define_singleton_method(:mini_tools_release_context) do |channel:|
  [ARGV[1], "2026.10.20.1", "v2026.10.20.1-beta.5"]
end
ENV["GITHUB_SHA"] = ARGV[2]
ENV["GITHUB_RUN_NUMBER"] = "5"
ENV["RUNNER_TEMP"] = ARGV[1]
mini_tools_package(channel: :beta, publish: false)
print File.read(File.join(ARGV[1], "miniTools-beta-release-notes.md"))
'''
        result = subprocess.run(['ruby', '-e', code, str(FASTFILE), str(clone), self.candidate],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'Source commit: {self.parent}', result.stdout)
        self.assertIn(f'Candidate commit: {self.candidate}', result.stdout)
        self.assertIn('Candidate tag: v2026.10.20.1-beta.5', result.stdout)


if __name__ == '__main__':
    unittest.main()
