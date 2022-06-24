#!/usr/bin/env python3

"""Verify contents of .cirrus.yml meet specific expectations."""

import asyncio
import os
import re
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock, mock_open, patch

import ccia

import yaml


def fake_makedirs(*args, **dargs):
    return None


# Needed for testing asyncio functions and calls
# ref: https://agariinc.medium.com/strategies-for-testing-async-code-in-python-c52163f2deab
class AsyncMock(MagicMock):

    async def __call__(self, *args, **dargs):
        return super().__call__(*args, **dargs)


class AsyncContextManager(MagicMock):

    async def __aenter__(self, *args, **dargs):
        return self.__enter__(*args, **dargs)

    async def __aexit__(self, *args, **dargs):
        return self.__exit__(*args, **dargs)


class TestBase(unittest.TestCase):

    FAKE_CCI = "sql://fake.url.invalid/graphql"
    FAKE_API = "smb://fake.url.invalid/artifact"

    def setUp(self):
        ccia.VERBOSE = True
        patch('ccia.CCI_GQL_URL', new=self.FAKE_CCI).start()
        patch('ccia.CCI_ART_URL', new=self.FAKE_API).start()
        self.addCleanup(patch.stopall)


class TestUtils(TestBase):

    # YAML is easier on human eyeballs
    # Ref: https://github.com/cirruslabs/cirrus-ci-web/blob/master/schema.graphql
    # type Artifacts and ArtifactFileInfo
    TEST_TASK_YAML = """
        - &test_task
          name: task_1
          id: 1
          buildId: 0987654321
          artifacts:
            - name: test_art-0
              type: test_type-0
              format: art_format-0
              files:
                - path: path/test/art/0
                  size: 0
            - name: test_art-1
              type: test_type-1
              format: art_format-1
              files:
                - path: path/test/art/1
                  size: 1
                - path: path/test/art/2
                  size: 2
            - name: test_art-2
              type: test_type-2
              format: art_format-2
              files:
                - path: path/test/art/3
                  size: 3
                - path: path/test/art/4
                  size: 4
                - path: path/test/art/5
                  size: 5
                - path: path/test/art/6
                  size: 6
        - <<: *test_task
          name: task_2
          id: 2
    """
    TEST_TASKS = yaml.safe_load(TEST_TASK_YAML)
    TEST_URL_RX = re.compile(r"987654321/task_.+/test_art-.+/path/test/art/.+")

    def test_task_art_url_sfxs(self):
        for test_task in self.TEST_TASKS:
            actual = ccia.task_art_url_sfxs(test_task)
            with self.subTest(test_task=test_task):
                for url in actual:
                    with self.subTest(url=url):
                        self.assertRegex(url, self.TEST_URL_RX)

    # N/B: The ClientSession mock causes a (probably) harmless warning:
    # ResourceWarning: unclosed transport <_SelectorSocketTransport fd=7>
    # I have no idea how to fix or hide this, leaving it as-is.
    def test_download_artifacts_all(self):
        for test_task in self.TEST_TASKS:
            with self.subTest(test_task=test_task), \
                    patch('ccia.download_artifact', new_callable=AsyncMock), \
                    patch('ccia.ClientSession', new_callable=AsyncContextManager), \
                    patch('ccia.makedirs', new=fake_makedirs), \
                    patch('ccia.open', new=mock_open()):

                # N/B: This makes debugging VERY difficult, comment out for pdb use
                fake_stdout = StringIO()
                fake_stderr = StringIO()
                with redirect_stderr(fake_stderr), redirect_stdout(fake_stdout):
                    asyncio.run(ccia.download_artifacts(test_task))
                self.assertEqual(fake_stderr.getvalue(), '')
                for line in fake_stdout.getvalue().splitlines():
                    with self.subTest(line=line):
                        self.assertRegex(line.strip(), self.TEST_URL_RX)


class TestMain(unittest.TestCase):

    def setUp(self):
        ccia.VERBOSE = True
        try:
            self.bid = os.environ["CIRRUS_BUILD_ID"]
        except KeyError:
            self.skipTest("Requires running under Cirrus-CI")
        self.tmp = TemporaryDirectory(prefix="test_ccia_tmp")
        self.cwd = os.getcwd()
        os.chdir(self.tmp.name)

    def tearDown(self):
        os.chdir(self.cwd)
        self.tmp.cleanup()

    def main_result_has(self, results, stdout_filepath, action="downloaded"):
        for result in results:
            for action_filepath in result[action]:
                if action_filepath == stdout_filepath:
                    exists = os.path.isfile(os.path.join(self.tmp.name, action_filepath))
                    if "downloaded" in action:
                        self.assertTrue(exists,
                                        msg=f"Downloaded not found: '{action_filepath}'")
                        return
                    # action==skipped
                    self.assertFalse(exists,
                                     msg=f"Skipped file found: '{action_filepath}'")
                    return
        self.fail(f"Expecting to find {action_filepath} entry in main()'s {action} results")

    def test_cirrus_ci_download_all(self):
        expect_rx = re.compile(f".+'{self.bid}/[^/]+/[^/]+/.+'")
        # N/B: This makes debugging VERY difficult, comment out for pdb use
        fake_stdout = StringIO()
        fake_stderr = StringIO()
        with redirect_stderr(fake_stderr), redirect_stdout(fake_stdout):
            results = ccia.main(self.bid)
        self.assertEqual(fake_stderr.getvalue(), '')
        for line in fake_stdout.getvalue().splitlines():
            with self.subTest(line=line):
                s_line = line.lower().strip()
                filepath = line.split(sep="'", maxsplit=3)[1]
                self.assertRegex(s_line, expect_rx)
                if s_line.startswith("download"):
                    self.main_result_has(results, filepath)
                elif s_line.startswith("skip"):
                    self.main_result_has(results, filepath, "skipped")
                else:
                    self.fail(f"Unexpected stdout line: '{s_line}'")

    def test_cirrus_ci_download_none(self):
        # N/B: This makes debugging VERY difficult, comment out for pdb use
        fake_stdout = StringIO()
        fake_stderr = StringIO()
        with redirect_stderr(fake_stderr), redirect_stdout(fake_stdout):
            results = ccia.main(self.bid, r"this-will-match-nothing")
        for line in fake_stdout.getvalue().splitlines():
            with self.subTest(line=line):
                s_line = line.lower().strip()
                filepath = line.split(sep="'", maxsplit=3)[1]
                self.assertRegex(s_line, r"skipping")
                self.main_result_has(results, filepath, "skipped")


if __name__ == "__main__":
    unittest.main()
