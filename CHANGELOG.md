# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.4] - 2025-11-22

### Added
- Generator now automatically creates `lib/page_helpers.rb` with `PageHelpers::PAGES` structure for page metadata
- Generator now automatically creates `config/sitemap.rb` for sitemap generation
- `sitemap_generator` gem is now automatically included in generated Gemfiles
- `build:sitemap` task is automatically added to generated Rakefiles
- Sitemap generation is integrated into `build:all` task

### Changed
- Page metadata is now managed via `PageHelpers::PAGES` hash instead of frontmatter
- README updated to reflect `PageHelpers::PAGES` approach (frontmatter example removed)
- ActionView requirement changed from `>= 8.0` to `~> 7.1` for Ruby 3.1 compatibility
- Generated layouts now use `@title` and `@js_modules` instance variables instead of frontmatter

### Fixed
- Fixed `js_modules` variable reference in generated layouts (now uses `@js_modules`)
- Fixed PageHelpers metadata loading to occur before page content rendering, allowing partials to access `@title`, `@description`, etc.
- Removed all frontmatter parsing code and references
- Updated all specs to use `PageHelpers::PAGES` instead of frontmatter

## [0.1.3] - 2025-11-22

### Added
- Integrated ActionView 8+ for proper Rails-style partial rendering
- Support for Rails-style render syntax: `render 'shared/header'` and `render partial: 'shared/header'`
- Support for passing locals to partials: `render partial: 'shared/header', locals: { title: 'Hello' }`
- Nested partial support (partials can render other partials)
- Multiple partials on the same page now work correctly

### Changed
- Replaced raw ERB implementation with ActionView::Base for template rendering
- Render method now uses ActionView's rendering system, matching Rails behaviour exactly
- Partials automatically receive page variables (@js_modules, importmap_json, current_page)
- Improved error messages for missing partials (converted from ActionView format for backwards compatibility)
- Template annotations now preserve both page and layout annotations correctly

### Fixed
- Fixed issue where nested partials (partials rendering other partials) would fail or produce incorrect output
- Fixed issue where multiple partials on the same page would only render the last one
- Fixed template annotations being stripped when layout annotations were added

## [0.1.2] - 2025-11-22

### Fixed
- CSS directory is now always created when Tailwind handles CSS compilation, preventing 404 errors for stylesheets
- Build process now updates files in place instead of cleaning and recreating the dist directory, preventing 404 errors during rebuilds in development mode
- Fixed race condition where pages would return 404 when code changes triggered rebuilds

## [0.1.1] - 2025-11-21

### Added
- `render` helper method for ERB templates to include partials
- Support for rendering partials from `app/views/shared/` directory
- Partial files should be named with `_` prefix (e.g., `_header.html.erb`)
- Partials have access to page variables (@js_modules, etc.)

### Changed
- Improved ERB compilation to support partial rendering

## [0.0.1] - 2025-11-21

### Added
- Initial release of static-site-builder gem
- Generator for creating new static site projects
- Builder for compiling ERB templates to static HTML
- Support for multiple template engines (ERB, Phlex)
- Support for multiple JavaScript bundlers (Importmap, ESBuild, Webpack, Vite, None)
- Support for multiple CSS frameworks (TailwindCSS, shadcn/ui, Plain CSS)
- Support for multiple JavaScript frameworks (Stimulus, React, Vue, Alpine.js, Vanilla)
- Page metadata via `PageHelpers::PAGES` hash
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

