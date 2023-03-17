#!/usr/bin/env python3

"""Verify bench_stuff.py functions and functionality across valid and invalid inputs."""

import unittest
from pathlib import PosixPath
from shutil import copytree
from tempfile import TemporaryDirectory
from unittest.mock import Mock, call, patch

import bench_stuff


class FakeEnv(Mock):

    envs = None

    def int(self, key):
        return int(self.envs[key])

    def str(self, key):
        return str(self.envs[key])


def fakedie(msg, code=1):
    raise RuntimeError(msg)


class TestBase(unittest.TestCase):

    TEMPDIR = None
    FAKE_FIRESTORE = None
    FAKE_DIE = None
    FAKE_ENV = None
    FAKE_BENCH_VER = 1
    FAKE_CPUS = 96
    FAKE_MEM = 1024 * 1024
    FAKE_TASK = 12345
    FAKE_BUILD = 54321
    FAKE_BRANCH = "test/testing"
    FAKE_DISTRO = "TestOS-42"
    FAKE_UNAME_R = "1.2.3-4.i386"
    FAKE_UNAME_M = "i386"
    FAKE_INST = "box"
    FAKE_COMMIT = "1e06c1a47a71cc649032bf6ee71e14b990dae957"

    def setUp(self):
        bench_stuff.VERBOSE = False
        self.FAKE_FIRESTORE = Mock(spec=bench_stuff.firestore)
        # The env class/objects operate with a global-scope, which makes testing hard.
        # Avoid trying to keep globals "sane" by mocking out envparse.env() entirely.
        self.FAKE_ENV = FakeEnv()
        self.FAKE_ENV.envs = {
            "BENCH_ENV_VER": self.FAKE_BENCH_VER,
            "CPUTOTAL": self.FAKE_CPUS,
            "MEMTOTALKB": self.FAKE_MEM,
            "CIRRUS_TASK_ID": self.FAKE_TASK,
            "CIRRUS_BUILD_ID": self.FAKE_BUILD,
            "CIRRUS_BRANCH": self.FAKE_BRANCH,
            "DISTRO_NV": self.FAKE_DISTRO,
            "UNAME_R": self.FAKE_UNAME_R,
            "UNAME_M": self.FAKE_UNAME_M,
            "INST_TYPE": self.FAKE_INST,
            "CIRRUS_CHANGE_IN_REPO": self.FAKE_COMMIT,
        }
        self.FAKE_DIE = Mock(side_effect=fakedie)
        patch('bench_stuff.firestore', new=self.FAKE_FIRESTORE).start()
        patch('bench_stuff.env', new=self.FAKE_ENV).start()
        patch('bench_stuff.die', new=self.FAKE_DIE).start()
        self.addCleanup(patch.stopall)
        self.TEMPDIR = TemporaryDirectory(prefix="tmp_test_bench_stuff_")

    def tearDown(self):
        self.TEMPDIR.cleanup()


class TestMain(TestBase):

    def setUp(self):
        super().setUp()

    def test_good(self):
        tmp = PosixPath(self.TEMPDIR.name)
        copytree("./test_data/good", tmp, dirs_exist_ok=True)

        bench_stuff.main(tmp / "benchmarks.env", tmp / "benchmarks.csv")
        self.FAKE_ENV.read_envfile.assert_called_with(tmp / "benchmarks.env")

        self.assertTrue(self.FAKE_FIRESTORE.Client.called)
        test_client = self.FAKE_FIRESTORE.Client

        bench_call = call().collection('benchmarks')
        type_call = call().collection().document(self.FAKE_UNAME_M)
        key_call = call().collection().document().collection().document(str(self.FAKE_TASK))
        calls = [bench_call, type_call, key_call]
        test_client.assert_has_calls(calls, any_order=True)

    @patch('bench_stuff.DRYRUN', new=True)
    def test_dry_run(self):
        tmp = PosixPath(self.TEMPDIR.name)
        copytree("./test_data/good", tmp, dirs_exist_ok=True)
        bench_stuff.main(tmp / "benchmarks.env", tmp / "benchmarks.csv")
        self.FAKE_FIRESTORE.Client.assert_not_called()

    def test_unknown_units(self):
        tmp = PosixPath(self.TEMPDIR.name)
        # Contains data with an invalid unit-suffix
        copytree("./test_data/bad", tmp, dirs_exist_ok=True)
        self.FAKE_DIE.assert_not_called()
        self.assertRaisesRegex(RuntimeError,
                               r"parse units from",
                               bench_stuff.main,
                               tmp / "benchmarks.env",
                               tmp / "benchmarks.csv")
        self.FAKE_DIE.assert_called_once()


class TestUtils(TestBase):

    def test_seconds(self):
        data = {"lower": "1.0001s", "upper": "1.0001S", "space": "1.0001 s"}
        result = bench_stuff.handle_units(data)
        for key in ("lower", "upper", "space"):
            self.assertAlmostEqual(result[key], 1.0001)

    def test_kb(self):
        data = {"lower": "1023.99kb", "upper": "1023.99KB", "space": "1023.99 kb"}
        result = bench_stuff.handle_units(data)
        for key in ("lower", "upper", "space"):
            self.assertEqual(result[key], 1048566)

    def test_no_units(self):
        self.FAKE_DIE.assert_not_called()
        self.assertRaisesRegex(RuntimeError,
                               r"parse units from.+answer.+42",
                               bench_stuff.handle_units,
                               {"answer": "42"})
        self.FAKE_DIE.assert_called_once()


if __name__ == "__main__":
    unittest.main()
