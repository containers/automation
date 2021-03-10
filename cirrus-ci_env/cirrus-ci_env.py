#!/usr/bin/env python3

"""Utility to provide canonical listing of Cirrus-CI tasks and env. vars."""

import argparse
import re
import sys
from typing import Any, Mapping

import yaml


def err(msg: str):
    """Print an error message to stderr and exit non-zero."""
    print(f"\nError: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


class DefFmt(dict):
    """
    Defaulting-dict helper class for render_env()'s str.format_map().

    See: https://docs.python.org/3.7/library/stdtypes.html#str.format_map
    """

    dollar_env_var = re.compile(r"\$(\w+)")
    dollarcurly_env_var = re.compile(r"\$\{(\w+)\}")

    def __missing__(self, key: str) -> str:
        """Not-found items converted back to shell env var format."""
        return "${{{0}}}".format(key)


class CirrusCfg:
    """Represent a fully realized list of .cirrus.yml tasks."""

    # Dictionary of global, configuration-wide environment variable values.
    global_env = None

    # String values representing instance type and image name/path/uri
    global_type = None
    global_image = None

    def __init__(self, config: Mapping[str, Any]) -> None:
        """Create a new instance, given a parsed .cirrus.yml config object."""
        if not isinstance(config, dict):
            whatsit = config.__class__
            raise TypeError(f"Expected 'config' argument to be a dictionary, not a {whatsit}")
        # This makes a copy, doesn't touch the original
        self.global_env = self.render_env(config.get("env", dict()))
        self.global_type, self.global_image = self.get_type_image(config)
        self.tasks = self.render_tasks(config)
        self.names = list(self.tasks.keys())
        self.names.sort()
        self.names = tuple(self.names)  # help notice attempts to modify

    def render_env(self, env: Mapping[str, str]) -> Mapping[str, str]:
        """
        Repeatedly call format_env() to render out-of-order env key values.

        This is a compromise vs recursion. Since substitution values may be
        referenced while processing, and dictionary keys have no defined
        order.  Simply provide multiple chances for the substitution to
        occur.  On failure, a shell-compatible variable reference is simply
        left in place.
        """
        # There's no simple way to detect when substitutions are
        # complete, so we mirror Cirrus-CI's behavior which
        # loops 10 times (according to their support) through
        # the substitution routine.
        out = self.format_env(env, self.global_env)
        for _ in range(9):
            out = self.format_env(out, self.global_env)
        return out

    @staticmethod
    def format_env(env, global_env: Mapping[str, str]) -> Mapping[str, str]:
        """Replace shell-style references in env values, from global_env then env."""
        # This method is also used to initialize self.global_env
        if global_env is None:
            global_env = dict()

        rep = r"{\1}"  # Shell env var to python format string conversion regex
        def_fmt = DefFmt(**global_env)  # Assumes global_env already rendered

        for k, v in env.items():
            if "ENCRYPTED" in str(v):
                continue
            _ = def_fmt.dollarcurly_env_var.sub(rep, str(v))
            def_fmt[k] = def_fmt.dollar_env_var.sub(rep, _)
        out = dict()
        for k, v in def_fmt.items():
            if k in env:  # Don't unnecessarily duplicate globals
                out[k] = str(v).format_map(def_fmt)
        return out

    def render_tasks(self, tasks: Mapping[str, Any]) -> Mapping[str, Any]:
        """Return new tasks dict with envs rendered and matrices unrolled."""
        result = dict()
        for k, v in tasks.items():
            if not k.endswith("_task"):
                continue
            # Cirrus-CI uses this defaulting priority order
            alias = v.get("alias", k.replace("_task", ""))
            name = v.get("name", alias)
            if "matrix" in v:
                # Assume Cirrus-CI accepted this config., don't check name clashes
                result.update(self.unroll_matrix(name, alias, v))
            else:
                task = dict(alias=alias)
                task["env"] = self.render_env(v.get("env", dict()))
                task_name = self.render_value(name, task["env"])
                _ = self.get_type_image(v, self.global_type, self.global_image)
                self.init_task_type_image(task, *_)
                result[task_name] = task
        return result

    def unroll_matrix(self, name_default: str, alias_default: str,
                      task: Mapping[str, Any]) -> Mapping[str, Any]:
        """Produce copies of task with attributes replaced from matrix list."""
        result = dict()
        for item in task["matrix"]:
            if "name" not in task and "name" not in item:
                # Cirrus-CI goes a step further, attempting to generate a
                # unique name based on alias + matrix attributes.  This is
                # a very complex process that would be insane to attempt to
                # duplicate.  Instead, simply require a defined 'name'
                # attribute in every case, throwing an error if not found.
                raise ValueError(f"Expecting 'name' attribute in"
                                 f" '{alias_default}_task'"
                                 f" or matrix definition: {item}"
                                 f" for task definition: {task}")
            # default values for the rendered task - not mutable, needs a copy.
            matrix_task = dict(alias=alias_default, env=task.get("env").copy())
            matrix_name = item.get("name", name_default)

            # matrix item env. overwrites task env.
            matrix_task["env"].update(item.get("env", dict()))
            matrix_task["env"] = self.render_env(matrix_task["env"])
            matrix_name = self.render_value(matrix_name, matrix_task["env"])

            # Matrix item overides task dict, overrides global defaults.
            _ = self.get_type_image(item, self.global_type, self.global_image)
            matrix_type, matrix_image = self.get_type_image(task, *_)
            self.init_task_type_image(matrix_task, matrix_type, matrix_image)
            result[matrix_name] = matrix_task
        return result

    def render_value(self, value: str, env: Mapping[str, str]) -> str:
        """Given a string value and task env dict, safely render references."""
        tmp_env = env.copy()  # don't mess up the original
        tmp_env["__value__"] = value
        return self.format_env(tmp_env, self.global_env)["__value__"]

    def get_type_image(self, item: dict,
                       default_type: str = None,
                       default_image: str = None) -> tuple:
        """Given Cirrus-CI config or task dict., return instance type and image."""
        # Order is significant, VMs always override containers
        if "gce_instance" in item:
            return "gcevm", item["gce_instance"].get("image_name", default_image)
        elif "osx_instance" in item:
            return "osx", item["osx_instance"].get("image", default_image)
        elif "image" in item.get("container", ""):
            return "container", item["container"].get("image", default_image)
        elif "dockerfile" in item.get("container", ""):
            return "dockerfile", item["container"].get("dockerfile", default_image)
        else:
            inst_type = None
            if self.global_type is not None:
                inst_type = default_type
            inst_image = None
            if self.global_image is not None:
                inst_image = default_image
            return inst_type, inst_image

    def init_task_type_image(self, task: Mapping[str, Any],
                             task_type: str, task_image: str) -> None:
        """Render any envs. and assert non-none values for task."""
        if task_type is None or task_image is None:
            raise ValueError(f"Invalid instance type "
                             f"({task_type}) or image ({task_image}) "
                             f"for task ({task})")
        task["inst_type"] = task_type
        task["inst_image"] = self.render_value(task_image, task["env"])


class CLI:
    """Represent command-line-interface runtime state and behaviors."""

    # An argparse parser instance
    parser = None

    # When valid, namespace instance from parser
    args = None

    # When loaded successfully, instance of CirrusCFG
    ccfg = None

    def __init__(self) -> None:
        """Initialize runtime context based on command-line options and parameters."""
        self.parser = self.args_parser()
        self.args = self.parser.parse_args()
        self.ccfg = CirrusCfg(yaml.safe_load(self.args.filepath))
        if not len(self.ccfg.names):
            self.parser.print_help()
            err(f"No Cirrus-CI tasks found in '{self.args.filepath.name}'")

    def __call__(self) -> None:
        """Execute request command-line actions."""
        if self.args.list:
            for task_name in self.ccfg.names:
                sys.stdout.write(f"{task_name}\n")
        elif bool(self.args.inst):
            task = self.ccfg.tasks[self.valid_name()]
            inst_type = task['inst_type']
            inst_image = task['inst_image']
            sys.stdout.write(f"{inst_type} {inst_image}\n")
        elif bool(self.args.envs):
            task = self.ccfg.tasks[self.valid_name()]
            env = self.ccfg.global_env.copy()
            env.update(task['env'])
            keys = list(env.keys())
            keys.sort()
            for key in keys:
                if key.startswith("_"):
                    continue  # Assume private to Cirrus-CI
                value = env[key]
                sys.stdout.write(f'{key}="{value}"\n')

    def args_parser(self) -> argparse.ArgumentParser:
        """Parse command-line options and arguments."""
        epilog = "Note: One of --list, --envs, or --inst MUST be specified"
        parser = argparse.ArgumentParser(description=__doc__,
                                         epilog=epilog)
        parser.add_argument('filepath', type=argparse.FileType("rt"),
                            help="File path to .cirrus.yml",
                            metavar='<filepath>')
        mgroup = parser.add_mutually_exclusive_group(required=True)
        mgroup.add_argument('--list', action='store_true',
                            help="List canonical task names")
        mgroup.add_argument('--envs', action='store',
                            help="List env. vars. for task <name>",
                            metavar="<name>")
        mgroup.add_argument('--inst', action='store',
                            help="List instance type and image for task <name>",
                            metavar="<name>")
        return parser

    def valid_name(self) -> str:
        """Print helpful error message when task name is invalid, or return it."""
        if self.args.envs is not None:
            task_name = self.args.envs
        else:
            task_name = self.args.inst
        file_name = self.args.filepath.name
        if task_name not in self.ccfg.names:
            self.parser.print_help()
            err(f"Unknown task name '{task_name}' from '{file_name}'")
        return task_name


if __name__ == "__main__":
    cli = CLI()
    cli()
