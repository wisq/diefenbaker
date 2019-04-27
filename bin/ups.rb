#!/usr/bin/env ruby

require 'bundler/setup'
require 'datadog/statsd'
require 'pathname'
require 'set'

INTERESTING = Set.new [
  'ups.status',
  'ups.load',
  'ups.battery.charge',
  'ups.battery.runtime',
  'ups.input.voltage',
  'ups.input.voltage.nominal',
  'ups.output.voltage',
]

def get_ups_data(ups)
  data = {}
  IO.popen(['upsc', ups]) do |fh|
    fh.each_line do |line|
      key, str = line.chomp.split(': ', 2)

      key = "ups.#{key}" unless key.start_with?("ups.")
      next unless INTERESTING.member?(key)

      value = nil
      if key == 'ups.status'
        value = str.split(' ')
      elsif str == '0'
        value = 0
      elsif str =~ /\A[1-9-][0-9]*\z/
        value = str.to_i
      elsif str =~ /\A[0-9]+\.[0-9]+\z/
        value = str.to_f
      elsif str == 'enabled'
        value = true
      elsif str == 'disabled' || str == 'muted'
        value = false
      else
        value = str
      end

      data[key] = value
    end
  end

  return data
end

def record_ups_data(statsd, ups, data)
  ups_name = ups.split('@', 2).first

  data.each do |key, value|
    tags = ["ups:#{ups_name}"]

    if key == 'ups.status'
      value.each do |flag|
        statsd.gauge(key, 1, tags: tags + ["flag:#{flag}"])
      end
      next
    end

    if value.kind_of?(Numeric)
      # send it raw
    elsif value == true
      value = 1
    elsif value == false
      value = 0
    elsif value.kind_of?(String)
      next
    else
      raise "Unknown type: #{value.inspect} (#{value.class})"
    end

    statsd.gauge(key, value, tags: tags)
  end
end

ups_data = ARGV.map do |ups|
  data = get_ups_data(ups)
  puts "Got #{data.count} values for #{ups}."
  data['upsmon.count'] = data.count
  [ups, data]
end.to_h

#statsd = Datadog::Statsd.new
Datadog::Statsd.new.batch do |statsd|
  ups_data.each do |ups, data|
    record_ups_data(statsd, ups, data)
  end
end
