#!/bin/bash

# This script is intended to be executed by the `registry_details`
# github composite action.  Use under any other environment is virtually
# guaranteed to behave unexpectedly.

set -eo pipefail

# For human readability, reference input variable name used
# in the workflow, not the mangled action variable name.
inp_var_name() {
    echo -n $(tr "[A-Z]" "[a-z]" <<<"${1#INPUT_}")
}

req_inp_vars() {
    local var
    local val
    for var in "$@"; do
        val=$(tr -d "[:space:]" <<<"${!var}")
        if [[ -z "${val}" ]]; then
            echo "::error::Input variable '$(inp_var_name $var)' must not be empty or whitespace."
            exit 1
        fi
    done
}

req_inp_vars INPUT_SOURCE_NAME INPUT_SECRET_PREFIX \
             INPUT_REPONAME_QUAY_USERNAME INPUT_REPONAME_QUAY_PASSWORD \
             INPUT_CONTAINERS_QUAY_USERNAME INPUT_CONTAINERS_QUAY_PASSWORD

reponame=$(cut -d "/" -f 2 <<<"$GITHUB_REPOSITORY")
username_varname="INPUT_${INPUT_SECRET_PREFIX}_QUAY_USERNAME"
password_varname="INPUT_${INPUT_SECRET_PREFIX}_QUAY_PASSWORD"

case "$INPUT_SECRET_PREFIX" in
  REPONAME)
      echo "Will operate on 'quay.io/$reponame/$INPUT_SOURCE_NAME'"
      echo "::set-output name=namespace::quay.io/$reponame"
      echo "::set-output name=image_name::$INPUT_SOURCE_NAME"
      ;;
  CONTAINERS)
      echo "Will operate on 'quay.io/containers/$reponame'"
      echo "::set-output name=namespace::quay.io/containers"
      echo "::set-output name=image_name::$reponame"
      ;;
  *)
      echo "::error::Unknown secret_prefix '$INPUT_SECRET_PREFIX'"
      exit 1
      ;;
esac

username="${!username_varname}"
password="${!password_varname}"
echo "Getting username from $(inp_var_name $username_varname), password from $(inp_var_name $password_varname)"
echo "::set-output name=username::$username"
echo "::set-output name=password::$password"
