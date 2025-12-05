# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Generated site structure" do
  let(:site_root) { @tmp_dir.join("test-site") }

  describe "Gemfile validation" do
    it "generates valid Gemfile syntax" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      gemfile = site_root.join("Gemfile")
      expect(gemfile).to exist

      # Try to parse it as Ruby (basic syntax check)
      expect { eval(File.read(gemfile)) }.not_to raise_error(SyntaxError)
    end

    it "includes required dependencies" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      gemfile_content = File.read(site_root.join("Gemfile"))
      expect(gemfile_content).to include("static-site-builder")
      expect(gemfile_content).to include("rake")
    end
  end


  describe "Rakefile validation" do
    it "generates valid Rakefile" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      rakefile = site_root.join("Rakefile")
      expect(rakefile).to exist

      # Basic syntax check
      expect { eval(File.read(rakefile)) }.not_to raise_error(SyntaxError)
    end

    it "includes build:html task" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      rakefile_content = File.read(site_root.join("Rakefile"))
      expect(rakefile_content).to include("namespace :build")
      expect(rakefile_content).to include("task :html")
      expect(rakefile_content).to include("task :all")
      expect(rakefile_content).to include("namespace :dev")
      expect(rakefile_content).to include("task :server")
    end
  end

  describe "site_builder.rb validation" do
    it "generates valid Ruby file" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      site_builder = site_root.join("lib/site_builder.rb")
      expect(site_builder).to exist

      # Basic syntax check
      expect { eval(File.read(site_builder)) }.not_to raise_error(SyntaxError)
    end

    it "requires static-site-builder gem" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      site_builder_content = File.read(site_root.join("lib/site_builder.rb"))
      expect(site_builder_content).to include("static_site_builder")
      expect(site_builder_content).to include("StaticSiteBuilder::Builder")
    end
  end
end
