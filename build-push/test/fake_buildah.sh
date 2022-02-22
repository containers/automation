#!/bin/bash

set -e

# Need to keep track of values from 'build' to 'manifest' calls
DATF='/tmp/fake_buildah.json'

if [[ "$1" == "build" ]]; then
    echo '{"manifests":[' > $DATF
    for arg; do
        if [[ "$arg" =~ --platform= ]]; then
            for platarch in $(cut -d '=' -f 2 <<<"$arg" | tr ',' ' '); do
                arch=$(cut -d '/' -f 2 <<<"$platarch")
                [[ -n "$arch" ]] || continue
                echo "FAKEBUILDAH ($arch)" > /dev/stderr
                echo -n '    {"platform":{"architecture":"' >> $DATF
                echo -n "$arch" >> $DATF
                echo '"}},' >> $DATF
            done
        fi
    done
    # dummy-value to avoid dealing with JSON oddity: last item must not
    # end with a comma
    echo '    {}' >> $DATF
    echo ']}' >> $DATF

    # Tests expect to see this
    echo "FAKEBUILDAH $@"
elif [[ "$1" == "manifest" ]]; then
    # validate json while outputing it
    jq . $DATF
elif [[ "$1" =~ info ]]; then
    case "$@" in
        *arch*) echo "amd64" ;;
        *cpus*) echo "2" ;;
        *) exit 1 ;;
    esac
else
    echo "ERROR: Unexpected call to fake_buildah.sh"
    exit 9
fi
