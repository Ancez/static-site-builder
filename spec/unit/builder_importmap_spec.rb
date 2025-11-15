# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "Importmap generation" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "generates importmap.json when using importmap bundler" do
      create_importmap_config(site_root.to_s, <<~RUBY)
        pin "application", preload: true
        pin_all_from "app/javascript", under: ""
      RUBY

      create_test_js_file(site_root.to_s, "application.js", "console.log('test');")

      builder = described_class.new(root: site_root.to_s, js_bundler: "importmap")
      builder.build

      importmap_json = site_root.join("dist/assets/importmap.json")
      expect(importmap_json).to exist

      content = JSON.parse(File.read(importmap_json))
      expect(content).to have_key("imports")
    end

    it "does not generate importmap.json when not using importmap" do
      builder = described_class.new(root: site_root.to_s, js_bundler: "esbuild")
      builder.build

      importmap_json = site_root.join("dist/assets/importmap.json")
      expect(importmap_json).not_to exist
    end

    it "resolves asset paths correctly" do
      create_importmap_config(site_root.to_s, <<~RUBY)
        pin "application", to: "application.js", preload: true
      RUBY

      create_test_js_file(site_root.to_s, "application.js", "test")

      builder = described_class.new(root: site_root.to_s, js_bundler: "importmap")
      builder.build

      importmap_json = site_root.join("dist/assets/importmap.json")
      content = JSON.parse(File.read(importmap_json))

      expect(content["imports"]["application"]).to include("/assets/javascripts/application.js")
    end

    it "handles pin_all_from correctly" do
      controllers_dir = site_root.join("app/javascript/controllers")
      FileUtils.mkdir_p(controllers_dir)
      File.write(controllers_dir.join("test_controller.js"), "export default class {}")

      create_importmap_config(site_root.to_s, <<~RUBY)
        pin_all_from "app/javascript/controllers", under: "controllers"
      RUBY

      builder = described_class.new(root: site_root.to_s, js_bundler: "importmap")
      builder.build

      importmap_json = site_root.join("dist/assets/importmap.json")
      content = JSON.parse(File.read(importmap_json))

      expect(content["imports"]).to have_key("controllers/test")
    end
  end

  describe "AssetResolver" do
    let(:resolver) { StaticSiteBuilder::Builder::AssetResolver.new(@tmp_dir, @tmp_dir.join("dist")) }

    it "resolves javascript paths" do
      path = resolver.javascript_path("application.js")
      expect(path).to eq("/assets/javascripts/application.js")
    end

    it "resolves asset paths" do
      path = resolver.asset_path("styles.css")
      expect(path).to eq("/assets/styles.css")
    end
  end

  describe "SimpleImportMap" do
    let(:resolver) { StaticSiteBuilder::Builder::AssetResolver.new(@tmp_dir, @tmp_dir.join("dist")) }
    let(:importmap) { StaticSiteBuilder::Builder::SimpleImportMap.new }

    it "pins modules" do
      importmap.pin("test", to: "test.js")

      json = JSON.parse(importmap.to_json(resolver: resolver))
      expect(json["imports"]).to have_key("test")
      expect(json["imports"]["test"]).to include("test.js")
    end

    it "pins all from directory" do
      js_dir = @tmp_dir.join("app/javascript")
      FileUtils.mkdir_p(js_dir)
      File.write(js_dir.join("module1.js"), "export default {}")
      File.write(js_dir.join("module2.js"), "export default {}")

      importmap.pin_all_from(js_dir.to_s, under: "modules")

      json = JSON.parse(importmap.to_json(resolver: resolver))
      expect(json["imports"]).to have_key("modules/module1")
      expect(json["imports"]).to have_key("modules/module2")
    end
  end
end
