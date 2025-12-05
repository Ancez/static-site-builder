# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Generator do
  describe "#initialize" do
    it "sets default options when none provided" do
      generator = described_class.new("test-app")

      expect(generator.instance_variable_get(:@app_name)).to eq("test-app")
      expect(generator.instance_variable_get(:@options)[:template_engine]).to eq("erb")
    end

    it "accepts custom options" do
      options = {
        template_engine: "erb"
      }

      generator = described_class.new("test-app", options)

      expect(generator.instance_variable_get(:@options)[:template_engine]).to eq("erb")
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

    it "does not create package.json" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      package_json = app_path.join("package.json")
      expect(package_json).not_to exist
    end


    it "creates CSS file" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      css_file = app_path.join("app/assets/stylesheets/application.css")
      expect(css_file).to exist

      content = File.read(css_file)
      expect(content).to include("font-family")
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

    it "creates example ERB page" do
      generator = described_class.new(app_path.to_s, template_engine: "erb")
      generator.generate

      page = app_path.join("app/views/pages/index.html.erb")
      expect(page).to exist

      content = File.read(page)
      expect(content).to include("Welcome")
    end

    it "creates JavaScript entry file" do
      generator = described_class.new(app_path.to_s)
      generator.generate

      js_file = app_path.join("app/javascript/application.js")
      expect(js_file).to exist

      content = File.read(js_file)
      expect(content).to include("Application loaded")
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
