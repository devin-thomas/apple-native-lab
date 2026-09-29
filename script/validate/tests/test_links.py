from __future__ import annotations

import os
import unittest

from support import ROOT, RepositoryCopyTestCase

import links


class RepositoryLinksTests(unittest.TestCase):
    def test_repository_links_resolve(self):
        result = links.check(ROOT)
        self.assertEqual(result.result, "passed", "\n".join(result.problems))
        self.assertRegex(result.summary, r"^[1-9]\d* local links")


class BrokenLinkTests(RepositoryCopyTestCase):
    def assertFailsWith(self, fragment: str) -> list:
        result = links.check(self.root)
        self.assertEqual(result.result, "failed")
        matching = [problem for problem in result.problems if fragment in problem]
        self.assertTrue(matching, f"no problem mentions {fragment!r}: {result.problems}")
        return matching

    def test_missing_file_fails_with_file_and_line(self):
        self.write("docs/NOTE.md", "# Note\n\nSee [the plan](PLAN_THAT_DOES_NOT_EXIST.md).\n")
        problems = self.assertFailsWith("PLAN_THAT_DOES_NOT_EXIST.md")
        self.assertIn("docs/NOTE.md:3: link to `PLAN_THAT_DOES_NOT_EXIST.md`", problems[0])
        self.assertIn("does not exist", problems[0])

    def test_link_escaping_the_root_fails_even_when_the_target_exists(self):
        sibling = self.outside / "sibling-repository" / "README.md"
        sibling.parent.mkdir(parents=True)
        sibling.write_text("# Outside\n", encoding="utf-8")
        self.write("docs/NOTE.md", "[outside](../../sibling-repository/README.md)\n")
        self.assertTrue((self.root / "docs" / "../../sibling-repository/README.md").exists())
        self.assertIn("escapes the repository root", self.assertFailsWith("sibling-repository")[0])

    def test_symbolic_link_out_of_the_root_fails(self):
        (self.outside / "elsewhere.md").write_text("# Elsewhere\n", encoding="utf-8")
        os.symlink(self.outside / "elsewhere.md", self.root / "docs" / "ALIAS.md")
        self.write("docs/NOTE.md", "[alias](ALIAS.md)\n")
        self.assertIn("symbolic link", self.assertFailsWith("ALIAS.md")[0])

    def test_missing_anchor_fails(self):
        self.write("docs/NOTE.md", "[strategy](TEST_STRATEGY.md#a-heading-that-does-not-exist)\n")
        self.assertIn("renders the anchor", self.assertFailsWith("#a-heading-that-does-not-exist")[0])

    def test_missing_same_file_anchor_fails(self):
        self.write("docs/NOTE.md", "# Note\n\n[here](#nowhere)\n")
        self.assertFailsWith("#nowhere")

    def test_github_heading_anchors_resolve(self):
        self.write("docs/NOTE.md", "\n".join([
            "# CORE-900 — A title: with `code` and **bold**",
            "## Setup", "## Setup", "Setext heading", "--------------",
            '<a id="explicit-anchor"></a>',
            "[a](#core-900--a-title-with-code-and-bold) [b](#setup) [c](#setup-1) [d](#setext-heading)",
            "[e](#explicit-anchor) [f](../SPEC.md#7-states-and-definition-of-done) [g](SOURCE_INDEX.md#s05)",
            "",
        ]))
        result = links.check(self.root)
        self.assertEqual(result.result, "passed", result.problems)

    def test_third_repeated_heading_is_not_invented(self):
        self.write("docs/NOTE.md", "## Setup\n## Setup\n[c](#setup-2)\n")
        self.assertFailsWith("#setup-2")

    def test_case_mismatch_fails(self):
        self.write("docs/NOTE.md", "[strategy](test_strategy.md)\n")
        problem = self.assertFailsWith("test_strategy.md")[0]
        self.assertTrue("differs in case" in problem or "does not exist" in problem, problem)

    def test_links_in_code_are_ignored(self):
        self.write("docs/NOTE.md", "Inline `[x](missing-one.md)` code.\n\n```\n[y](missing-two.md)\n```\n")
        self.assertEqual(links.check(self.root).result, "passed")

    def test_empty_target_fails(self):
        self.write("docs/NOTE.md", "[nothing]()\n")
        self.assertIn("empty", self.assertFailsWith("docs/NOTE.md:1")[0])

    def test_reference_and_html_links_are_checked(self):
        self.write("docs/NOTE.md", "[ref]: missing-reference.md\n\n<a href=\"missing-html.md\">x</a>\n")
        self.assertFailsWith("missing-reference.md")
        self.assertFailsWith("missing-html.md")

    def test_root_relative_and_line_anchors(self):
        self.write("docs/NOTE.md", "[a](/docs/TEST_STRATEGY.md) [b](../script/test.sh#L2) [c](../README.md)\n")
        self.assertEqual(links.check(self.root).result, "passed")
        self.write("docs/NOTE.md", "[b](../script/test.sh#L9999)\n")
        self.assertIn("past the end", self.assertFailsWith("#L9999")[0])

    def test_external_links_are_not_fetched(self):
        self.write("docs/NOTE.md", "[a](https://example.com/nothing) [b](mailto:someone@example.com)\n")
        self.assertEqual(links.check(self.root).result, "passed")

    def test_link_to_a_file_git_ignores_fails(self):
        self.init_git()
        self.write("Config/Local.xcconfig", "LAB_BUNDLE_PREFIX = org.example.local\n")
        self.write("docs/NOTE.md", "[local](../Config/Local.xcconfig)\n")
        self.assertIn("Git ignores it", self.assertFailsWith("Local.xcconfig")[0])


if __name__ == "__main__":
    unittest.main()
