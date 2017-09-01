#!/usr/bin/env ruby

require 'bundler/setup'
require 'datadog/statsd'

class TemperatureList
  def initialize
    @devices = {}
  end

  def device(name)
    return @devices[name] ||= Device.new(name)
  end

  def devices
    return @devices.values
  end

  def datadog_stats
    return devices.map(&:datadog_stats).flatten(1)
  end
end

class Device
  attr_reader :name
  attr_accessor :adapter

  def initialize(name)
    @name = name
    @subdevices = {}
  end

  def subdevice(index)
    return @subdevices[index] ||= Subdevice.new(index)
  end

  def subdevices
    return @subdevices.values
  end

  def datadog_stats
    return subdevices.map { |sub| sub.datadog_stats(self) }.flatten(1)
  end
end

class Subdevice
  attr_reader :index
  attr_accessor :label

  def initialize(index)
    @index = index
    @readings = {}
  end

  def add_reading(type, value)
    @readings[type] = value
  end

  def datadog_stats(device)
    return @readings.map do |type, value|
      {
        key: "sensors.#{type}",
        value: value,
        tags: {
          dev: device.name,
          path: [device.name, index].join('/'),
          index: @index,
          label: @label,
          is_cpu: !!(@label =~ /^core \d+$/i),
        }
      }
    end
  end

  def temperature
    return @readings.fetch('input').to_s + "C"
  rescue KeyError
    return "unknown"
  end
end

def get_temperature_list
  temps = TemperatureList.new

  IO.popen(['sensors', '-u']) do |fh|
    device = nil
    next_subdevice_label = nil
    fh.each_line do |line|
      line.chomp!

      if line.empty?
        # ignore separators between sections
      elsif line =~ /Adapter: /
        device.adapter = $'
      elsif line =~ /:$/
        next_subdevice_label = $`
      elsif line =~ /^[a-z0-9-]+$/
        device = temps.device(line)
      elsif line =~ /^\s+temp(\d+)_([a-z_]+): ([0-9\.]+)$/
        index = $1.to_i
        type = $2
        reading = $3.to_f

        subdevice = device.subdevice(index)
        if next_subdevice_label
          subdevice.label = next_subdevice_label
          next_subdevice_label = nil
        end
        subdevice.add_reading(type, reading)
      else
        raise "Unexpected line: #{line.inspect}"
      end
    end
  end

  return temps
end

def tags_to_datadog(hash)
  array = hash.map do |key, value|
    [key.to_s.gsub('_', '-'), value].join(':')
  end
end

temps = get_temperature_list
stats = temps.datadog_stats

datadog = Datadog::Statsd.new
datadog.batch do
  stats.each do |stat|
    datadog.gauge(stat[:key], stat[:value], tags: tags_to_datadog(stat[:tags]))
  end
end

temps.devices.each do |device|
  device.subdevices.each do |subdevice|
    puts "#{device.adapter} #{subdevice.label}: #{subdevice.temperature}"
  end
end
