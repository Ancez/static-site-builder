# frozen_string_literal: true

require "uri"
require "action_view"
require "action_view/helpers"
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

# ViewComponent will be required when needed in compile_view_component_pages
# to avoid loading it unnecessarily and to handle Rails dependencies

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

      dist_dir = @root.join("dist")
      
      # Only clean dist directory for production/release builds
      # In development, update files in place to prevent 404s during rebuilds
      production_build = ENV["PRODUCTION"] == "true" || ENV["RELEASE"] == "true"
      if production_build
        if dist_dir.exist?
          puts "Cleaning dist directory for production build..."
          FileUtils.rm_rf(dist_dir)
        else
          puts "Dist directory does not exist, skipping clean"
        end
      end
      
      # Ensure dist directory exists
      FileUtils.mkdir_p(dist_dir)

      # Copy assets (overwrites existing files)
      copy_assets(dist_dir)

      # Generate importmap JSON if using importmap (overwrites existing file)
      generate_importmap(dist_dir) if @js_bundler == "importmap"

      # Compile pages based on template engine (overwrites existing files)
      case @template_engine
      when "erb"
        compile_erb_pages(dist_dir)
      when "phlex"
        compile_phlex_pages(dist_dir)
      when "view_component"
        compile_view_component_pages(dist_dir)
      when "view_component"
        compile_view_component_pages(dist_dir)
      end

      # Copy static files (overwrites existing files)
      copy_static_files(dist_dir)

      # Notify WebSocket server (always update, even if file doesn't exist yet)
      reload_file = @root.join(".reload")
      File.write(reload_file, Time.now.to_f.to_s)

      puts "\n✓ Build complete! Output in #{dist_dir}"
    end

    # Public method to render partials - no longer needed as ActionView handles this directly
    # ActionView's render method automatically finds and renders partials from app/views
    # This method is kept for backwards compatibility but should not be called
    def render_partial(partial_path, view_context, locals = {})
      # ActionView handles partial rendering automatically through its render method
      # When templates call render 'shared/header', ActionView finds _header.html.erb automatically
      begin
        view_context.render(partial: partial_path, locals: locals)
      rescue ActionView::MissingTemplate => e
        # Convert ActionView's error to our format for backwards compatibility
        raise "Partial not found: #{partial_path} (looked for #{e.path})"
      end
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

      # Copy vendor JavaScript files directly from node_modules to dist (for importmap)
      if @js_bundler == "importmap"
        copy_vendor_files_from_node_modules(dist_dir)
      end

      # Copy CSS (skip if Tailwind is handling it - check for tailwind.config.js)
      # Tailwind outputs directly to dist, so we don't want to overwrite with raw files
      # But we still need to ensure the directory exists for Tailwind to write to
      tailwind_config = @root.join("tailwind.config.js")
      css_dir = @root.join("app", "assets", "stylesheets")
      dist_css = dist_dir.join("assets", "stylesheets")
      
      if tailwind_config.exist?
        # Tailwind is handling CSS - ensure directory exists but don't copy raw files
        FileUtils.mkdir_p(dist_css)
      elsif css_dir.exist? && css_dir.directory?
        # No Tailwind - copy CSS files normally
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
        next if dest_file.exist?

        # Try to copy directly from node_modules to dist
        if copy_vendor_file_from_node_modules(package_name, file_name, dest_file)
          puts "  ✓ Copied #{file_name} from #{package_name}"
        else
          puts "  ⚠️  Warning: Could not find #{file_name} for #{package_name} in node_modules"
          puts "     Ensure 'npm install' has been run and the package is installed."
        end
      end
    end

    def copy_vendor_file_from_node_modules(package_name, file_name, dest_file)
      node_modules = @root.join("node_modules")
      return false unless node_modules.exist?

      package_dir = node_modules.join(*package_name.split("/"))
      return false unless package_dir.exist?

      # Try common source paths for the package
      # Extract base name from file_name (e.g., "stimulus.min.js" -> "stimulus")
      base_name = file_name.gsub(/\.(min\.)?js$/, "")
      source_paths = [
        "dist/#{base_name}.js",
        "dist/#{base_name}.min.js",
        "dist/index.js",
        "#{base_name}.js",
        "index.js",
        "dist/#{file_name}",
        file_name
      ]

      source_paths.each do |source_path|
        source_file = package_dir.join(*source_path.split("/"))
        if source_file.exist? && source_file.file?
          FileUtils.cp(source_file, dest_file)
          return true
        end
      end

      false
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

      # Read ERB content - ActionView will process it directly
      content = File.read(erb_file)

      # Default layout
      layout = "application"

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

      # Set current_page based on the file being compiled
      current_page_path = if page_name == 'index.html'
        '/'
      else
        "/#{page_name.gsub(/\.html$/, '')}"
      end

      # Create ActionView lookup context with view paths
      view_paths = ActionView::PathSet.new([@root.join("app", "views").to_s])
      lookup_context = ActionView::LookupContext.new(view_paths)
      
      # Create ActionView::Base instance for rendering using with_empty_template_cache
      # This is the recommended way for standalone ActionView usage
      view_class = ActionView::Base.with_empty_template_cache
      view = view_class.new(lookup_context, {}, self)

      # Include PageHelpers if available (look in project root)
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

      # Set instance variables that will be available in templates
      # Pages can set @title, @js_modules, etc. via ERB at the top
      view.instance_variable_set(:@js_modules, [])
      view.instance_variable_set(:@importmap_json, importmap_json_str) if importmap_json_str
      view.instance_variable_set(:@current_page, current_page_path)
      view.instance_variable_set(:@page_content, nil)
      
      # Set title and metadata from PageHelpers BEFORE rendering page content
      # This ensures partials rendered within the page have access to metadata
      page_helpers_path = @root.join('lib', 'page_helpers.rb')
      begin
        if page_helpers_path.exist?
          require page_helpers_path.to_s
          pages = ::PageHelpers::PAGES rescue nil
          if pages && pages.is_a?(Hash) && pages.key?(current_page_path)
            metadata = pages[current_page_path]
            view.instance_variable_set(:@title, metadata[:title])
            view.instance_variable_set(:@description, metadata[:description])
            view.instance_variable_set(:@url, metadata[:url])
            view.instance_variable_set(:@image, metadata[:image])
          end
        end
      rescue => e
        # Silently continue if PageHelpers can't be loaded
      end
      
      # Override render to handle 'footer' -> 'shared/footer' conversion
      # and ensure locals are passed to partials
      view.define_singleton_method(:render) do |options = {}, locals = {}, &block|
        begin
          # Handle string/symbol partial names: render 'footer' -> render 'shared/footer'
          if options.is_a?(String) || options.is_a?(Symbol)
            partial_name = options.to_s
            # If no path separator, assume it's in shared/
            unless partial_name.include?('/')
              partial_name = "shared/#{partial_name}"
            end
            # Merge page locals with any provided locals
            merged_locals = {
              importmap_json: importmap_json_str,
              current_page: current_page_path
            }.merge(locals.is_a?(Hash) ? locals : {})
            super(partial: partial_name, locals: merged_locals, &block)
          elsif options.is_a?(Hash)
            # Handle hash options: render partial: 'footer', locals: {}
            partial_path = options[:partial] || options['partial']
            if partial_path
              # Convert 'footer' to 'shared/footer' if no path
              unless partial_path.to_s.include?('/')
                partial_path = "shared/#{partial_path}"
              end
              # Merge page locals with provided locals
              provided_locals = options[:locals] || options['locals'] || {}
              merged_locals = {
                importmap_json: importmap_json_str,
                current_page: current_page_path
              }.merge(provided_locals)
              super(partial: partial_path, locals: merged_locals, &block)
            else
              # Other render options (template, etc.)
              super(options, locals, &block)
            end
          else
            super(options, locals, &block)
          end
        rescue ActionView::MissingTemplate => e
          # Convert ActionView's error to our format for backwards compatibility
          raise "Partial not found: #{partial_path || partial_name || 'unknown'} (looked for #{e.path})"
        end
      end

      # Render page content using ActionView
      # Pages can set instance variables via ERB (e.g., <% @title = '...' %>)
      page_template = ActionView::Template.new(
        content,
        "inline:page",
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
        # Convert ActionView errors to our format
        if e.cause.is_a?(ActionView::MissingTemplate)
          raise "Partial not found: #{e.cause.path} (looked for #{e.cause.path})"
        end
        raise
      end

      # Annotate page content if enabled
      if @annotate_template_file_names
        relative_template_path = Pathname.new(erb_file).relative_path_from(@root)
        page_content = annotate_template(page_content, relative_template_path.to_s)
      end

      # Render layout using ActionView
      # Instance variables set in the page template are available in the layout
      layout_template = ActionView::Template.new(
        layout_content,
        "inline:layout",
        ActionView::Template::Handlers::ERB.new,
        virtual_path: "layouts/#{layout}",
        format: :html,
        locals: [:page_content, :importmap_json, :current_page]
      )

      # Mark page_content as HTML safe to prevent escaping
      # ActionView will escape strings by default in ERB, so we mark it as safe
      safe_page_content = page_content.respond_to?(:html_safe) ? page_content.html_safe : page_content
      
      rendered = view.render(template: layout_template, locals: {
        page_content: safe_page_content,
        importmap_json: importmap_json_str,
        current_page: current_page_path
      })

      # Annotate layout if enabled
      # Note: We wrap the rendered content without removing existing annotations
      # This preserves page annotations that are already in the content
      if @annotate_template_file_names && layout_file.exist?
        relative_layout_path = Pathname.new(layout_file).relative_path_from(@root)
        begin_comment = "<!-- BEGIN #{relative_layout_path} -->"
        end_comment = "<!-- END #{relative_layout_path} -->"
        rendered = "#{begin_comment}\n#{rendered}\n#{end_comment}"
      end

      output_path = dist_dir.join(page_name)
      FileUtils.mkdir_p(output_path.dirname)
      puts "  Debug: Writing #{rendered.length} chars to #{output_path}"
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

    def compile_view_component_pages(dist_dir)
      pages_dir = @root.join("app", "views", "pages")
      return unless pages_dir.exist?

      # Load all ViewComponent classes from app/views/pages and app/components
      # This will also ensure ViewComponent is loaded
      load_view_component_classes

      # Ensure ViewComponent is available after loading
      unless defined?(ViewComponent::Base)
        raise "ViewComponent gem is required but not loaded. Add 'gem \"view_component\"' to your Gemfile."
      end

      # Generate importmap JSON once for all pages
      resolver = AssetResolver.new(@root, dist_dir)
      importmap_json_str = @importmap.to_json(resolver: resolver) if defined?(@importmap) && @importmap

      # Find all ViewComponent page files (*_component.rb)
      Dir.glob(pages_dir.join("**", "*_component.rb")).each do |component_file|
        relative_path = Pathname.new(component_file).relative_path_from(pages_dir)
        component_name = relative_path.to_s.gsub(/\.rb$/, "")
        page_name = component_name.gsub(/_component$/, "").gsub(/_/, "/")
        page_name = "index" if page_name.empty?
        page_name = "#{page_name}.html" unless page_name.end_with?(".html")

        compile_view_component_page(component_file, component_name, page_name, dist_dir, importmap_json_str)
      end
    end

    def compile_view_component_page(component_file, component_name, page_name, dist_dir, importmap_json_str)
      puts "Compiling #{page_name}..."

      # Extract class name from file path
      # e.g., index_component.rb -> IndexPageComponent
      # e.g., blog/index_component.rb -> Blog::IndexPageComponent
      # The file name pattern is: {name}_component.rb, class should be {Name}PageComponent
      parts = component_name.split("/")
      class_parts = parts.map do |part|
        # Remove _component suffix and convert to PascalCase, then add "Page"
        base_name = part.gsub(/_component$/, "")
        pascal_case = base_name.split("_").map(&:capitalize).join
        "#{pascal_case}Page"
      end
      # Join parts: for single part use no separator, for multiple use ::
      if class_parts.length > 1
        class_name = (class_parts + ["Component"]).join("::")
      else
        class_name = (class_parts + ["Component"]).join("")
      end

      # Load the component class
      begin
        # Use load instead of require to ensure file is executed (important for tests)
        load component_file
        # Navigate nested constants step by step to ensure proper loading
        component_class = class_name.split("::").inject(Object) do |mod, const_name|
          mod.const_get(const_name)
        end
      rescue NameError, LoadError => e
        raise "Could not load ViewComponent class #{class_name} from #{component_file}: #{e.message}"
      end

      unless defined?(ViewComponent::Base) && component_class < ViewComponent::Base
        raise "#{class_name} must inherit from ViewComponent::Base"
      end

      # Override template path to match the file name convention
      # ViewComponent expects templates named after the class (e.g., IndexPageComponent -> index_page_component.html.erb)
      # But we use the file name convention (e.g., index_component.html.erb)
      template_file = component_file.sub(/\.rb$/, ".html.erb")
      template_file_path = Pathname.new(template_file)
      
      if template_file_path.exist?
        # ViewComponent 4.x looks for templates based on the component class name
        # We need to override this to use our file naming convention
        # The simplest way is to define a render method that uses our template file
        component_class.class_eval do
          # Store the template file path
          @_vc_custom_template_file = template_file_path.to_s
          
          # Override ViewComponent's template lookup
          # ViewComponent 4.x uses a compiler, we need to tell it about our template
          if respond_to?(:compile)
            # Clear compilation cache to force recompilation
            remove_instance_variable(:@__vc_compiled) if instance_variable_defined?(:@__vc_compiled)
          end
        end
        
        # Use ViewComponent's compiler API to set the template
        # ViewComponent 4.x stores template information in the compiler
        begin
          if defined?(ViewComponent::Compiler)
            # Get or create compiler for this component
            compiler = ViewComponent::Compiler.new(component_class)
            # Set the template file if the compiler supports it
            if compiler.respond_to?(:template=)
              compiler.template = template_file_path.to_s
            elsif compiler.instance_variable_defined?(:@template)
              compiler.instance_variable_set(:@template, template_file_path.to_s)
            end
          end
        rescue => e
          # If compiler API doesn't work, we'll handle it in rendering
        end
      end

      # Set current_page based on the file being compiled
      current_page_path = if page_name == 'index.html'
        '/'
      else
        "/#{page_name.gsub(/\.html$/, '')}"
      end

      # Create ActionView lookup context
      view_paths = ActionView::PathSet.new([
        @root.join("app", "views").to_s,
        @root.join("app", "components").to_s
      ])
      lookup_context = ActionView::LookupContext.new(view_paths)
      
      # Create ActionView::Base instance
      view_class = ActionView::Base.with_empty_template_cache
      view = view_class.new(lookup_context, {}, self)

      # Include PageHelpers if available
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
      
      if defined?(PageHelpers)
        view.extend(PageHelpers) unless view.singleton_class.included_modules.include?(PageHelpers)
      end

      # Set instance variables
      view.instance_variable_set(:@js_modules, [])
      view.instance_variable_set(:@importmap_json, importmap_json_str) if importmap_json_str
      view.instance_variable_set(:@current_page, current_page_path)
      
      # Set title and metadata from PageHelpers
      page_helpers_path = @root.join('lib', 'page_helpers.rb')
      begin
        if page_helpers_path.exist?
          require page_helpers_path.to_s
          pages = ::PageHelpers::PAGES rescue nil
          if pages && pages.is_a?(Hash) && pages.key?(current_page_path)
            metadata = pages[current_page_path]
            view.instance_variable_set(:@title, metadata[:title])
            view.instance_variable_set(:@description, metadata[:description])
            view.instance_variable_set(:@url, metadata[:url])
            view.instance_variable_set(:@image, metadata[:image])
          end
        end
      rescue => e
        # Silently continue if PageHelpers can't be loaded
      end

      # Render the page component
      begin
        page_component = component_class.new(title: view.instance_variable_get(:@title) || "Site")
        
        # Try to render using ViewComponent's standard rendering
        # If that fails due to template not found, render the template manually
        begin
          page_content = view.render(page_component)
        rescue ViewComponent::TemplateError => e
          # ViewComponent couldn't find the template, render it manually using ActionView
          template_file_path = component_file.sub(/\.rb$/, ".html.erb")
          if File.exist?(template_file_path)
            # Render the template file directly using ActionView
            # ViewComponent templates are rendered in the context of the component,
            # so we need to make component methods and instance variables available to the view
            
            # Set component instance variables on the view
            page_component.instance_variables.each do |ivar|
              view.instance_variable_set(ivar, page_component.instance_variable_get(ivar))
            end
            
            # Make component methods available to the template by extending the view
            # This allows templates to call methods like `title` that exist on the component
            # Include both public and private methods since ViewComponent templates can access private methods
            component_methods_module = Module.new do
              # Get all methods (public and private) excluding Object methods
              all_methods = (page_component.methods(false) + page_component.private_methods(false)).uniq
              all_methods.each do |method_name|
                # Skip methods that might conflict with ActionView
                next if [:render, :output_buffer, :output_buffer=].include?(method_name)
                define_method(method_name) do |*args, &block|
                  page_component.send(method_name, *args, &block)
                end
              end
            end
            view.extend(component_methods_module)
            
            template_content = File.read(template_file_path)
            # Extract local variable names from instance variables for ActionView::Template
            local_names = page_component.instance_variables.map { |ivar| ivar.to_s.delete('@').to_sym }
            template = ActionView::Template.new(
              template_content,
              template_file_path,
              ActionView::Template::Handlers::ERB.new,
              virtual_path: template_file_path,
              format: :html,
              locals: local_names
            )
            page_content = view.render(template: template)
          else
            raise e
          end
        end
      rescue => e
        raise "Error rendering ViewComponent #{class_name}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end

      # Annotate page content if enabled
      if @annotate_template_file_names
        relative_template_path = Pathname.new(component_file).relative_path_from(@root)
        page_content = annotate_template(page_content, relative_template_path.to_s)
      end

      # Render layout component
      layout_component_class = begin
        layout_file = @root.join("app", "components", "application_layout_component.rb")
        if layout_file.exist?
          require layout_file.to_s
          ApplicationLayoutComponent
        else
          nil
        end
      rescue LoadError, NameError
        nil
      end

      if layout_component_class
        # Use ViewComponent layout
        layout_title = view.instance_variable_get(:@title) || "Site"
        safe_page_content = page_content.respond_to?(:html_safe) ? page_content.html_safe : page_content
        
        # ViewComponent's render method in ActionView accepts a block for content
        layout_component = layout_component_class.new(title: layout_title)
        rendered = view.render(layout_component) do
          safe_page_content
        end
      else
        # Fall back to default layout if no ViewComponent layout found
        layout_content = default_layout
        layout_template = ActionView::Template.new(
          layout_content,
          "inline:layout",
          ActionView::Template::Handlers::ERB.new,
          virtual_path: "layouts/application",
          format: :html,
          locals: [:page_content, :importmap_json, :current_page]
        )
        
        safe_page_content = page_content.respond_to?(:html_safe) ? page_content.html_safe : page_content
        rendered = view.render(template: layout_template, locals: {
          page_content: safe_page_content,
          importmap_json: importmap_json_str,
          current_page: current_page_path
        })
      end

      # Annotate layout if enabled
      if @annotate_template_file_names && layout_component_class
        relative_layout_path = @root.join("app", "components", "application_layout_component.rb").relative_path_from(@root)
        begin_comment = "<!-- BEGIN #{relative_layout_path} -->"
        end_comment = "<!-- END #{relative_layout_path} -->"
        rendered = "#{begin_comment}\n#{rendered}\n#{end_comment}"
      end

      output_path = dist_dir.join(page_name)
      FileUtils.mkdir_p(output_path.dirname)
      File.write(output_path, rendered)

      puts "  ✓ Created #{page_name}"
    end

    def load_view_component_classes
      # Ensure ViewComponent is loaded first
      unless defined?(ViewComponent::Base)
        begin
          # ViewComponent requires Rails.env and Rails::VERSION, so set them up if not already defined
          unless defined?(Rails) && Rails.respond_to?(:env)
            require "active_support/string_inquirer"
            unless defined?(Rails)
              Object.const_set(:Rails, Module.new)
            end
            unless Rails.respond_to?(:env)
              Rails.define_singleton_method(:env) do
                @env ||= ActiveSupport::StringInquirer.new(ENV["RAILS_ENV"] || "production")
              end
            end
            # ViewComponent also checks Rails::VERSION::MAJOR and Rails::VERSION::MINOR as constants
            unless defined?(Rails::VERSION)
              version_module = Module.new
              version_module.const_set(:MAJOR, 7)
              version_module.const_set(:MINOR, 1)
              Rails.const_set(:VERSION, version_module)
            end
            # ViewComponent may also access Rails.application.routes.url_helpers
            unless Rails.respond_to?(:application)
              require "ostruct"
              app = OpenStruct.new
              routes = OpenStruct.new
              routes.define_singleton_method(:url_helpers) { Module.new }
              app.routes = routes
              Rails.define_singleton_method(:application) { app }
            end
          end
          
          require "view_component"
          
          # Configure ViewComponent to look for templates in the correct directories
          # ViewComponent 4.x uses ActionView's lookup context
          if ViewComponent.respond_to?(:view_paths=)
            ViewComponent.view_paths = [
              @root.join("app", "views", "pages").to_s,
              @root.join("app", "components").to_s,
              @root.join("app", "views").to_s
            ]
          elsif ViewComponent.respond_to?(:configure)
            ViewComponent.configure do |config|
              config.view_paths = [
                @root.join("app", "views", "pages").to_s,
                @root.join("app", "components").to_s,
                @root.join("app", "views").to_s
              ] if config.respond_to?(:view_paths=)
            end
          end
        rescue LoadError => e
          raise "ViewComponent gem is required but not available. Add 'gem \"view_component\"' to your Gemfile. Error: #{e.message}"
        end
      end

      # Load all component classes from app/components and app/views/pages
      components_dir = @root.join("app", "components")
      pages_dir = @root.join("app", "views", "pages")

      [components_dir, pages_dir].each do |dir|
        next unless dir.exist?
        
        Dir.glob(dir.join("**", "*_component.rb")).each do |file|
          begin
            require file.to_s
          rescue LoadError, SyntaxError, NameError => e
            # Skip files that can't be loaded (might be intentional)
            file_path = Pathname.new(file)
            puts "  ⚠️  Warning: Could not load #{file_path.relative_path_from(@root)}: #{e.message}"
          end
        end
      end
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
          <title><%= @title || 'Site' %></title>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <%= page_content %>
          <% if defined?(@importmap_json) && @importmap_json %>
            <script type="importmap"><%= @importmap_json %></script>
          <% end %>
          <% if @js_modules && !@js_modules.empty? %>
            <% @js_modules.each do |module_name| %>
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
