"""Behaviour checks for selection, removal and repository discovery."""

import importlib.machinery
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("git-wt")
LOADER = importlib.machinery.SourceFileLoader("git_wt", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
git_wt = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(git_wt)


class WorktreeSelectionTests(unittest.TestCase):
    def test_choose_returns_all_marked_worktrees(self):
        entries = [
            {"path": "/trees/one", "branch": "one"},
            {"path": "/trees/two", "branch": "two"},
        ]
        output = b"x\0" + b"0\t/trees/one\tone\0" + b"1\t/trees/two\ttwo\0"
        result = subprocess.CompletedProcess([], 0, output)

        with mock.patch.object(git_wt.subprocess, "run", return_value=result) as run:
            self.assertEqual(git_wt.choose(entries), (b"x", entries))

        self.assertIn("--multi", run.call_args.args[0])

    def test_removal_continues_after_git_refuses_one(self):
        entries = [{"path": path} for path in ("/trees/one", "/trees/two")]
        results = [subprocess.CompletedProcess([], code) for code in (1, 0)]

        with mock.patch.object(git_wt.os, "getcwd", return_value="/elsewhere"), \
             mock.patch.object(git_wt, "confirm_removal", return_value=True) as confirm, \
             mock.patch.object(git_wt.subprocess, "run", side_effect=results) as run:
            self.assertEqual(git_wt.remove_worktrees(entries), 1)

        confirm.assert_called_once_with(["/trees/one", "/trees/two"])
        self.assertEqual([call.args[0][-1] for call in run.call_args_list],
                         ["/trees/one", "/trees/two"])

    def test_current_worktree_is_skipped(self):
        entries = [{"path": path} for path in ("/trees/current", "/trees/other")]

        with mock.patch.object(git_wt.os, "getcwd", return_value="/trees/current/subdir"), \
             mock.patch.object(git_wt, "confirm_removal", return_value=True) as confirm, \
             mock.patch.object(git_wt.subprocess, "run",
                               return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(git_wt.remove_worktrees(entries), 1)

        confirm.assert_called_once_with(["/trees/other"])
        run.assert_called_once()


class RepositoryDiscoveryTests(unittest.TestCase):
    def make_tree(self, root, directories, files=()):
        for directory in directories:
            (root / directory).mkdir(parents=True)
        for file in files:
            (root / file).write_text("gitdir: elsewhere\n")

    def test_finds_main_checkouts_without_entering_them(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_tree(root, [
                "shallow/.git",
                "github.com/org/deep/.git",
                "github.com/org/deep/vendor/nested/.git",
                "github.com/org/.hidden/repo/.git",
                "linked",
            ], files=["linked/.git"])

            found = sorted(git_wt.find_repositories(str(root)))

        self.assertEqual(found, [str(root / "github.com/org/deep"), str(root / "shallow")])

    def test_stops_at_scan_depth(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make_tree(root, ["a/b/.git", "a/b2/c/.git"])

            found = list(git_wt.find_repositories(str(root), depth=2))

        self.assertEqual(found, [str(root / "a/b")])

    def test_names_use_shortest_unique_trailing_path(self):
        repos = ["/src/github.com/alde/tool", "/src/ghe/team/tool", "/src/github.com/alde/solo"]

        self.assertEqual(git_wt.repository_names(repos), {
            "/src/github.com/alde/tool": "alde/tool",
            "/src/ghe/team/tool": "team/tool",
            "/src/github.com/alde/solo": "solo",
        })


if __name__ == "__main__":
    unittest.main()
