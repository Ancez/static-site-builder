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
      puts "  rake dev:server    # Start development server with live reload"
      puts "  # or"
      puts "  rake build:all     # Build for production deployment"
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
        "rake",
        "static-site-builder",
        "webrick",  # Required for dev server (removed from stdlib in Ruby 3.0+)
        "sitemap_generator"  # For generating sitemaps from actual pages
      ]
      
      # listen gem is included in static-site-builder, no need to add here

      content = <<~RUBY
        # frozen_string_literal: true

        source "https://rubygems.org"

        #{gems.map { |g| %(gem "#{g}") }.join("\n")}
      RUBY

      write_file("Gemfile", content)
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

        # Generate sitemap from actual pages in app/views/pages
        SitemapGenerator::Sitemap.create do
          pages_dir = Pathname.new('app/views/pages')
          next unless pages_dir.exist?
          
          Dir.glob(pages_dir.join('**', '*.html.erb')).each do |erb_file|
            relative_path = Pathname.new(erb_file).relative_path_from(pages_dir)
            page_name = relative_path.to_s.gsub(/\.html\.erb$/, '')
            
            # Convert page name to URL path
            # Handle index pages: 'index' -> '/', 'blog/index' -> '/blog/'
            path = if page_name == 'index'
              '/'
            elsif page_name.end_with?('/index')
              "/\#{page_name.gsub(/\/index$/, '')}/"
            else
              "/\#{page_name}"
            end
            
            add path, lastmod: File.mtime(erb_file), changefreq: 'weekly', priority: 0.5
          end
        end
      RUBY

      write_file("config/sitemap.rb", content)
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
          <%= display_meta_tags site: 'Site', title: 'Site' %>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <main>
            <%= yield %>
          </main>

          <% if content_for?(:javascript) %>
            <%= yield(:javascript) %>
          <% end %>
        </body>
        </html>
      ERB

      write_file("app/views/layouts/application.html.erb", content)
    end

    def create_javascript_entry
      content = <<~JS
        // Your JavaScript code here
        console.log("Application loaded")
      JS

      write_file("app/javascript/application.js", content)
    end

    def create_css_entry
      write_file("app/assets/stylesheets/application.css", <<~CSS)
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

        require_relative "lib/site_builder"
        require "fileutils"
        require "pathname"

        namespace :build do
          desc "Build everything (HTML + Sitemap)"
          task :all => [:html, :sitemap] do
            puts "\\n✓ Build complete!"
          end

          desc "Compile all pages to static HTML"
          task :html do
            load "lib/site_builder.rb"
          end

          desc "Clean dist directory"
          task :clean do
            dist_dir = Pathname.new(Dir.pwd).join("dist")
            FileUtils.rm_rf(dist_dir) if dist_dir.exist?
            puts "Cleaned \#{dist_dir}"
          end

          desc "Build for production/release (cleans dist directory first)"
          task :production do
            ENV["PRODUCTION"] = "true"
            Rake::Task["build:all"].invoke
          end

          desc "Generate sitemap from actual pages"
          task :sitemap do
            require './config/sitemap'
          end
        end

        namespace :dev do
          desc "Start development server with auto-rebuild and live reload"
          task :server do
            require 'static_site_builder/dev_server'
            
            port = ENV['PORT']&.to_i || #{DEFAULT_PORT}
            ws_port = ENV['WS_PORT']&.to_i || #{DEFAULT_WS_PORT}
            
            server = StaticSiteBuilder::DevServer.new(
              root: Dir.pwd,
              port: port,
              ws_port: ws_port
            )
            
            server.start
          end
        end

        task default: "build:all"
      RUBY

      write_file("Rakefile", content)
    end



    def create_site_builder
      # Generated sites use the static-site-builder gem
      # This file configures the builder
      content = <<~RUBY
        # frozen_string_literal: true

        require "static_site_builder"

        # Configure the builder
        builder = StaticSiteBuilder::Builder.new(
          root: Dir.pwd
        )

        # Build the site
        builder.build
      RUBY

      write_file("lib/site_builder.rb", content)
    end

    def create_example_pages
      create_erb_example
    end

    def create_erb_example
      content = <<~ERB
        <% content_for :javascript do %>
          <script src="/assets/javascripts/application.js"></script>
        <% end %>

        <h1>Welcome</h1>
        <p>This is your generated static site.</p>
      ERB

      write_file("app/views/pages/index.html.erb", content)
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

        Build for production:

        ```bash
        rake build:all     # Build everything (assets + HTML)
        rake build:html    # Build HTML only
        ```

        Output goes to `dist/` directory.

        ## JavaScript Bundling

        This generator doesn't handle JavaScript bundling. You can set up your own bundler:

        - [ESBuild](https://github.com/Ancez/static-site-builder/blob/main/guides/setup-esbuild.md)
        - [Webpack](https://webpack.js.org/) - see webpack documentation
        - [Vite](https://github.com/ElMassimo/vite_ruby) - see vite-plugin-ruby

        Or simply include JavaScript files directly in your page templates:
        ```erb
        <% content_for :javascript do %>
          <script src="/assets/javascripts/application.js"></script>
        <% end %>
        ```

        ## CSS Frameworks

        This generator provides a basic `application.css` file. You can integrate CSS frameworks:

        - [Tailwind CSS](https://github.com/Ancez/static-site-builder/blob/main/guides/setup-tailwind.md)
        - PostCSS, Sass, Less, or any other CSS processor - just compile your CSS files to `dist/assets/stylesheets/` before building HTML.
      MD

      write_file("README.md", content)
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
