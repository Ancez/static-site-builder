# frozen_string_literal: true

require "uri"
require "action_view"
require "action_view/helpers"
require "erb"
require "fileutils"
require "json"
require "pathname"
require "digest"

# Create minimal ActionController stub for meta-tags gem compatibility
# meta-tags expects ActionController to be available but we're using ActionView standalone
unless defined?(ActionController)
  module ActionController
    class Base
      # meta-tags gem calls ActionController::Base.helpers
      # In Rails, this returns an instance that includes ActionView::Helpers
      # We create a simple object that extends ActionView::Helpers modules
      def self.helpers
        @helpers ||= Object.new.tap do |helper_obj|
          helper_obj.extend(ActionView::Helpers::TagHelper)
          helper_obj.extend(ActionView::Helpers::OutputSafetyHelper)
          helper_obj.extend(ActionView::Helpers::TextHelper)
        end
      end
    end
  end
end

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


module StaticSiteBuilder
  class Builder
    # Output directory name
    DIST_DIR = "dist"
    # Default JavaScript entry point
    JS_ENTRY_POINT = "application"
    def initialize(root: Dir.pwd, annotate_template_file_names: nil)
      @root = Pathname.new(root)

      # Auto-enable annotations in development (when LIVE_RELOAD is enabled)
      @annotate_template_file_names = if annotate_template_file_names.nil?
        ENV["LIVE_RELOAD"] == "true" || ENV["RAILS_ENV"] == "development"
      else
        annotate_template_file_names
      end
    end

    # Builds the complete static site.
    #
    # Compiles ERB templates to HTML, copies JavaScript and CSS assets, and outputs
    # everything to the dist/ directory. In development mode, files are updated in place
    # to prevent 404 errors during live reload. In production mode, the dist directory
    # is cleaned first for a fresh build.
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

      # Compile ERB templates to static HTML pages
      compile_erb_pages(dist_dir)

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
    #
    # Creates an ActionView::Base instance with helpers included (Rails pattern).
    # Helpers are included on the class before instantiation, which is more
    # Rails-like than extending individual instances.
    def setup_action_view_context
      view_paths = ActionView::PathSet.new([@root.join('app', 'views').to_s])
      lookup_context = ActionView::LookupContext.new(view_paths)
      view_class = ActionView::Base.with_empty_template_cache
      
      # Include helpers on the class (Rails pattern) rather than extending instances
      view_class.include(MetaTags::ViewHelper) unless view_class.included_modules.include?(MetaTags::ViewHelper)
      
      # Automatically load helpers from app/helpers/
      load_helpers(view_class)
      
      view = view_class.new(lookup_context, {}, self)
      view
    end

    # Automatically load helper modules from app/helpers/ directory
    def load_helpers(view_class)
      helpers_dir = @root.join('app', 'helpers')
      return unless helpers_dir.exist? && helpers_dir.directory?

      Dir.glob(helpers_dir.join('**', '*_helper.rb')).each do |helper_file|
        begin
          # Get the module name from the file (e.g., app/helpers/application_helper.rb -> ApplicationHelper)
          relative_path = Pathname.new(helper_file).relative_path_from(helpers_dir)
          module_name = relative_path.to_s.gsub(/\.rb$/, '').split('_').map(&:capitalize).join
          
          # Require the file
          require helper_file
          
          # Include the module if it exists
          if Object.const_defined?(module_name)
            helper_module = Object.const_get(module_name)
            view_class.include(helper_module) unless view_class.included_modules.include?(helper_module)
          end
        rescue LoadError, NameError => e
          # Silently skip if helper can't be loaded (e.g., missing dependencies)
          # This allows users to have helpers that require additional gems
        end
      end
    end



    # Render page template using ActionView (file-based, not inline)
    def render_page_template(view, content, page_name, erb_file)
      # Calculate the template path relative to app/views
      # e.g., app/views/pages/index.html.erb -> pages/index
      pages_dir = @root.join("app", "views", "pages")
      template_path = Pathname.new(erb_file).relative_path_from(pages_dir).to_s.gsub(/\.html\.erb$/, '')
      full_template_path = "pages/#{template_path}"

      # Set prefixes on lookup_context so ActionView can resolve partials relative to template directory
      # For pages/index -> prefix is 'pages', for pages/blog/index -> prefix is 'pages/blog'
      lookup_context = view.lookup_context
      original_prefixes = lookup_context.prefixes.dup
      template_dir = File.dirname(full_template_path)
      lookup_context.prefixes = [template_dir]

      begin
        # Set instance variables on view (Rails pattern: controllers set instance variables)
        # Templates set their own @title, @description etc. using meta-tags gem
        
        # Use file-based rendering - ActionView will find the actual file
        # With prefixes set, partials can be resolved relative to the template directory
        template = lookup_context.find_template(full_template_path, [], false, [], {})
        page_content = view.render(template: template)
      rescue ActionView::Template::Error => e
        if e.cause.is_a?(ActionView::MissingTemplate)
          raise "Partial template not found. Searched in: #{e.cause.path}"
        end
        raise
      ensure
        # Restore original prefixes
        lookup_context.prefixes = original_prefixes
      end

      if @annotate_template_file_names
        relative_template_path = Pathname.new(erb_file).relative_path_from(@root)
        page_content = annotate_template(page_content, relative_template_path.to_s)
      end

      page_content
    end

    # Render layout template using ActionView
    def render_layout_template(view, layout_content, layout_file, page_content)
      layout = StaticSiteBuilder::DEFAULT_LAYOUT_NAME
      
      # Replace <%= yield %> with a local variable in the layout content
      # This allows us to pass page_content as a local while maintaining Rails-like syntax
      layout_content_with_yield = layout_content.gsub(/<%=?\s*yield\s*%>/, '<%= page_content %>')
      
      layout_template = ActionView::Template.new(
        layout_content_with_yield,
        'inline:layout',
        ActionView::Template::Handlers::ERB.new,
        virtual_path: "layouts/#{layout}",
        format: :html,
        locals: [:page_content]
      )

      safe_page_content = page_content.respond_to?(:html_safe) ? page_content.html_safe : page_content
      
      # Render layout with page_content as local
      rendered = view.render(template: layout_template, locals: {
        page_content: safe_page_content
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

      # Handle CSS files
      # Copy CSS files from app/assets/stylesheets to dist/assets/stylesheets
      css_dir = @root.join("app", "assets", "stylesheets")
      dist_css = dist_dir.join("assets", "stylesheets")
      
      if css_dir.exist? && css_dir.directory?
        FileUtils.mkdir_p(dist_css)
        Dir.glob(css_dir.join("*")).each do |item|
          FileUtils.cp_r(item, dist_css, preserve: true)
        end
      end
    end


    def compile_erb_pages(dist_dir)
      pages_dir = @root.join("app", "views", "pages")
      return unless pages_dir.exist?

      # Find all ERB files, including nested directories
      Dir.glob(pages_dir.join("**", "*.html.erb")).each do |erb_file|
        relative_path = Pathname.new(erb_file).relative_path_from(pages_dir)
        page_name = relative_path.to_s.gsub(/\.html\.erb$/, ".html")

        compile_erb_page(erb_file, page_name, dist_dir)
      end
    end

    def compile_erb_page(erb_file, page_name, dist_dir)
      puts "Compiling page: #{page_name}..."

      layout_content, layout_file = load_layout_content
      view = setup_action_view_context
      
      # Pass erb_file directly - render_page_template will use file-based rendering
      # Page templates set their own @title, @description, @js_modules etc.
      page_content = render_page_template(view, nil, page_name, erb_file)
      rendered = render_layout_template(view, layout_content, layout_file, page_content)
      
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
          <%# Set meta tags in your page templates using: %>
          <%# <% set_meta_tags title: 'Page Title', description: 'Description' %> %>
          <%= display_meta_tags %>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <%= yield %>
          <% if content_for?(:javascript) %>
            <%= yield(:javascript) %>
          <% end %>
          #{live_reload_script_content}
        </body>
        </html>
      HTML
    end

  end
end
