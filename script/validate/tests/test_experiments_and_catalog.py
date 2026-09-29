from __future__ import annotations

import unittest

from support import ROOT, RepositoryCopyTestCase

import catalog
import experiments


class RepositoryExperimentsTests(unittest.TestCase):
    def test_repository_experiments_and_vocabulary_pass(self):
        for result in (experiments.check_frontmatter(ROOT), experiments.check_vocabulary(ROOT), catalog.check(ROOT)):
            self.assertEqual(result.result, "passed", "\n".join(result.problems))

    def test_vocabulary_is_read_from_the_specification(self):
        self.assertEqual(
            experiments.spec_states(ROOT),
            ["specified", "spiked", "implemented", "device-verified", "release-ready", "blocked"],
        )


class ExperimentStateTests(RepositoryCopyTestCase):
    def test_state_outside_the_spec_vocabulary_fails(self):
        self.edit("experiments/LAB-001-action-atlas.md", r'^state: .*$', 'state: "verified-on-simulator"')
        result = experiments.check_frontmatter(self.root)
        self.assertEqual(result.result, "failed")
        self.assertIn("state 'verified-on-simulator' is not in the SPEC vocabulary", result.problems[0])

    def test_unknown_experiment_dependency_fails(self):
        self.edit("experiments/LAB-001-action-atlas.md", r'^depends_on: .*$', 'depends_on: ["LAB-999"]')
        result = experiments.check_frontmatter(self.root)
        self.assertEqual(result.result, "failed")
        self.assertIn("LAB-001: depends_on LAB-999, which has no experiment spec in experiments/", result.problems)

    def test_experiment_cycle_fails(self):
        self.edit("experiments/LAB-001-action-atlas.md", r'^depends_on: .*$', 'depends_on: ["LAB-004"]')
        result = experiments.check_frontmatter(self.root)
        self.assertEqual(result.result, "failed")
        self.assertTrue(any("experiment dependency cycle: LAB-001 -> LAB-004 -> LAB-001" in p for p in result.problems),
                        result.problems)

    def test_vocabulary_drift_fails(self):
        self.edit("SPEC.md", r"`spiked`, ", "")
        result = experiments.check_vocabulary(self.root)
        self.assertEqual(result.result, "failed")
        self.assertEqual(len(result.problems), 2)

    def test_missing_vocabulary_sentence_blocks_instead_of_passing(self):
        self.edit("SPEC.md", r"Use exactly these implementation states:", "The implementation states are:")
        self.assertEqual(experiments.check_vocabulary(self.root).result, "blocked")
        self.assertEqual(experiments.check_frontmatter(self.root).result, "blocked")


class CatalogTests(RepositoryCopyTestCase):
    def test_stale_catalog_fails(self):
        self.edit("experiments/LAB-001-action-atlas.md", r'^title: .*$', 'title: "Action Atlas Renamed"')
        result = catalog.check(self.root)
        self.assertEqual(result.result, "failed")
        self.assertIn("experiments.json is stale", result.problems[0])

    def test_missing_generator_blocks(self):
        (self.root / "script" / "generate_catalog.py").unlink()
        self.assertEqual(catalog.check(self.root).result, "blocked")


if __name__ == "__main__":
    unittest.main()
