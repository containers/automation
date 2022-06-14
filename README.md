# Automation scripts, libraries for re-use in other repositories


## Dependencies

The install script and `common` subdirectory components require the following
system packages (or their equivalents):

* bash
* core-utils
* git
* install


## Installation

During build of an environment (VM, container image, etc), execute *any version*
of [the install
script](https://github.com/containers/automation/releases/download/latest/install_automation.sh),
preferably as root.  The script ***must*** be passed the version number of [the project
release to install](https://github.com/containers/automation/releases).  Alternatively
it may be passed `latest` to install the HEAD of the main branch.

For example, to install the `v1.1.3` release, run:
```bash
~# url='https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh'
~# curl -sL "$url" | bash -s 1.1.3
```

To install `latest`, run:
```bash
~# url='https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh'
~# curl -sL "$url" | bash -s latest
```

### Alt. Installation

If you're leery of piping to bash and/or a local clone of the repository is already
available locally, the installer can be invoked with the *magic version* '0.0.0'.
Note this will limit the install to the local clone (as-is). The installer script
will still reach out to github.com to retrieve version information.  For example:

```bash
~# cd /path/to/clone
/path/to/clone# ./bin/install_automation.sh 0.0.0
```

### Component installation

The installer may also be passed the names of one or more components to
install system-wide.  Available components are simply any subdirectory in the repo
which contain a `.install.sh` file.  For example, to install the latest `build-push` system-wide run:

```bash
~# url='https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh'
~# curl -sL "$url" | bash -s latest build-push
```

## Usage

The basic install consists of copying the contents of the `common` (subdirectory) and
the installer script into a central location on the system.  Because this location
can vary by platform, a global shell variable `$AUTOMATION_LIB_PATH` is established
by a central configuration at install-time.  It is highly recommended that all
callers explicitly load and export the contents of the file
`/etc/automation_environment` before making use of the common library or any
components.  For example:

```bash
#!/bin/bash

set -a
if [[ -r "/etc/automation_environment" ]]; then
    source /etc/automation_environment
fi
set +a

if [[ -n "$AUTOMATION_LIB_PATH" ]]; then
    source $AUTOMATION_LIB_PATH/common_lib.sh
else
    (
    echo "WARNING: It doesn't appear containers/automation common was installed."
    ) > /dev/stderr
fi

...do stuff...
```


## Subdirectories

### `.github/workflows`

Directory containing workflows for Github Actions.

### `bin`

This directory contains scripts intended for execution under multiple environments,
pertaining to operations on this whole repository.  For example, executing all
unit tests, installing components, etc.

### `build-push`

Handy automation too to help with parallel building and pushing container images,
including support for multi-arch (via QEMU emulation).  See the
[README.md file in the subdirectory](build-push/README.md) for more information.

### `cirrus-ci_artifacts`

Handy python script that may be used to download artifacts from any build,
based on knowing its ID.  Downloads will be stored properly nested, by task
name and artifact so there are no name clashes.

### `cirrus-ci_env`

Python script used to minimally parse `.cirrus.yml` tasks as written/formatted
in other containers projects.  This is not intended to be used directly, but
called by other scripts to help extract env. var. values from matrix tasks.

### `cirrus-ci_retrospective`

See the [README.md file in the subdirectory](cirrus-ci_retrospective/README.md) for more information.

### `cirrus-task-map`

Handy script that parses a `.cirrus.yml` and outputs an flow-diagram to illustrate
task dependencies.  Useful for visualizing complex configurations, like that of
`containers/podman`.

### `common`

This directory contains general-purpose scripts, libraries, and their unit-tests.
They're intended to be used individually or as a whole from within automation of
other repositories.

### `github`

Contains some helper scripts/libraries for using `cirrus-ci_retrospective` from
within github-actions workflow.  Not intended to be used otherwise.
