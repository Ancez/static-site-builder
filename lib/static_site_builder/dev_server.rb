# frozen_string_literal: true

require 'listen'
require 'pathname'
require 'static_site_builder/websocket_server'

begin
  require 'webrick'
rescue LoadError
  # webrick may not be available in all environments
end

module StaticSiteBuilder
  # Development server with file watching and live reload
  #
  # Watches for file changes using the listen gem, rebuilds the site automatically,
  # and provides live reload via WebSocket server.
  class DevServer
    def initialize(root: Dir.pwd, port: nil, ws_port: nil)
      @root = Pathname.new(root)
      @port = port || ENV['PORT']&.to_i || DEFAULT_PORT
      @ws_port = ws_port || ENV['WS_PORT']&.to_i || DEFAULT_WS_PORT
      @dist_dir = @root.join('dist')
      @reload_file = @root.join('.reload')
      @listener = nil
      @ws_server = nil
      @http_server = nil
      @running = false
    end

    # Start the development server
    #
    # Builds the site initially, starts file watcher, WebSocket server, and HTTP server
    def start
      puts 'Building site...'
      build_site

      puts "\nStarting development server..."
      puts "  HTTP server: http://localhost:#{@port}"
      puts "  WebSocket server: ws://localhost:#{@ws_port}"
      puts "  Watching for changes... (Ctrl+C to stop)\n"

      start_websocket_server
      start_file_watcher
      start_http_server
    end

    # Stop the development server
    def stop
      @running = false
      @listener&.stop
      @ws_server&.stop
      @http_server&.shutdown if @http_server
      puts "\nShutting down..."
    end

    private

    def build_site
      ENV['LIVE_RELOAD'] = 'true'
      ENV['WS_PORT'] = @ws_port.to_s
      
      begin
        require 'rake'
        Rake::Task['build:html'].invoke
      rescue LoadError, RuntimeError
        # If Rakefile not loaded or task not found, build directly
        require 'static_site_builder'
        builder = Builder.new(root: @root.to_s)
        builder.build
      end
    end

    def start_websocket_server
      @ws_server = WebSocketServer.new(port: @ws_port, reload_file: @reload_file)
      @ws_server.start
    end

    def start_file_watcher
      @running = true
      watched_dirs = ['app', 'config'].select { |dir| @root.join(dir).exist? }
      return if watched_dirs.empty?

      @listener = Listen.to(*watched_dirs.map { |dir| @root.join(dir).to_s }) do |modified, added, removed|
        next if modified.empty? && added.empty? && removed.empty?

        files_changed = (modified + added + removed).select do |file|
          file.end_with?('.erb', '.rb', '.js')
        end

        if files_changed.any?
          puts "\nFiles changed, rebuilding..."
          build_site
          puts 'Rebuild complete'
        end
      end

      @listener.start
    end

    def start_http_server
      unless defined?(WEBrick)
        raise 'webrick gem is required for the development server. Add "gem \'webrick\'" to your Gemfile.'
      end

      @http_server = WEBrick::HTTPServer.new(
        Port: @port,
        DocumentRoot: @dist_dir.to_s,
        BindAddress: '127.0.0.1'
      )

      trap('INT') { stop }
      trap('TERM') { stop }

      @http_server.start
    end
  end
end

