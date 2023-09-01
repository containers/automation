# README.md

`validate_image_cirrus.py` is a complex and somewhat hastily-written script
for validating the safety of various `quay.io` container images using several
methods in concert with data pulled from the Cirrus-CI API.  It's intended
for use in response to a specific incident outlined here:

https://github.com/containers/podman/discussions/19796

# Usage

Running it locally requires quite a bit of network-bandwidth and storage
space.  The subject-images for validation must be synced using a skopeo
command substantially similar to:

```
$ skopeo sync -a --scoped --preserve-digests -s docker -d dir \
    registry.example.com/foo/bar:tag \
    /path/to/dir
$ ...repeat as necessary...
```

Running the validation script then goes something like:

```
$ virtualenv venv
$ source venv/bin/activate
$ pip3 install --upgrade pip
$ pip3 install -r requirements.txt
$ ./validate_image_cirrus.py --help
$ ...repeat as necessary...
$ deactivate  # assuming you're all done.
```

# Note re: `-c,--cirrus` option

If the `quay.io` push dates are missing an EST/EDT suffix, they can be
converted inline with a command similar to:

```
$ push_date="4/28/2022 14:54:00"
$ unix_push_date
$ ./validate_image_cirrus.py \
  -c $(date -u --iso-8601=seconds -d @$(\
    TZ=America/New_York date -d "$push_date" "+%s")) \
  ...
```
