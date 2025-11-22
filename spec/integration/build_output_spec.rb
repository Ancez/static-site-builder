# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Build output validation" do
  let(:site_root) { @tmp_dir.join("test-site") }

  before do
    create_test_site_structure(site_root.to_s)
  end

  describe "HTML output" do
    it "generates valid HTML" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Test</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<!DOCTYPE html><html><body><%= page_content %></body></html>")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      html_file = site_root.join("dist/index.html")
      expect(html_file).to exist

      content = File.read(html_file)
      expect(content).to include("<!DOCTYPE html>")
      expect(content).to include("<h1>Test</h1>")
    end

    it "includes PageHelpers title in output" do
      # Create page_helpers.rb with metadata
      FileUtils.mkdir_p(site_root.join("lib"))
      page_helpers_content = <<~RUBY
        module PageHelpers
          PAGES = {
            '/page' => {
              title: 'My Page',
              description: 'A test page'
            }
          }.freeze
        end
      RUBY
      File.write(site_root.join("lib/page_helpers.rb"), page_helpers_content)

      page_content = <<~ERB
        <h1>Content</h1>
      ERB

      create_test_page(site_root.to_s, "page.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><head><title><%= @title || 'Site' %></title></head><body><%= page_content %></body></html>")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      html_file = site_root.join("dist/page.html")
      content = File.read(html_file)
      expect(content).to include("My Page")
    end
  end

  describe "Importmap JSON output" do
    it "generates valid JSON" do
      create_importmap_config(site_root.to_s, <<~RUBY)
        pin "application", preload: true
      RUBY

      create_test_js_file(site_root.to_s, "application.js", "test")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "importmap")
      builder.build

      importmap_file = site_root.join("dist/assets/importmap.json")
      expect(importmap_file).to exist

      expect { JSON.parse(File.read(importmap_file)) }.not_to raise_error
    end

    it "includes correct import paths" do
      create_importmap_config(site_root.to_s, <<~RUBY)
        pin "application", to: "application.js", preload: true
      RUBY

      create_test_js_file(site_root.to_s, "application.js", "test")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "importmap")
      builder.build

      importmap = JSON.parse(File.read(site_root.join("dist/assets/importmap.json")))
      expect(importmap["imports"]["application"]).to include("/assets/javascripts/application.js")
    end
  end

  describe "Asset paths" do
    it "copies JavaScript files to correct location" do
      create_test_js_file(site_root.to_s, "application.js", "console.log('test');")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      js_file = site_root.join("dist/assets/javascripts/application.js")
      expect(js_file).to exist
    end

    it "copies CSS files to correct location" do
      create_test_css_file(site_root.to_s, "application.css", "body { margin: 0; }")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      css_file = site_root.join("dist/assets/stylesheets/application.css")
      expect(css_file).to exist
    end

    it "maintains directory structure for nested assets" do
      js_dir = site_root.join("app/javascript/nested")
      FileUtils.mkdir_p(js_dir)
      File.write(js_dir.join("module.js"), "export default {}")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      nested_file = site_root.join("dist/assets/javascripts/nested/module.js")
      expect(nested_file).to exist
    end
  end
end
