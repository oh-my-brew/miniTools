import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).resolve().parents[2] / 'Scripts/beta-preflight.py')
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class CandidateLifecycleTests(unittest.TestCase):
    def candidate(self, source='old', labels=None, version='2026.10.20.1'):
        return dict(number=47, source=source, labels=labels or [], version=version)

    def test_supersedes_only_ancestor(self):
        self.assertEqual(preflight.decide('new', [self.candidate()], [], lambda a, b: True),
                         dict(reuse=[], supersede=[47], target_version='2026.10.20.1'))

    def test_same_source_reuses(self):
        self.assertEqual(preflight.decide('old', [self.candidate()], [], lambda a, b: False),
                         dict(reuse=[47], supersede=[], target_version='2026.10.20.1'))

    def test_no_candidate_leaves_target_version_unallocated(self):
        self.assertEqual(preflight.decide('new', [], [], lambda a, b: True),
                         dict(reuse=[], supersede=[], target_version=None))

    def test_multiple_target_versions_require_resolution(self):
        with self.assertRaises(ValueError):
            preflight.decide('new', [self.candidate(), self.candidate(version='2026.10.20.2')], [], lambda a, b: True)

    def test_approved_blocks_even_when_same_source(self):
        with self.assertRaises(ValueError):
            preflight.decide('old', [self.candidate(labels=['release-approved'])], [], lambda a, b: True)

    def test_active_workflow_blocks(self):
        with self.assertRaises(ValueError):
            preflight.decide('new', [], [dict(status='waiting')], lambda a, b: True)

    def test_divergence_blocks(self):
        with self.assertRaises(ValueError):
            preflight.decide('new', [self.candidate()], [], lambda a, b: False)

    def test_conflict_after_replaceable_candidate_prevents_plan(self):
        with self.assertRaises(ValueError):
            preflight.decide('new', [self.candidate(), self.candidate(labels=['release-approved'])], [], lambda a, b: True)


if __name__ == '__main__':
    unittest.main()
