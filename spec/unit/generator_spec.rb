# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Generator do
  describe "#initialize" do
    it "sets default options when none provided" do
      generator = described_class.new("test-app")

      expect(generator.instance_variable_get(:@app_name)).to eq("test-app")
      expect(generator.instance_variable_get(:@options)[:template_engine]).to eq("erb")
      expect(generator.instance_variable_get(:@options)[:js_bundler]).to eq("importmap")
      expect(generator.instance_variable_get(:@options)[:css_framework]).to eq("tailwindcss")
      expect(generator.instance_variable_get(:@options)[:js_framework]).to eq("stimulus")
    end

    it "accepts custom options" do
      options = {
        template_engine: "phlex",
        js_bundler: "esbuild",
        css_framework: "plain",
        js_framework: "react"
      }

      generator = described_class.new("test-app", options)

      expect(generator.instance_variable_get(:@options)[:template_engine]).to eq("phlex")
      expect(generator.instance_variable_get(:@options)[:js_bundler]).to eq("esbuild")
      expect(generator.instance_variable_get(:@options)[:css_framework]).to eq("plain")
      expect(generator.instance_variable_get(:@options)[:js_framework]).to eq("react")
    end

    it "creates app_path as Pathname" do
      generator = described_class.new("test-app")
      app_path = generator.instance_variable_get(:@app_path)

      expect(app_path).to be_a(Pathname)
      expect(app_path.to_s).to include("test-app")
    end
  end

  describe "#generate" do
    let(:app_name) { "test-site" }
    let(:app_path) { @tmp_dir.join(app_name) }

    it "creates directory structure" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      expect(app_path.join("app/views/layouts")).to exist
      expect(app_path.join("app/views/pages")).to exist
      expect(app_path.join("app/javascript")).to exist
      expect(app_path.join("app/assets/stylesheets")).to exist
      expect(app_path.join("config")).to exist
      expect(app_path.join("lib")).to exist
      expect(app_path.join("public")).to exist
    end

    it "creates Gemfile" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      gemfile = app_path.join("Gemfile")
      expect(gemfile).to exist

      content = File.read(gemfile)
      expect(content).to include("static-site-builder")
      expect(content).to include("rake")
    end

    it "includes importmap-rails in Gemfile when using importmap" do
      generator = described_class.new(app_path.to_s, js_bundler: "importmap")
      generator.generate

      gemfile = app_path.join("Gemfile")
      content = File.read(gemfile)
      expect(content).to include("importmap-rails")
    end

    it "includes phlex-rails in Gemfile when using phlex" do
      generator = described_class.new(app_path.to_s, template_engine: "phlex")
      generator.generate

      gemfile = app_path.join("Gemfile")
      content = File.read(gemfile)
      expect(content).to include("phlex-rails")
    end

    it "creates package.json when npm is needed" do
      generator = described_class.new(app_path.to_s, js_bundler: "esbuild")
      generator.generate

      package_json = app_path.join("package.json")
      expect(package_json).to exist

      content = JSON.parse(File.read(package_json))
      expect(content["devDependencies"]).to have_key("esbuild")
    end

    it "does not create package.json when npm is not needed" do
      generator = described_class.new(app_path.to_s, js_bundler: "none", css_framework: "plain", js_framework: "vanilla")
      generator.generate

      package_json = app_path.join("package.json")
      expect(package_json).not_to exist
    end

    it "creates importmap config when using importmap" do
      generator = described_class.new(app_path.to_s, js_bundler: "importmap")
      generator.generate

      importmap_config = app_path.join("config/importmap.rb")
      expect(importmap_config).to exist

      content = File.read(importmap_config)
      expect(content).to include("pin")
    end

    it "creates tailwind config when using tailwindcss" do
      generator = described_class.new(app_path.to_s, css_framework: "tailwindcss")
      generator.generate

      tailwind_config = app_path.join("tailwind.config.js")
      expect(tailwind_config).to exist

      postcss_config = app_path.join("postcss.config.js")
      expect(postcss_config).to exist
    end

    it "creates CSS file with Tailwind directives and custom layers for tailwindcss" do
      generator = described_class.new(app_path.to_s, css_framework: "tailwindcss")
      generator.generate

      css_file = app_path.join("app/assets/stylesheets/application.css")
      expect(css_file).to exist

      content = File.read(css_file)
      expect(content).to include("@tailwind base")
      expect(content).to include("@tailwind components")
      expect(content).to include("@tailwind utilities")
      expect(content).to include("@layer base")
      expect(content).to include("scroll-behavior: smooth")
      expect(content).to include("@layer utilities")
      expect(content).to include("scroll-margin-top: 5rem")
    end

    it "creates esbuild config when using esbuild" do
      generator = described_class.new(app_path.to_s, js_bundler: "esbuild")
      generator.generate

      esbuild_config = app_path.join("esbuild.config.js")
      expect(esbuild_config).to exist
    end

    it "creates ERB layout when using erb" do
      generator = described_class.new(app_path.to_s, template_engine: "erb")
      generator.generate

      layout = app_path.join("app/views/layouts/application.html.erb")
      expect(layout).to exist

      content = File.read(layout)
      expect(content).to include("<!DOCTYPE html>")
      expect(content).to include("<%= page_content %>")
    end

    it "creates Phlex layout when using phlex" do
      generator = described_class.new(app_path.to_s, template_engine: "phlex")
      generator.generate

      layout = app_path.join("app/views/layouts/application.rb")
      expect(layout).to exist

      content = File.read(layout)
      expect(content).to include("ApplicationLayout")
      expect(content).to include("Phlex::HTML")
    end

    it "creates example ERB page" do
      generator = described_class.new(app_path.to_s, template_engine: "erb")
      generator.generate

      page = app_path.join("app/views/pages/index.html.erb")
      expect(page).to exist

      content = File.read(page)
      expect(content).to include("Welcome")
    end

    it "creates example Phlex page" do
      generator = described_class.new(app_path.to_s, template_engine: "phlex")
      generator.generate

      page = app_path.join("app/views/pages/index.rb")
      expect(page).to exist

      content = File.read(page)
      expect(content).to include("IndexPage")
    end

    it "creates Stimulus entry when using stimulus" do
      generator = described_class.new(app_path.to_s, js_framework: "stimulus")
      generator.generate

      js_file = app_path.join("app/javascript/application.js")
      expect(js_file).to exist

      content = File.read(js_file)
      expect(content).to include("@hotwired/stimulus")
      expect(content).to include("Application.start()")
      expect(content).to include("controllers")

      controllers_dir = app_path.join("app/javascript/controllers")
      expect(controllers_dir).to exist
    end

    it "creates React entry when using react" do
      generator = described_class.new(app_path.to_s, js_framework: "react")
      generator.generate

      js_file = app_path.join("app/javascript/application.js")
      expect(js_file).to exist

      content = File.read(js_file)
      expect(content).to include("react")
    end

    it "creates Rakefile" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      rakefile = app_path.join("Rakefile")
      expect(rakefile).to exist

      content = File.read(rakefile)
      expect(content).to include("namespace :build")
      expect(content).to include("task :html")
      expect(content).to include("task :all")
      expect(content).to include("namespace :dev")
      expect(content).to include("task :server")
    end

    it "creates site_builder.rb" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      site_builder = app_path.join("lib/site_builder.rb")
      expect(site_builder).to exist

      content = File.read(site_builder)
      expect(content).to include("StaticSiteBuilder::Builder")
    end

    it "creates README.md" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      readme = app_path.join("README.md")
      expect(readme).to exist

      content = File.read(readme)
      expect(content).to include(app_name)
    end
  end
end
