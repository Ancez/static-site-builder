# frozen_string_literal: true

require "fileutils"
require "pathname"
require "erb"
require "json"

module StaticSiteBuilder
  # Generator for creating new static site projects
  #
  # @example Generate a site with default options
  #   generator = StaticSiteBuilder::Generator.new("my-site")
  #   generator.generate
  #
  # @example Generate a site with custom stack
  #   generator = StaticSiteBuilder::Generator.new("my-site", {
  #     template_engine: "phlex",
  #     js_bundler: "esbuild",
  #     css_framework: "shadcn",
  #     js_framework: "react"
  #   })
  #   generator.generate
  class Generator
    # Available template engines
    TEMPLATE_ENGINES = %w[erb phlex view_component].freeze

    # Available JavaScript bundlers
    JS_BUNDLERS = %w[importmap esbuild webpack vite none].freeze

    # Available CSS frameworks
    CSS_FRAMEWORKS = %w[tailwindcss shadcn plain].freeze

    # Available JavaScript frameworks
    JS_FRAMEWORKS = %w[stimulus react vue alpine vanilla].freeze

    # Initialize a new generator
    #
    # @param app_name [String] Name of the application/site to generate
    # @param options [Hash] Configuration options
    # @option options [String] :template_engine ("erb") Template engine to use (erb, phlex, or view_component)
    # @option options [String] :js_bundler ("importmap") JavaScript bundler (importmap, esbuild, webpack, vite, none)
    # @option options [String] :css_framework ("tailwindcss") CSS framework (tailwindcss, shadcn, plain)
    # @option options [String] :js_framework ("stimulus") JavaScript framework (stimulus, react, vue, alpine, vanilla)
    def initialize(app_name, options = {})
      @app_name = app_name
      @app_path = Pathname.new(app_name)
      @options = {
        template_engine: options[:template_engine] || "erb",
        js_bundler: options[:js_bundler] || "importmap",
        css_framework: options[:css_framework] || "tailwindcss",
        js_framework: options[:js_framework] || "stimulus"
      }
    end

    # Generate the static site project
    #
    # Creates all necessary files and directory structure for the project.
    # Outputs instructions for next steps after generation.
    #
    # @return [void]
    def generate
      puts "Generating static site: #{@app_name}"
      puts "Stack: #{@options[:template_engine]} + #{@options[:js_bundler]} + #{@options[:css_framework]} + #{@options[:js_framework]}"

      create_directory_structure
      create_gemfile
      create_package_json
      create_config_files
      create_app_structure
      create_build_files
      create_page_helpers
      create_sitemap_config
      create_example_pages
      create_readme
      create_gitignore

      puts "\n✓ Site generated successfully!"
      puts "\nNext steps:"
      puts "  cd #{@app_name}"
      puts "  bundle install"
      puts "  npm install" if needs_npm?
      puts "  rake dev:server    # Start development server with auto-rebuild"
      puts "  # or"
      puts "  rake build:all     # Build for production"
    end

    private

    def create_directory_structure
      dirs = [
        "app/views/layouts",
        "app/views/pages",
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
        "sitemap_generator"  # For generating sitemaps from PageHelpers::PAGES
      ]
      gems << "importmap-rails" if @options[:js_bundler] == "importmap"
      gems << "phlex-rails" if @options[:template_engine] == "phlex"
      gems << "view_component" if @options[:template_engine] == "view_component"
      if @options[:edit_rails]
        gems << "rails"
        gems << "edit_rails"
      end

      content = <<~RUBY
        # frozen_string_literal: true

        source "https://rubygems.org"

        #{gems.map { |g| %(gem "#{g}") }.join("\n")}
      RUBY

      write_file("Gemfile", content)
    end

    def create_package_json
      return unless needs_npm?

      deps = {}
      dev_deps = {}

      case @options[:js_bundler]
      when "esbuild"
        dev_deps["esbuild"] = "^0.19.0"
      when "webpack"
        dev_deps["webpack"] = "^5.0.0"
        dev_deps["webpack-cli"] = "^5.0.0"
      when "vite"
        dev_deps["vite"] = "^5.0.0"
        dev_deps["vite-plugin-ruby"] = "^3.0.0"
      end

      case @options[:css_framework]
      when "tailwindcss", "shadcn"
        dev_deps["tailwindcss"] = "^3.4.0"
        dev_deps["autoprefixer"] = "^10.4.0"
        dev_deps["postcss"] = "^8.4.0"
      end

      case @options[:js_framework]
      when "react"
        deps["react"] = "^18.0.0"
        deps["react-dom"] = "^18.0.0"
      when "vue"
        deps["vue"] = "^3.0.0"
      when "alpine"
        deps["alpinejs"] = "^3.0.0"
      when "stimulus"
        deps["@hotwired/stimulus"] = "^3.2.0"
      end

      scripts = {}
      scripts["build"] = build_script
      scripts["build:css"] = css_build_script if needs_css_build?
      scripts["watch:css"] = css_watch_script if needs_css_build?

      content = {
        name: @app_name,
        version: "1.0.0",
        description: "Static site generated with static-site-generator",
        scripts: scripts,
        dependencies: deps,
        devDependencies: dev_deps
      }

      write_file("package.json", JSON.pretty_generate(content))
    end

    def create_config_files
      create_importmap_config if @options[:js_bundler] == "importmap"
      create_tailwind_config if @options[:css_framework] == "tailwindcss" || @options[:css_framework] == "shadcn"
      create_esbuild_config if @options[:js_bundler] == "esbuild"
      create_webpack_config if @options[:js_bundler] == "webpack"
      create_vite_config if @options[:js_bundler] == "vite"
      create_rails_config if @options[:edit_rails]
    end

    def create_page_helpers
      content = <<~RUBY
        # frozen_string_literal: true

        module PageHelpers
          # Page metadata configuration
          # The builder automatically loads this and sets @title, @description, @url, and @image
          # instance variables for use in your templates.
          # This metadata is also used by sitemap_generator for generating sitemaps.
          PAGES = {
            '/' => {
              title: 'Home',
              description: 'Welcome to my site',
              url: 'https://example.com',
              image: 'https://example.com/image.jpg',
              priority: 1.0,
              changefreq: 'weekly'
            }
          }.freeze

          def page_title(path = nil)
            path ||= @current_page
            PAGES[path]&.fetch(:title) || 'Site'
          end

          def page_description(path = nil)
            path ||= @current_page
            PAGES[path]&.fetch(:description) || 'A static site'
          end

          def page_url(path = nil)
            path ||= @current_page
            PAGES[path]&.fetch(:url) || 'https://example.com'
          end

          def page_image(path = nil)
            path ||= @current_page
            PAGES[path]&.fetch(:image) || 'https://example.com/image.jpg'
          end
        end
      RUBY

      write_file("lib/page_helpers.rb", content)
    end

    def create_sitemap_config
      content = <<~RUBY
        # frozen_string_literal: true

        require 'sitemap_generator'
        require_relative '../lib/page_helpers'

        # Configure sitemap generator
        # Update default_host to your actual domain
        SitemapGenerator::Sitemap.default_host = 'https://example.com'
        SitemapGenerator::Sitemap.sitemaps_path = 'sitemaps'
        SitemapGenerator::Sitemap.public_path = 'dist'

        # Generate sitemap from PageHelpers::PAGES
        SitemapGenerator::Sitemap.create do
          PageHelpers::PAGES.each do |path, metadata|
            add path,
                lastmod: Time.now,
                priority: metadata[:priority] || 0.5,
                changefreq: metadata[:changefreq] || 'weekly'
          end
        end
      RUBY

      write_file("config/sitemap.rb", content)
    end

    def create_importmap_config
      content = <<~RUBY
        # frozen_string_literal: true

        pin "application", preload: true
        #{stimulus_pin if @options[:js_framework] == "stimulus"}
      RUBY

      write_file("config/importmap.rb", content)
    end

    def stimulus_pin
      <<~RUBY
        pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
        pin_all_from "app/javascript/controllers", under: "controllers"
      RUBY
    end


    # Detect which package manager is available
    def detect_package_manager
      # Check in order: yarn, pnpm, bun, npm
      return "yarn" if system("which yarn > /dev/null 2>&1")
      return "pnpm" if system("which pnpm > /dev/null 2>&1")
      return "bun" if system("which bun > /dev/null 2>&1")
      return "npm" if system("which npm > /dev/null 2>&1")
      nil
    end

    def create_tailwind_config
      content = <<~JS
        /** @type {import('tailwindcss').Config} */
        module.exports = {
          content: [
            "./app/views/**/*.{html,erb,phlex}",
            "./app/javascript/**/*.js",
          ],
          theme: {
            extend: {},
          },
          plugins: [],
        }
      JS

      write_file("tailwind.config.js", content)

      # Create PostCSS config
      postcss_content = <<~JS
        module.exports = {
          plugins: {
            tailwindcss: {},
            autoprefixer: {},
          },
        }
      JS

      write_file("postcss.config.js", postcss_content)
    end

    def create_esbuild_config
      content = <<~JS
        require('esbuild').build({
          entryPoints: ['app/javascript/application.js'],
          bundle: true,
          outdir: 'dist/assets/javascripts',
          format: 'esm',
          minify: true,
        }).catch(() => process.exit(1))
      JS

      write_file("esbuild.config.js", content)
    end

    def create_webpack_config
      content = <<~JS
        const path = require('path');

        module.exports = {
          entry: './app/javascript/application.js',
          output: {
            filename: 'application.js',
            path: path.resolve(__dirname, 'dist/assets/javascripts'),
          },
          mode: 'production',
        };
      JS

      write_file("webpack.config.js", content)
    end

    def create_vite_config
      content = <<~JS
        import { defineConfig } from 'vite';
        import RubyPlugin from 'vite-plugin-ruby';

        export default defineConfig({
          plugins: [RubyPlugin()],
        });
      JS

      write_file("vite.config.js", content)
    end

    def create_rails_config
      create_boot_config
      create_routes_config
      create_application_config
      create_environment_file
      create_environment_configs
    end

    def create_boot_config
      content = <<~RUBY
        # frozen_string_literal: true

        ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

        require "bundler/setup" # Set up gems listed in the Gemfile.
      RUBY

      write_file("config/boot.rb", content)
    end

    def create_routes_config
      content = <<~RUBY
        # frozen_string_literal: true

        Rails.application.routes.draw do
          mount EditRails::Engine => "/edit_rails", as: "edit_rails"
        end
      RUBY

      write_file("config/routes.rb", content)
    end

    def create_application_config
      content = <<~RUBY
        # frozen_string_literal: true

        require_relative "boot"

        require "rails/all"

        Bundler.require(*Rails.groups)

        module StaticSite
          class Application < Rails::Application
            config.load_defaults Rails::VERSION::STRING.to_f

            # Configuration for the application's routes
            config.api_only = false

            # Don't generate system test files
            config.generators.system_tests = nil

            # Serve static files from public directory
            config.public_file_server.enabled = true

            # Don't require database
            config.active_record.maintain_test_schema = false
          end
        end
      RUBY

      write_file("config/application.rb", content)
    end

    def create_environment_file
      content = <<~RUBY
        # frozen_string_literal: true

        # Load the Rails application.
        require_relative "application"

        # Initialize the Rails application.
        Rails.application.initialize!
      RUBY

      write_file("config/environment.rb", content)
    end

    def create_environment_configs
      # Create development environment config
      dev_content = <<~RUBY
        # frozen_string_literal: true

        require "active_support/core_ext/integer/time"

        Rails.application.configure do
          config.cache_classes = false
          config.eager_load = false
          config.consider_all_requests_local = true
          config.server_timing = true
          config.public_file_server.enabled = true
          config.public_file_server.headers = {
            "Cache-Control" => "public, max-age=#{1.hour.to_i}"
          }
        end
      RUBY

      write_file("config/environments/development.rb", dev_content)
    end

    def create_app_structure
      create_layout
      create_javascript_entry
      create_css_entry
    end

    def create_layout
      if @options[:template_engine] == "phlex"
        create_phlex_layout
      elsif @options[:template_engine] == "view_component"
        create_view_component_layout
      else
        create_erb_layout
      end
    end

    def create_erb_layout
      content = <<~ERB
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title><%= @title || 'Site' %></title>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <main>
            <%= page_content %>
          </main>

          #{importmap_script if @options[:js_bundler] == "importmap"}
          #{js_script}
        </body>
        </html>
      ERB

      write_file("app/views/layouts/application.html.erb", content)
    end

    def create_phlex_layout
      content = <<~RUBY
        # frozen_string_literal: true

        class ApplicationLayout < Phlex::HTML
          def initialize(title: "Site", **options)
            @title = title
            @options = options
          end

          def template
            html do
              head do
                meta charset: "UTF-8"
                meta name: "viewport", content: "width=device-width, initial-scale=1.0"
                title { @title }
                link rel: "stylesheet", href: "/assets/stylesheets/application.css"
              end
              body do
                main { yield }
                #{importmap_script if @options[:js_bundler] == "importmap"}
                #{js_script}
              end
            end
          end
        end
      RUBY

      write_file("app/views/layouts/application.rb", content)
    end

    def create_view_component_layout
      # Create components directory
      FileUtils.mkdir_p(@app_path.join("app/components"))

      # Create the layout component class
      component_content = <<~RUBY
        # frozen_string_literal: true

        class ApplicationLayoutComponent < ViewComponent::Base
          def initialize(title: "Site", **options)
            @title = title
            @options = options
          end

          private

          attr_reader :title, :options
        end
      RUBY

      write_file("app/components/application_layout_component.rb", component_content)

      # Create the ERB template for the layout
      template_content = <<~ERB
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title><%= title %></title>
          <link rel="stylesheet" href="/assets/stylesheets/application.css">
        </head>
        <body>
          <main>
            <%= content %>
          </main>

          #{importmap_script if @options[:js_bundler] == "importmap"}
          #{js_script}
        </body>
        </html>
      ERB

      write_file("app/components/application_layout_component.html.erb", template_content)
    end

    def importmap_script
      <<~ERB
        <script type="importmap">
        <%= importmap_json %>
        </script>
      ERB
    end

    def js_script
      case @options[:js_bundler]
      when "importmap"
        <<~ERB
          <% if @js_modules.present? %>
            <% @js_modules.each do |module_name| %>
              <script type="module">import "<%= module_name %>";</script>
            <% end %>
          <% else %>
            <script type="module">import "application";</script>
          <% end %>
        ERB
      when "esbuild", "webpack", "vite"
        '<script type="module" src="/assets/javascripts/application.js"></script>'
      else
        '<script src="/assets/javascripts/application.js"></script>'
      end
    end

    def create_javascript_entry
      case @options[:js_framework]
      when "stimulus"
        create_stimulus_entry
      when "react"
        create_react_entry
      when "vue"
        create_vue_entry
      when "alpine"
        create_alpine_entry
      else
        create_vanilla_entry
      end
    end

    def create_stimulus_entry
      # Create controllers directory
      FileUtils.mkdir_p(@app_path.join("app/javascript/controllers"))

      # Main entry - starts Application and registers controllers (standard Stimulus pattern)
      content = <<~JS
        import { Application } from "@hotwired/stimulus"

        window.Stimulus = Application.start()

        // Register your controllers here
        // import HelloController from "./controllers/hello_controller"
        // Stimulus.register("hello", HelloController)
      JS

      write_file("app/javascript/application.js", content)
    end

    def create_react_entry
      content = <<~JS
        import React from 'react'
        import { createRoot } from 'react-dom/client'

        // Import your React components
        // import App from './components/App'

        document.addEventListener('DOMContentLoaded', () => {
          const container = document.getElementById('app')
          if (container) {
            const root = createRoot(container)
            root.render(<App />)
          }
        })
      JS

      write_file("app/javascript/application.js", content)
    end

    def create_vue_entry
      content = <<~JS
        import { createApp } from 'vue'

        // Import your Vue components
        // import App from './components/App.vue'

        document.addEventListener('DOMContentLoaded', () => {
          const app = createApp(App)
          app.mount('#app')
        })
      JS

      write_file("app/javascript/application.js", content)
    end

    def create_alpine_entry
      content = <<~JS
        import Alpine from 'alpinejs'

        window.Alpine = Alpine
        Alpine.start()
      JS

      write_file("app/javascript/application.js", content)
    end

    def create_vanilla_entry
      content = <<~JS
        // Your vanilla JavaScript code here
        console.log("Application loaded")
      JS

      write_file("app/javascript/application.js", content)
    end

    def create_css_entry
      case @options[:css_framework]
      when "tailwindcss"
        write_file("app/assets/stylesheets/application.css", <<~CSS)
          @tailwind base;
          @tailwind components;
          @tailwind utilities;

          @layer base {
            html {
              scroll-behavior: smooth;
            }
          }

          @layer utilities {
            section[id] {
              scroll-margin-top: 5rem;
            }
          }
        CSS
      when "shadcn"
        write_file("app/assets/stylesheets/application.css", <<~CSS)
          @tailwind base;
          @tailwind components;
          @tailwind utilities;

          @layer base {
            :root {
              --background: 0 0% 100%;
              --foreground: 222.2 84% 4.9%;
            }
          }
        CSS
      else
        write_file("app/assets/stylesheets/application.css", <<~CSS)
          /* Your custom CSS here */
          body {
            font-family: system-ui, sans-serif;
          }
        CSS
      end
    end

    def create_build_files
      create_rakefile
      create_site_builder
    end

    def webrick_server_code
      <<~'RUBY'
        require "webrick"
        require "fileutils"
        require "static_site_builder/websocket_server"
        require "json"

        port = ENV["PORT"] || 3000
        ws_port = ENV["WS_PORT"] || 3001
        dist_dir = Pathname.new(Dir.pwd).join("dist")
        reload_file = Pathname.new(Dir.pwd).join(".reload")

        # Start WebSocket server for live reload (before first build)
        ws_server = StaticSiteBuilder::WebSocketServer.new(port: ws_port, reload_file: reload_file)
        ws_server.start

        # Build once before starting (with live reload enabled)
        ENV["LIVE_RELOAD"] = "true"
        ENV["WS_PORT"] = ws_port.to_s
        Rake::Task["build:all"].invoke

        # Check if we need to run Tailwind CSS watch (after initial build)
        tailwind_pid = nil
        package_json_path = Pathname.new(Dir.pwd).join("package.json")
        if package_json_path.exist?
          package_json = JSON.parse(File.read(package_json_path))
          if package_json.dig("scripts", "watch:css")
            puts "🎨 Starting Tailwind CSS watch mode..."
            tailwind_pid = spawn("npm", "run", "watch:css", :err => File::NULL, :out => File::NULL)
            # Touch the source file to trigger Tailwind watch to process CSS immediately
            css_source = Pathname.new(Dir.pwd).join("app", "assets", "stylesheets", "application.css")
            if css_source.exist?
              FileUtils.touch(css_source)
            end
            # Give Tailwind a moment to process CSS
            sleep 1.5
          end
        end

        puts "\n🚀 Starting development server at http://localhost:#{port}"
        puts "📡 WebSocket server at ws://localhost:#{ws_port}"
        puts "📝 Watching for changes... (Ctrl+C to stop)"
        puts "🔄 Live reload enabled - pages will auto-refresh on changes\n"

        # Simple file watcher - rebuild HTML when non-CSS files change
        # CSS changes are handled by Tailwind watch, so we skip rebuild for CSS files
        # When HTML rebuilds, it cleans dist, so we need to rebuild CSS immediately after
        watcher_code = %q{watched = ['app', 'config']; exts = ['.erb', '.rb', '.js']; mtimes = {}; loop do; changed = false; watched.each do |dir|; Dir.glob(File.join(dir, '**', '*')).each do |f|; next unless File.file?(f) && exts.any? { |e| f.end_with?(e) }; next if f.end_with?('.css'); mtime = File.mtime(f); if mtimes[f] != mtime; mtimes[f] = mtime; changed = true; end; end; end; if changed; system('rake build:html > /dev/null 2>&1 && rake build:css > /dev/null 2>&1'); end; sleep 0.5; end}
        watcher_pid = spawn("ruby", "-e", watcher_code, :err => File::NULL)

        # Start web server
        server = WEBrick::HTTPServer.new(
          Port: port,
          DocumentRoot: dist_dir.to_s,
          BindAddress: "127.0.0.1"
        )

        trap("INT") do
          puts "\n\nShutting down..."
          Process.kill("TERM", watcher_pid) if watcher_pid
          Process.kill("TERM", tailwind_pid) if tailwind_pid
          ws_server.stop
          server.shutdown
        end

        server.start
      RUBY
    end

    def rails_server_code
      <<~'RUBY'
        require "fileutils"
        require "pathname"

        # Load Rails environment
        require_relative "config/environment"

        port = ENV["PORT"] || 3000

        # Build once before starting
        ENV["LIVE_RELOAD"] = "true"
        Rake::Task["build:all"].invoke

        puts "\n🚀 Starting Rails development server at http://localhost:#{port}"
        puts "📝 EditRails available at http://localhost:#{port}/edit_rails"
        puts "📝 Watching for changes... (Ctrl+C to stop)\n"

        # Start Rails server
        exec "rails server -p #{port} -b 127.0.0.1"
      RUBY
    end

    def create_rakefile
      needs_npm = needs_npm?
      has_edit_rails = @options[:edit_rails]
      server_code = has_edit_rails ? rails_server_code : webrick_server_code

      if needs_npm
        content = <<~RUBY
          # frozen_string_literal: true

          require_relative "lib/site_builder"
          require "fileutils"
          require "pathname"

          namespace :build do
            desc "Build everything (HTML + CSS + Sitemap)"
            task :all => [:html, :css, :sitemap] do
              puts "\\n✓ Build complete!"
            end

            desc "Build JavaScript assets"
            task :assets do
              if File.exist?("package.json")
                package_json = JSON.parse(File.read("package.json"))
                build_script = package_json.dig("scripts", "build")
                # Only run if build script exists and doesn't include CSS (CSS handled separately)
                if build_script && !build_script.include?("build:css")
                  sh "npm run build"
                end
              end
            end

            desc "Compile all pages to static HTML"
            task :html => [:assets] do
              load "lib/site_builder.rb"
            end

            desc "Build CSS (runs after HTML so dist directory exists)"
            task :css do
              if File.exist?("package.json")
                package_json = JSON.parse(File.read("package.json"))
                if package_json.dig("scripts", "build:css")
                  sh "npm run build:css"
                end
              elsif File.exist?("tailwind.config.js")
                # Build CSS even if no package.json (standalone Tailwind)
                if system("which tailwindcss > /dev/null 2>&1")
                  FileUtils.mkdir_p("dist/assets/stylesheets")
                  sh "tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --minify"
                end
              end
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

            desc "Generate sitemap from PageHelpers::PAGES"
            task :sitemap do
              require './config/sitemap'
            end
          end

          namespace :dev do
            desc "Start development server with auto-rebuild and live reload"
            task :server do
              #{server_code}
            end
          end

          task default: "build:all"
        RUBY
      else
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

            desc "Generate sitemap from PageHelpers::PAGES"
            task :sitemap do
              require './config/sitemap'
            end
          end

          namespace :dev do
            desc "Start development server with auto-rebuild and live reload"
            task :server do
              #{server_code}
            end
          end

          task default: "build:all"
        RUBY
      end

      write_file("Rakefile", content)
    end

    def create_site_builder
      # Generated sites use the static-site-builder gem
      # This file just configures it for the chosen stack
      phlex_require = @options[:template_engine] == "phlex" ? 'require "phlex-rails"' : ""
      view_component_require = @options[:template_engine] == "view_component" ? 'require "view_component"' : ""
      importmap_require = @options[:js_bundler] == "importmap" ? 'require "importmap-rails"' : ""
      importmap_config_line = @options[:js_bundler] == "importmap" ? importmap_config : ""

      content = <<~RUBY
        # frozen_string_literal: true

        require "static_site_builder"
        #{phlex_require}
        #{view_component_require}
        #{importmap_require}

        # Configure the builder for your stack
        builder = StaticSiteBuilder::Builder.new(
          root: Dir.pwd,
          template_engine: "#{@options[:template_engine]}",
          js_bundler: "#{@options[:js_bundler]}",
          #{importmap_config_line}
        )

        # Build the site
        builder.build
      RUBY

      write_file("lib/site_builder.rb", content)
    end

    def importmap_config
      <<~RUBY
        importmap_config: "config/importmap.rb",
      RUBY
    end

    def create_example_pages
      if @options[:template_engine] == "phlex"
        create_phlex_example
      elsif @options[:template_engine] == "view_component"
        create_view_component_example
      else
        create_erb_example
      end
    end

    def create_erb_example
      content = <<~ERB
        ---
        title: Home Page
        js: application
        ---

        <h1>Welcome</h1>
        <p>This is your generated static site.</p>
      ERB

      write_file("app/views/pages/index.html.erb", content)
    end

    def create_phlex_example
      content = <<~RUBY
        # frozen_string_literal: true

        class IndexPage < Phlex::HTML
          def template
            h1 { "Welcome" }
            p { "This is your generated static site." }
          end
        end
      RUBY

      write_file("app/views/pages/index.rb", content)
    end

    def create_view_component_example
      # Create components directory
      FileUtils.mkdir_p(@app_path.join("app/components"))

      # Create the page component
      component_content = <<~RUBY
        # frozen_string_literal: true

        class IndexPageComponent < ViewComponent::Base
          def initialize(title: "Welcome")
            @title = title
          end

          private

          attr_reader :title
        end
      RUBY

      write_file("app/views/pages/index_component.rb", component_content)

      # Create the ERB template for the component
      template_content = <<~ERB
        <h1><%= title %></h1>
        <p>This is your generated static site.</p>
      ERB

      write_file("app/views/pages/index_component.html.erb", template_content)
    end

    def create_readme
      content = <<~MD
        # #{@app_name}

        Generated static site using:
        - Template: #{@options[:template_engine]}
        - JS Bundler: #{@options[:js_bundler]}
        - CSS: #{@options[:css_framework]}
        - JS Framework: #{@options[:js_framework]}

        ## Setup

        ```bash
        bundle install
        #{'npm install' if needs_npm?}
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
      MD

      write_file("README.md", content)
    end

    def build_script
      js_build = case @options[:js_bundler]
      when "esbuild"
        "node esbuild.config.js"
      when "webpack"
        "webpack --mode production"
      when "vite"
        "vite build"
      else
        nil
      end

      css_build = if needs_css_build?
        "npm run build:css"
      else
        nil
      end

      builds = [js_build, css_build].compact
      if builds.empty?
        "echo 'No bundling needed'"
      else
        builds.join(" && ")
      end
    end

    def css_build_script
      if @options[:css_framework] == "tailwindcss" || @options[:css_framework] == "shadcn"
        "tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --minify"
      end
    end

    def css_watch_script
      if @options[:css_framework] == "tailwindcss" || @options[:css_framework] == "shadcn"
        "tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --watch"
      end
    end

    def needs_npm?
      @options[:js_bundler] != "none" ||
        @options[:css_framework] == "tailwindcss" ||
        @options[:css_framework] == "shadcn" ||
        @options[:js_framework] == "react" ||
        @options[:js_framework] == "vue" ||
        @options[:js_framework] == "alpine"
    end

    def needs_css_build?
      @options[:css_framework] == "tailwindcss" || @options[:css_framework] == "shadcn"
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
