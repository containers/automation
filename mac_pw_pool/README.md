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

## Manual maintenance

As Mac instances are provisioned onto dedicated hosts, they utilize an
AWS EC2 "Launch Template" to define the system's configuration.  Importantly
this Launch Template defines the AMI (Amazon Machine Image) booted by the
system.  These AMIs are maintained and updated by Amazon, and so periodically
(suggest 3-6 months) the Launch Template should be updated to utilize the
latest AMI.

While it's technically possible to automate these updates, unfortunately,
it's not simple/easy.  Worse, since the `LaunchInstances.sh` always uses
the "latest" template version, testing the changes isn't currently possible.
That said, the steps for updating the AMI are fairly simple and mostly
low-risk (i.e. rollbacks are possible):

1. In the AWS EC2 console, click "Launch Templates".
1. Select the "CirrusMacM1PWinstance" template.
1. Scroll to "Application and OS Images".  Copy the current AMI name
   (includes a date stamp) and ID for use in the final steps.
1. Click "Browse more AMIs" button.
1. On the left, select the "64-bit (Mac-Arm)" filter.
1. Use google to look up the latest OS Release name (e.x. "Sonoma").
1. Under the latest entry in the filtered AMI list, select the
   "64-bit (Mac-Arm)" radio-button on the left, beneath the "Select" button.
1. Click the "Select" button.
1. Copy the new AMI name and ID.
1. Near the top of the Launch Template form, under "Launch template name
   and version description", fill in the "Template Version Description"
   field with the old and new AMI name for future reference.  For example:
   `Update from amzn-ec2-macos-14.1-20231110-071234-arm64 to amzn-ec2-macos-14.4.1-20240411-223504-arm64`.  This will make the version-history clear to
   future operators as well as simplify the choice in case a roll-back is required.
1. On the right-hand-side, click "Create template version" button.  The new
   template will automatically be utilized the next time `LaunchInstances.sh`
   creates a new instance (i.e. complete rollout will take at least 24-hours).
