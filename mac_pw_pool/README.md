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
1-1/2 hours, but instances come up in ~10-20m, ready to run tasks.

Either hosts and/or instances may be removed from management by
setting "false" or removing their `PWPoolReady=true` tag.  Otherwise,
the pool should be maintained by installing the crontab lines
indicated in the `Cron.sh` script.

Cirrus-CI will assign tasks (specially) targeted at the pool, to an
instance with a running listener.  If there are none, the task will
queue forever (there might be a 24-hour timeout, I can't remember).
From a PR perspective, there is zero control over which instance you
get.  It could easily be one somebody's previous task barfed all over
and ruined.

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

1. Using the AWS EC2 WebUI, allocate one or more dedicated hosts.
   - Make sure there are no white space characters in the name.
   - Set instance family to `mac2`
   - Set instance type to `mac2.metal`
   - Choose an Availability zone, `us-east-1a` preferred but it's not critical.
   - Turn off `Instance auto-placement`, `Host recovery` and `Host maintenance`.
   - Set the tags: `automation==false`, `PWPoolReady==true`, and
     `purpose==<name>_testing` where `<name>` is your name.
1. Temporarily edit `pw_lib.sh` (DO NOT PUSH THIS CHANGE) to update the
   `DH_REQ_VAL` value to `<name>_testing`, same as you set in step 1.
1. Obtain the current worker pool token by clicking the "show"
   button on [the status
   page](https://cirrus-ci.com/pool/1cf8c7f7d7db0b56aecd89759721d2e710778c523a8c91c7c3aaee5b15b48d05).
   You must be logged in with a github account having admin access
   to view this page.
1. Make sure you have locally met all requirements spelled out in the
   header-comment of `LaunchInstances.sh` and `SetupInstances.sh`.
   Importantly, make sure the shared ssh key has been added to the
   currently running agent.
1. Repeatedly execute `LaunchInstances.sh`. It will update `dh_status.txt`
   with any warnings/errors.  When all new Mac instance(s) are successfully
   allocated, it will show lines includeing the host name,
   an ID, and a datetime stamp.
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

## Security

To thwart attempts to hijack or use instances for nefarious purposes,
each employs three separate self-termination mechanisms.  Two of them
depend on the instance's shutdown behavior being set to `terminate`
(see above).  These mechanisms also ensure the workers remain relatively
"clean" an "fresh" from a "CI-Working" perspective.

Note: Should there be an in-flight CI task on a worker at
shutdown, Cirrus-CI will perform a single automatic re-run on an
available worker.

1. Daily, a Cirrus-cron job runs and kills any instance running longer
   than 3 days.
2. Each instance's startup script runs a background 2-day sleep and
   shutdown command (via MacOS-init consuming instance user-data).
3. A setup script run on each instance starts a pool-listener
   process.
   1. If the worker process dies the instance shuts down.
   2. After 22 hours the instance shuts down if there are no
      cirrus-agent processes (presumably servicing a CI task).
   3. After 24 hours, the instance shuts down regardless of any
      running agents - probably hung/stuck agent process or somebody's
      started a fake agent doing "bad things".
