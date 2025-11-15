# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"
require "pathname"
require "digest"

begin
  require "importmap-rails"
rescue LoadError
  # importmap-rails is optional
end

module StaticSiteBuilder
  class Builder
    def initialize(root: Dir.pwd, template_engine: "erb", js_bundler: "importmap", importmap_config: nil, annotate_template_file_names: nil)
      @root = Pathname.new(root)
      @template_engine = template_engine
      @js_bundler = js_bundler
      @importmap_config_path = if importmap_config
        Pathname.new(importmap_config)
      else
        @root.join("config", "importmap.rb")
      end

      # Auto-enable annotations in development (when LIVE_RELOAD is enabled)
      @annotate_template_file_names = if annotate_template_file_names.nil?
        ENV["LIVE_RELOAD"] == "true" || ENV["RAILS_ENV"] == "development"
      else
        annotate_template_file_names
      end

      @importmap = if defined?(Importmap::Map)
        Importmap::Map.new
      else
        SimpleImportMap.new(root: @root)
      end

      load_importmap_config if @js_bundler == "importmap"
    end

    # Build the static site
    #
    # Compiles all templates, copies assets, generates importmap (if needed),
    # and outputs everything to the dist/ directory.
    #
    # @return [void]
    def build
      puts "Building static site..."

      # Clean dist directory
      dist_dir = @root.join("dist")
      FileUtils.rm_rf(dist_dir) if dist_dir.exist?
      FileUtils.mkdir_p(dist_dir)

      # Copy assets
      copy_assets(dist_dir)

      # Generate importmap JSON if using importmap
      generate_importmap(dist_dir) if @js_bundler == "importmap"

      # Compile pages based on template engine
      case @template_engine
      when "erb"
        compile_erb_pages(dist_dir)
      when "phlex"
        compile_phlex_pages(dist_dir)
      end

      # Copy static files
      copy_static_files(dist_dir)

      # Notify WebSocket server (always update, even if file doesn't exist yet)
      reload_file = @root.join(".reload")
      File.write(reload_file, Time.now.to_f.to_s)

      puts "\n✓ Build complete! Output in #{dist_dir}"
    end

    private

    def load_importmap_config
      return unless @importmap_config_path.exist?

      config_content = File.read(@importmap_config_path)
      # Replace relative paths with absolute paths
      config_content = config_content.gsub(/"app\//, %("#{@root.join("app").to_s}/))
      config_content = config_content.gsub(/"vendor\//, %("#{@root.join("vendor").to_s}/))

      # Replace File.expand_path calls with actual paths
      config_content = config_content.gsub(/File\.expand_path\(["'](.*?)["'], __dir__\)/) do |match|
        path = $1
        @root.join("config", path).expand_path.to_s.inspect
      end

      @importmap.instance_eval(config_content, @importmap_config_path.to_s)
    end

    def copy_assets(dist_dir)
      puts "Copying assets..."

      # Copy JavaScript files
      js_dir = @root.join("app", "javascript")
      if js_dir.exist? && js_dir.directory?
        dist_js = dist_dir.join("assets", "javascripts")
        FileUtils.mkdir_p(dist_js)
        # Copy all files and subdirectories from js_dir to dist_js
        Dir.glob(js_dir.join("*")).each do |item|
          FileUtils.cp_r(item, dist_js, preserve: true)
        end
      end

      # Validate and copy vendor JavaScript files
      if @js_bundler == "importmap"
        validate_vendor_files
      end

      vendor_js = @root.join("vendor", "javascript")
      if vendor_js.exist? && vendor_js.directory?
        dist_js = dist_dir.join("assets", "javascripts")
        FileUtils.mkdir_p(dist_js)
        Dir.glob(vendor_js.join("*.js")).each do |item|
          FileUtils.cp(item, dist_js.join(File.basename(item)), preserve: true)
        end
      end

      # Copy CSS
      css_dir = @root.join("app", "assets", "stylesheets")
      if css_dir.exist? && css_dir.directory?
        dist_css = dist_dir.join("assets", "stylesheets")
        FileUtils.mkdir_p(dist_css)
        Dir.glob(css_dir.join("*")).each do |item|
          FileUtils.cp_r(item, dist_css, preserve: true)
        end
      end
    end

    def validate_vendor_files
      return unless @importmap_config_path && @importmap_config_path.exist?

      config_content = File.read(@importmap_config_path.to_s)
      vendor_js = @root.join("vendor", "javascript")
      missing_files = []

      # Extract vendor file references from importmap config
      # Look for patterns like: pin "@hotwired/stimulus", to: "stimulus.min.js"
      config_content.scan(/pin\s+["']([^"']+)["'],\s*to:\s*["']([^"']+)["']/) do |package_name, file_name|
        vendor_file = vendor_js.join(file_name)
        unless vendor_file.exist?
          missing_files << { package: package_name, file: file_name, path: vendor_file }
        end
      end

      unless missing_files.empty?
        puts "\n❌ Error: Missing required vendor JavaScript files:"
        missing_files.each do |missing|
          puts "   - #{missing[:file]} (required by #{missing[:package]})"
          puts "     Expected at: #{missing[:path]}"
        end
        puts "\nTo fix this:"
        puts "   1. Run 'npm install' to install dependencies"
        puts "   2. Copy the required files from node_modules to vendor/javascript/"
        puts "   Example:"
        missing_files.each do |missing|
          if missing[:package].include?("@hotwired/stimulus")
            puts "      cp node_modules/@hotwired/stimulus/dist/stimulus.js vendor/javascript/#{missing[:file]}"
          end
        end
        puts "\nNote: Vendor files should be committed to your repository."
        raise "Missing required vendor JavaScript files"
      end
    end

    def generate_importmap(dist_dir)
      return unless defined?(@importmap) && @importmap

      puts "Generating importmap..."

      # Create a simple resolver for asset paths
      resolver = AssetResolver.new(@root, dist_dir)

      importmap_json = @importmap.to_json(resolver: resolver)

      FileUtils.mkdir_p(dist_dir.join("assets"))
      File.write(dist_dir.join("assets", "importmap.json"), JSON.pretty_generate(JSON.parse(importmap_json)))
    end

    def compile_erb_pages(dist_dir)
      pages_dir = @root.join("app", "views", "pages")
      return unless pages_dir.exist?

      # Generate importmap JSON once for all pages
      resolver = AssetResolver.new(@root, dist_dir)
      importmap_json_str = @importmap.to_json(resolver: resolver) if defined?(@importmap) && @importmap

      # Find all ERB files, including nested directories
      Dir.glob(pages_dir.join("**", "*.html.erb")).each do |erb_file|
        relative_path = Pathname.new(erb_file).relative_path_from(pages_dir)
        page_name = relative_path.to_s.gsub(/\.html\.erb$/, ".html")

        compile_erb_page(erb_file, page_name, dist_dir, importmap_json_str)
      end
    end

    def compile_erb_page(erb_file, page_name, dist_dir, importmap_json_str)
      puts "Compiling #{page_name}..."

      # Read and parse frontmatter
      content = File.read(erb_file)
      frontmatter = {}
      layout = "application"
      js_modules = []

      if content.match?(/^---\s*\n/)
        match = content.match(/^---\s*\n(.*?)\n---\s*\n/m)
        if match
          frontmatter_text = match[1]
          frontmatter_text.each_line do |line|
            key, value = line.split(":", 2).map(&:strip)
            case key
            when "layout"
              layout = value
            when "js"
              js_modules = value.split(",").map(&:strip)
            else
              frontmatter[key] = value
            end
          end
          content = content.sub(/^---\s*\n.*?\n---\s*\n/m, "")
        end
      end

      # Load layout - try .html.erb first, then .html
      layout_file = @root.join("app", "views", "layouts", "#{layout}.html.erb")
      layout_file = @root.join("app", "views", "layouts", "#{layout}.html") unless layout_file.exist?
      layout_content = layout_file.exist? ? File.read(layout_file) : default_layout

      # Inject live reload script if enabled and using custom layout
      if ENV["LIVE_RELOAD"] == "true" && layout_file.exist?
        # Inject live reload into custom layouts too
        unless layout_content.include?("live reload") || layout_content.include?("LIVE_RELOAD")
          ws_port = ENV["WS_PORT"] || 3001
          live_reload_script = <<~HTML
            <script>
              (function() {
                function connect() {
                  var ws = new WebSocket('ws://localhost:#{ws_port}');
                  ws.onmessage = function(e) {
                    if (e.data === 'reload') window.location.reload();
                  };
                  ws.onclose = function() { setTimeout(connect, 1000); };
                  ws.onerror = function() {};
                }
                connect();
              })();
            </script>
          HTML
          layout_content = layout_content.gsub(/<\/body>/, "#{live_reload_script}</body>")
        end
      end

      # Create binding with variables for ERB
      page_binding = binding
      page_binding.local_variable_set(:frontmatter, frontmatter)
      page_binding.local_variable_set(:js_modules, js_modules)
      page_binding.local_variable_set(:importmap_json, importmap_json_str) if importmap_json_str

      # Render ERB content
      page_content = ERB.new(content).result(page_binding)

      # Annotate page content if enabled
      if @annotate_template_file_names
        relative_template_path = Pathname.new(erb_file).relative_path_from(@root)
        page_content = annotate_template(page_content, relative_template_path.to_s)
      end

      page_binding.local_variable_set(:page_content, page_content)

      # Render layout with page content
      layout_erb = ERB.new(layout_content)
      rendered = layout_erb.result(page_binding)

      # Annotate layout if enabled
      if @annotate_template_file_names && layout_file.exist?
        relative_layout_path = Pathname.new(layout_file).relative_path_from(@root)
        rendered = annotate_template(rendered, relative_layout_path.to_s)
      end

      output_path = dist_dir.join(page_name)
      FileUtils.mkdir_p(output_path.dirname)
      File.write(output_path, rendered)

      puts "  ✓ Created #{page_name}"
    end

    def compile_phlex_pages(dist_dir)
      # Phlex compilation will be implemented when phlex-rails is available
      pages_dir = @root.join("app", "views", "pages")
      return unless pages_dir.exist?

      puts "Phlex compilation not yet implemented"
      # TODO: Implement Phlex page compilation
    end

    def copy_static_files(dist_dir)
      public_dir = @root.join("public")
      return unless public_dir.exist? && public_dir.directory?

      puts "Copying public files..."
      # Copy all files and subdirectories from public to dist
      Dir.glob(public_dir.join("*")).each do |item|
        FileUtils.cp_r(item, dist_dir, preserve: true)
      end
    end

    def annotate_template(content, template_path)
      # Remove any existing annotations to avoid duplicates
      content = content.gsub(/<!-- BEGIN .*? -->\n?/, "")
      content = content.gsub(/\n?<!-- END .*? -->/, "")

      begin_comment = "<!-- BEGIN #{template_path} -->"
      end_comment = "<!-- END #{template_path} -->"

      # Wrap content with template path annotations
      "#{begin_comment}\n#{content}\n#{end_comment}"
    end

    def default_layout
      live_reload_script = if ENV["LIVE_RELOAD"] == "true"
        ws_port = ENV["WS_PORT"] || 3001
        <<~HTML
          <script>
            (function() {
              function connect() {
                var ws = new WebSocket('ws://localhost:#{ws_port}');
                ws.onmessage = function(e) {
                  if (e.data === 'reload') window.location.reload();
                };
                ws.onclose = function() { setTimeout(connect, 1000); };
                ws.onerror = function() {};
              }
              connect();
            })();
          </script>
        HTML
      else
        ""
      end

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title><%= frontmatter['title'] || 'Site' %></title>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <%= page_content %>
          <% if defined?(importmap_json) && importmap_json %>
            <script type="importmap"><%= importmap_json %></script>
          <% end %>
          <% if js_modules && !js_modules.empty? %>
            <% js_modules.each do |module_name| %>
              <script type="module">import "<%= module_name %>";</script>
            <% end %>
          <% else %>
            <script type="module">import "application";</script>
          <% end %>
          #{live_reload_script}
        </body>
        </html>
      HTML
    end

    # Simple asset resolver for importmap
    class AssetResolver
      def initialize(root, dist_dir)
        @root = root
        @dist_dir = dist_dir
      end

      def javascript_path(path)
        "/assets/javascripts/#{path}"
      end

      def asset_path(path)
        "/assets/#{path}"
      end
    end

    # Simple importmap implementation if importmap-rails is not available
    class SimpleImportMap
      def initialize(root: nil)
        @pins = {}
        @root = root || Pathname.new(Dir.pwd)
      end

      def pin(name, to: nil, preload: true)
        # If 'to' is provided, use it as-is. Otherwise, default to name.js
        to_path = to || "#{name}.js"
        @pins[name] = { to: to_path, preload: preload }
      end

      def pin_all_from(directory, under: nil)
        dir_path = Pathname.new(directory)
        # Resolve to absolute path
        full_dir_path = dir_path.absolute? ? dir_path : @root.join(dir_path)
        return unless full_dir_path.exist?

        # Calculate base path from app/javascript for proper resolution
        app_js_path = @root.join("app", "javascript")

        Dir.glob(full_dir_path.join("**", "*.js")).each do |file|
          relative_path = Pathname.new(file).relative_path_from(full_dir_path)
          name = relative_path.to_s.gsub(/\.js$/, "")
          name = name.gsub(/_controller$/, "")
          # If under is specified, prepend it to the name
          name = under ? "#{under}/#{name}" : name
          # Store full path from app/javascript, preserving directory structure
          to_path = Pathname.new(file).relative_path_from(app_js_path).to_s
          pin(name, to: to_path, preload: true)
        end
      end

      def to_json(resolver:)
        imports = {}
        @pins.each do |name, config|
          path = resolver.javascript_path(config[:to])
          imports[name] = path
        end

        JSON.generate({ imports: imports })
      end
    end
  end
end
