# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-11-14

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
- Comprehensive test suite with 397 examples
- YARD documentation
- CI/CD setup (GitHub Actions)

### Changed
- Renamed from static-site-generator to static-site-builder
- Refactored to use gem-based architecture

### Fixed
- Fixed indentation issues throughout codebase
- Fixed Rakefile template interpolation issues
- Fixed asset copying to handle empty directories
- Fixed test helper loading

### Security
- No known security issues

[0.1.0]: https://github.com/yourusername/html-importmap-ruby/releases/tag/v0.1.0

