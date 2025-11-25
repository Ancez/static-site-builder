# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Generator do
  describe "stack combinations" do
    let(:app_path) { @tmp_dir.join("test-site") }

    # Test all valid combinations
    StaticSiteBuilder::Generator::TEMPLATE_ENGINES.each do |template|
      StaticSiteBuilder::Generator::JS_BUNDLERS.each do |bundler|
        StaticSiteBuilder::Generator::CSS_FRAMEWORKS.each do |css|
          StaticSiteBuilder::Generator::JS_FRAMEWORKS.each do |js|
            context "with #{template} + #{bundler} + #{css} + #{js}" do
              it "generates valid project structure" do
                options = {
                  template_engine: template,
                  js_bundler: bundler,
                  css_framework: css,
                  js_framework: js
                }

                generator = described_class.new(app_path.to_s, options)
                generator.generate

                # Verify core structure exists
                expect(app_path.join("app/views/layouts")).to exist
                expect(app_path.join("app/views/pages")).to exist
                expect(app_path.join("app/javascript")).to exist
                expect(app_path.join("Gemfile")).to exist
                expect(app_path.join("lib/site_builder.rb")).to exist

                # Verify template-specific files
                expect(app_path.join("app/views/layouts/application.html.erb")).to exist
                expect(app_path.join("app/views/pages/index.html.erb")).to exist

                # Verify bundler-specific configs
                if bundler == "importmap"
                  expect(app_path.join("config/importmap.rb")).to exist
                elsif bundler == "esbuild"
                  expect(app_path.join("esbuild.config.js")).to exist
                elsif bundler == "webpack"
                  expect(app_path.join("webpack.config.js")).to exist
                elsif bundler == "vite"
                  expect(app_path.join("vite.config.js")).to exist
                end

                # Verify CSS-specific configs
                if css == "tailwindcss" || css == "shadcn"
                  expect(app_path.join("tailwind.config.js")).to exist
                  expect(app_path.join("postcss.config.js")).to exist
                end

                # Verify npm files when needed
                needs_npm = bundler != "none" || css == "tailwindcss" || css == "shadcn" ||
                           js == "react" || js == "vue" || js == "alpine"

                if needs_npm
                  expect(app_path.join("package.json")).to exist
                end
              end

              it "generates valid Gemfile" do
                options = {
                  template_engine: template,
                  js_bundler: bundler,
                  css_framework: css,
                  js_framework: js
                }

                generator = described_class.new(app_path.to_s, options)
                generator.generate

                gemfile = app_path.join("Gemfile")
                content = File.read(gemfile)

                expect(content).to include("static-site-builder")
                expect(content).to include("rake")

                if bundler == "importmap"
                  expect(content).to include("importmap-rails")
                end
              end
            end
          end
        end
      end
    end
  end
end
