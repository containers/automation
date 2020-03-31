# automation
Automation scripts, libraries, and other tooling for re-use by other containers org.
repositories

## Usage

During build of an environment (VM, container image, etc), execute *any version*
of [the install
script](https://github.com/containers/automation/releases/download/latest/install_automation.sh),
preferably as root.  The script ***must*** be passed the version number of [the project
release to install](https://github.com/containers/automation/releases).  Before making
changes to the environment, the script will first download and then re-execute
the requested version of itself.

For example, to install the `v1.0.0` release, run:
```sh
url='https://github.com/containers/automation/releases/latest/download/install_automation.sh'
curl -sL "$url" | bash -s 1.0.0
```

The basic install consists of copying the contents of the `common` (subdirectory) and
the installer script into a central location on the system.  A global shell variable
(`$AUTOMATION_LIB_PATH`) is set so that any dependent scripts can easily access the
installed files.

## Alt. Usage

If a clone of the repository is already available locally, the installer can be invoked
with the magic version number '0.0.0'.  Note that, while it will install the files
from the local clone as-is, the installer still needs to reach out to github to
retrieve tree-history details.  This is required for the installer to properly
set the actual version-number as part of the process.

Though not recommended at all, it is also possible to specify the version as
`latest`.  This will clone down whatever happens to be on the master branch
at the time.  Though it will probably work, it's best for stability to specify
an explicit released version.

## Dependencies

The install script and `common` subdirectory components require the following
system packages (or their equivalents):

* bash
* core-utils
* git
* install

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

This directory contains items intended for use in/by a github-action, under a
that environment.  It helps perform automated analysis of a Cirrus-CI execution
after-the-fact.  Providing cross-references and other runtime details in a JSON
output file.

An commented example of using the cirrus-ci_retrospective container is present in
this repository, and used to bootstrap testing of PRs that modify it's files.

Outside of the github-action environment, there is a `bin/debug.sh` script.  This
is intended for local use, and will provide additional runtime operational details.
See the comments in the script for its usage.
