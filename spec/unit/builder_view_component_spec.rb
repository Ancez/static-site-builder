# frozen_string_literal: true

require "spec_helper"

RSpec.describe StaticSiteBuilder::Builder do
  describe "ViewComponent compilation" do
    let(:site_root) { @tmp_dir.join("test-site") }

    before do
      create_test_site_structure(site_root.to_s)
      # Create components directory
      FileUtils.mkdir_p(site_root.join("app/components"))
    end

    it "compiles ViewComponent page" do
      # Create a page component
      component_class = <<~RUBY
        # frozen_string_literal: true

        class IndexPageComponent < ViewComponent::Base
          def initialize(title: "Welcome")
            @title = title
          end

          private

          attr_reader :title
        end
      RUBY

      File.write(site_root.join("app/views/pages/index_component.rb"), component_class)

      # Create the ERB template for the component
      template_content = <<~ERB
        <h1><%= title %></h1>
        <p>Hello from ViewComponent</p>
      ERB

      File.write(site_root.join("app/views/pages/index_component.html.erb"), template_content)

      # Create layout component
      layout_class = <<~RUBY
        # frozen_string_literal: true

        class ApplicationLayoutComponent < ViewComponent::Base
          def initialize(title: "Site")
            @title = title
          end

          private

          attr_reader :title
        end
      RUBY

      File.write(site_root.join("app/components/application_layout_component.rb"), layout_class)

      layout_template = <<~ERB
        <!DOCTYPE html>
        <html>
        <head><title><%= title %></title></head>
        <body><main><%= content %></main></body>
        </html>
      ERB

      File.write(site_root.join("app/components/application_layout_component.html.erb"), layout_template)

      builder = described_class.new(root: site_root.to_s, template_engine: "view_component", js_bundler: "none")
      builder.build

      output = site_root.join("dist/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Welcome</h1>")
      expect(content).to include("<p>Hello from ViewComponent</p>")
      expect(content).to include("<!DOCTYPE html>")
    end

    it "uses default layout when ViewComponent layout is not found" do
      # Create a page component
      component_class = <<~RUBY
        # frozen_string_literal: true

        class TestPageComponent < ViewComponent::Base
          def initialize(title: "Test")
            @title = title
          end

          private

          attr_reader :title
        end
      RUBY

      File.write(site_root.join("app/views/pages/test_component.rb"), component_class)

      template_content = <<~ERB
        <h1><%= title %></h1>
      ERB

      File.write(site_root.join("app/views/pages/test_component.html.erb"), template_content)

      builder = described_class.new(root: site_root.to_s, template_engine: "view_component", js_bundler: "none")
      builder.build

      output = site_root.join("dist/test.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<!DOCTYPE html>")
      expect(content).to include("<h1>Test</h1>")
    end

    it "uses PageHelpers::PAGES metadata correctly" do
      # Create page_helpers.rb with metadata
      lib_dir = site_root.join("lib")
      FileUtils.mkdir_p(lib_dir)
      page_helpers_content = <<~RUBY
        module PageHelpers
          PAGES = {
            '/about' => {
              title: 'About Page',
              description: 'An about page'
            }
          }.freeze
        end
      RUBY
      File.write(lib_dir.join("page_helpers.rb"), page_helpers_content)

      # Create about page component
      component_class = <<~RUBY
        # frozen_string_literal: true

        class AboutPageComponent < ViewComponent::Base
          def initialize(title: "About")
            @title = title
          end

          private

          attr_reader :title
        end
      RUBY

      File.write(site_root.join("app/views/pages/about_component.rb"), component_class)

      template_content = <<~ERB
        <h1><%= title %></h1>
        <p>About content</p>
      ERB

      File.write(site_root.join("app/views/pages/about_component.html.erb"), template_content)

      # Create layout component
      layout_class = <<~RUBY
        # frozen_string_literal: true

        class ApplicationLayoutComponent < ViewComponent::Base
          def initialize(title: "Site")
            @title = title
          end

          private

          attr_reader :title
        end
      RUBY

      File.write(site_root.join("app/components/application_layout_component.rb"), layout_class)

      layout_template = <<~ERB
        <!DOCTYPE html>
        <html>
        <head><title><%= title %></title></head>
        <body><main><%= content %></main></body>
        </html>
      ERB

      File.write(site_root.join("app/components/application_layout_component.html.erb"), layout_template)

      builder = described_class.new(root: site_root.to_s, template_engine: "view_component", js_bundler: "none")
      builder.build

      output = site_root.join("dist/about.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("About Page")
      expect(content).to include("<h1>About Page</h1>")
    end

    it "compiles nested ViewComponent pages" do
      nested_dir = site_root.join("app/views/pages/blog")
      FileUtils.mkdir_p(nested_dir)

      component_class = <<~RUBY
        # frozen_string_literal: true

        module BlogPage
          module IndexPage
            class Component < ViewComponent::Base
              def initialize(title: "Blog")
                @title = title
              end

              private

              attr_reader :title
            end
          end
        end
      RUBY

      File.write(nested_dir.join("index_component.rb"), component_class)

      template_content = <<~ERB
        <h1><%= title %></h1>
      ERB

      File.write(nested_dir.join("index_component.html.erb"), template_content)

      builder = described_class.new(root: site_root.to_s, template_engine: "view_component", js_bundler: "none")
      builder.build

      output = site_root.join("dist/blog/index.html")
      expect(output).to exist

      content = File.read(output)
      expect(content).to include("<h1>Blog</h1>")
    end

    it "raises error when component class does not inherit from ViewComponent::Base" do
      component_class = <<~RUBY
        # frozen_string_literal: true

        class InvalidPageComponent
          def initialize(title: "Test")
            @title = title
          end
        end
      RUBY

      File.write(site_root.join("app/views/pages/invalid_component.rb"), component_class)

      File.write(site_root.join("app/views/pages/invalid_component.html.erb"), "<h1>Test</h1>")

      builder = described_class.new(root: site_root.to_s, template_engine: "view_component", js_bundler: "none")
      
      expect { builder.build }.to raise_error(/must inherit from ViewComponent::Base/)
    end
  end
end

