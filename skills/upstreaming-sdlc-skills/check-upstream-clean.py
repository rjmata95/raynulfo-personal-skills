#!/usr/bin/env python3
"""Gate a SDLC-skills port branch before it is pushed toward the enterprise repo.

Compares the current branch against the mirror (`main`) and fails on anything that
would reveal the personal fork or ship personal-only content. See
references/classification.md for the policy behind these patterns.

Usage:
    check-upstream-clean.py [--repo PATH] [--mirror REF] [--branch REF]
                            [--allow-multi-commit]

Exit codes: 0 clean (warnings allowed), 1 findings, 2 usage or git error.
"""

import argparse
import fnmatch
import re
import subprocess
import sys

# --- policy ---------------------------------------------------------------

# Paths that must never appear on a port branch.
QUARANTINE_PATHS = [
    "skills/_shared/standards.local/*",
    "skills/_shared/standards.local/**",
    "skills/_shared/selection-facts.local.json",
    "skills/_shared/validators/test-jira-auth-mode.py",
    "sdlc/*",
    "sdlc/**",
    "*config.local.md",
    "*repo-sources.local.tsv",
    ".claude/*",
    ".claude/**",
    ".worktrees/*",
    ".worktrees/**",
]

# Trees a port branch may legitimately add files to. Anything else is unclassified.
SHARED_PATHS = [
    "skills/**",
    "docs/**",
    "evals/**",
    "bin/**",
    "AGENTS.md",
    "README.md",
    "CHANGELOG.md",
    "VERSION",
    "design-with-docs-flow.md",
    ".gitignore",
]

# Paths that are shareable only alongside the capability they document.
REVIEW_PATHS = [
    "docs/specs/**",
    "docs/plans/**",
]

# Substrings that must not appear in an added line or a commit message.
# (label, regex)
CONTENT_MARKERS = [
    ("personal stack: ts-nest", r"ts-nest"),
    ("personal stack: react-rest", r"react-rest"),
    ("personal repo owner", r"rjmata95"),
    ("fork branch name", r"personal-branch"),
    ("bridge remote", r"\bbridge/(feat|main)\b|remote\.bridge"),
    ("Claude commit trailer", r"Co-Authored-By:\s*Claude"),
    ("Claude session trailer", r"Claude-Session:|claude\.ai/code/session"),
    ("Claude Code attribution", r"Generated with \[Claude Code\]"),
    ("Jira Cloud support (plausibility quarantine)", r"JIRA_EMAIL"),
]


# --- helpers --------------------------------------------------------------


def git(repo, *args):
    proc = subprocess.run(
        ["git", "-C", repo, *args], capture_output=True, text=True
    )
    if proc.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed:\n{proc.stderr.strip()}")
    return proc.stdout


def matches(path, patterns):
    return any(fnmatch.fnmatch(path, p) for p in patterns)


class Report:
    def __init__(self):
        self.failures = []
        self.warnings = []

    def fail(self, where, message):
        self.failures.append((where, message))

    def warn(self, where, message):
        self.warnings.append((where, message))


# --- checks ---------------------------------------------------------------


def check_lineage(repo, mirror, branch, allow_multi, report):
    ancestor = subprocess.run(
        ["git", "-C", repo, "merge-base", "--is-ancestor", mirror, branch],
        capture_output=True,
    )
    if ancestor.returncode != 0:
        report.fail(
            "lineage",
            f"{branch} does not descend from {mirror}; cut the port branch from the mirror",
        )

    for ref in ("personal-branch", f"origin/personal-branch"):
        exists = subprocess.run(
            ["git", "-C", repo, "rev-parse", "--verify", "--quiet", ref],
            capture_output=True,
        )
        if exists.returncode != 0:
            continue
        merged = subprocess.run(
            ["git", "-C", repo, "merge-base", "--is-ancestor", ref, branch],
            capture_output=True,
        )
        if merged.returncode == 0:
            report.fail(
                "lineage",
                f"{ref} is an ancestor of {branch}; the fork's history has crossed",
            )

    commits = [c for c in git(repo, "rev-list", f"{mirror}..{branch}").split() if c]
    if not commits:
        report.fail("lineage", f"{branch} adds no commits over {mirror}")
    elif len(commits) > 1 and not allow_multi:
        report.fail(
            "lineage",
            f"{len(commits)} commits over {mirror}; squash to one before pushing "
            "(--allow-multi-commit to override)",
        )


def check_paths(repo, mirror, branch, report):
    raw = git(repo, "diff", "--name-status", f"{mirror}..{branch}")
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        status, path = parts[0], parts[-1]
        if matches(path, QUARANTINE_PATHS):
            report.fail(path, "quarantined path")
            continue
        if status.startswith("A") and not matches(path, SHARED_PATHS):
            report.fail(path, "unclassified new path; classify it in classification.md")
        if matches(path, REVIEW_PATHS):
            report.warn(
                path, "review by hand: ship only alongside the capability it documents"
            )


def check_content(repo, mirror, branch, report):
    diff = git(repo, "diff", "--unified=0", f"{mirror}..{branch}")
    current = "?"
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
            continue
        if not line.startswith("+") or line.startswith("+++"):
            continue
        for label, pattern in CONTENT_MARKERS:
            if re.search(pattern, line):
                report.fail(current, f"{label}: {line[1:].strip()[:100]}")


def check_messages(repo, mirror, branch, report):
    # Message bodies only. Author identity stays personal by design: the company laptop
    # re-authors the content with `git read-tree`, so the commit itself never crosses.
    log = git(repo, "log", "--format=%B", f"{mirror}..{branch}")
    for line in log.splitlines():
        for label, pattern in CONTENT_MARKERS:
            if re.search(pattern, line):
                report.fail("commit message", f"{label}: {line.strip()[:100]}")


# --- main -----------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--mirror", default="main")
    parser.add_argument("--branch", default="HEAD")
    parser.add_argument("--allow-multi-commit", action="store_true")
    args = parser.parse_args()

    report = Report()
    check_lineage(args.repo, args.mirror, args.branch, args.allow_multi_commit, report)
    check_paths(args.repo, args.mirror, args.branch, report)
    check_content(args.repo, args.mirror, args.branch, report)
    check_messages(args.repo, args.mirror, args.branch, report)

    for where, message in report.warnings:
        print(f"WARN  {where}: {message}")
    for where, message in report.failures:
        print(f"FAIL  {where}: {message}")

    if report.failures:
        print(
            f"\n{len(report.failures)} finding(s). This branch is not clean to push upstream."
        )
        return 1
    print(f"\nClean against {args.mirror}. {len(report.warnings)} warning(s) to eyeball.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
