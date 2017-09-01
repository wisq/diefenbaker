require 'tempfile'

class CommandFailed < StandardError; end

def capture_lines(*command)
  Tempfile.open('stderr') do |stderr_fh|
    IO.popen(command, err: stderr_fh) do |fh|
      fh.each_line.with_index do |line, index|
        yield line, index
      end
    end
    unless $?.success?
      puts "*** Command FAILED: #{command.inspect}"
      stderr_fh.seek(0)
      stderr_fh.each_line do |line|
        puts "ERR #{line}"
      end
      raise CommandFailed
    end
  end
end
