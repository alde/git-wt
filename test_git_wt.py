"""Behaviour checks for multi-selection and worktree removal."""

import importlib.machinery
import importlib.util
import pathlib
import subprocess
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


if __name__ == "__main__":
    unittest.main()
