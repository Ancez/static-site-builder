# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Generator do
  describe "helper methods" do
    describe "#needs_npm?" do
      it "returns false" do
        generator = described_class.new("test")
        expect(generator.send(:needs_npm?)).to be false
      end
    end
  end
end
