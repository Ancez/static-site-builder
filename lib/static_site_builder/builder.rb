# frozen_string_literal: true

require "uri"
require "action_view"
require "action_view/helpers"
require "erb"
require "fileutils"
require "json"
require "pathname"
require "digest"
# Require meta-tags gem (handle Railtie gracefully for non-Rails usage)
begin
  require "meta_tags"
rescue NameError => e
  # If Rails::Railtie is not available, require components directly
  if e.message.include?("Railtie")
    require "meta_tags/meta_tags_collection"
    require "meta_tags/view_helper"
  else
    raise
  end
end

begin
  require "importmap-rails"
rescue LoadError
  # importmap-rails is optional
end

module StaticSiteBuilder
  class Builder
    # Default directory for partials when no path separator is provided
    PARTIALS_DIR = "shared"
    # Output directory name
    DIST_DIR = "dist"
    # Default JavaScript entry point
    JS_ENTRY_POINT = "application"
    # Template engine names
    TEMPLATE_ERB = "erb"
    # JavaScript bundler names
    JS_BUNDLER_IMPORTMAP = "importmap"
    # Common vendor file paths to check in node_modules packages
    VENDOR_FILE_PATHS = [
      "dist/%s.js",
      "dist/%s.min.js",
      "dist/index.js",
      "%s.js",
      "index.js",
      "dist/%s",
      "%s"
    ].freeze

    def initialize(root: Dir.pwd, template_engine: TEMPLATE_ERB, js_bundler: JS_BUNDLER_IMPORTMAP, importmap_config: nil, annotate_template_file_names: nil)
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

      load_importmap_config if @js_bundler == JS_BUNDLER_IMPORTMAP
    end

    # Builds the complete static site.
    #
    # Compiles ERB templates to HTML, copies JavaScript and CSS assets, generates
    # importmap configuration (if using importmap), and outputs everything to the
    # dist/ directory. In development mode, files are updated in place to prevent
    # 404 errors during live reload. In production mode, the dist directory is
    # cleaned first for a fresh build.
    #
    # @return [void]
    def build
      puts "Building static site..."

      dist_dir = @root.join(DIST_DIR)
      
      # Clean dist directory only for production/release builds
      # In development, update files in place to prevent 404s during live reload
      production_build = ENV["PRODUCTION"] == "true" || ENV["RELEASE"] == "true"
      if production_build
        if dist_dir.exist?
          puts "Cleaning dist directory for production build..."
          FileUtils.rm_rf(dist_dir)
        end
      end
      
      # Ensure dist directory exists
      FileUtils.mkdir_p(dist_dir)

      # Copy JavaScript and CSS assets to dist
      copy_assets(dist_dir)

      # Generate importmap JSON once if using importmap (reused for both file and templates)
      @importmap_json_str = generate_importmap_json(dist_dir) if @js_bundler == JS_BUNDLER_IMPORTMAP

      # Write importmap JSON file to dist/assets/ if using importmap
      write_importmap_file(dist_dir) if @js_bundler == JS_BUNDLER_IMPORTMAP

      # Compile ERB templates to static HTML pages
      compile_erb_pages(dist_dir) if @template_engine == TEMPLATE_ERB

      # Copy static files from public/ directory to dist
      copy_static_files(dist_dir)

      # Notify WebSocket server of rebuild for live reload
      # Always update the reload file, even if it doesn't exist yet
      reload_file = @root.join(".reload")
      File.write(reload_file, Time.current.to_f.to_s)

      puts "\n✓ Build complete! Output in #{dist_dir}"
    end

    # Helper methods that need to be accessible from closures.
    #
    # These methods are public to allow access from ActionView template closures,
    # but they are considered internal API and should not be called directly.

    # Accesses hash values using either symbol or string keys.
    #
    # Tries each key in order until a non-nil value is found. This allows
    # compatibility with both symbol and string keys in options hashes.
    #
    # @param hash [Hash] The hash to search
    # @param keys [Array<Symbol, String>] Keys to try in order
    # @return [Object, nil] The first non-nil value found, or nil if none found
    def hash_value(hash, *keys)
      keys.each do |key|
        value = hash[key]
        return value if value.present?
      end
      nil
    end

    # Determine current page path from page name
    def determine_current_page_path(page_name)
      if page_name == 'index.html'
        '/'
      else
        "/#{page_name.gsub(/\.html$/, '')}"
      end
    end

    # Load layout content, trying .html.erb first, then .html, or default layout
    def load_layout_content
      layout = StaticSiteBuilder::DEFAULT_LAYOUT_NAME
      layout_file = @root.join('app', 'views', 'layouts', "#{layout}.html.erb")
      layout_file = @root.join('app', 'views', 'layouts', "#{layout}.html") unless layout_file.exist?
      layout_content = layout_file.exist? ? File.read(layout_file) : default_layout

      # Inject live reload script if enabled and using custom layout
      if ENV['LIVE_RELOAD'] == 'true' && layout_file.exist?
        unless layout_content.include?('live reload') || layout_content.include?('LIVE_RELOAD')
          script = live_reload_script
          layout_content = layout_content.gsub(/<\/body>/, "#{script}</body>") unless script.blank?
        end
      end

      [layout_content, layout_file]
    end

    # Setup ActionView context and create view instance
    def setup_action_view_context
      view_paths = ActionView::PathSet.new([@root.join('app', 'views').to_s])
      lookup_context = ActionView::LookupContext.new(view_paths)
      view_class = ActionView::Base.with_empty_template_cache
      view = view_class.new(lookup_context, {}, self)
      # Include MetaTags helper methods
      view.extend(MetaTags::ViewHelper)
      view
    end

    # Set instance variables on the view that will be available in templates
    def setup_view_instance_variables(view, importmap_json_str, current_page_path)
      view.instance_variable_set(:@js_modules, [])
      view.instance_variable_set(:@importmap_json, importmap_json_str) if importmap_json_str
      view.instance_variable_set(:@current_page, current_page_path)
      view.instance_variable_set(:@page_content, nil)
    end

    # Override render method to handle 'footer' -> 'shared/footer' conversion
    def override_view_render_method(view, importmap_json_str, current_page_path)
      builder_self = self
      view.define_singleton_method(:render) do |options = {}, locals = {}, &block|
        begin
          render_options, render_locals = builder_self.resolve_render_options(options, locals, importmap_json_str, current_page_path)
          # Merge locals into options hash for ActionView
          final_options = render_options.merge(locals: render_locals)
          super(final_options, {}, &block)
        rescue ActionView::MissingTemplate => e
          partial_name = builder_self.extract_partial_name(options)
          raise "Partial template not found: '#{partial_name.presence || 'unknown'}'. Searched in: #{e.path}"
        end
      end
    end

    # Extract partial name from options for error messages
    def extract_partial_name(options)
      if options.is_a?(Hash)
        hash_value(options, :partial, 'partial') || 'unknown'
      else
        options.to_s
      end
    end

    # Resolve render options and locals, handling partial path normalization
    def resolve_render_options(options, locals, importmap_json_str, current_page_path)
      if options.is_a?(String) || options.is_a?(Symbol)
        partial_name = normalize_partial_path(options.to_s)
        merged_locals = merge_page_locals(locals, importmap_json_str, current_page_path)
        [{ partial: partial_name }, merged_locals]
      elsif options.is_a?(Hash)
        partial_path = hash_value(options, :partial, 'partial')
        if partial_path
          normalized_path = normalize_partial_path(partial_path.to_s)
          provided_locals = hash_value(options, :locals, 'locals').presence || locals.presence || {}
          merged_locals = merge_page_locals(provided_locals, importmap_json_str, current_page_path)
          # Remove :partial and :locals from options to avoid conflicts
          clean_options = options.reject { |k, _| [:partial, 'partial', :locals, 'locals'].include?(k) }
          [{ partial: normalized_path }.merge(clean_options), merged_locals]
        else
          merged_locals = merge_page_locals(locals, importmap_json_str, current_page_path)
          [options, merged_locals]
        end
      else
        [options, locals]
      end
    end

    # Render page template using ActionView
    def render_page_template(view, content, page_name, importmap_json_str, current_page_path, erb_file)
      page_template = ActionView::Template.new(
        content,
        'inline:page',
        ActionView::Template::Handlers::ERB.new,
        virtual_path: "pages/#{page_name.gsub(/\.html$/, '')}",
        format: :html,
        locals: [:importmap_json, :current_page]
      )

      begin
        page_content = view.render(template: page_template, locals: {
          importmap_json: importmap_json_str,
          current_page: current_page_path
        })
      rescue ActionView::Template::Error => e
        if e.cause.is_a?(ActionView::MissingTemplate)
          raise "Partial template not found. Searched in: #{e.cause.path}"
        end
        raise
      end

      if @annotate_template_file_names
        relative_template_path = Pathname.new(erb_file).relative_path_from(@root)
        page_content = annotate_template(page_content, relative_template_path.to_s)
      end

      page_content
    end

    # Render layout template using ActionView
    def render_layout_template(view, layout_content, layout_file, page_content, importmap_json_str, current_page_path)
      layout = StaticSiteBuilder::DEFAULT_LAYOUT_NAME
      layout_template = ActionView::Template.new(
        layout_content,
        'inline:layout',
        ActionView::Template::Handlers::ERB.new,
        virtual_path: "layouts/#{layout}",
        format: :html,
        locals: [:page_content, :importmap_json, :current_page]
      )

      safe_page_content = page_content.respond_to?(:html_safe) ? page_content.html_safe : page_content
      
      rendered = view.render(template: layout_template, locals: {
        page_content: safe_page_content,
        importmap_json: importmap_json_str,
        current_page: current_page_path
      })

      if @annotate_template_file_names && layout_file.exist?
        relative_layout_path = Pathname.new(layout_file).relative_path_from(@root)
        begin_comment = "<!-- BEGIN #{relative_layout_path} -->"
        end_comment = "<!-- END #{relative_layout_path} -->"
        rendered = "#{begin_comment}\n#{rendered}\n#{end_comment}"
      end

      rendered
    end

    # Write final rendered output to file
    def write_page_output(dist_dir, page_name, rendered)
      output_path = dist_dir.join(page_name)
      FileUtils.mkdir_p(output_path.dirname)
      File.write(output_path, rendered)
    end

    # Load PageHelpers module and set metadata from PageHelpers::PAGES using meta-tags
    # This ensures partials rendered within the page have access to metadata
    def load_page_helpers_and_set_metadata(view, current_page_path)
      # Only require once (first time)
      unless defined?(@page_helpers_loaded)
        begin
          page_helpers_path = @root.join('lib', 'page_helpers.rb')
          if page_helpers_path.exist?
            require page_helpers_path.to_s
            @page_helpers_loaded = true
          end
        rescue LoadError
          # PageHelpers not available, continue without it
        end
      end

      # Extend view with PageHelpers if available
      if defined?(PageHelpers)
        view.extend(PageHelpers) unless view.singleton_class.included_modules.include?(PageHelpers)
      end

      # Set meta tags from PageHelpers::PAGES using meta-tags gem
      begin
        if defined?(PageHelpers) && PageHelpers.const_defined?(:PAGES)
          pages = PageHelpers::PAGES
          if pages.is_a?(Hash) && pages.key?(current_page_path)
            metadata = pages[current_page_path]
            meta_tags_hash = {}
            
            # Map PageHelpers metadata to meta-tags format
            meta_tags_hash[:title] = metadata[:title] if metadata[:title].present?
            meta_tags_hash[:description] = metadata[:description] if metadata[:description].present?
            meta_tags_hash[:canonical] = metadata[:url] if metadata[:url].present?
            
            # Open Graph tags
            if metadata[:image].present? || metadata[:title].present? || metadata[:url].present?
              meta_tags_hash[:og] = {}
              meta_tags_hash[:og][:title] = metadata[:title] if metadata[:title].present?
              meta_tags_hash[:og][:description] = metadata[:description] if metadata[:description].present?
              meta_tags_hash[:og][:url] = metadata[:url] if metadata[:url].present?
              meta_tags_hash[:og][:image] = metadata[:image] if metadata[:image].present?
            end
            
            # Twitter Card tags
            if metadata[:image].present? || metadata[:title].present?
              meta_tags_hash[:twitter] = {}
              meta_tags_hash[:twitter][:card] = 'summary_large_image' if metadata[:image].present?
              meta_tags_hash[:twitter][:title] = metadata[:title] if metadata[:title].present?
              meta_tags_hash[:twitter][:description] = metadata[:description] if metadata[:description].present?
              meta_tags_hash[:twitter][:image] = metadata[:image] if metadata[:image].present?
            end
            
            view.set_meta_tags(meta_tags_hash) if meta_tags_hash.present?
          end
        end
      rescue NameError, TypeError, NoMethodError => e
        # PageHelpers metadata loading failed, continue without it
        # This is non-fatal - pages can still be rendered without metadata
        # Log silently as this is expected in some scenarios
      end
    end

    # Normalize partial path by adding PARTIALS_DIR prefix if no path separator exists
    def normalize_partial_path(partial_name)
      if partial_name.include?('/')
        partial_name
      else
        "#{PARTIALS_DIR}/#{partial_name}"
      end
    end

    # Merge page-level locals (importmap_json, current_page) with provided locals
    def merge_page_locals(locals, importmap_json_str, current_page_path)
      {
        importmap_json: importmap_json_str,
        current_page: current_page_path
      }.merge(locals.is_a?(Hash) ? locals : {})
    end

    # Generate live reload WebSocket script if live reload is enabled
    def live_reload_script
      if ENV["LIVE_RELOAD"] == "true"
        ws_port = ENV["WS_PORT"] || StaticSiteBuilder::DEFAULT_WS_PORT
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
    end

    def load_importmap_config
      return unless @importmap_config_path.exist?

      begin
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
      rescue Errno::ENOENT, Errno::EACCES, SystemCallError => e
        puts "Warning: Could not load importmap config from #{@importmap_config_path}: #{e.message}"
      rescue SyntaxError, StandardError => e
        puts "Error: Invalid importmap config syntax in #{@importmap_config_path}: #{e.message}"
        raise
      end
    end

    def copy_assets(dist_dir)
      puts "Copying assets..."

      # Copy JavaScript files from app/javascript to dist/assets/javascripts
      js_dir = @root.join("app", "javascript")
      if js_dir.exist? && js_dir.directory?
        dist_js = dist_dir.join("assets", "javascripts")
        FileUtils.mkdir_p(dist_js)
        # Copy all files and subdirectories recursively
        Dir.glob(js_dir.join("*")).each do |item|
          FileUtils.cp_r(item, dist_js, preserve: true)
        end
      end

      # Copy vendor JavaScript files from node_modules to dist (for importmap)
      # These are packages like @hotwired/stimulus that are referenced in importmap config
      if @js_bundler == JS_BUNDLER_IMPORTMAP
        copy_vendor_files_from_node_modules(dist_dir)
      end

      # Handle CSS files
      # If Tailwind is configured, it outputs directly to dist, so we only ensure
      # the directory exists. Otherwise, copy CSS files from app/assets/stylesheets.
      tailwind_config = @root.join("tailwind.config.js")
      css_dir = @root.join("app", "assets", "stylesheets")
      dist_css = dist_dir.join("assets", "stylesheets")
      
      if tailwind_config.exist?
        # Tailwind handles CSS compilation - just ensure output directory exists
        FileUtils.mkdir_p(dist_css)
      elsif css_dir.exist? && css_dir.directory?
        # No Tailwind - copy CSS files directly
        FileUtils.mkdir_p(dist_css)
        Dir.glob(css_dir.join("*")).each do |item|
          FileUtils.cp_r(item, dist_css, preserve: true)
        end
      end
    end

    def copy_vendor_files_from_node_modules(dist_dir)
      return unless @importmap_config_path && @importmap_config_path.exist?

      config_content = File.read(@importmap_config_path.to_s)
      dist_js = dist_dir.join("assets", "javascripts")
      FileUtils.mkdir_p(dist_js)

      # Extract vendor file references from importmap config
      # Look for patterns like: pin "@hotwired/stimulus", to: "stimulus.min.js"
      # Only process pins that have 'to:' specified (vendor files), not local app files
      config_content.scan(/pin\s+["']([^"']+)["'],\s*to:\s*["']([^"']+)["']/) do |package_name, file_name|
        # Skip if this is a local app file
        next if file_name.start_with?("app/") || file_name.start_with?("./app/")

        # Only try to copy npm packages (scoped packages like @hotwired/stimulus or known packages)
        # Skip simple names like "application" that are local files
        next unless package_name.include?("/") || package_name.start_with?("@")

        dest_file = dist_js.join(file_name)
        # Always copy/overwrite vendor files to ensure they're up to date

        # Try to copy directly from node_modules to dist
        if copy_vendor_file_from_node_modules(package_name, file_name, dest_file)
          puts "  ✓ Copied #{file_name} from #{package_name}"
        else
          puts "  ⚠️  Warning: Could not find #{file_name} for package #{package_name} in node_modules"
          puts "     Make sure you've run 'npm install' and the package is installed."
        end
      end
    end

    def copy_vendor_file_from_node_modules(package_name, file_name, dest_file)
      node_modules = @root.join("node_modules")
      return false unless node_modules.exist?

      package_dir = node_modules.join(*package_name.split("/"))
      return false unless package_dir.exist?

      source_file = find_vendor_file_in_package(package_dir, file_name)
      if source_file&.exist? && source_file.file?
        FileUtils.cp(source_file, dest_file)
        true
      else
        false
      end
    end

    # Find vendor file in package directory using common path patterns
    def find_vendor_file_in_package(package_dir, file_name)
      base_name = extract_base_name(file_name)
      candidate_paths = generate_vendor_file_paths(base_name, file_name)

      candidate_paths.each do |source_path|
        source_file = package_dir.join(*source_path.split("/"))
        return source_file if source_file.exist? && source_file.file?
      end
      nil
    end

    # Extract base name from file (e.g., "stimulus.min.js" -> "stimulus")
    def extract_base_name(file_name)
      file_name.gsub(/\.(min\.)?js$/, "")
    end

    # Generate candidate paths for vendor file lookup
    def generate_vendor_file_paths(base_name, file_name)
      paths = VENDOR_FILE_PATHS.map do |pattern|
        if pattern.include?("%s")
          pattern % base_name
        else
          pattern
        end
      end
      paths.uniq.concat([file_name])
    end

    def generate_importmap_json(dist_dir)
      return nil unless defined?(@importmap) && @importmap

      puts "Generating importmap..."

      # Create a simple resolver for asset paths
      resolver = AssetResolver.new(@root, dist_dir)

      @importmap.to_json(resolver: resolver)
    end

    def write_importmap_file(dist_dir)
      return unless @importmap_json_str.present?

      FileUtils.mkdir_p(dist_dir.join("assets"))
      parsed_json = JSON.parse(@importmap_json_str)
      File.write(dist_dir.join("assets", "importmap.json"), JSON.pretty_generate(parsed_json))
    end

    def compile_erb_pages(dist_dir)
      pages_dir = @root.join("app", "views", "pages")
      return unless pages_dir.exist?

      # Use pre-generated importmap JSON (generated once in build method)
      importmap_json_str = @importmap_json_str

      # Find all ERB files, including nested directories
      Dir.glob(pages_dir.join("**", "*.html.erb")).each do |erb_file|
        relative_path = Pathname.new(erb_file).relative_path_from(pages_dir)
        page_name = relative_path.to_s.gsub(/\.html\.erb$/, ".html")

        compile_erb_page(erb_file, page_name, dist_dir, importmap_json_str)
      end
    end

    def compile_erb_page(erb_file, page_name, dist_dir, importmap_json_str)
      puts "Compiling page: #{page_name}..."

      begin
        content = File.read(erb_file)
      rescue Errno::ENOENT, Errno::EACCES, SystemCallError => e
        puts "Error: Could not read ERB file #{erb_file}: #{e.message}"
        raise
      end

      current_page_path = determine_current_page_path(page_name)
      layout_content, layout_file = load_layout_content
      view = setup_action_view_context
      
      load_page_helpers_and_set_metadata(view, current_page_path)
      setup_view_instance_variables(view, importmap_json_str, current_page_path)
      override_view_render_method(view, importmap_json_str, current_page_path)
      
      page_content = render_page_template(view, content, page_name, importmap_json_str, current_page_path, erb_file)
      rendered = render_layout_template(view, layout_content, layout_file, page_content, importmap_json_str, current_page_path)
      
      write_page_output(dist_dir, page_name, rendered)
      
      puts "  ✓ Created #{page_name}"
    end


    def copy_static_files(dist_dir)
      public_dir = @root.join("public")
      return unless public_dir.exist? && public_dir.directory?

      puts "Copying static files from public/..."
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
      live_reload_script_content = live_reload_script

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <%= display_meta_tags site: 'Site', title: 'Site' %>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <%= page_content %>
          <% if defined?(@importmap_json) && @importmap_json %>
            <script type="importmap"><%= @importmap_json %></script>
          <% end %>
          <% if @js_modules.present? %>
            <% @js_modules.each do |module_name| %>
              <script type="module">import "<%= module_name %>";</script>
            <% end %>
          <% else %>
            <script type="module">import "application";</script>
          <% end %>
          #{live_reload_script_content}
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
        to_path = to.presence || "#{name}.js"
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
