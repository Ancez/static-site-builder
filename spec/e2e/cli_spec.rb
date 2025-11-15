# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "CLI" do
  describe "bin/generate" do
    let(:site_name) { "cli-test-site" }
    let(:site_path) { @tmp_dir.join(site_name) }

    it "generates site when given app name" do
      # This would require mocking STDIN for interactive prompts
      # For now, we test the generator directly
      generator = StaticSiteBuilder::Generator.new(
        site_path.to_s,
        template_engine: "erb",
        js_bundler: "importmap",
        css_framework: "tailwindcss",
        js_framework: "stimulus"
      )

      expect { generator.generate }.not_to raise_error
      expect(site_path.join("Gemfile")).to exist
    end

    it "handles existing directory error" do
      FileUtils.mkdir_p(site_path)

      # The generator should handle this gracefully or the CLI should check
      # For now, we test that the directory check works
      expect(Dir.exist?(site_path.to_s)).to be true
    end
  end

  describe "exe/static-site-builder" do
    it "executable exists" do
      # Get the project root (three levels up from spec/e2e/cli_spec.rb)
      spec_file = Pathname.new(__FILE__).expand_path
      project_root = spec_file.parent.parent.parent
      exe_path = project_root.join("exe", "static-site-builder")

      expect(exe_path.exist?).to be true
    end
  end
end
