# frozen_string_literal: true

module FileHelpers
  def create_test_site_structure(base_path)
    base = Pathname.new(base_path)

    # Create directory structure
    [
      "app/views/layouts",
      "app/views/pages",
      "app/javascript",
      "app/assets/stylesheets",
      "config",
      "public"
    ].each do |dir|
      FileUtils.mkdir_p(base.join(dir))
    end
  end

  def create_test_page(base_path, filename, content)
    page_path = Pathname.new(base_path).join("app/views/pages", filename)
    FileUtils.mkdir_p(page_path.dirname)
    File.write(page_path, content)
  end

  def create_test_layout(base_path, filename, content)
    layout_path = Pathname.new(base_path).join("app/views/layouts", filename)
    FileUtils.mkdir_p(layout_path.dirname)
    File.write(layout_path, content)
  end

  def create_test_js_file(base_path, filename, content)
    js_path = Pathname.new(base_path).join("app/javascript", filename)
    FileUtils.mkdir_p(js_path.dirname)
    File.write(js_path, content)
  end

  def create_test_css_file(base_path, filename, content)
    css_path = Pathname.new(base_path).join("app/assets/stylesheets", filename)
    FileUtils.mkdir_p(css_path.dirname)
    File.write(css_path, content)
  end

  def create_importmap_config(base_path, content)
    config_path = Pathname.new(base_path).join("config/importmap.rb")
    FileUtils.mkdir_p(config_path.dirname)
    File.write(config_path, content)
  end
end

RSpec.configure do |config|
  config.include FileHelpers
end
