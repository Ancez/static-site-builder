# frozen_string_literal: true

require "fileutils"
require "pathname"
require "erb"
require "json"

module StaticSiteBuilder
  # Generates new static site projects.
  #
  # Creates a complete project structure including Gemfile, build
  # configuration files, example pages, and development server setup.
  #
  # @example Generate a site
  #   generator = StaticSiteBuilder::Generator.new("my-site")
  #   generator.generate
  class Generator

    # Reference StaticSiteBuilder constants for consistency
    DEFAULT_PORT = StaticSiteBuilder::DEFAULT_PORT
    DEFAULT_WS_PORT = StaticSiteBuilder::DEFAULT_WS_PORT

    # Initializes a new generator instance.
    #
    # @param app_name [String] The name of the site to generate (will be used as directory name)
    def initialize(app_name, options = {})
      @app_name = app_name
      @app_path = Pathname.new(app_name)
      @options = {}
    end

    # Generates the complete static site project.
    #
    # Creates the directory structure, configuration files, example pages, build
    # scripts, and all necessary dependencies. Provides next steps after successful generation.
    #
    # @return [void]
    def generate
      puts "Generating static site: #{@app_name}"

      create_directory_structure
      create_gemfile
      create_config_files
      create_app_structure
      create_build_files
      create_sitemap_config
      create_example_pages
      create_readme
      create_gitignore

      puts "\n✓ Site generated successfully!"
      puts "\nNext steps:"
      puts "  cd #{@app_name}"
      puts "  bundle install"
      puts "  bundle exec rake dev:server    # Start development server with live reload"
      puts "  # or"
      puts "  bundle exec rake build:all     # Build for deployment"
    end

    private

    def create_directory_structure
      dirs = [
        "app/views/layouts",
        "app/views/pages",
        "app/helpers",
        "app/javascript",
        "app/assets/stylesheets",
        "config",
        "lib",
        "public"
      ]

      dirs.each do |dir|
        FileUtils.mkdir_p(@app_path.join(dir))
      end
    end

    def create_gemfile
      gems = [
        'rake',
        'actionview',
        'base64', # Required for Ruby 3.4+ (removed from default gems)
        'webrick', # Required for dev server (removed from stdlib in Ruby 3.0+)
        'sitemap_generator' # For generating sitemaps from actual pages
      ]

      content = <<~RUBY
        # frozen_string_literal: true

        source 'https://rubygems.org'

        #{gems.map { |g| %(gem '#{g}') }.join("\n")}
      RUBY

      write_file('Gemfile', content)
    end


    def create_config_files
    end


    def create_sitemap_config
      content = <<~RUBY
        # frozen_string_literal: true

        require 'sitemap_generator'
        require 'pathname'

        # Configure sitemap generator
        # Update default_host to your actual domain
        SitemapGenerator::Sitemap.default_host = 'https://example.com'
        SitemapGenerator::Sitemap.sitemaps_path = 'sitemaps'
        SitemapGenerator::Sitemap.public_path = 'dist'

        # Generate sitemap from templates in app/views (excluding layouts and partials)
        SitemapGenerator::Sitemap.create do
          views_dir = Pathname.new('app/views')
          if views_dir.exist?
            Dir.glob(views_dir.join('**', '*.html.erb')).each do |erb_file|
              relative_path = Pathname.new(erb_file).relative_path_from(views_dir)
              file_name = Pathname.new(erb_file).basename.to_s

              if file_name.start_with?('_') == false && relative_path.to_s.start_with?('layouts/') == false
                page_name = relative_path.to_s.gsub(/\.html\.erb$/, '')

                # Convert page name to URL path
                # Handle index pages: 'index' -> '/', 'blog/index' -> '/blog/'
                path = if page_name == 'index'
                  '/'
                elsif page_name.end_with?('/index')
                  "/\#{page_name[0..-7]}/"
                else
                  "/\#{page_name}"
                end

                add path, lastmod: File.mtime(erb_file), changefreq: 'weekly', priority: 0.5
              end
            end
          end
        end
      RUBY

      write_file('config/sitemap.rb', content)
    end




    def create_app_structure
      create_layout
      create_javascript_entry
      create_css_entry
    end

    def create_layout
      create_erb_layout
    end

    def create_erb_layout
      content = <<~ERB
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <main>
            <%= yield %>
          </main>

          <% if content_for?(:javascript) %>
            <%= yield(:javascript) %>
          <% end %>

          <% if ENV['LIVE_RELOAD'] == 'true' %>
            <script>
              (function() {
                function connect() {
                  var port = '<%= ENV['WS_PORT'] || #{DEFAULT_WS_PORT} %>';
                  var ws = new WebSocket('ws://localhost:' + port);
                  ws.onmessage = function(e) {
                    if (e.data === 'reload') window.location.reload();
                  };
                  ws.onclose = function() { setTimeout(connect, 500); };
                  ws.onerror = function() {};
                }
                connect();
              })();
            </script>
          <% end %>
        </body>
        </html>
      ERB

      write_file('app/views/layouts/application.html.erb', content)
    end

    def create_javascript_entry
      content = <<~JS
        // Your JavaScript code here
        console.log("Application loaded")
      JS

      write_file('app/javascript/application.js', content)
    end

    def create_css_entry
      write_file('app/assets/stylesheets/application.css', <<~CSS)
        /* Your custom CSS here */
        body {
          font-family: system-ui, sans-serif;
        }
      CSS
    end

    def create_build_files
      create_rakefile
      create_site_builder
    end

    def create_rakefile 
      content = <<~RUBY
        # frozen_string_literal: true
        # encoding: utf-8

        # Set default external encoding to UTF-8
        Encoding.default_external = Encoding::UTF_8

        require_relative 'lib/site_builder'
        require 'fileutils'
        require 'pathname'
        require 'json'

        namespace :build do
          desc 'Build everything (assets + HTML + CSS + sitemap)'
          task :all do
            Rake::Task['build:clean'].invoke
            Rake::Task['build:assets'].invoke
            Rake::Task['build:html'].invoke
            Rake::Task['build:css'].invoke
            Rake::Task['build:sitemap'].invoke

            puts "\\n✓ Build complete!"
          end

          desc 'Build JavaScript assets'
          task :assets do
            package_json_path = Pathname.new(Dir.pwd).join('package.json')
            if package_json_path.exist?
              package_json = JSON.parse(File.read(package_json_path))
              build_script = package_json.dig('scripts', 'build')

              if build_script && !build_script.include?('build:css') && build_script != "echo 'No JS bundling needed'"
                sh 'npm run build'
              end
            else
              js_dir = Pathname.new(Dir.pwd).join('app', 'javascript')
              if js_dir.exist?
                dist_js = Pathname.new(Dir.pwd).join('dist', 'assets', 'javascripts')
                FileUtils.mkdir_p(dist_js)
                Dir.glob(js_dir.join('**', '*')).each do |item|
                  if File.file?(item)
                    dest = dist_js.join(Pathname.new(item).relative_path_from(js_dir))
                    FileUtils.mkdir_p(dest.dirname)
                    FileUtils.cp(item, dest)
                  end
                end
              end
            end
          end

          desc 'Compile all pages to static HTML'
          task :html => [:assets] do
            builder = SiteBuilder::Builder.new(root: Dir.pwd)
            builder.build
          end

          desc 'Build CSS (runs after HTML so dist directory exists)'
          task :css do
            package_json_path = Pathname.new(Dir.pwd).join('package.json')
            dist_css = Pathname.new(Dir.pwd).join('dist', 'assets', 'stylesheets')

            if package_json_path.exist?
              package_json = JSON.parse(File.read(package_json_path))
              if package_json.dig('scripts', 'build:css')
                sh 'npm run build:css'
              end
            elsif File.exist?('tailwind.config.js')
              if system('which tailwindcss > /dev/null 2>&1')
                FileUtils.mkdir_p(dist_css)
                sh 'tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --minify'
              end
            else
              css_dir = Pathname.new(Dir.pwd).join('app', 'assets', 'stylesheets')
              if css_dir.exist?
                FileUtils.mkdir_p(dist_css)
                Dir.glob(css_dir.join('**', '*')).each do |item|
                  if File.file?(item)
                    dest = dist_css.join(Pathname.new(item).relative_path_from(css_dir))
                    FileUtils.mkdir_p(dest.dirname)
                    FileUtils.cp(item, dest)
                  end
                end
              end
            end
          end

          desc 'Clean dist directory'
          task :clean do
            dist_dir = Pathname.new(Dir.pwd).join('dist')
            FileUtils.rm_rf(dist_dir) if dist_dir.exist?
            puts "Cleaned \#{dist_dir}"
          end

          desc 'Generate sitemap from actual pages'
          task :sitemap do
            require './config/sitemap'
          end
        end

        namespace :dev do
          desc 'Start development server with auto-rebuild and live reload'
          task :server do
            require 'webrick'

            port = ENV['PORT'] || #{DEFAULT_PORT}
            ws_port = ENV['WS_PORT'] || #{DEFAULT_WS_PORT}
            dist_dir = Pathname.new(Dir.pwd).join('dist')
            reload_file = Pathname.new(Dir.pwd).join('.reload')

            ws_server = SiteBuilder::WebSocketServer.new(port: ws_port.to_i, reload_file: reload_file)
            ws_server.start

            ENV['LIVE_RELOAD'] = 'true'
            ENV['WS_PORT'] = ws_port.to_s

            Rake::Task['build:html'].invoke
            Rake::Task['build:css'].invoke

            puts "\\n🚀 Starting development server at http://localhost:\#{port}"
            puts "📡 WebSocket server at ws://localhost:\#{ws_port}"
            puts "📝 Watching for changes... (Ctrl+C to stop)"
            puts "🔄 Live reload enabled - pages will auto-refresh on changes\\n"

            watcher_code = %q{
              watched = ['app', 'config']
              exts = ['.erb', '.rb', '.js', '.css']
              mtimes = {}
              last_build = Time.now

              loop do
                changed = false

                watched.each do |dir|
                  Dir.glob(File.join(dir, '**', '*')).each do |f|
                    if File.file?(f) && exts.any? { |e| f.end_with?(e) }
                      mtime = File.mtime(f)
                      if mtimes[f] != mtime
                        mtimes[f] = mtime
                        changed = true
                      end
                    end
                  end
                end

                if changed && (Time.now - last_build) > 1
                  system('rake build:html > /dev/null 2>&1 && rake build:css > /dev/null 2>&1')
                  last_build = Time.now
                end

                sleep 0.5
              end
            }

            watcher_pid = spawn('ruby', '-e', watcher_code, err: File::NULL, out: File::NULL)

            server = WEBrick::HTTPServer.new(
              Port: port,
              BindAddress: '127.0.0.1'
            )

            server.mount('/assets', WEBrick::HTTPServlet::FileHandler, File.join(dist_dir.to_s, 'assets'))
            server.mount('/images', WEBrick::HTTPServlet::FileHandler, File.join(dist_dir.to_s, 'images'))

            server.mount_proc('/') do |req, res|
              path = req.path

              if path == '/'
                index_path = File.join(dist_dir.to_s, 'index.html')
                if File.exist?(index_path)
                  res.status = 200
                  res['Content-Type'] = 'text/html'
                  res.body = File.read(index_path)
                else
                  res.status = 404
                  res['Content-Type'] = 'text/plain'
                  res.body = "Not Found\\n"
                end
              else
                clean_path = path.start_with?('/') ? path[1..] : path
                served = false

                if !path.include?('.') && !path.end_with?('/')
                  html_path = File.join(dist_dir.to_s, "\#{clean_path}.html")
                  if File.exist?(html_path)
                    res.status = 200
                    res['Content-Type'] = 'text/html'
                    res.body = File.read(html_path)
                    served = true
                  end
                end

                if served == false
                  file_path = File.join(dist_dir.to_s, clean_path)

                  if File.directory?(file_path)
                    nested_index = File.join(file_path, 'index.html')
                    if File.exist?(nested_index)
                      res.status = 200
                      res['Content-Type'] = 'text/html'
                      res.body = File.read(nested_index)
                      served = true
                    end
                  elsif File.exist?(file_path) && File.file?(file_path)
                    res.status = 200
                    res['Content-Type'] = WEBrick::HTTPUtils.mime_type(file_path, WEBrick::HTTPUtils::DefaultMimeTypes)
                    res.body = File.read(file_path)
                    served = true
                  end
                end

                if served == false
                  res.status = 404
                  res['Content-Type'] = 'text/plain'
                  res.body = "Not Found\\n"
                end
              end
            end

            trap('INT') do
              puts "\\n\\nShutting down..."
              Process.kill('TERM', watcher_pid) if watcher_pid
              ws_server.stop
              server.shutdown
            end

            server.start
          end
        end

        task default: 'build:all'
      RUBY

      write_file('Rakefile', content)
    end



    def create_site_builder
      content = <<~RUBY
        # frozen_string_literal: true

        require 'action_view'
        require 'action_view/helpers'
        require 'fileutils'
        require 'pathname'
        require 'socket'
        require 'base64'
        require 'digest/sha1'
        require 'json'

        module SiteBuilder
          DIST_DIR = 'dist'
          DEFAULT_PORT = 3000
          DEFAULT_WS_PORT = 3001

          class Builder
            def initialize(root: Dir.pwd)
              @root = Pathname.new(root)
              @dist_dir = @root.join(DIST_DIR)
              @views_dir = @root.join('app', 'views')
            end

            def build
              copy_javascript
              copy_stylesheets
              compile_views
              copy_public
              write_reload_file
            end

            private

            def compile_views
              FileUtils.mkdir_p(@dist_dir)

              if @views_dir.exist?
                view = build_action_view
                layout_virtual = 'layouts/application'

                Dir.glob(@views_dir.join('**', '*.html.erb')).each do |erb_file|
                  relative = Pathname.new(erb_file).relative_path_from(@views_dir).to_s
                  file_name = Pathname.new(erb_file).basename.to_s

                  is_partial = file_name.start_with?('_')
                  is_layout = relative.start_with?('layouts/')

                  if is_partial == false && is_layout == false
                    virtual_path = relative.gsub(/\.html\.erb$/, '')
                    output_rel = relative.gsub(/\.html\.erb$/, '.html')
                    output_path = @dist_dir.join(output_rel)

                    rendered = view.render(template: virtual_path, layout: layout_virtual)

                    FileUtils.mkdir_p(output_path.dirname)
                    File.write(output_path, rendered)
                  end
                end
              end
            end

            def build_action_view
              view_paths = ActionView::PathSet.new([@views_dir.to_s])
              lookup_context = ActionView::LookupContext.new(view_paths)
              view_class = ActionView::Base.with_empty_template_cache

              load_and_include_helpers(view_class)

              view = view_class.new(lookup_context, {}, nil)
              view
            end

            def load_and_include_helpers(view_class)
              helpers_dir = @root.join('app', 'helpers')
              if helpers_dir.exist? && helpers_dir.directory?
                Dir.glob(helpers_dir.join('**', '*_helper.rb')).each do |helper_file|
                  load helper_file

                  relative = Pathname.new(helper_file).relative_path_from(helpers_dir).to_s
                  module_name = helper_module_name(relative)

                  if Object.const_defined?(module_name)
                    view_class.include(Object.const_get(module_name))
                  end
                end
              end
            end

            def helper_module_name(relative_path)
              without_ext = relative_path.gsub(/\.rb$/, '')
              parts = without_ext.split('/')
              parts.map { |p| camelize(p) }.join('::')
            end

            def camelize(value)
              value.split('_').map { |part| part[0] ? part[0].upcase + part[1..] : '' }.join
            end

            def copy_javascript
              package_json_path = @root.join('package.json')
              should_copy = true

              if package_json_path.exist?
                begin
                  package_json = JSON.parse(File.read(package_json_path))
                  should_copy = package_json.dig('scripts', 'build').nil?
                rescue JSON::ParserError
                  should_copy = true
                end
              end

              if should_copy
                js_dir = @root.join('app', 'javascript')
                if js_dir.exist? && js_dir.directory?
                  dist_js = @dist_dir.join('assets', 'javascripts')
                  FileUtils.mkdir_p(dist_js)
                  copy_tree_skip_existing(js_dir, dist_js)
                end
              end
            end

            def copy_stylesheets
              package_json_path = @root.join('package.json')
              should_copy = true

              if package_json_path.exist?
                begin
                  package_json = JSON.parse(File.read(package_json_path))
                  should_copy = package_json.dig('scripts', 'build:css').nil?
                rescue JSON::ParserError
                  should_copy = true
                end
              end

              if should_copy
                css_dir = @root.join('app', 'assets', 'stylesheets')
                if css_dir.exist? && css_dir.directory?
                  dist_css = @dist_dir.join('assets', 'stylesheets')
                  FileUtils.mkdir_p(dist_css)
                  copy_tree_skip_existing(css_dir, dist_css)
                end
              end
            end

            def copy_public
              public_dir = @root.join('public')
              if public_dir.exist? && public_dir.directory?
                Dir.glob(public_dir.join('**', '*')).each do |item|
                  if File.file?(item)
                    dest = @dist_dir.join(Pathname.new(item).relative_path_from(public_dir))
                    FileUtils.mkdir_p(dest.dirname)
                    FileUtils.cp(item, dest)
                  end
                end
              end
            end

            def write_reload_file
              reload_file = @root.join('.reload')
              File.write(reload_file, Time.now.to_f.to_s)
            end

            def copy_tree_skip_existing(source_dir, dest_dir)
              Dir.glob(source_dir.join('**', '*')).each do |item|
                if File.file?(item)
                  relative = Pathname.new(item).relative_path_from(source_dir)
                  dest = dest_dir.join(relative)

                  if dest.exist? == false
                    FileUtils.mkdir_p(dest.dirname)
                    FileUtils.cp(item, dest)
                  end
                end
              end
            end
          end

          class WebSocketServer
            ACCEPT_RETRY_INTERVAL = 0.1
            WATCH_POLL_INTERVAL = 0.3
            CLIENT_KEEPALIVE_INTERVAL = 1

            def initialize(port: DEFAULT_WS_PORT, reload_file: nil)
              @port = port
              @reload_file = reload_file || Pathname.new(Dir.pwd).join('.reload')
              @clients = []
              @running = false
              @server = nil
            end

            def start
              @running = true
              @server = TCPServer.new('127.0.0.1', @port)

              if @reload_file.exist?
                @last_mtime = @reload_file.mtime
              else
                File.write(@reload_file, Time.now.to_f.to_s)
                @last_mtime = @reload_file.mtime
              end

              @accept_thread = Thread.new do
                while @running
                  begin
                    client = @server.accept
                    Thread.new { handle_client(client) }
                  rescue IOError, Errno::EBADF, Errno::ECONNABORTED
                    sleep ACCEPT_RETRY_INTERVAL
                    if @running == false
                      break
                    end
                  end
                end
              end

              @watch_thread = Thread.new do
                while @running
                  begin
                    sleep WATCH_POLL_INTERVAL
                    if @reload_file.exist? && @reload_file.mtime > @last_mtime
                      @last_mtime = @reload_file.mtime
                      broadcast('reload')
                    end
                  rescue Errno::ENOENT, Errno::EACCES, SystemCallError
                    sleep WATCH_POLL_INTERVAL
                    if @running == false
                      break
                    end
                  end
                end
              end
            end

            def stop
              @running = false

              @clients.each do |client|
                safe_close(client)
              end

              if @server
                safe_close(@server)
              end

              safe_kill_thread(@accept_thread)
              safe_kill_thread(@watch_thread)
            end

            private

            def safe_close(io)
              if io && io.closed? == false
                begin
                  io.close
                rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::EBADF
                end
              end
            end

            def safe_kill_thread(thread)
              if thread && thread.alive?
                begin
                  thread.kill
                rescue ThreadError
                end
              end
            end

            def handle_client(client)
              begin
                _request = client.gets
                headers = {}
                line = nil

                while (line = client.gets)
                  stripped = line.chomp
                  if stripped == ''
                    break
                  end

                  key, value = stripped.split(': ', 2)
                  if key && value
                    headers[key] = value
                  end
                end

                if headers['Upgrade']&.downcase == 'websocket'
                  key = headers['Sec-WebSocket-Key']
                  accept = Base64.strict_encode64(Digest::SHA1.digest(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))

                  client.print "HTTP/1.1 101 Switching Protocols\r\n"
                  client.print "Upgrade: websocket\r\n"
                  client.print "Connection: Upgrade\r\n"
                  client.print "Sec-WebSocket-Accept: \#{accept}\r\n\r\n"

                  @clients << client

                  loop do
                    sleep CLIENT_KEEPALIVE_INTERVAL
                    if @running == false || client.closed?
                      break
                    end
                  end
                else
                  safe_close(client)
                end
              rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
                @clients.delete(client)
                safe_close(client)
              end
            end

            def broadcast(message)
              frame = create_frame(message)
              @clients.dup.each do |client|
                begin
                  if client.closed? == false
                    client.write(frame)
                  end
                rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED
                  @clients.delete(client)
                end
              end
            end

            def create_frame(message)
              data = message.dup.force_encoding('BINARY')
              length = data.bytesize

              if length < 126
                [0x81, length].pack('C*') + data
              elsif length < 65_536
                [0x81, 126, length].pack('CCn') + data
              else
                [0x81, 127, length >> 32, length & 0xFFFFFFFF].pack('CCNN') + data
              end
            end
          end
        end

        # This file provides the build and live reload code for the generated project.
      RUBY

      write_file('lib/site_builder.rb', content)
    end

    def create_example_pages
      create_erb_example
    end

    def create_erb_example
      content = <<~ERB
        <% content_for(:javascript) do %>
          <script src="/assets/javascripts/application.js"></script>
        <% end %>

        <h1>Welcome</h1>
        <p>This is your generated static site.</p>
      ERB

      write_file('app/views/index.html.erb', content)
    end


    def create_readme
      content = <<~MD
        # #{@app_name}

        Generated static site using ERB templates.

        ## Setup

        ```bash
        bundle install
        ```

        ## Development

        Start the development server with auto-rebuild and live reload:

        ```bash
        rake dev:server
        ```

        This will:
        - Build your site to `dist/`
        - Start a web server at `http://localhost:3000`
        - Watch for file changes and rebuild automatically
        - Auto-refresh your browser when files change

        Change the port with: `PORT=8080 rake dev:server`

        ## Build

        Build for deployment:

        ```bash
        rake build:all     # Clean dist and build everything (assets + HTML + CSS + sitemap)
        rake build:html    # Build HTML only (still runs build:assets)
        rake build:css     # Build CSS only
        rake build:sitemap # Build sitemap only
        ```

        Output goes to `dist/` directory.

        ## JavaScript Bundling

        If you add a `package.json` with a `scripts.build`, `rake build:assets` will run `npm run build`.
        If you do not use a bundler, it will copy files from `app/javascript/` into `dist/assets/javascripts/`.

        ## CSS

        If you add a `package.json` with a `scripts.build:css`, `rake build:css` will run `npm run build:css`.
        If you do not use a CSS build step, it will copy files from `app/assets/stylesheets/` into `dist/assets/stylesheets/`.
      MD

      write_file('README.md', content)
    end



    def create_gitignore
      content = <<~GITIGNORE
        # Dependencies
        /.bundle/
        /vendor/bundle
        /node_modules/

        # Build artifacts
        *.gem
        *.gemspec.bak
        /dist/
        /tmp/
        /coverage/

        # Test artifacts
        /.rspec_status

        # IDE
        /.idea/
        /.vscode/
        *.swp
        *.swo
        *~

        # OS
        .DS_Store
        Thumbs.db

        # Logs
        *.log
      GITIGNORE

      write_file(".gitignore", content)
    end

    def write_file(path, content)
      file_path = @app_path.join(path)
      FileUtils.mkdir_p(file_path.dirname)
      File.write(file_path, content)
    end
  end
end
