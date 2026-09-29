"""Every local Markdown link and anchor resolves inside the repository.

Reads inline links and images, reference definitions, and HTML href/src attributes outside code.
External URLs (any scheme, or //host) are counted but not fetched. A local target must exist
with the exact case Git records, must not be ignored by Git, must stay inside the repository
root, and, when it names an anchor, must have a heading or HTML id that GitHub renders with that
anchor.
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from urllib.parse import unquote

from common import FRONTMATTER, CheckResult, git_files, relative, repository_files

CHECK = "links"

FENCE_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})")
FENCE_CLOSE = re.compile(r"^ {0,3}(`{3,}|~{3,})[ \t]*$")
CODE_SPAN = re.compile(r"(`+)(?!`)(.+?)(?<!`)\1(?!`)")
LINK_OPEN = re.compile(r"!?\[(?:[^\[\]\\]|\\.|\[(?:[^\[\]\\]|\\.)*\])*\]\(")
REFERENCE = re.compile(r"^ {0,3}\[([^\]]+)\]:[ \t]*(<[^>]*>|\S+)")
HTML_TARGET = re.compile(r"<[A-Za-z][^>]*?\b(?:href|src)\s*=\s*[\"']([^\"']*)[\"']")
HTML_ID = re.compile(r"<[A-Za-z][^>]*?\b(?:id|name)\s*=\s*[\"']([^\"']+)[\"']")
ATX = re.compile(r"^ {0,3}#{1,6}(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$")
SETEXT = re.compile(r"^ {0,3}(?:=+|-+)[ \t]*$")
NOT_PARAGRAPH = re.compile(r"^ {0,3}(?:[>|<#*+-]|\d+[.)])")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
LINE_ANCHOR = re.compile(r"^L(\d+)(?:-L(\d+))?$")


def scan_lines(text: str) -> list:
    """(prose, raw) per line. Prose has code spans blanked; both are None inside frontmatter and
    fenced code, where nothing is a link or heading."""
    lines = text.split("\n")
    match = FRONTMATTER.match(text)
    hidden = match.group(0).count("\n") if match else 0
    scanned = []
    fence = None
    for number, line in enumerate(lines):
        if number < hidden:
            scanned.append((None, None))
            continue
        if fence:
            closing = FENCE_CLOSE.match(line)
            if closing and closing.group(1)[0] == fence[0] and len(closing.group(1)) >= len(fence):
                fence = None
            scanned.append((None, None))
            continue
        opening = FENCE_OPEN.match(line)
        if opening:
            fence = opening.group(1)
            scanned.append((None, None))
            continue
        scanned.append((CODE_SPAN.sub(lambda m: " " * len(m.group(0)), line), line))
    return scanned


def destination(line: str, start: int) -> str:
    """The link destination that begins at `start`, just after `(`."""
    while start < len(line) and line[start] in " \t":
        start += 1
    if line.startswith("<", start):
        end = line.find(">", start)
        return line[start + 1:end] if end != -1 else line[start + 1:]
    end, depth = start, 0
    while end < len(line):
        character = line[end]
        if character == "\\":
            end += 2
            continue
        if character.isspace():
            break
        if character == "(":
            depth += 1
        elif character == ")":
            if depth == 0:
                break
            depth -= 1
        end += 1
    return line[start:end]


def targets(prose: str) -> list:
    found = [destination(prose, match.end()) for match in LINK_OPEN.finditer(prose)]
    reference = REFERENCE.match(prose)
    if reference:
        found.append(reference.group(2).strip("<>"))
    found.extend(match.group(1) for match in HTML_TARGET.finditer(prose))
    return found


def heading_text(raw: str) -> str:
    """The text GitHub renders for a heading's inline Markdown."""
    text = CODE_SPAN.sub(lambda m: m.group(2).strip(), raw)
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"(\*\*|__|~~)(.+?)\1", r"\2", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"\1", text)
    text = re.sub(r"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)", r"\1", text)
    return text


def slug(text: str) -> str:
    """GitHub's heading anchor: lowercase, punctuation removed, each space a hyphen."""
    return re.sub(r"[^\w\- ]", "", text.strip().lower()).replace(" ", "-")


def anchors(text: str) -> set:
    """Every anchor a Markdown file defines: heading slugs, with GitHub's -1, -2 suffixes for
    repeats, and explicit HTML id and name attributes."""
    found = set()
    counts: dict = {}
    previous = None
    for prose, raw in scan_lines(text):
        if raw is None:
            previous = None
            continue
        heading = None
        atx = ATX.match(raw)
        if atx:
            heading = atx.group(1) or ""
        elif SETEXT.match(raw) and previous is not None:
            heading = previous
        if heading is not None:
            base = slug(heading_text(heading))
            count = counts.get(base, 0)
            counts[base] = count + 1
            found.add(base if count == 0 else f"{base}-{count}")
            previous = None
        else:
            previous = raw if raw.strip() and not NOT_PARAGRAPH.match(raw) else None
        found.update(match.group(1) for match in HTML_ID.finditer(prose))
    return found


class Resolver:
    def __init__(self, root: Path):
        self.root = Path(os.path.realpath(root))
        tracked = git_files(self.root)
        self.tracked = None
        if tracked is not None:
            self.tracked = {path.relative_to(self.root).as_posix() for path in tracked}
            self.tracked |= {parent.as_posix() for name in list(self.tracked) for parent in Path(name).parents}
        self.listings: dict = {}
        self.anchor_cache: dict = {}

    def listing(self, directory: Path) -> set:
        if directory not in self.listings:
            try:
                self.listings[directory] = set(os.listdir(directory))
            except OSError:
                self.listings[directory] = set()
        return self.listings[directory]

    def problem(self, source: Path, target: str):
        """Why `target`, linked from `source`, does not resolve, or None when it does."""
        if not target.strip():
            return "the link target is empty"
        if SCHEME.match(target) or target.startswith("//"):
            return None
        decoded = unquote(target)
        location, _, fragment = decoded.partition("#")
        location = location.split("?", 1)[0]
        if not location:
            resolved = source
        elif location.startswith("/"):
            resolved = Path(os.path.normpath(self.root / location.lstrip("/")))
        else:
            resolved = Path(os.path.normpath(source.parent / location))
        inside = resolved == self.root or str(resolved).startswith(str(self.root) + os.sep)
        if not inside:
            return "escapes the repository root; link only to files inside this repository"
        if resolved.exists() and not Path(os.path.realpath(resolved)).is_relative_to(self.root):
            return "resolves through a symbolic link to a path outside the repository"
        path_problem = self.case_problem(resolved)
        if path_problem:
            return path_problem
        name = resolved.relative_to(self.root).as_posix() if resolved != self.root else "."
        if self.tracked is not None and name != "." and name not in self.tracked:
            return f"{name} exists only locally: Git ignores it, so it is not in the repository"
        if fragment:
            return self.anchor_problem(resolved, name, fragment)
        return None

    def case_problem(self, resolved: Path):
        current = self.root
        for part in resolved.relative_to(self.root).parts:
            entries = self.listing(current)
            if part not in entries:
                matches = sorted(entry for entry in entries if entry.lower() == part.lower())
                if matches:
                    return (f"{relative(current / part, self.root)} differs in case from {matches[0]} on disk; "
                            "Git and GitHub are case-sensitive")
                return f"{relative(current / part, self.root)} does not exist"
            current = current / part
        return None

    def anchor_problem(self, resolved: Path, name: str, fragment: str):
        if resolved.is_dir():
            return f"#{fragment} cannot be checked on a directory ({name})"
        if resolved.suffix.lower() != ".md":
            line = LINE_ANCHOR.match(fragment)
            if not line:
                return f"#{fragment} cannot be checked in {name}; only #L<n> line anchors are supported outside Markdown"
            total = resolved.read_text(encoding="utf-8", errors="replace").count("\n") + 1
            if max(int(value) for value in line.groups() if value) > total:
                return f"#{fragment} is past the end of {name} ({total} lines)"
            return None
        if resolved not in self.anchor_cache:
            self.anchor_cache[resolved] = anchors(resolved.read_text(encoding="utf-8"))
        if fragment not in self.anchor_cache[resolved]:
            return f"no heading or HTML id in {name} renders the anchor #{fragment}"
        return None


def check(root: Path) -> CheckResult:
    resolver = Resolver(root)
    files = repository_files(resolver.root, ".md")
    problems = []
    local = external = anchored = 0
    for source in files:
        source = Path(os.path.realpath(source))
        text = source.read_text(encoding="utf-8")
        for number, (prose, _) in enumerate(scan_lines(text), start=1):
            if prose is None:
                continue
            for target in targets(prose):
                if SCHEME.match(target) or target.startswith("//"):
                    external += 1
                    continue
                local += 1
                anchored += "#" in target
                reason = resolver.problem(source, target)
                if reason:
                    problems.append(f"{relative(source, resolver.root)}:{number}: link to `{target}`: {reason}")
    if problems:
        return CheckResult(CHECK, "failed", f"{len(problems)} of {local} local links do not resolve", problems)
    return CheckResult(
        CHECK, "passed",
        f"{local} local links ({anchored} with anchors) in {len(files)} Markdown files resolve inside the "
        f"repository; {external} external links not fetched",
    )
