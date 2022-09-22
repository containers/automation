#!/usr/bin/env python3

"""Verify cirrus-ci_env.py functions as expected."""

import contextlib
import importlib.util
import os
import sys
import unittest
import unittest.mock as mock
from io import StringIO

import yaml

# Assumes directory structure of this file relative to repo.
TEST_DIRPATH = os.path.dirname(os.path.realpath(__file__))
SCRIPT_FILENAME = os.path.basename(__file__).replace('test_', '')
SCRIPT_DIRPATH = os.path.realpath(os.path.join(TEST_DIRPATH, '..', SCRIPT_FILENAME))


class TestBase(unittest.TestCase):
    """Base test class fixture."""

    def setUp(self):
        """Initialize before every test."""
        super().setUp()
        spec = importlib.util.spec_from_file_location("cci_env", SCRIPT_DIRPATH)
        self.cci_env = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.cci_env)

    def tearDown(self):
        """Finalize after every test."""
        del self.cci_env
        try:
            del sys.modules["cci_env"]
        except KeyError:
            pass


class TestEnvRender(TestBase):
    """Confirming Cirrus-CI in-line env. var. rendering behaviors."""

    def setUp(self):
        """Initialize before every test."""
        super().setUp()
        self.fake_cirrus = mock.Mock(spec=self.cci_env.CirrusCfg)
        attrs = {"format_env.side_effect": self.cci_env.CirrusCfg.format_env,
                 "render_env.side_effect": self.cci_env.CirrusCfg.render_env,
                 "render_value.side_effect": self.cci_env.CirrusCfg.render_value,
                 "get_type_image.return_value": (None, None),
                 "init_task_type_image.return_value": None}
        self.fake_cirrus.configure_mock(**attrs)
        self.render_env = self.fake_cirrus.render_env
        self.render_value = self.fake_cirrus.render_value

    def test_empty(self):
        """Verify an empty env dict is unmodified."""
        self.fake_cirrus.global_env = None
        result = self.render_env(self.fake_cirrus, {})
        self.assertDictEqual(result, {})

    def test_simple_string(self):
        """Verify an simple string value is unmodified."""
        self.fake_cirrus.global_env = None
        result = self.render_env(self.fake_cirrus, dict(foo="bar"))
        self.assertDictEqual(result, dict(foo="bar"))

    def test_simple_sub(self):
        """Verify that a simple string substitution is performed."""
        self.fake_cirrus.global_env = None
        result = self.render_env(self.fake_cirrus, dict(foo="$bar", bar="foo"))
        self.assertDictEqual(result, dict(foo="foo", bar="foo"))

    def test_simple_multi(self):
        """Verify that multiple string substitution are performed."""
        self.fake_cirrus.global_env = None
        result = self.render_env(self.fake_cirrus,
                                 dict(foo="$bar", bar="$baz", baz="foobarbaz"))
        self.assertDictEqual(result,
                             dict(foo="foobarbaz", bar="foobarbaz", baz="foobarbaz"))

    def test_simple_undefined(self):
        """Verify an undefined substitution falls back to dollar-curly env var."""
        self.fake_cirrus.global_env = None
        result = self.render_env(self.fake_cirrus, dict(foo="$baz", bar="${jar}"))
        self.assertDictEqual(result, dict(foo="${baz}", bar="${jar}"))

    def test_simple_global(self):
        """Verify global keys not duplicated into env."""
        self.fake_cirrus.global_env = dict(bar="baz")
        result = self.render_env(self.fake_cirrus, dict(foo="bar"))
        self.assertDictEqual(result, dict(foo="bar"))

    def test_simple_globalsub(self):
        """Verify global keys render substitutions."""
        self.fake_cirrus.global_env = dict(bar="baz")
        result = self.render_env(self.fake_cirrus, dict(foo="${bar}"))
        self.assertDictEqual(result, dict(foo="baz"))

    def test_readonly_params(self):
        """Verify global keys not modified while rendering substitutions."""
        original_global_env = dict(
            foo="foo", bar="bar", baz="baz", test="$item")
        self.fake_cirrus.global_env = dict(**original_global_env)  # A copy
        original_env = dict(item="${foo}$bar${baz}")
        env = dict(**original_env)  # A copy
        result = self.render_env(self.fake_cirrus, env)
        self.assertDictEqual(self.fake_cirrus.global_env, original_global_env)
        self.assertDictEqual(env, original_env)
        self.assertDictEqual(result, dict(item="foobarbaz"))

    def test_render_value(self):
        """Verify render_value() works by not modifying env parameter."""
        self.fake_cirrus.global_env = dict(foo="foo", bar="bar", baz="baz")
        original_env = dict(item="snafu")
        env = dict(**original_env)  # A copy
        test_value = "$foo${bar}$baz $item"
        expected_value = "foobarbaz snafu"
        actual_value = self.render_value(self.fake_cirrus, test_value, env)
        self.assertDictEqual(env, original_env)
        self.assertEqual(actual_value, expected_value)


class TestRenderTasks(TestBase):
    """Fixture for exercising Cirrus-CI task-level env. and matrix rendering behaviors."""

    def setUp(self):
        """Initialize before every test."""
        super().setUp()
        self.CCfg = self.cci_env.CirrusCfg
        self.global_env = dict(foo="foo", bar="bar", baz="baz")
        self.patchers = (
            mock.patch.object(self.CCfg, 'get_type_image',
                              mock.Mock(return_value=(None, None))),
            mock.patch.object(self.CCfg, 'init_task_type_image',
                              mock.Mock(return_value=None)))
        for patcher in self.patchers:
            patcher.start()

    def tearDown(self):
        """Finalize after every test."""
        for patcher in self.patchers:
            patcher.stop()
        super().tearDown()

    def test_empty_in_empty_out(self):
        """Verify initializing with empty tasks and globals results in empty output."""
        result = self.CCfg(dict(env=dict())).tasks
        self.assertDictEqual(result, dict())

    def test_simple_render(self):
        """Verify rendering of task local and global env. vars."""
        env = dict(item="${foo}$bar${baz}", test="$undefined")
        task = dict(something="ignored", env=env)
        config = dict(env=self.global_env, test_task=task)
        expected = {
            "test": {
                "alias": "test",
                "env": {
                    "item": "foobarbaz",
                    "test": "${undefined}"
                }
            }
        }
        result = self.CCfg(config).tasks
        self.assertDictEqual(result, expected)

    def test_noenv_render(self):
        """Verify rendering of task w/o local env. vars."""
        task = dict(something="ignored")
        config = dict(env=self.global_env, test_task=task)
        expected = {
            "test": {
                "alias": "test",
                "env": {}
            }
        }
        result = self.CCfg(config).tasks
        self.assertDictEqual(result, expected)

    def test_simple_matrix(self):
        """Verify unrolling of a simple matrix containing two tasks."""
        matrix1 = dict(name="test_matrix1", env=dict(item="${foo}bar"))
        matrix2 = dict(name="test_matrix2", env=dict(item="foo$baz"))
        task = dict(env=dict(something="untouched"), matrix=[matrix1, matrix2])
        config = dict(env=self.global_env, test_task=task)
        expected = {
            "test_matrix1": {
                "alias": "test",
                "env": {
                    "item": "foobar",
                    "something": "untouched"
                }
            },
            "test_matrix2": {
                "alias": "test",
                "env": {
                    "item": "foobaz",
                    "something": "untouched"
                }
            }
        }
        result = self.CCfg(config).tasks
        self.assertNotIn('test_task', result)
        for task_name in ('test_matrix1', 'test_matrix2'):
            self.assertIn(task_name, result)
            self.assertDictEqual(expected[task_name], result[task_name])
        self.assertDictEqual(result, expected)

    def test_noenv_matrix(self):
        """Verify unrolling of single matrix w/o env. vars."""
        matrix = dict(name="test_matrix")
        task = dict(env=dict(something="untouched"), matrix=[matrix])
        config = dict(env=self.global_env, test_task=task)
        expected = {
            "test_matrix": {
                "alias": "test",
                "env": {
                    "something": "untouched"
                }
            }
        }
        result = self.CCfg(config).tasks
        self.assertDictEqual(result, expected)

    def test_rendered_name_matrix(self):
        """Verify env. values may be used in matrix names with spaces."""
        test_foobar = dict(env=dict(item="$foo$bar", unique="item"))
        bar_test = dict(name="$bar test", env=dict(item="${bar}${foo}", NAME="snafu"))
        task = dict(name="test $item",
                    env=dict(something="untouched"),
                    matrix=[bar_test, test_foobar])
        config = dict(env=self.global_env, blah_task=task)
        expected = {
            "test foobar": {
                "alias": "blah",
                "env": {
                    "item": "foobar",
                    "something": "untouched",
                    "unique": "item"
                }
            },
            "bar test": {
                "alias": "blah",
                "env": {
                    "NAME": "snafu",
                    "item": "barfoo",
                    "something": "untouched"
                }
            }
        }
        result = self.CCfg(config).tasks
        self.assertDictEqual(result, expected)

    def test_bad_env_matrix(self):
        """Verify old-style 'matrix' key of 'env' attr. throws helpful error."""
        env = dict(foo="bar", matrix=dict(will="error"))
        task = dict(env=env)
        config = dict(env=self.global_env, test_task=task)
        err = StringIO()
        with contextlib.suppress(SystemExit), mock.patch.object(self.cci_env,
                                                                'err', err.write):
            self.assertRaises(ValueError, self.CCfg, config)
        self.assertRegex(err.getvalue(), ".+'matrix'.+'env'.+'test'.+")


class TestCirrusCfg(TestBase):
    """Fixture to verify loading/parsing from an actual YAML file."""

    def setUp(self):
        """Initialize before every test."""
        super().setUp()
        self.CirrusCfg = self.cci_env.CirrusCfg
        with open(os.path.join(TEST_DIRPATH, "actual_cirrus.yml")) as actual:
            self.actual_cirrus = yaml.safe_load(actual)

    def test_complex_cirrus_cfg(self):
        """Verify that CirrusCfg can be initialized from a complex .cirrus.yml."""
        with open(os.path.join(TEST_DIRPATH, "expected_cirrus.yml")) as expected:
            expected_cirrus = yaml.safe_load(expected)
        actual_cfg = self.CirrusCfg(self.actual_cirrus)
        self.assertSetEqual(set(actual_cfg.tasks.keys()),
                            set(expected_cirrus["tasks"].keys()))

    def test_complex_type_image(self):
        """Verify that CirrusCfg initializes with expected image types and values."""
        with open(os.path.join(TEST_DIRPATH, "expected_ti.yml")) as expected:
            expected_ti = yaml.safe_load(expected)
        actual_cfg = self.CirrusCfg(self.actual_cirrus)
        self.assertEqual(len(actual_cfg.tasks), len(expected_ti))
        actual_ti = {k: [v["inst_type"], v["inst_image"]]
                     for (k, v) in actual_cfg.tasks.items()}
        self.maxDiff = None  # show the full dif
        self.assertDictEqual(actual_ti, expected_ti)


if __name__ == "__main__":
    unittest.main()
