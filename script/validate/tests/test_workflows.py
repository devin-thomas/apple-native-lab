from __future__ import annotations

import unittest

from support import ROOT, RepositoryCopyTestCase

import workflows

WORKFLOW = ".github/workflows/ci.yml"


class RepositoryWorkflowTests(unittest.TestCase):
    def test_repository_workflows_keep_the_trust_boundary(self):
        result = workflows.check(ROOT)
        self.assertEqual(result.result, "passed", "\n".join(result.problems))
        self.assertRegex(result.summary, r"^[1-9]\d* workflow files?:")


class WorkflowPolicyTests(RepositoryCopyTestCase):
    def assertPolicyProblem(self, fragment: str) -> None:
        result = workflows.check(self.root)
        self.assertEqual(result.result, "failed")
        self.assertTrue(any(fragment in problem for problem in result.problems), result.problems)

    def test_pull_request_target_fails(self):
        self.edit(WORKFLOW, r"^  pull_request:$", "  pull_request_target:")
        self.assertPolicyProblem("pull_request_target runs with the base repository's secrets")

    def test_secret_reference_fails(self):
        self.edit(WORKFLOW, r"^      PYTHONDONTWRITEBYTECODE: \"1\"$",
                  '      PYTHONDONTWRITEBYTECODE: "1"\n      SIGNING_KEY: ${{ secrets.SIGNING_KEY }}')
        self.assertPolicyProblem("references secrets")

    def test_write_permission_fails(self):
        self.edit(WORKFLOW, r"^  contents: read$", "  contents: write")
        self.assertPolicyProblem("grants more than read access")

    def test_write_all_fails(self):
        self.edit(WORKFLOW, r"^permissions:\n  contents: read$", "permissions: write-all")
        self.assertPolicyProblem("grants more than read access")

    def test_missing_permissions_fails(self):
        self.edit(WORKFLOW, r"^permissions:\n  contents: read\n", "")
        self.assertPolicyProblem("no top-level permissions block")

    def test_self_hosted_runner_fails(self):
        self.edit(WORKFLOW, r"^    runs-on: macos-26$", "    runs-on: [self-hosted, macOS]")
        self.assertPolicyProblem("self-hosted runner")

    def test_unpinned_action_fails(self):
        self.edit(WORKFLOW, r"actions/checkout@[0-9a-f]{40}", "actions/checkout@v6")
        self.assertPolicyProblem("actions/checkout@v6 is not pinned")

    def test_comments_do_not_count(self):
        self.edit(WORKFLOW, r"^name: CI$", "# Never pull_request_target, secrets.X, or self-hosted.\nname: CI")
        self.assertEqual(workflows.check(self.root).result, "passed")


if __name__ == "__main__":
    unittest.main()
