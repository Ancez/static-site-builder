# frozen_string_literal: true

require_relative "lib/static_site_builder/version"

Gem::Specification.new do |spec|
  spec.name          = "static-site-builder"
  spec.version       = StaticSiteBuilder::VERSION
  spec.authors       = ["Lukasz Czapiewski"]
  spec.email         = ["luke@mmtm.io"]

  spec.summary       = "Build static HTML sites from ERB/Phlex templates with working JavaScript"
  spec.description   = "A Ruby gem for building static HTML sites from ERB or Phlex templates using ActionView. Compiles templates to static HTML with full JavaScript support. Includes a generator for creating projects and a builder for compilation. Choose your stack: ERB or Phlex templates, Importmap/ESBuild/Webpack/Vite for JavaScript, TailwindCSS or shadcn for CSS, and Stimulus/React/Vue/Alpine.js for interactivity. No backend required - deploy static HTML anywhere."
  spec.homepage      = "https://github.com/Ancez/static-site-builder"
  spec.license       = "MIT"

  spec.metadata["source_code_uri"] = "https://github.com/Ancez/static-site-builder"
  spec.metadata["changelog_uri"] = "https://github.com/Ancez/static-site-builder/blob/master/CHANGELOG.md"

  spec.files         = Dir["lib/**/*", "bin/**/*", "exe/**/*", "README.md", "ARCHITECTURE.md", "CHANGELOG.md", "LICENSE"].reject { |f| f.match?(/\.gem$/) }
  spec.bindir        = "exe"
  spec.executables   = ["static-site-builder"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "actionview", "~> 7.1"
  spec.add_dependency "base64", "~> 0.1"  # Required for Ruby 3.4+ (removed from default gems)
  spec.add_dependency "rake", "~> 13.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "websocket", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.0"
end
