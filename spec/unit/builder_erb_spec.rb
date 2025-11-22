# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "ERB compilation" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "compiles ERB page without frontmatter" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Hello</h1>")
    end

    it "parses frontmatter correctly" do
      page_content = <<~ERB
        ---
        title: Test Page
        layout: custom
        js: application, controllers/test
        ---

        <h1>Content</h1>
      ERB

      create_test_page(site_root.to_s, "test.html.erb", page_content)
      create_test_layout(site_root.to_s, "custom.html.erb", "<html><head><title><%= frontmatter['title'] %></title></head><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/test.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("Test Page")
      expect(content).to include("<h1>Content</h1>")
    end

    it "uses default layout when not specified" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<!DOCTYPE html>")
      expect(content).to include("<h1>Hello</h1>")
    end

    it "compiles nested pages" do
      nested_dir = site_root.join("app/views/pages/blog")
      FileUtils.mkdir_p(nested_dir)
      File.write(nested_dir.join("index.html.erb"), "<h1>Blog</h1>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/blog/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Blog</h1>")
    end

    it "handles js_modules from frontmatter" do
      page_content = <<~ERB
        ---
        js: application, controllers/test
        ---

        <h1>Test</h1>
      ERB

      create_test_page(site_root.to_s, "test.html.erb", page_content)

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/test.html")
      content = File.read(output)

      # Should include script tags for the modules
      expect(content).to include("application")
    end

    it "annotates template file names when enabled" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none", annotate_template_file_names: true)
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)

      # Should include annotations for both page and layout
      expect(content).to include("<!-- BEGIN app/views/pages/index.html.erb -->")
      expect(content).to include("<!-- END app/views/pages/index.html.erb -->")
      expect(content).to include("<!-- BEGIN app/views/layouts/application.html.erb -->")
      expect(content).to include("<!-- END app/views/layouts/application.html.erb -->")
    end

    it "does not annotate template file names when disabled" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none", annotate_template_file_names: false)
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)

      # Should not include annotations
      expect(content).not_to include("<!-- BEGIN")
      expect(content).not_to include("<!-- END")
    end

    it "auto-enables annotations when LIVE_RELOAD is set" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      ENV["LIVE_RELOAD"] = "true"
      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)

      # Should include annotations
      expect(content).to include("<!-- BEGIN app/views/pages/index.html.erb -->")
    ensure
      ENV.delete("LIVE_RELOAD")
    end

    it "renders partials using render helper" do
      # Create a partial
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_header.html.erb"), "<header>Header Content</header>")
      
      # Create a page that uses the partial
      page_content = <<~ERB
        <div>
          <%= render 'shared/header' %>
          <main>Page Content</main>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<header>Header Content</header>")
      expect(content).to include("<main>Page Content</main>")
    end

    it "renders partials from default shared directory" do
      # Create a partial in shared directory
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_footer.html.erb"), "<footer>Footer Content</footer>")
      
      # Create a page that uses the partial without 'shared/' prefix
      page_content = <<~ERB
        <div>
          <main>Page Content</main>
          <%= render 'footer' %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<footer>Footer Content</footer>")
    end

    it "raises error when partial is not found" do
      page_content = <<~ERB
        <div>
          <%= render 'shared/nonexistent' %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      
      expect { builder.build }.to raise_error(/Partial not found/)
    end

    it "renders partials with access to page variables" do
      # Create a partial that uses frontmatter
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_title.html.erb"), "<h1><%= frontmatter['title'] %></h1>")
      
      page_content = <<~ERB
        ---
        title: My Page Title
        ---
        <div>
          <%= render 'shared/title' %>
          <p>Content</p>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<h1>My Page Title</h1>")
    end

    it "renders nested partials (partial rendering another partial)" do
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      
      # Create a nested partial
      File.write(shared_dir.join("_nested.html.erb"), "<div class='nested'>Nested Content</div>")
      
      # Create a partial that renders another partial
      File.write(shared_dir.join("_parent.html.erb"), "<div class='parent'><%= render 'shared/nested' %></div>")
      
      page_content = <<~ERB
        <div>
          <%= render 'shared/parent' %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<div class='parent'>")
      expect(content).to include("<div class='nested'>Nested Content</div>")
    end

    it "supports Rails-style render partial: syntax" do
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_header.html.erb"), "<header>Header Content</header>")
      
      page_content = <<~ERB
        <div>
          <%= render partial: 'shared/header' %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<header>Header Content</header>")
    end

    it "supports render partial: with locals" do
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_title.html.erb"), "<h1><%= title %></h1>")
      
      page_content = <<~ERB
        <div>
          <%= render partial: 'shared/title', locals: { title: 'Custom Title' } %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<h1>Custom Title</h1>")
    end

    it "renders multiple partials on the same page" do
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_header.html.erb"), "<header>Header</header>")
      File.write(shared_dir.join("_footer.html.erb"), "<footer>Footer</footer>")
      
      page_content = <<~ERB
        <div>
          <%= render 'shared/header' %>
          <main>Content</main>
          <%= render partial: 'shared/footer' %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<header>Header</header>")
      expect(content).to include("<main>Content</main>")
      expect(content).to include("<footer>Footer</footer>")
    end
  end
end
