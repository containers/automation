# automation
Automation scripts, libraries, and other tooling for re-use by other containers org. repositories

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
very specific environment.  It will examine a Cirrus-CI execution after-the-fact,
and provide cross-references and other details in the form of a JSON file.  The
only useful component outside of a github-action environment, is the
`bin/debug.sh` script.  See the comments in that script for usage.

An example of a deployed workflow for this action can be seen in this repo.'s
`.github/workflows/cirrus-ci_retrospective.yml` file.  Execution of this
workflow can be observed under the *actions* tab of the main repository
page.
