### Performance metrics stuffer

Python script which digests a `benchmarks.env` and `benchmarks.csv` file
into a meaningful JSON document-set, then uploads it to google firestore.
It's intended to be run from inside a container, in a podman CI environment.
Besides the two benchmark related files, it requires the env. var.
`$GOOGLE_APPLICATION_CREDENTIALS` is set to the path of a file containing
JSON encoded credentials with access to firestore.
