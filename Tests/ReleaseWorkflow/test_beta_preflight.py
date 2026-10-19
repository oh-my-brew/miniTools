import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).resolve().parents[2] / 'Scripts/beta-preflight.py')
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class CandidateLifecycleTests(unittest.TestCase):
    def candidate(self, source='old', labels=None):
        return dict(number=47, source=source, labels=labels or [])

    def test_supersedes_only_ancestor(self):
        self.assertEqual(preflight.decide('new', [self.candidate()], [], lambda a, b: True),
                         dict(reuse=[], supersede=[47]))

    def test_same_source_reuses(self):
        self.assertEqual(preflight.decide('old', [self.candidate()], [], lambda a, b: False),
                         dict(reuse=[47], supersede=[]))

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
