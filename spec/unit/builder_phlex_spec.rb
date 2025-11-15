# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "Phlex compilation" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "acknowledges Phlex compilation is not yet implemented" do
      # Phlex compilation will be implemented when phlex-rails is available
      builder = described_class.new(root: site_root.to_s, template_engine: "phlex", js_bundler: "none")

      expect { builder.build }.not_to raise_error
      # Currently Phlex compilation prints a message and does nothing
      # This test will be updated when Phlex support is added
    end
  end
end
