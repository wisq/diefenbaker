#!/usr/bin/env ruby

require 'uri'
require 'socket'
require 'openssl'
require 'datadog/statsd'

class SocketCert
  def default_host
    return '127.0.0.1'
  end

  def name
    return 'raw TLS'
  end

  def initialize(uri)
    @host = uri.host || default_host
    @port = uri.port || default_port
  end

  def starttls(socket)
    # nothing by default, but child classes may need this
  end

  def get
    puts "Getting #{name} cert from #{@host.inspect}, port #{@port} ..."
    socket = TCPSocket.open(@host, @port)
    starttls(socket)

    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket)
    ssl_socket.hostname = @host
    ssl_socket.connect
    return ssl_socket.peer_cert
  ensure
    ssl_socket.close if ssl_socket
    socket.close if socket
  end

  def tags
    return {
      connect_host: @host,
      connect_port: @port,
    }
  end
end

class HttpsCert < SocketCert
  def default_port
    return 443
  end
  def name
    return "HTTPS"
  end
end

class PostgresCert < SocketCert
  def default_port
    return 5432
  end
  def name
    return "Postgres"
  end

  # Based on https://github.com/openssl/openssl/pull/683/files
  SSL_REQUEST = [
    0, 0, 0, 8,     # length of request
    4, 210, 22, 47, # request payload
  ].pack('C8')

  def starttls(socket)
    socket.write(SSL_REQUEST)
    raise "Server does not support SSL" unless socket.getc == 'S'
  end
end

class FileCert
  def initialize(uri)
    @path = uri.path
  end

  def get
    puts "Reading certificate from #{@path.inspect} ..."
    raw = File.read(@path)
    return OpenSSL::X509::Certificate.new(raw)
  end

  def tags
    return {disk_path: @path}
  end
end

class CertChecker
  GETTER_TYPES = {
    'pg' => PostgresCert,
    'https' => HttpsCert,
    'file' => FileCert,
  }

  def initialize
    @statsd = Datadog::Statsd.new
  end

  def check(text)
    uri = URI.parse(text)
    getter = GETTER_TYPES.fetch(uri.scheme).new(uri)
    cert = getter.get

    common_name = get_common_name(cert)
    puts "Got cert for #{common_name.inspect}."

    created = cert.not_before
    create_delta = Time.now - created
    puts "Cert created at #{created} (#{create_delta.round}s ago)."

    expires = cert.not_after
    expire_delta = expires - Time.now
    puts "Cert expires at #{expires} (in #{expire_delta.round}s)."

    tags_hash = {
      proto: uri.scheme,
      common_name: common_name,
    }.merge(getter.tags)
    tags = tags_to_datadog(tags_hash)

    @statsd.batch do
      @statsd.gauge('tls.cert.created', create_delta, tags: tags)
      @statsd.gauge('tls.cert.expires', expire_delta, tags: tags)
    end
  end

  def get_common_name(cert)
    cert.subject.to_a.each do |elem|
      if elem[0] == 'CN'
        return elem[1]
      end
    end
  end

  def tags_to_datadog(hash)
    array = hash.map do |key, value|
      [key.to_s.gsub('_', '-'), value].join(':')
    end
  end

  def record_success_rate(success, total)
    success_rate = 100.0 * success.to_f / total.to_f
    @statsd.gauge('tls.cert.success_rate', success_rate)
  end
end

checker = CertChecker.new
success = total = 0
ARGV.each do |arg|
  begin
    checker.check(arg)
    success += 1
  rescue StandardError => e
    puts "Failed to retrieve cert: #{e.message} (#{e.class})"
  end
  total += 1
end

puts "Done: #{success} out of #{total} certs checked."
checker.record_success_rate(success, total)
exit(1) unless success == total
