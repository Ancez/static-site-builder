# frozen_string_literal: true

require "socket"
require "base64"  # Required for Ruby 3.4+ (removed from default gems)
require "digest/sha1"
require "pathname"

module StaticSiteBuilder
  # WebSocket server for live reload functionality during development.
  #
  # Watches for rebuild notifications via a reload file and broadcasts reload
  # messages to connected browser clients, enabling automatic page refresh.
  class WebSocketServer
    # Sleep intervals for thread operations (in seconds)
    ACCEPT_RETRY_INTERVAL = 0.1  # Retry delay when accepting connections fails
    WATCH_POLL_INTERVAL = 0.3     # How often to check for rebuild notifications
    CLIENT_KEEPALIVE_INTERVAL = 1 # Keep-alive check interval for client connections

    # Initializes a new WebSocket server instance.
    #
    # @param port [Integer] Port number for the WebSocket server (default: 3001)
    # @param reload_file [Pathname, nil] Path to the reload notification file. If nil, defaults to .reload in current directory.
    def initialize(port: StaticSiteBuilder::DEFAULT_WS_PORT, reload_file: nil)
      @port = port
      @reload_file = reload_file || Pathname.new(Dir.pwd).join(".reload")
      @clients = []
      @running = false
    end

    # Starts the WebSocket server and begins watching for rebuild notifications.
    #
    # Spawns two background threads: one for accepting client connections and
    # one for watching the reload file for changes. Returns immediately after
    # starting the threads.
    #
    # @return [void]
    def start
      @running = true
      @server = TCPServer.new("127.0.0.1", @port)

      # Initialize reload file if it doesn't exist
      File.write(@reload_file, Time.current.to_f.to_s) unless @reload_file.exist?
      @last_mtime = @reload_file.mtime

      # Accept client connections in background thread
      @accept_thread = Thread.new do
        while @running
          begin
            client = @server.accept
            Thread.new { handle_client(client) }
          rescue IOError, Errno::EBADF, Errno::ECONNABORTED
            # Connection errors are expected during shutdown or network issues
            # Retry accepting connections unless server is stopping
            sleep ACCEPT_RETRY_INTERVAL
            break unless @running
          end
        end
      end

      # Watch for rebuild notifications in background thread
      @watch_thread = Thread.new do
        while @running
          begin
            sleep WATCH_POLL_INTERVAL
            if @reload_file.exist? && @reload_file.mtime > @last_mtime
              @last_mtime = @reload_file.mtime
              broadcast("reload")
            end
          rescue Errno::ENOENT, Errno::EACCES, SystemCallError
            # File system errors during watch are non-fatal
            # Continue watching unless server is stopping
            sleep WATCH_POLL_INTERVAL
            break unless @running
          end
        end
      end
    end

    # Stops the WebSocket server gracefully.
    #
    # Closes all client connections, stops accepting new connections, stops
    # watching for rebuilds, and closes the server socket.
    #
    # @return [void]
    def stop
      @running = false
      @clients.each { |client| safe_close(client) }
      safe_close(@server) if @server
      safe_kill_thread(@accept_thread)
      safe_kill_thread(@watch_thread)
    end

    private

    # Safely closes a socket or connection, ignoring common connection errors.
    #
    # Used to handle cases where connections may already be closed or reset,
    # preventing exceptions during cleanup.
    #
    # @param io [IO] The IO object to close
    def safe_close(io)
      return if io.nil? || io.closed?

      io.close
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::EBADF
      # Connection already closed or reset - this is expected during shutdown
    end

    # Safely terminates a thread, ignoring errors if the thread is already dead.
    #
    # @param thread [Thread, nil] The thread to kill
    def safe_kill_thread(thread)
      return unless thread&.alive?

      thread.kill
    rescue ThreadError
      # Thread already dead - this is expected during shutdown
    end

    # Handles a new client connection, performing WebSocket handshake.
    #
    # Reads the HTTP upgrade request, validates it's a WebSocket request, performs
    # the handshake, and keeps the connection alive for receiving reload messages.
    #
    # @param client [TCPSocket] The client socket connection
    def handle_client(client)
      begin
        # Read HTTP upgrade request headers
        request = client.gets
        headers = {}
        while (line = client.gets.chomp) != ""
          key, value = line.split(": ", 2)
          headers[key] = value if key && value
        end

        if headers["Upgrade"]&.downcase == "websocket"
          # Perform WebSocket handshake
          key = headers["Sec-WebSocket-Key"]
          accept = Base64.strict_encode64(Digest::SHA1.digest(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

          client.print "HTTP/1.1 101 Switching Protocols\r\n"
          client.print "Upgrade: websocket\r\n"
          client.print "Connection: Upgrade\r\n"
          client.print "Sec-WebSocket-Accept: #{accept}\r\n\r\n"

          @clients << client

          # Keep connection alive, waiting for reload messages
          loop do
            sleep CLIENT_KEEPALIVE_INTERVAL
            break unless @running
            break if client.closed?
          end
        else
          # Not a WebSocket request - close connection
          client.close
        end
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
        # Client connection errors are expected (e.g., browser tab closed)
        # Clean up and continue accepting other connections
        @clients.delete(client)
        safe_close(client)
      end
    end

    # Broadcasts a reload message to all connected clients.
    #
    # @param message [String] The message to broadcast (typically "reload")
    def broadcast(message)
      frame = create_frame(message)
      @clients.dup.each do |client|
        begin
          client.write(frame) unless client.closed?
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
          # Broadcast errors are expected when clients disconnect
          # Remove failed client and continue broadcasting to others
          @clients.delete(client)
        end
      end
    end

    # Creates a WebSocket frame for the given message.
    #
    # Implements WebSocket frame encoding according to RFC 6455, supporting
    # messages up to 2^32 bytes in length.
    #
    # @param message [String] The message to encode
    # @return [String] Binary WebSocket frame data
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
