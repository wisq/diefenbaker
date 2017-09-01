require 'json'
require 'tempfile'
require 'forwardable'

class JsonStore
  def self.open(filename)
    store = new(filename)
    yield store
    store.save
  end

  extend Forwardable
  def_delegators :@store, :[], :[]=, :fetch

  def initialize(filename)
    @filename = filename
    File.open(filename) do |fh|
      @store = JSON.load(fh)
    end
  rescue Errno::ENOENT
    @store = {}
  end

  def save
    Tempfile.open(['store', '.json'], tmpdir=File.dirname(@filename)) do |fh|
      fh.puts @store.to_json
      fh.close
      File.rename(fh.path, @filename)
    end
  end
end
