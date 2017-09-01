#!/usr/bin/env ruby

require 'bundler/setup'

require 'datadog/statsd'
require 'uri'
require 'aws-sdk'
require 'time'

ROOT = File.dirname(File.dirname(__FILE__))
$LOAD_PATH << File.join(ROOT, 'lib')
require 'diefenbaker/capture'
require 'diefenbaker/json_store'

STORE_PATH = File.join(ROOT, 'tmp/wal-e_last_wal.json')

@statsd = Datadog::Statsd.new
@s3 = Aws::S3::Client.new
uri = URI.parse(ENV['WALE_S3_PREFIX'])
@bucket = uri.host
@prefix = uri.path.sub(%r{^/}, '')

class Array
  def sum
    inject(0) { |a, b| a + b }
  end
end

def record_time_size(time, size, dd_type, description)
  delta = Time.now - time
  @statsd.batch do
    @statsd.gauge("wal_e.#{dd_type}.age", delta)
    @statsd.gauge("wal_e.#{dd_type}.size", size)
  end
  bytes = format_size(size)
  puts "Latest #{description}: #{time} (#{delta.to_i}s ago, #{bytes})"
end

SIZE_UNITS = {
  1_000_000_000_000 => 'TB',
  1_000_000_000 => 'GB',
  1_000_000 => 'MB',
  1_000 => 'kB',
}

def format_size(bytes)
  SIZE_UNITS.each do |denom, unit|
    value = bytes.to_f / denom
    if value >= 1.0
      return "%.1f %s" % [value, unit]
    end
  end

  return "#{bytes} bytes"
end

def measure_last_full
  capture_lines('wal-e', 'backup-list', 'LATEST') do |line, line_no|
    if line_no == 1
      backup_id, raw_time, *_ = line.split("\t")
      time = Time.parse(raw_time)
      record_time_size(time, get_base_size(backup_id), 'base', 'base image')
    end
  end

end

def get_base_size(backup_id)
  response = @s3.list_objects_v2(bucket: @bucket, prefix: "#{@prefix}basebackups_", delimiter: "/")
  prefixes = response.common_prefixes.map(&:prefix)

  total = 0
  prefixes.each do |prefix|
    response = @s3.list_objects_v2(bucket: @bucket, prefix: prefix + backup_id)
    total += response.contents.map(&:size).sum
  end
  return total
end

def measure_last_wal
  JsonStore.open(STORE_PATH) do |store|
    response = @s3.list_objects_v2(bucket: @bucket, prefix: "#{@prefix}wal_", start_after: store['start_after'])
    objects = response.contents

    if response.is_truncated
      puts "Cannot measure last WAL: Response truncated.  Repeated runs should fix this."
      store['start_after'] = objects[-1].key
    elsif objects.empty?
      puts "No objects returned from S3!"
    else
      latest = objects[-1]
      record_time_size(latest.last_modified, latest.size, 'wal', 'archived WAL')

      # Start after the second-last item, if there are 2+ items.
      # In general, once we've established a start_after,
      # all requests will be 2 (new WAL) or 1 (no new WAL) objects.
      store['start_after'] = objects[-2].key if objects.length >= 2
    end
  end
end

%w(last_full last_wal).each do |target|
  begin
    send(:"measure_#{target}")
  rescue StandardError => e
    puts "measure_#{target} failed: #{e.inspect}"
    e.backtrace.each { |bt| puts "\t#{bt}" }
  end
end
