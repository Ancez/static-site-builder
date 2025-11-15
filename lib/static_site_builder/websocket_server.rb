# frozen_string_literal: true

require "socket"
require "base64"
require "digest/sha1"
require "pathname"

module StaticSiteBuilder
  # Simple WebSocket server for live reload
  class WebSocketServer
    def initialize(port: 3001, reload_file: nil)
      @port = port
      @reload_file = reload_file || Pathname.new(Dir.pwd).join(".reload")
      @clients = []
      @running = false
    end

    def start
      @running = true
      @server = TCPServer.new("127.0.0.1", @port)

      # Initialize reload file
      File.write(@reload_file, Time.now.to_f.to_s) unless @reload_file.exist?
      @last_mtime = @reload_file.mtime

      # Accept connections in background
      @accept_thread = Thread.new do
        while @running
          begin
            client = @server.accept
            Thread.new { handle_client(client) }
          rescue => e
            sleep 0.1
            break unless @running
          end
        end
      end

      # Watch for rebuilds
      @watch_thread = Thread.new do
        while @running
          begin
            sleep 0.3
            if @reload_file.exist? && @reload_file.mtime > @last_mtime
              @last_mtime = @reload_file.mtime
              broadcast("reload")
            end
          rescue => e
            sleep 0.3
            break unless @running
          end
        end
      end
    end

    def stop
      @running = false
      @clients.each { |c| c.close rescue nil }
      @server.close rescue nil
      @accept_thread.kill rescue nil
      @watch_thread.kill rescue nil
    end

    private

    def handle_client(client)
      begin
        # Read handshake
        request = client.gets
        headers = {}
        while (line = client.gets.chomp) != ""
          key, value = line.split(": ", 2)
          headers[key] = value if key && value
        end

        if headers["Upgrade"]&.downcase == "websocket"
          key = headers["Sec-WebSocket-Key"]
          accept = Base64.strict_encode64(Digest::SHA1.digest(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

          client.print "HTTP/1.1 101 Switching Protocols\r\n"
          client.print "Upgrade: websocket\r\n"
          client.print "Connection: Upgrade\r\n"
          client.print "Sec-WebSocket-Accept: #{accept}\r\n\r\n"

          @clients << client

          # Keep connection alive - just wait
          loop do
            sleep 1
            break unless @running
            break if client.closed?
          end
        else
          client.close
        end
      rescue => e
        @clients.delete(client)
        client.close rescue nil
      end
    end

    def broadcast(message)
      frame = create_frame(message)
      @clients.dup.each do |client|
        begin
          client.write(frame) unless client.closed?
        rescue => e
          @clients.delete(client)
        end
      end
    end

    def create_frame(message)
      data = message.dup.force_encoding("BINARY")
      length = data.bytesize

      if length < 126
        [0x81, length].pack("C*") + data
      elsif length < 65536
        [0x81, 126, length].pack("CCn") + data
      else
        [0x81, 127, length >> 32, length & 0xFFFFFFFF].pack("CCNN") + data
      end
    end
  end
end
