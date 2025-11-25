# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "ERB compilation" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
    end

    it "compiles ERB page" do
      create_test_page(site_root.to_s, "index.html.erb", "<h1>Hello</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Hello</h1>")
    end

    it "uses PageHelpers::PAGES metadata correctly" do
      # Create page_helpers.rb with metadata
      lib_dir = site_root.join("lib")
      FileUtils.mkdir_p(lib_dir)
      page_helpers_content = <<~RUBY
        module PageHelpers
          PAGES = {
            '/test' => {
              title: 'Test Page',
              description: 'A test page'
            }
          }.freeze
        end
      RUBY
      File.write(lib_dir.join("page_helpers.rb"), page_helpers_content)

      create_test_page(site_root.to_s, "test.html.erb", "<h1>Content</h1>")
      create_test_layout(site_root.to_s, "application.html.erb", "<html><head><title><%= @title || 'Site' %></title></head><body><%= page_content %></body></html>")

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

    it "handles js_modules from page ERB" do
      page_content = <<~ERB
        <% @js_modules = ['application', 'controllers/test'] %>
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
      # Create a partial for reusable content (not layout elements)
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_card.html.erb"), "<div class='card'><%= content %></div>")
      
      # Create a page that uses the partial
      page_content = <<~ERB
        <div>
          <main>Page Content</main>
          <%= render partial: 'shared/card', locals: { content: 'Card Content' } %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<div class='card'>Card Content</div>")
      expect(content).to include("<main>Page Content</main>")
    end

    it "renders partials from shared directory with explicit path" do
      # Create a partial for reusable content
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_button.html.erb"), "<button class='btn'><%= text %></button>")
      
      # Create a page that uses the partial with explicit 'shared/' path
      page_content = <<~ERB
        <div>
          <main>Page Content</main>
          <%= render partial: 'shared/button', locals: { text: 'Click Me' } %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<button class='btn'>Click Me</button>")
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
      
      expect { builder.build }.to raise_error(/Partial template not found/)
    end

    it "renders partials with access to page variables" do
      # Create page_helpers.rb with metadata
      lib_dir = site_root.join("lib")
      FileUtils.mkdir_p(lib_dir)
      page_helpers_content = <<~RUBY
        module PageHelpers
          PAGES = {
            '/' => {
              title: 'My Page Title',
              description: 'A test page'
            }
          }.freeze
        end
      RUBY
      File.write(lib_dir.join("page_helpers.rb"), page_helpers_content)

      # Create a partial that uses @title
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_title.html.erb"), "<h1><%= @title %></h1>")
      
      page_content = <<~ERB
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
      File.write(shared_dir.join("_alert.html.erb"), "<div class='alert'><%= message %></div>")
      
      page_content = <<~ERB
        <div>
          <%= render partial: 'shared/alert', locals: { message: 'Success!' } %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<div class='alert'>Success!</div>")
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
      File.write(shared_dir.join("_card.html.erb"), "<div class='card'><%= title %></div>")
      File.write(shared_dir.join("_badge.html.erb"), "<span class='badge'><%= text %></span>")
      
      page_content = <<~ERB
        <div>
          <%= render partial: 'shared/card', locals: { title: 'Card Title' } %>
          <main>Content</main>
          <%= render partial: 'shared/badge', locals: { text: 'New' } %>
        </div>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      create_test_layout(site_root.to_s, "application.html.erb", "<html><body><%= page_content %></body></html>")

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      expect(content).to include("<div class='card'>Card Title</div>")
      expect(content).to include("<main>Content</main>")
      expect(content).to include("<span class='badge'>New</span>")
    end

    it "renders header and footer in layout, not in pages" do
      # Create header and footer partials
      shared_dir = site_root.join("app/views/shared")
      FileUtils.mkdir_p(shared_dir)
      File.write(shared_dir.join("_header.html.erb"), "<header>Site Header</header>")
      File.write(shared_dir.join("_footer.html.erb"), "<footer>Site Footer</footer>")
      
      # Page should only contain content, not layout elements
      page_content = <<~ERB
        <main>
          <h1>Page Title</h1>
          <p>Page content goes here</p>
        </main>
      ERB
      create_test_page(site_root.to_s, "index.html.erb", page_content)
      
      # Layout should contain header and footer
      layout_content = <<~ERB
        <html>
        <body>
          <%= render 'shared/header' %>
          <%= page_content %>
          <%= render 'shared/footer' %>
        </body>
        </html>
      ERB
      create_test_layout(site_root.to_s, "application.html.erb", layout_content)

      builder = described_class.new(root: site_root.to_s, js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      content = File.read(output)
      
      # Header and footer should be in the output (from layout)
      expect(content).to include("<header>Site Header</header>")
      expect(content).to include("<footer>Site Footer</footer>")
      # Page content should be between them
      expect(content).to include("<h1>Page Title</h1>")
      expect(content).to include("<p>Page content goes here</p>")
    end
  end
end
