# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/.bundle/"
end

require "pathname"
require "fileutils"
require "tmpdir"

# Add the lib directory to the load path
lib_path = Pathname.new(__FILE__).expand_path.join("..", "..", "lib")
$LOAD_PATH.unshift(lib_path.to_s) unless $LOAD_PATH.include?(lib_path.to_s)

require "static_site_builder"

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Create temporary directories for tests
  config.before(:each) do
    @tmp_dir = Pathname.new(Dir.mktmpdir("static-site-builder-test"))
  end

  config.after(:each) do
    FileUtils.rm_rf(@tmp_dir) if @tmp_dir&.exist?
  end
end
