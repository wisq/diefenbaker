# Ruby scripts

To run these scripts, you'll need …

* A working copy of Ruby, ideally version 2.3 or higher.
  * Prior 2.x versions _might_ work.
* All required gems, via `bundler`
  * Run `gem install bundler`.
  * Then, run `bundle install --path .bundle/gems --deployment` (in this directory).

Then, run each script using `bundle exec bin/<script>` (while in this directory), plus any arguments.

## Scripts

### cert-expiry.rb

Monitors TLS certificates as presented by various servers (or on disk).

Usage: `cert-expiry.rb <uri1> <uri2> ...`

Each argument is a certificate URI to check:

* `file:///path/to/file` monitors certificate files on disk
* `https://hostname[:port]` monitors certs presented by HTTPS
  * Port optional; defaults to 443.
  * SNI is supported.
* `pg://hostname[:port]` monitors certs presented by Postgres.
  * Port optional; defaults to 5432.

No certificate validation occurs.  Instead, we send stats about **each** certificate to Datadog:

* `tls.cert.created` is the number of seconds since the cert was created.
* `tls.cert.expires` is the number of seconds until the cert expires.
* Tags:
  * `proto` indicates the method used (`file`, `https`, etc.).
  * `common_name` indicates the certificate common name (CN).

After all certificates are checked, one more stat is sent:

* `tls.cert.success_rate` is a percentage figure of the number of certs that we were able to check.
  * Since we do not do certificate validation, only file/network/protocol errors can reduce this below 100%.

### wal-e.rb

Monitors WAL-E Postgres backups.

Usage: `wal-e.rb` (no arguments)

**Requires S3 credentials in environment variables.**  See "S3 scripts" below.

Also requires a `WALE_S3_PREFIX` environment variable, which should be identical to the one you used to set up WAL-E.

Two separate checks are performed:

* **Last full backup:** Executes `wal-e backup-list LATEST` and records data about the latest full backup.
  * Also issues a single S3 request to get the backup size.
* **Last incremental backup:** Executes an S3 directory listing and records data about the last incremental backup (i.e. WAL) it finds.
  * Issues a single S3 request to list incremental backups.

For each check, the following metrics are reported:

* `wal-e.<type>.age` is the age of the backup, in seconds.
* `wal-e.<type>.size` is the size of the backup, in bytes.

**This script may need to be invoked multiple times to find the latest backup.**  See "Partial S3 listings" below.

### redis-backup.rb

Monitors timestamped dumps of our Redis database, stored on Amazon S3.

Usage: `redis-backup.rb s3://<bucket>/<path>`

**Requires S3 credentials in environment variables.**  See "S3 scripts" below.

This is really just a generic S3 directory watcher.  Under the given S3 bucket and path, it expects to find files matching `redis/dump-*`.  These files can have any suffix, so long as the filenames are sorted chronologically.

Each time you run `redis-backup.rb`, it will list matching files on S3, find the most recent file, and record the following stats:

* `redis.backup.age` is the age (in seconds) of the latest backup.
* `redis.backup.size` is the size (in bytes) of the latest backup.

**This script may need to be invoked multiple times to find the latest backup.**  See "Partial S3 listings" below.

### sensors.rb

Reads temperature data from `lm-sensors` (Linux) and passes it to Datadog.

Usage: `sensors.rb` (no arguments)

This takes data from the `sensors -u` command and converts it to Datadog metrics.  All numeric values are sent verbatim.

Generally, this will report at least the following Datadog metrics:

* `sensors.input` is the current value of the sensor.
* `sensors.max` is some sort of defined maximum value.

Certain devices like CPUs may also report the following:

* `sensors.crit` is a critical threshold of some sort.
* `sensors.crit_alarm` is … something?  It's always zero for me.

(Honestly, the only sensor I'm sure about is `sensors.input`.  The rest are undocumented.  I think they come from the `lm-sensors` configuration, not from the sensor itself.)

In each case, the following tags are applied to each metric:

* `dev` is the adapter device name.
  * This is the first line of each `sensors` section.
  * Examples: `coretemp-isa-0000`, `acpitz-virtual-0`.
* `index` is the metric's index within a section, starting from 1.
  * If the `sensors -u` metric is `temp4_max` then the index is 4.
* `path` is just `dev` and `index` separated by a slash.
  * This should uniquely identify each metric.
* `label` is the metric's label.
  * This appears at the top of each metric's section, e.g. `Physical id 0` or `Core 2`.
  * The label is downcased, with spaces replaced by underscores.
* `is_cpu` is `true` if the label matches `Core <number>`, or `false` otherwise.
  * This can be used for easily separating CPU core temperatures into a separate graph.

These metrics are very raw and "as is", and their relevance to your situation will depend heavily on how well `lm-sensors` supports your particular hardware.  Once these metrics are loaded into Datadog, you can use dashboards to make sense of them, and choose what makes sense to monitor.

### ups.rb

Monitors UPS data, using `upsc` from the Network UPS Tools (NUT) project.

Usage: `ups.rb <ups1> <ups2> ...`

Each UPS may be either a bare name (e.g. `myups`) for a local UPS, or `name@IP` for a remote UPS (e.g. `yourups@1.2.3.4`).

All values from `upsc <ups>` will be reported:

* Numbers are reported as gauges.
* Strings are converted to a number:
  * A directory is created under `tags/<metric name>`.
  * Each time a new string value is seen, a file is added to this directory.
  * The filename is the `upsc` string, and the value is the number to report to Datadog.
  * If the number is over 100, we won't report this metric.  This is to avoid excessive tag proliferation in Datadog.
  * Regardless of what value we send, we will also tag the metric with `value:<str>`, where `str` is a sanitised version of the string.
* The `ups.status` field is handled specially:
  * We split the status flags up and report each one.
  * Each will have a value of `1` and a tag of `flag:<flag>`, e.g. `flag:OL` for the "online" (OL) status.

All values are reported as `ups.<name>`.  Values that already begin with `ups.` are reported verbatim.

## S3 scripts

Some of the scripts (`redis-backup.rb` and `wal-e.rb`) work by issuing file listing requests to S3.

These scripts need special environment variables, and may require multiple invocations to begin performing their duty.

### Environment variables

The following environmental variables should be set prior to running these scripts:

* `AWS_REGION` is the AWS region (e.g. `us-east-1`)
* `AWS_ACCESS_KEY_ID` is the AWS access key ID.
* `AWS_SECRET_ACCESS_KEY` is the AWS access key's secret value.

The API key referenced by `AWS_ACCESS_KEY_ID` will need `s3:ListBucket` access to the target S3 bucket(s).

### Partial S3 listings

Only one S3 `list-objects` request is sent per script invocation.  (This is designed to prevent misconfigurations causing excessive S3 API requests.)

If you're running one of these scripts for the first time — or if there's been a lot of dumps since the last time it was successfully run — it may not be able to reach the latest backup in a single S3 request.

In this case, it will cache the last filename it saw, and pick up from there on the next invocation.  After this happens enough times, it will eventually reach the last backup and resume operating normally.
