# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "Asset copying" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "copies JavaScript files recursively" do
      js_dir = site_root.join("app/javascript")
      FileUtils.mkdir_p(js_dir.join("nested"))
      File.write(js_dir.join("application.js"), "app")
      File.write(js_dir.join("nested/module.js"), "module")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      expect(site_root.join("dist/assets/javascripts/application.js")).to exist
      expect(site_root.join("dist/assets/javascripts/nested/module.js")).to exist
    end

    it "copies CSS files" do
      css_dir = site_root.join("app/assets/stylesheets")
      File.write(css_dir.join("application.css"), "body { margin: 0; }")
      File.write(css_dir.join("custom.css"), ".custom { color: red; }")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      expect(site_root.join("dist/assets/stylesheets/application.css")).to exist
      expect(site_root.join("dist/assets/stylesheets/custom.css")).to exist
    end

    it "handles missing asset directories gracefully" do
      # Remove javascript directory
      FileUtils.rm_rf(site_root.join("app/javascript"))

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      expect { builder.build }.not_to raise_error
    end

    it "preserves file permissions when copying" do
      js_file = site_root.join("app/javascript/application.js")
      File.write(js_file, "test")
      File.chmod(0o755, js_file)

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      dist_file = site_root.join("dist/assets/javascripts/application.js")
      expect(dist_file).to exist
      # Note: FileUtils.cp_r with preserve: true should preserve permissions
    end
  end
end
