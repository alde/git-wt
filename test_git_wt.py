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

    def test_lists_repositories_by_name_with_main_checkout_first(self):
        listings = {
            "/src/zeta": [{"path": "/src/zeta", "branch": "main"}],
            "/src/Alpha": [
                {"path": "/src/Alpha", "branch": "trunk"},
                {"path": "/src/Alpha/.worktrees/z", "branch": "zed"},
                {"path": "/src/Alpha/.worktrees/a", "branch": "able"},
            ],
        }

        with mock.patch.object(git_wt, "find_repositories", return_value=["/src/zeta", "/src/Alpha"]), \
             mock.patch.object(git_wt, "worktrees", side_effect=listings.get), \
             mock.patch.object(git_wt.os.path, "isdir", return_value=True):
            listed = git_wt.all_worktrees(["/src"])

        self.assertEqual([(entry["repo"], entry["branch"]) for entry in listed],
                         [("Alpha", "trunk"), ("Alpha", "able"), ("Alpha", "zed"), ("zeta", "main")])

    def list_ranked(self, scores_output):
        repos = ["/src/zeta", "/src/Alpha"]
        listings = {repo: [{"path": repo, "branch": "main"}] for repo in repos}
        with mock.patch.object(git_wt, "find_repositories", return_value=repos), \
             mock.patch.object(git_wt, "worktrees", side_effect=listings.get), \
             mock.patch.object(git_wt.os.path, "isdir", return_value=True), \
             mock.patch.object(git_wt.subprocess, "run", side_effect=scores_output):
            return [entry["repo"] for entry in git_wt.all_worktrees(["/src"])]

    def test_ranks_repositories_by_zoxide_usage(self):
        scores = subprocess.CompletedProcess([], 0, "  9.0 /src/zeta/sub\n  2.0 /src/Alpha\n", "")

        self.assertEqual(self.list_ranked([scores]), ["zeta", "Alpha"])

    def test_without_zoxide_repositories_are_alphabetical(self):
        self.assertEqual(self.list_ranked(FileNotFoundError("zoxide")), ["Alpha", "zeta"])


class StaleWorktreeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = pathlib.Path(self.tmp.name) / "repo"
        self.git("init", "-q", "-b", "main", str(self.repo), cwd=self.tmp.name)
        self.git("commit", "-q", "--allow-empty", "-m", "initial")

    def git(self, *args, cwd=None):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                       cwd=cwd or self.repo, check=True, capture_output=True)

    def add_worktree(self, branch, commit=False):
        path = self.repo / ".worktrees" / branch
        self.git("worktree", "add", "-q", "-b", branch, str(path))
        if commit:
            self.git("commit", "-q", "--allow-empty", "-m", branch, cwd=path)
        return path

    def test_lists_merged_worktrees_and_flags_dirty_ones(self):
        self.add_worktree("merged")
        dirty = self.add_worktree("dirty")
        (dirty / "notes.txt").write_text("unsaved\n")
        self.add_worktree("active", commit=True)

        stale = git_wt.stale_worktrees(git_wt.all_worktrees([self.tmp.name]))

        self.assertEqual([(entry["branch"], entry["reason"], entry["dirty"]) for entry in stale],
                         [("dirty", "merged into main", True), ("merged", "merged into main", False)])

    def test_clean_removes_chosen_merged_worktrees_and_keeps_dirty_ones(self):
        merged = self.add_worktree("merged")
        dirty = self.add_worktree("dirty")
        (dirty / "notes.txt").write_text("unsaved\n")

        with mock.patch.object(git_wt, "choose_stale", side_effect=lambda entries: entries) as choose, \
             mock.patch.object(git_wt, "confirm_removal", return_value=True), \
             mock.patch.object(git_wt.os, "getcwd", return_value=self.tmp.name):
            self.assertEqual(git_wt.clean(lambda: git_wt.repository_worktrees(str(self.repo))), 0)

        self.assertEqual([entry["branch"] for entry in choose.call_args.args[0]], ["merged"])
        self.assertFalse(merged.exists())
        self.assertTrue(dirty.exists())


if __name__ == "__main__":
    unittest.main()
