#!/usr/bin/env python3

"""
Verify contents of .cirrus.yml meet specific expectations
"""

import sys
import os
from io import StringIO
import unittest
import importlib.util
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import Mock, patch
from urllib.parse import quote
import yaml

# Assumes directory structure of this file relative to repo.
TEST_DIRPATH = os.path.dirname(os.path.realpath(__file__))
SCRIPT_FILENAME = os.path.basename(__file__).replace('test_','')
SCRIPT_DIRPATH = os.path.realpath(os.path.join(TEST_DIRPATH, '..', SCRIPT_FILENAME))

# Script otherwise not intended to be loaded as a module
spec = importlib.util.spec_from_file_location("cci_arts", SCRIPT_DIRPATH)
cci_arts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cci_arts)


class TestBase(unittest.TestCase):

    FAKE_GCS = "ftp://foo.bar"
    FAKE_CCI = "sql://sna.fu"

    ORIGINAL_GCS = cci_arts.GCS_URL_BASE
    ORIGINAL_CCI = cci_arts.CCI_GQL_URL

    def setUp(self):
        cci_arts.GCS_URL_BASE = self.FAKE_GCS
        cci_arts.CCI_GQL_URL = self.FAKE_CCI

    def tearDown(self):
        cci_arts.GCS_URL_BASE = self.ORIGINAL_GCS
        cci_arts.CCI_GQL_URL = self.ORIGINAL_CCI


class TestUtils(TestBase):

    # YAML is easier on human eyeballs
    # Ref: https://github.com/cirruslabs/cirrus-ci-web/blob/master/schema.graphql
    # type Artifacts and ArtifactFileInfo
    TEST_ARTIFACTS_YAML = """
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
        - name: test_art-2
          type: test_type-2
          format: art_format-2
          files:
            - path: path/test/art/2
              size: 2
    """
    TEST_ARTIFACTS = yaml.safe_load(TEST_ARTIFACTS_YAML)

    def setUp(self):
        super().setUp()

    def test_get_arg(self):
        argv=('test0', 'test1', 'test2', 'test3', 'test4', 'test5')
        with patch('sys.argv', new=argv):
            for arg_n in range(0,6):
                with self.subTest(arg_n=arg_n):
                    expected = f"test{arg_n}"
                    self.assertEqual(
                        cci_arts.get_arg(arg_n, "foobar"),
                        expected)

    def test_empty_get_arg(self):
        argv=('test1', '')
        with patch('sys.argv', new=argv):
            self.assertRaisesRegex(ValueError, f"Usage: {argv[0]}",
                cci_arts.get_arg, 1, "empty")

    def test_empty_get_arg(self):
        argv=('test2', '')
        fake_exit = Mock()
        fake_stdout = StringIO()
        fake_stderr = StringIO()
        with patch('sys.argv', new=argv), patch('sys.exit', new=fake_exit):
            # N/B: This makes debugging VERY difficult
            with redirect_stderr(fake_stderr), redirect_stdout(fake_stdout):
                cci_arts.get_arg(2, "unset")
        self.assertEqual(fake_stdout.getvalue(), '')
        self.assertRegex(fake_stderr.getvalue(), r'Error: Missing')
        fake_exit.assert_called_with(1)

    def test_art_to_url(self, test_arts=TEST_ARTIFACTS):
        exp_tid=1234
        exp_repo="foo/bar"
        exp_bucket="snafu"
        args = (exp_tid, test_arts, exp_repo, exp_bucket)
        actual = cci_arts.art_to_url(*args)
        for art_n, act_name_url in enumerate(actual):
            exp_name = f"test_art-{art_n}"
            act_name = act_name_url[0]
            with self.subTest(exp_name=exp_name, act_name=act_name):
                self.assertEqual(exp_name, act_name)

            # Name and path must be url-encoded
            exp_q_name = quote(exp_name)
            exp_q_path = quote(test_arts[art_n]["files"][0]["path"])
            # No shortcut here other than duplicating the well-established format
            exp_url = f"{self.FAKE_GCS}/{exp_bucket}/artifacts/{exp_repo}/{exp_tid}/{exp_q_name}/{exp_q_path}"
            act_url = act_name_url[1]
            with self.subTest(exp_url=exp_url, act_url=act_url):
                self.assertEqual(exp_url, act_url)

    def test_bad_art_to_url(self):
        broken_artifacts = yaml.safe_load(TestUtils.TEST_ARTIFACTS_YAML)
        del broken_artifacts[0]["files"]  # Ref #1 (below)
        broken_artifacts[1]["files"] = {}
        broken_artifacts[2] = {}  # Ref #2 (below)
        fake_stdout = StringIO()
        fake_stderr = StringIO()
        # N/B: debugging VERY difficult
        with redirect_stderr(fake_stderr), redirect_stdout(fake_stdout):
            self.test_art_to_url(test_arts=broken_artifacts)

        stderr = fake_stderr.getvalue()
        stdout = fake_stdout.getvalue()
        self.assertEqual(stdout, '')
        # Ref #1 (above)
        self.assertRegex(stderr, r"Warning:.+TID 1234.+key 'files'")
        # Ref #2 (above)
        self.assertRegex(stderr, r"Warning:.+TID 1234.+key 'name'")


if __name__ == "__main__":
    unittest.main()
