from __future__ import annotations

import unittest

from support import ROOT, RepositoryCopyTestCase

import tickets
from common import find_cycles


class RepositoryTicketsTests(unittest.TestCase):
    def test_repository_tickets_are_well_formed_and_acyclic(self):
        for result in (tickets.check_frontmatter(ROOT), tickets.check_graph(ROOT)):
            self.assertEqual(result.result, "passed", "\n".join(result.problems))


class FindCyclesTests(unittest.TestCase):
    def test_reports_each_cycle_rotated_to_its_smallest_id(self):
        graph = {"C": ["A"], "A": ["B"], "B": ["C"], "D": ["D"], "E": ["A"], "F": []}
        self.assertEqual(find_cycles(graph), [["A", "B", "C", "A"], ["D", "D"]])

    def test_acyclic_graph_has_none(self):
        self.assertEqual(find_cycles({"A": ["B", "C"], "B": ["C"], "C": [], "D": ["missing"]}), [])


class TicketGraphTests(RepositoryCopyTestCase):
    def graph(self):
        return tickets.check_graph(self.root)

    def test_two_ticket_cycle_fails_with_the_path(self):
        self.set_depends_on("CORE-001", ["CORE-002"])
        result = self.graph()
        self.assertEqual(result.result, "failed")
        self.assertIn("dependency cycle: CORE-001 -> CORE-002 -> CORE-001", result.problems)

    def test_longer_cycle_fails(self):
        self.set_depends_on("CORE-001", ["CORE-004"])
        self.set_depends_on("CORE-004", ["CORE-002"])
        result = self.graph()
        self.assertEqual(result.result, "failed")
        self.assertIn("dependency cycle: CORE-001 -> CORE-004 -> CORE-002 -> CORE-001", result.problems)

    def test_self_dependency_is_a_cycle(self):
        self.set_depends_on("CORE-001", ["CORE-001"])
        self.assertIn("dependency cycle: CORE-001 -> CORE-001", self.graph().problems)

    def test_missing_dependency_fails(self):
        self.set_depends_on("CORE-003", ["CORE-002", "CORE-999"])
        result = self.graph()
        self.assertEqual(result.result, "failed")
        self.assertIn("tickets/CORE-003.md: depends_on CORE-999, which has no ticket file (tickets/CORE-999.md)",
                      result.problems)

    def test_unreadable_dependencies_block_the_graph(self):
        self.edit("tickets/CORE-003.md", r"^depends_on: .*$", "depends_on: CORE-002")
        result = self.graph()
        self.assertEqual(result.result, "blocked")
        self.assertIn("fix ticket-frontmatter first", result.summary)


class TicketFrontmatterTests(RepositoryCopyTestCase):
    def assertFrontmatterProblem(self, fragment: str) -> None:
        result = tickets.check_frontmatter(self.root)
        self.assertEqual(result.result, "failed")
        self.assertTrue(any(fragment in problem for problem in result.problems), result.problems)

    def test_unknown_status(self):
        self.edit("tickets/CORE-003.md", r'^status: .*$', 'status: "started"')
        self.assertFrontmatterProblem("status 'started' is not one of planned, in-progress, blocked, done")

    def test_unknown_and_missing_keys(self):
        self.edit("tickets/CORE-003.md", r"^depends_on:", "depend_on:")
        self.assertFrontmatterProblem("missing depends_on")
        self.assertFrontmatterProblem("unknown key depend_on")

    def test_value_that_is_not_json(self):
        self.edit("tickets/CORE-003.md", r'^title: .*$', "title: Unquoted title")
        self.assertFrontmatterProblem("`title` must be a JSON value")

    def test_id_must_match_the_file(self):
        self.edit("tickets/CORE-003.md", r'^id: .*$', 'id: "CORE-033"')
        self.assertFrontmatterProblem("does not match the file name CORE-003.md")

    def test_missing_frontmatter(self):
        path = self.root / "tickets" / "CORE-003.md"
        path.write_text(path.read_text(encoding="utf-8").split("---\n", 2)[2], encoding="utf-8")
        self.assertFrontmatterProblem("tickets/CORE-003.md: missing frontmatter")

    def test_duplicate_dependency(self):
        self.set_depends_on("CORE-003", ["CORE-002", "CORE-002"])
        self.assertFrontmatterProblem("lists a ticket more than once")


if __name__ == "__main__":
    unittest.main()
