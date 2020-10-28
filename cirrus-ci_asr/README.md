# Description

This is a quickly hacked-together script which examines a Cirrus-CI
build and prints out task IDs and names based on their status.  Additionally,
it will specifically detect and list task IDs which have exhibited
an "CI agent stopped responding!" condition using the status code
`CIASR`.

The output format is very simple: Each line is composed of the
task status (all caps) followed by a comma-separated list
of task IDs, a colon, and quoted task name.

# Installation

Install the python3 module requirements using pip3:
(Note: These go into `$HOME/.local/lib/python<version>`)

```
$ pip3 install --user --requirement ./requirements.txt
```

# Usage

Simply execute the script, providing as arguments:

1. The *user* component of a github repository
2. The *name* component of a github repository
3. The *commit SHA* for the target Cirrus-CI build

# Example: Build monitoring

```
$ watch -n 5 ./cirrus-ci_asr.py containers podman 5d1f8dcea1401854291932d11bea6aa6920a5682

CREATED 6720901876023296:"int podman fedora-32 root host",4521878620471296:"int remote fedora-32 root host",5647778527313920:"int podman fedora-32 rootless host",5084828573892608:"sys podman fedora-32 root host",6210728480735232:"sys remote fedora-32 root host",4803353597181952:"sys podman fedora-32 rootless host"
TRIGGERED
SCHEDULED
EXECUTING 5595001969180672:"Build for fedora-32"
ABORTED
FAILED
COMPLETED 5032052015759360:"Ext. services",6157951922601984:"Smoke Test"
SKIPPED
PAUSED
CIASR
(updates every 5 seconds)
```
