#!/bin/bash

if [[ "$1" == "manifest" ]]; then
    cat <<EOF
{"manifests":[
    {"platform":{"architecture":"amd64"}},
    {"platform":{"architecture":"correct"}},
    {"platform":{"architecture":"horse"}},
    {"platform":{"architecture":"battery"}},
    {"platform":{"architecture":"staple"}}
]}
EOF
elif [[ "$1" =~ info ]]; then
    case "$@" in
        *arch*) echo "amd64" ;;
        *cpus*) echo "2" ;;
        *) exit 1 ;;
    esac
else
    echo "FAKEBUILDAH $@"
fi
