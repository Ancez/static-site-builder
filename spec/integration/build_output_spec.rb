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
      create_test_layout(site_root.to_s, "application.html.erb", "<!DOCTYPE html><html><body><%= yield %></body></html>")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s)
      builder.build

      html_file = site_root.join("dist/index.html")
      expect(html_file).to exist

      content = File.read(html_file)
      expect(content).to include("<!DOCTYPE html>")
      expect(content).to include("<h1>Test</h1>")
    end

    it "includes meta tags title in output" do
      page_content = <<~ERB
        <% set_meta_tags title: 'My Page', description: 'A test page' %>
        <h1>Content</h1>
      ERB

      create_test_page(site_root.to_s, "page.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><head><%= display_meta_tags site: 'Site', title: 'Site' %></head><body><%= yield %></body></html>")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s)
      builder.build

      html_file = site_root.join("dist/page.html")
      content = File.read(html_file)
      expect(content).to include("My Page")
    end
  end

  describe "Asset paths" do
    it "copies JavaScript files to correct location" do
      create_test_js_file(site_root.to_s, "application.js", "console.log('test');")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s)
      builder.build

      js_file = site_root.join("dist/assets/javascripts/application.js")
      expect(js_file).to exist
    end

    it "copies CSS files to correct location" do
      create_test_css_file(site_root.to_s, "application.css", "body { margin: 0; }")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s)
      builder.build

      css_file = site_root.join("dist/assets/stylesheets/application.css")
      expect(css_file).to exist
    end

    it "maintains directory structure for nested assets" do
      js_dir = site_root.join("app/javascript/nested")
      FileUtils.mkdir_p(js_dir)
      File.write(js_dir.join("module.js"), "export default {}")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s)
      builder.build

      nested_file = site_root.join("dist/assets/javascripts/nested/module.js")
      expect(nested_file).to exist
    end
  end
end
