# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "ERB compilation" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "compiles ERB page without frontmatter" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Hello</h1>")
    end

    it "parses frontmatter correctly" do
      page_content = <<~ERB
        ---
        title: Test Page
        layout: custom
        js: application, controllers/test
        ---

        <h1>Content</h1>
      ERB

      create_test_page(site_root.to_s, "test.html.erb", page_content)
      create_test_layout(site_root.to_s, "custom.html.erb", "<html><head><title><%= frontmatter['title'] %></title></head><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/test.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("Test Page")
      expect(content).to include("<h1>Content</h1>")
    end

    it "uses default layout when not specified" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<!DOCTYPE html>")
      expect(content).to include("<h1>Hello</h1>")
    end

    it "compiles nested pages" do
      nested_dir = site_root.join("app/views/pages/blog")
      FileUtils.mkdir_p(nested_dir)
      File.write(nested_dir.join("index.html.erb"), "<h1>Blog</h1>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/blog/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Blog</h1>")
    end

    it "handles js_modules from frontmatter" do
      page_content = <<~ERB
        ---
        js: application, controllers/test
        ---

        <h1>Test</h1>
      ERB

      create_test_page(site_root.to_s, "test.html.erb", page_content)

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/test.html")
      content = File.read(output)

      # Should include script tags for the modules
      expect(content).to include("application")
    end

    it "annotates template file names when enabled" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none", annotate_template_file_names: true)
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)

      # Should include annotations for both page and layout
      expect(content).to include("<!-- BEGIN app/views/pages/index.html.erb -->")
      expect(content).to include("<!-- END app/views/pages/index.html.erb -->")
      expect(content).to include("<!-- BEGIN app/views/layouts/application.html.erb -->")
      expect(content).to include("<!-- END app/views/layouts/application.html.erb -->")
    end

    it "does not annotate template file names when disabled" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none", annotate_template_file_names: false)
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)

      # Should not include annotations
      expect(content).not_to include("<!-- BEGIN")
      expect(content).not_to include("<!-- END")
    end

    it "auto-enables annotations when LIVE_RELOAD is set" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      ENV["LIVE_RELOAD"] = "true"
      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)

      # Should include annotations
      expect(content).to include("<!-- BEGIN app/views/pages/index.html.erb -->")
    ensure
      ENV.delete("LIVE_RELOAD")
    end
  end
end
