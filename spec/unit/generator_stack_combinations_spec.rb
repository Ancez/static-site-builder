# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Generator do
  describe "stack combinations" do
    let(:app_path) { @tmp_dir.join("test-site") }

    context "with ERB" do
      it "generates valid project structure" do
        generator = described_class.new(app_path.to_s)
        generator.generate

        # Verify core structure exists
        expect(app_path.join("app/views/layouts")).to exist
        expect(app_path.join("app/views/pages")).to exist
        expect(app_path.join("app/javascript")).to exist
        expect(app_path.join("Gemfile")).to exist
        expect(app_path.join("lib/site_builder.rb")).to exist

        # Verify template-specific files
        expect(app_path.join("app/views/layouts/application.html.erb")).to exist
        expect(app_path.join("app/views/pages/index.html.erb")).to exist
      end

      it "generates valid Gemfile" do
        generator = described_class.new(app_path.to_s)
        generator.generate

        gemfile = app_path.join("Gemfile")
        content = File.read(gemfile)

        expect(content).to include("static-site-builder")
        expect(content).to include("rake")
      end
    end
  end
end
