# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "#initialize" do
    it "sets default root to current directory" do
      builder = described_class.new
      expect(builder.instance_variable_get(:@root)).to eq(Pathname.new(Dir.pwd))
    end

    it "accepts custom root directory" do
      root_path = @tmp_dir.join("custom-root")
      builder = described_class.new(root: root_path.to_s)
      expect(builder.instance_variable_get(:@root)).to eq(root_path)
    end

    it "sets default template_engine to erb" do
      builder = described_class.new
      expect(builder.instance_variable_get(:@template_engine)).to eq("erb")
    end

    it "sets default js_bundler to importmap" do
      builder = described_class.new
      expect(builder.instance_variable_get(:@js_bundler)).to eq("importmap")
    end

    it "accepts custom options" do
      builder = described_class.new(
        root: @tmp_dir.to_s,
        template_engine: "phlex",
        js_bundler: "esbuild"
      )

      expect(builder.instance_variable_get(:@template_engine)).to eq("phlex")
      expect(builder.instance_variable_get(:@js_bundler)).to eq("esbuild")
    end

    it "creates SimpleImportMap when importmap-rails is not available" do
      builder = described_class.new(js_bundler: "importmap")
      importmap = builder.instance_variable_get(:@importmap)

      expect(importmap).to be_a(StaticSiteBuilder::Builder::SimpleImportMap)
    end
  end

  describe "#build" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "creates dist directory" do
      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      expect(site_root.join("dist")).to exist
      expect(site_root.join("dist")).to be_directory
    end

    it "cleans dist directory if it exists" do
      dist_dir = site_root.join("dist")
      FileUtils.mkdir_p(dist_dir)
      File.write(dist_dir.join("old-file.txt"), "content")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      expect(dist_dir.join("old-file.txt")).not_to exist
    end

    it "copies JavaScript assets" do
      create_test_js_file(site_root.to_s, "application.js", "console.log('test');")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      dist_js = site_root.join("dist/assets/javascripts/application.js")
      expect(dist_js).to exist
      expect(File.read(dist_js)).to include("console.log('test')")
    end

    it "copies CSS assets" do
      create_test_css_file(site_root.to_s, "application.css", "body { margin: 0; }")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      dist_css = site_root.join("dist/assets/stylesheets/application.css")
      expect(dist_css).to exist
      expect(File.read(dist_css)).to include("body { margin: 0; }")
    end

    it "copies vendor JavaScript files" do
      vendor_dir = site_root.join("vendor/javascript")
      FileUtils.mkdir_p(vendor_dir)
      File.write(vendor_dir.join("library.js"), "library code")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      dist_vendor = site_root.join("dist/assets/javascripts/vendor/library.js")
      expect(dist_vendor).to exist
    end

    it "copies static files from public directory" do
      public_dir = site_root.join("public")
      FileUtils.mkdir_p(public_dir)
      File.write(public_dir.join("robots.txt"), "User-agent: *")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      dist_robots = site_root.join("dist/robots.txt")
      expect(dist_robots).to exist
      expect(File.read(dist_robots)).to include("User-agent")
    end
  end
end
