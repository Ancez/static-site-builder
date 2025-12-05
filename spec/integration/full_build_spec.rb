# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Full build integration" do
  let(:site_root) { @tmp_dir.join("generated-site") }

  describe "ERB" do
    before do
      generator = StaticSiteBuilder::Generator.new(
        site_root.to_s,
        
      )
      generator.generate
    end

    it "generates valid project structure" do
      expect(site_root.join("Gemfile")).to exist
      expect(site_root.join("app/views/pages/index.html.erb")).to exist
    end

    it "builds successfully" do
      # Create page_helpers.rb with metadata
      FileUtils.mkdir_p(site_root.join("lib"))
      page_helpers_content = <<~RUBY
        module PageHelpers
          PAGES = {
            '/' => {
              title: 'Test Page',
              description: 'A test page'
            }
          }.freeze
        end
      RUBY
      File.write(site_root.join("lib/page_helpers.rb"), page_helpers_content)

      # Create a simple page for testing
      page_content = <<~ERB
        <h1>Test</h1>
      ERB

      File.write(site_root.join("app/views/pages/index.html.erb"), page_content)

      # Create layout
      layout_content = <<~ERB
        <!DOCTYPE html>
        <html>
        <head><title><%= @title || 'Site' %></title></head>
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

      builder = StaticSiteBuilder::Builder.new(
        root: site_root.to_s,
        
      )

      expect { builder.build }.not_to raise_error

      expect(site_root.join("dist/index.html")).to exist
      expect(site_root.join("dist/assets/javascripts/application.js")).to exist
      expect(site_root.join("dist/assets/stylesheets")).to exist
    end
  end

  describe "ERB + None + Vanilla + Plain CSS" do
    before do
      generator = StaticSiteBuilder::Generator.new(
        site_root.to_s,
          
        )
      generator.generate
    end

    it "generates minimal project structure" do
      expect(site_root.join("Gemfile")).to exist
      expect(site_root.join("app/views/pages/index.html.erb")).to exist
      expect(site_root.join("package.json")).not_to exist
    end

    it "builds successfully without npm dependencies" do
      builder = StaticSiteBuilder::Builder.new(
        root: site_root.to_s,
        
      )

      expect { builder.build }.not_to raise_error
      expect(site_root.join("dist/index.html")).to exist
    end
  end
end
