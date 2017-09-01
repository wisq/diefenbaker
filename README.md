# diefenbaker

A set of scripts for monitoring various server subsystems using Datadog.

## What do these do?

### Ruby scripts

* `cert-expiry.rb`: Monitors TLS certificates as presented by various servers (or on disk).
* `redis-backup.rb`: Monitors timestamped dumps of a Redis database, stored on Amazon S3.
* `sensors.rb`: Reads temperature data from [`lm-sensors`](https://en.wikipedia.org/wiki/Lm_sensors) and passes it to Datadog.
* `ups.rb`: Monitors UPS data, using `upsc` from the [Network UPS Tools (NUT)](http://networkupstools.org/) project.
* `wal-e.rb`: Monitors [WAL-E](https://github.com/wal-e/wal-e) Postgres backups.

See [docs/RUBY.md](docs/RUBY.md) for more complete info.

## How do I use them?

All of these scripts are meant to be run over and over on a regular basis.  This could be done via `cron`, but I prefer to set them up as a `runit` service with a `sleep` inbetween.

See [docs/RUNIT.md](docs/RUNIT.md) for an example setup.

## Legal stuff

Copyright © 2016-2017, Adrian Irving-Beer.

These scripts are released under the [Apache 2 License](LICENSE) and are provided with **no warranty**.  They're mainly read-only and they shouldn't break anything — but regardless, you use them at your own risk.
