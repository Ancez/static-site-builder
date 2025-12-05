# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Complete workflow" do
  let(:site_root) { @tmp_dir.join("workflow-site") }

  describe "ERB workflow" do
    it "generates and builds successfully" do
      # Generate site
      generator = StaticSiteBuilder::Generator.new(
        site_root.to_s,
        
      )
      generator.generate

      # Verify generation
      expect(site_root.join("Gemfile")).to exist
      expect(site_root.join("app/views/pages/index.html.erb")).to exist

      # Build site
      builder = StaticSiteBuilder::Builder.new(
        root: site_root.to_s,
        
      )
      builder.build

      # Verify build output
      expect(site_root.join("dist/index.html")).to exist
      expect(site_root.join("dist/assets/javascripts/application.js")).to exist
      expect(site_root.join("dist/assets/stylesheets")).to exist
    end
  end

  describe "ERB + None + Vanilla + Plain CSS workflow" do
    it "generates and builds successfully" do
      # Generate site
      generator = StaticSiteBuilder::Generator.new(
        site_root.to_s,
        
      )
      generator.generate

      # Verify generation
      expect(site_root.join("Gemfile")).to exist
      expect(site_root.join("app/views/pages/index.html.erb")).to exist
      expect(site_root.join("package.json")).not_to exist

      # Build site
      builder = StaticSiteBuilder::Builder.new(
        root: site_root.to_s,
        
        
      )
      builder.build

      # Verify build output
      expect(site_root.join("dist/index.html")).to exist
      expect(site_root.join("dist/assets/javascripts/application.js")).to exist
      expect(site_root.join("dist/assets/stylesheets/application.css")).to exist
    end
  end

  describe "Multiple pages workflow" do
    it "compiles all pages correctly" do
      generator = StaticSiteBuilder::Generator.new(site_root.to_s)
      generator.generate

      # Add additional pages
      pages_dir = site_root.join("app/views/pages")
      File.write(pages_dir.join("about.html.erb"), "<h1>About</h1>")
      File.write(pages_dir.join("contact.html.erb"), "<h1>Contact</h1>")

      builder = StaticSiteBuilder::Builder.new(root: site_root.to_s)
      builder.build

      expect(site_root.join("dist/index.html")).to exist
      expect(site_root.join("dist/about.html")).to exist
      expect(site_root.join("dist/contact.html")).to exist
    end
  end
end
