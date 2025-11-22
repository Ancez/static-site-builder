# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Generator do
  describe "helper methods" do
    describe "#needs_npm?" do
      it "returns true for esbuild bundler" do
        generator = described_class.new("test", js_bundler: "esbuild")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for webpack bundler" do
        generator = described_class.new("test", js_bundler: "webpack")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for vite bundler" do
        generator = described_class.new("test", js_bundler: "vite")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for tailwindcss" do
        generator = described_class.new("test", css_framework: "tailwindcss")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for shadcn" do
        generator = described_class.new("test", css_framework: "shadcn")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for react framework" do
        generator = described_class.new("test", js_framework: "react")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for vue framework" do
        generator = described_class.new("test", js_framework: "vue")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns true for alpine framework" do
        generator = described_class.new("test", js_framework: "alpine")
        expect(generator.send(:needs_npm?)).to be true
      end

      it "returns false for none bundler, plain css, vanilla js" do
        generator = described_class.new("test", js_bundler: "none", css_framework: "plain", js_framework: "vanilla")
        expect(generator.send(:needs_npm?)).to be false
      end
    end

    describe "#needs_css_build?" do
      it "returns true for tailwindcss" do
        generator = described_class.new("test", css_framework: "tailwindcss")
        expect(generator.send(:needs_css_build?)).to be true
      end

      it "returns true for shadcn" do
        generator = described_class.new("test", css_framework: "shadcn")
        expect(generator.send(:needs_css_build?)).to be true
      end

      it "returns false for plain css" do
        generator = described_class.new("test", css_framework: "plain")
        expect(generator.send(:needs_css_build?)).to be false
      end
    end

    describe "#build_script" do
      it "returns esbuild command for esbuild bundler" do
        generator = described_class.new("test", js_bundler: "esbuild")
        expect(generator.send(:build_script)).to include("esbuild.config.js")
      end

      it "returns webpack command for webpack bundler" do
        generator = described_class.new("test", js_bundler: "webpack")
        expect(generator.send(:build_script)).to include("webpack")
      end

      it "returns vite command for vite bundler" do
        generator = described_class.new("test", js_bundler: "vite")
        expect(generator.send(:build_script)).to include("vite build")
      end

      it "returns echo for none bundler" do
        generator = described_class.new("test", js_bundler: "none", css_framework: "plain")
        expect(generator.send(:build_script)).to include("echo")
      end
    end

    describe "#css_build_script" do
      it "returns tailwindcss command for tailwindcss" do
        generator = described_class.new("test", css_framework: "tailwindcss")
        script = generator.send(:css_build_script)
        expect(script).to include("tailwindcss")
        expect(script).to include("--minify")
      end

      it "returns tailwindcss command for shadcn" do
        generator = described_class.new("test", css_framework: "shadcn")
        script = generator.send(:css_build_script)
        expect(script).to include("tailwindcss")
      end

      it "returns nil for plain css" do
        generator = described_class.new("test", css_framework: "plain")
        expect(generator.send(:css_build_script)).to be_nil
      end
    end

    describe "#css_watch_script" do
      it "returns watch command for tailwindcss" do
        generator = described_class.new("test", css_framework: "tailwindcss")
        script = generator.send(:css_watch_script)
        expect(script).to include("tailwindcss")
        expect(script).to include("--watch")
      end

      it "returns nil for plain css" do
        generator = described_class.new("test", css_framework: "plain")
        expect(generator.send(:css_watch_script)).to be_nil
      end
    end
  end
end
