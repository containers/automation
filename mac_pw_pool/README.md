# Cirrus-CI persistent worker maintenance

These scripts are intended to be used from a repository clone,
by cron, on an always-on cloud machine.  They make a lot of
other assumptions, some of which may not be well documented.
Please see the comments at the top of each scripts for more
detailed/specific information.

## Prerequisites

* The `aws` binary present somewhere on `$PATH`.
* Standard AWS `credentials` and `config` files exist under `~/.aws`
  and set the region to `us-east-1`.
* A copy of the ssh-key referenced by `CirrusMacM1PWinstance` launch template
  under "Assumptions" below.
* The ssh-key has been added to a running ssh-agent.
* The running ssh-agent sh-compatible env. vars. are stored in
  `/run/user/$UID/ssh-agent.env`
* The env. var. `POOLTOKEN` is set to the Cirrus-CI persistent worker pool
  token value.

## Assumptions

* You've read all scripts in this directory, generally follow
  their purpose, and meet any requirements stated within the
  header comment.
* You've read the [private documentation](https://docs.google.com/document/d/1PX6UyqDDq8S72Ko9qe_K3zoV2XZNRQjGxPiWEkFmQQ4/edit)
  and understand the safety/security section.
* You have permissions to access all referenced AWS resources.
* There are one or more dedicated hosts allocated and have set:
  * A name tag like `MacM1-<some number>` (NO SPACES!)
  * The `mac2` instance family
  * The `mac2.metal` instance type
  * Disabled "Instance auto-placement", "Host recovery", and "Host maintenance"
  * Quantity: 1
  * Tags: `automation=false`, `purpose=prod`, and `PWPoolReady=true`
* The EC2 `CirrusMacM1PWinstance` instance-template exists and sets:
  * Shutdown-behavior: terminate
  * Same "key pair" referenced under `Prerequisites`
  * All other required instance parameters complete
  * A user-data script that shuts down the instance after 2 days.

## Operation (Theory)

The goal is to maintain sufficient alive/running/working instances
to service most Cirrus-CI tasks pointing at the pool.  This is
best achieved with slower maintenance of hosts compared to setup
of ready instances.  This is because hosts can be inaccessible for
up to 2 hours, but instances come up in ~10-20m, ready to run tasks.

Either hosts and/or instances may be removed from management by
setting "false" or removing their `PWPoolReady=true` tag.  Otherwise,
the pool should be maintained by installing the crontab lines
indicated in the `Cron.sh` script.

Cirrus-CI will assign tasks (specially) targeted at the pool, to an
instance with a running listener (`cirrus worker run` process).  If
there are none, the task will queue forever (there might be a 24-hour
timeout, I can't remember). From a PR perspective, there is little
control over which instance you get.  It could easily be one where
a previous task barfed all over and rendered unusable.

## Initialization

It is assumed that neither the `Cron.sh` nor any related maintenance
scripts are installed (in crontab) or currently running.

Once several dedicated hosts have been manually created, they
should initially have no instances on them.  If left alone, the
maintenance scripts will eventually bring them all up, however
complete creation and setup will take many hours.  This may be
bypassed by *manually* running `LaunchInstances.sh --force`.

In order to prevent all the instances from being recycled at the same
(future) time, the shutdown time installed by `SetupInstances.sh` also
needs to be adjusted.  The operator should first wait about 20 minutes
for all new instances to fully boot.  Followed by a call to
`SetupInstances.sh --force`.

Now the `Cron.sh` cron-job may be installed, enabled and started.

## Manual Testing

Verifying changes to these scripts / cron-job must be done manually.
To support this, every dedicated host and instance has a `purpose`
tag, which must correspond to the value indicated in `pw_lib.sh`
and in the target repo `.cirrus.yml`.  To test script and/or
CI changes:

1. Make sure you have locally met all requirements spelled out in the
   header-comment of `AllocateTestDH.sh`.
1. Execute `AllocateTestDH.sh`.  It will operate out of a temporary
   clone of the repository to prevent pushing required test-modifications
   upstream.
1. Repeatedly execute `SetupInstances.sh`. It will update `pw_status.txt`
   with any warnings/errors.  When successful, lines will include
   the host name, "complete", and "alive" status strings.
1. If instance debugging is needed, the `InstanceSSH.sh` script may be
   used.  Simply pass the name of the host you want to access.  Every
   instance should have a `setup.log` file in the `ec2-user` homedir.  There
   should also be `/private/tmp/<name>-worker.log` with entries from the
   pool listener process.
1. To test CI changes against the test instance(s), push a PR that includes
   `.cirrus.yml` changes to the task's `persistent_worker` dictionary's
   `purpose` attribute.  Set the value the same as the tag in step 1.
1. When you're done with all testing, terminate the instance.  Then wait
   a full 24-hours before "releasing" the dedicated host.  Both operations
   can be performed using the AWS EC2 WebUI.  Please remember to do the
   release step, as the $-clock continues to run while it's allocated.

Note: Instances are set to auto-terminate on shutdown.  They should
self shutdown after 24-hours automatically.  After termination for
any cause, there's about a 2-hour waiting period before a new instance
can be allocated. The `LaunchInstances.sh` script is able deal with this
properly.


## Script Debugging Hints

* On each MacOS instance:
  * The pool listener process (running as the worker user) keeps a log under `/private/tmp`.  The
    file includes the registered name of the worker.  For example, on MacM1-7 you would find `/private/tmp/MacM1-7-worker.log`.
    This log shows tasks taken on, completed, and any errors reported back from Cirrus-CI internals.
  * In the ec2-user's home directory is a `setup.log` file.  This stores the output from executing
    `setup.sh`.  It also contains any warnings/errors from the (very important) `service_pool.sh` script - which should
    _always_ be running in the background.
  * There are several drop-files in the `ec2-user` home directory which are checked by `SetupInstances.sh`
    to record state.  If removed, along with `setup.log`, the script will re-execute (a possibly newer version of) `setup.sh`.
* On the management host:
  * Automated operations are setup and run by `Cron.sh`, and logged to `Cron.log`.  When running scripts manually, `Cron.sh`
    can serve as a template for the intended order of operations.
  * Critical operations are protected by a mandatory, exclusive file lock on `mac_pw_pool/Cron.sh`.  Should
    there be a deadlock, management of the pool (by `Cron.sh`) will stop.  However the effects of this will not be observed
    until workers begin hitting their lifetime and/or task limits.
  * Without intervention, the `nightly_maintenance.sh` script will update the containers/automation repo clone on the
    management VM.  This happens if the repo becomes out of sync by more than 7 days (or as defined in the script).
    When the repo is updated, the `pw_pool_web` container will be restarted.  The container will also be restarted if its
    found to not be running.
