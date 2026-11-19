import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "Tools/sync-upstream-release.sh"
MOCK_GH = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
endpoint = next(arg for arg in args if arg.startswith("repos/"))
route = endpoint.split("/", 3)[3]
upstream = endpoint.startswith("repos/vorssaint/")
scenario = os.environ["SCENARIO"]
with Path("calls").open("a") as calls:
    print(json.dumps(args), file=calls)
pull = {"number": 1, "state": "open", "head": {"sha": "upstream-release"}, "html_url": "https://example.invalid/pull/1"}
if upstream:
    responses = {"releases/latest": "v3.4.5", "commits/v3.4.5": "upstream-release",
                 "git/ref/heads/main": "upstream-main", "compare/upstream-release...upstream-main": "ahead"}
    print(responses[route])
elif route == "pulls":
    if "--method" not in args or scenario == "conflict":
        print(json.dumps(pull))
elif route == "pulls/1":
    print("false" if scenario == "conflict" else "true")
elif route == "pulls/1/merge":
    print(json.dumps({"merged": True, "sha": "merged-custom"}))
elif route.startswith("releases?"):
    print("custom-v3.5.0" if scenario == "published" else "")
elif route.startswith("git/matching-refs/") or route.startswith("git/refs"):
    pass
else:
    responses = {"git/ref/heads/main": "old-main", "git/ref/heads/custom": "custom-head",
                 "compare/upstream-release...custom-head": "ahead" if scenario in ("resolved", "published") else "diverged"}
    print(responses[route])
'''


class UpstreamSyncTests(unittest.TestCase):
    def run_sync(self, scenario, dry_run=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mock = root / "gh"
            mock.write_text(MOCK_GH, encoding="utf-8")
            mock.chmod(0o700)
            process = subprocess.run(
                ["bash", str(SCRIPT)], cwd=root, capture_output=True, text=True,
                env=dict(os.environ, SCENARIO=scenario, GH_REPO="yoyuzh/vorssaint-utils",
                         DRY_RUN=str(dry_run).lower(), GITHUB_OUTPUT="outputs",
                         GITHUB_STEP_SUMMARY="summary", PATH=f"{root}:{os.environ['PATH']}"),
            )
            calls = [json.loads(call) for call in (root / "calls").read_text().splitlines()]
            output = (root / "outputs").read_text() if (root / "outputs").exists() else ""
            return process, calls, output

    def test_dry_run_makes_no_writes(self):
        process, calls, output = self.run_sync("new", dry_run=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertFalse(any("-X" in call or "-f" in call for call in calls))
        self.assertEqual(output, "")

    def test_creates_pr_and_passes_the_merge_commit_to_cd(self):
        process, calls, output = self.run_sync("new")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertTrue(any("head=sync/upstream-v3.4.5" in call for call in calls))
        self.assertTrue(any("merge_method=merge" in call and "sha=upstream-release" in call for call in calls))
        self.assertEqual(output, "commit=merged-custom\nversion=3.4.5\n")

    def test_conflict_reuses_existing_pr_without_starting_cd(self):
        process, calls, output = self.run_sync("conflict")
        self.assertNotEqual(process.returncode, 0)
        self.assertIn("Resolve conflicts", process.stderr)
        self.assertFalse(any("merge_method=merge" in call or "head=sync/upstream-v3.4.5" in call for call in calls))
        self.assertEqual(output, "")

    def test_manually_merged_release_resumes_cd(self):
        process, _, output = self.run_sync("resolved")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(output, "commit=custom-head\nversion=3.4.5\n")

    def test_older_release_is_not_published(self):
        process, _, output = self.run_sync("published")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(output, "")


if __name__ == "__main__":
    unittest.main()
