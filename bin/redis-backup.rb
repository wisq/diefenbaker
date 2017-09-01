#!/usr/bin/env ruby

require 'bundler/setup'

require 'datadog/statsd'
require 'uri'
require 'aws-sdk'

ROOT = File.dirname(File.dirname(__FILE__))
$LOAD_PATH << File.join(ROOT, 'lib')
require 'diefenbaker/capture'
require 'diefenbaker/json_store'

STORE_PATH = File.join(ROOT, 'tmp/redis-backup.json')

@statsd = Datadog::Statsd.new

def record_time(time, dd_key, description)
  delta = Time.now - time
  @statsd.gauge(dd_key, delta)
  puts "Latest #{description}: #{time} (#{delta.to_i}s ago)"
end

# Pretty much the same code as wal-e.rb for incrementals.
# If we do this again, it's time to extract it out to a lib.
def measure_last_backup(prefix)
  s3 = Aws::S3::Client.new
  uri = URI.parse(prefix)
  bucket = uri.host
  prefix = "redis/dump-"

  JsonStore.open(STORE_PATH) do |store|
    response = s3.list_objects_v2(bucket: bucket, prefix: prefix, start_after: store['start_after'])
    objects = response.contents

    if response.is_truncated
      puts "Cannot measure last Redis backup: Response truncated.  Repeated runs should fix this."
      store['start_after'] = objects[-1].key
    elsif objects.empty?
      puts "No objects returned from S3!"
    else
      latest = objects[-1]
      record_time(latest.last_modified, 'redis.backup.age', 'Redis backup')
      @statsd.gauge('redis.backup.size', latest.size)

      # Start after the second-last item, if there are 2+ items.
      # In general, once we've established a start_after,
      # all requests will be 2 (new backup) or 1 (no new backup) objects.
      store['start_after'] = objects[-2].key if objects.length >= 2
    end
  end
end

measure_last_backup(*ARGV)
