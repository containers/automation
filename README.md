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

For example, to install the `v1.0.0` release, run:
```sh
# url='https://github.com/containers/automation/releases/latest/download/install_automation.sh'
# curl -sL "$url" | bash -s 1.1.3
```

To install `latest`, run:
```sh
# url='https://github.com/containers/automation/releases/latest/download/install_automation.sh'
# curl -sL "$url" | bash -s latest
```

Optionally, the installer may also be passed the names of one or more components to
install system-wide.  For example:

To install the latest `build-push`, run:
```sh
# url='https://github.com/containers/automation/releases/latest/download/install_automation.sh'
# curl -sL "$url" | bash -s latest build-push
```

## Alt. Installation

If you're leery of piping to bash and/or a local clone of the repository is already
available locally, the installer can be invoked with the *magic version* '0.0.0'.
Note that this will limit the install to the local clone (as-is), the installer script
will still reach out to github.com to retrieve version information.  For example:

```sh
# cd /path/to/clone
# ./bin/install_automation.sh 0.0.0
```

## Usage

The basic install consists of copying the contents of the `common` (subdirectory) and
the installer script into a central location on the system.  Because this location
can vary, a global shell variable `$AUTOMATION_LIB_PATH` is widely used.  Therefore,
it is highly recommended that all users and calling scripts explicitly load and export
env. var.  definitions set in the file `/etc/automation_environment`.  For example:

```sh
# set -a
# source /etc/automation_environment
# set +a
```


## Subdirectories

### `.github/workflows`

Directory containing workflows for Github Actions.

### `bin`

Ths directory contains scripts intended for execution under multiple environments,
pertaining to operations on this whole repository.  For example, executing all
unit tests, installing components, etc.

### `common`

This directory contains general-purpose scripts, libraries, and their unit-tests.
They're intended to be used individually or as a whole from within automation of
other repositories.

### `cirrus-ci_retrospective`

See the [README.md file in the subdirectory](cirrus-ci_retrospective/README.md) for more information

### `build-push`

Handy automation too to help with parallel building and pushing container images,
including support for multi-arch (via QEMU emulation).  See the
[README.md file in the subdirectory](build-push/README.md) for more information.
