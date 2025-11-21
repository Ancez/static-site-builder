# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2025-11-21

### Added
- Initial release of static-site-builder gem
- Generator for creating new static site projects
- Builder for compiling ERB templates to static HTML
- Support for multiple template engines (ERB, Phlex)
- Support for multiple JavaScript bundlers (Importmap, ESBuild, Webpack, Vite, None)
- Support for multiple CSS frameworks (TailwindCSS, shadcn/ui, Plain CSS)
- Support for multiple JavaScript frameworks (Stimulus, React, Vue, Alpine.js, Vanilla)
- Frontmatter parsing for ERB pages
- Layout support with nested layouts
- Importmap JSON generation
- Asset copying (JavaScript, CSS, vendor files, static files)
- Comprehensive test suite
- YARD documentation
- CI/CD setup (GitHub Actions)

### Changed
- Vendor JavaScript files are automatically copied directly from `node_modules` to `dist/assets/javascripts/` during build
- Removed requirement for `vendor/javascript/` folder - vendor files are copied automatically based on importmap configuration
- Generator no longer creates vendor files during project generation

### Fixed
- Added warning messages when vendor files cannot be found in `node_modules`
- Updated base64 dependency comments to clarify requirement for Ruby 3.4+

[0.0.1]: https://github.com/Ancez/static-site-builder/releases/tag/v0.0.1

