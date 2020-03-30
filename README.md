# automation
Automation scripts, libraries, and other tooling for re-use by other containers org.
repositories

## bin

Ths directory contains scripts intended for execution under multiple environments,
pertaining to operations on this whole repository.  For example, executing all
unit tests, installing components, etc.

## common

This directory contains general-purpose scripts, libraries, and their unit-tests.
They're intended to be used individually or as a whole from within automation of
other repositories.

## cirrus-ci_retrospective

This directory contains items intended for use in/by a github-action, under a
that environment.  It helps perform automated analysis of a Cirrus-CI execution
after-the-fact.  Providing cross-references and other runtime details in a JSON
output file.

An commented example of using the cirrus-ci_retrospective container is present in
this repository, and used to bootstrap testing of PRs that modify it's files.

Outside of the github-action environment, there is a `bin/debug.sh` script.  This
is intended for local use, and will provide additional runtime operational details.
See the comments in the script for its usage.
