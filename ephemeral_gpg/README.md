# Overview

This directory contains the necessary pieces to produce a container image
for executing gpg with an ephemeral home-directory and externally supplied
keyfiles.  This is intended to protect the keyfiles and avoid persisting any
runtime daemons/background processes or their temporary files.

It is assumed the reader is familiar with gpg [and it's unattended
usage.](https://www.gnupg.org/documentation//manuals/gnupg/Unattended-Usage-of-GPG.html#Unattended-Usage-of-GPG)
