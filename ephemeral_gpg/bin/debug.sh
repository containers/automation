#!/bin/bash

set -eo pipefail

# Intended to be used by humans for debugging purposes.  Drops the caller
# into a bash shell within a pre-configured ephemeral environment.

EPHEMERAL_GPG_LIB=$(dirname $(realpath "$0"))/../lib/ephemeral_gpg.sh
set -a
# Will be spawning interactive shell near the end, make sure it can access these functions
source "$EPHEMERAL_GPG_LIB"
set +a

##### MAIN() #####

msg "Setting up mock ephemeral directory, \$PRIVATE_KEY_FILEPATH and \$PRIVATE_PASSPHRASE_FILEPATH"

# These are required to pass verify_env_vars
export PRIVATE_KEY_FILEPATH=$(mktemp -p '' $(basename $(realpath "$SCRIPT_PATH/../"))_XXXX)
export PRIVATE_PASSPHRASE_FILEPATH=$(mktemp -p '' $(basename $(realpath "$SCRIPT_PATH/../"))_XXXX)
trap "rm -vf $PRIVATE_KEY_FILEPATH $PRIVATE_PASSPHRASE_FILEPATH" EXIT
# Nothing special here, mearly material for a passphrase
echo "$(basename $PRIVATE_KEY_FILEPATH)$RANDOM$(basename $PRIVATE_PASSPHRASE_FILEPATH)$RANDOM" | \
    base64 -w0 | tr -d -c '[:alnum:]' > $PRIVATE_PASSPHRASE_FILEPATH
cp "$PRIVATE_PASSPHRASE_FILEPATH" "$PRIVATE_KEY_FILEPATH"

msg "Running verification checks"
verify_env_vars

go_ephemeral

msg "Generating quick-key (low-security) for experimental use."
# Adds an encr and signing subkeys by default
gpg_cmd --quick-generate-key 'Funky Tea Oolong <foo@bar.baz>' default default never
gpg_status_error_die
GPG_KEY_ID=$(print_cached_key)
set_default_keyid "$GPG_KEY_ID"

# These are not added by default
for usage in sign auth; do
    msg "Generating '$usage' subkey"
    gpg_cmd --quick-add-key "$GPG_KEY_ID" default $usage
    gpg_status_error_die
done

msg "Enabling GPG signatures in git (Config file is $GNUPGHOME/gitconfig)"
configure_git_gpg

msg "Importing github public key and adding to keyring."
trust_github

msg "Entering shell within ephemeral environment, all library variables/functions are available for use."
msg "Notes:
    * Dummy public and private keys have been generated with the ID
      '$GPG_KEY_ID'.
    * Git has been pre-configured to use the dummy key without entering any passwords.
    * Reference the private-key passphrase as either \$_KEY_PASSPHRASE'
      or '$_KEY_PASSPHRASE'.
    * All normal shell commands can be used, in addition to all functions from
      '$EPHEMERAL_GPG_LIB'.
    * Enable additional debugging output at any time with 'export DEBUG=1'.
    * Both \$HOME and \$PWD are now an ephemeral/temporary directory which will be removed upon leaving the shell.
"

# Setup to run inside a debugging "shell", where it's environment mimics the ephemeral environment
cd $GNUPGHOME
cp -a /etc/skel/.??* $GNUPGHOME/  # $HOME will be set here, make sure we overwrite any git/gpg settings
rm -f $GNUPGHOME/.bash_logout  # don't clear screen on exit

# In a debugging use-case only, un-unset $_KEY_PASSPHRASE inside ephemeral_env (we're using a dummy key anyway)
ephemeral_env env _KEY_PASSPHRASE="$_KEY_PASSPHRASE" /bin/bash --login --norc -i
cd - &> /dev/null
dbg "Removing ephemeral environment"
