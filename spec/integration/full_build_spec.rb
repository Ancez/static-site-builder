# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Full build integration" do
  let(:site_root) { @tmp_dir.join("generated-site") }

  describe "ERB" do
    before do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate
    end

    it "generates valid project structure" do
      expect(site_root.join("Gemfile")).to exist
      expect(site_root.join("app/views/index.html.erb")).to exist
    end

    it "builds successfully" do
      # Create a simple page for testing
      page_content = <<~ERB
        <h1>Test</h1>
      ERB

      File.write(site_root.join("app/views/index.html.erb"), page_content)

      # Create layout
      layout_content = <<~ERB
        <!DOCTYPE html>
        <html>
        <head><title>Site</title></head>
        <body><%= yield %></body>
        </html>
      ERB

      FileUtils.mkdir_p(site_root.join("app/views/layouts"))
      File.write(site_root.join("app/views/layouts/application.html.erb"), layout_content)

      # Create minimal JS and CSS
      FileUtils.mkdir_p(site_root.join("app/javascript"))
      File.write(site_root.join("app/javascript/application.js"), "console.log('test');")

      FileUtils.mkdir_p(site_root.join("app/assets/stylesheets"))
      File.write(site_root.join("app/assets/stylesheets/application.css"), "body { margin: 0; }")

      if Object.const_defined?(:SiteBuilder)
        Object.send(:remove_const, :SiteBuilder)
      end

      load site_root.join("lib/site_builder.rb")

      builder = SiteBuilder::Builder.new(root: site_root.to_s)

      expect { builder.build }.not_to raise_error

      expect(site_root.join("dist/index.html")).to exist
      expect(site_root.join("dist/assets/javascripts/application.js")).to exist
      expect(site_root.join("dist/assets/stylesheets/application.css")).to exist
    end
  end

  describe "ERB + None + Vanilla + Plain CSS" do
    before do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate
    end

    it "generates minimal project structure" do
      expect(site_root.join("Gemfile")).to exist
      expect(site_root.join("app/views/index.html.erb")).to exist
      expect(site_root.join("package.json")).not_to exist
    end

    it "builds successfully without npm dependencies" do
      if Object.const_defined?(:SiteBuilder)
        Object.send(:remove_const, :SiteBuilder)
      end

      load site_root.join("lib/site_builder.rb")

      builder = SiteBuilder::Builder.new(root: site_root.to_s)

      expect { builder.build }.not_to raise_error
      expect(site_root.join("dist/index.html")).to exist
    end
  end
end
