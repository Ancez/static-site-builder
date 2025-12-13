# Changelog

## 1.0.0 (Current) - 2025-12-13

First stable release of Static Site Builder.

### Features

- Generate static HTML sites from ERB templates
- Development server with auto-rebuild and live reload
- Sitemap generation from pages
- Simple and flexible - add your own JavaScript bundling and CSS processing

### What Gets Generated

- Clean project structure with `app/views/`, `app/javascript/`, `app/assets/stylesheets/`
- Self-contained build code in `lib/site_builder.rb` (no runtime dependency on this gem), using ActionView for Rails-like templates/partials/helpers
- Rakefile with build tasks (`bundle exec rake build:all`, `bundle exec rake build:html`, `bundle exec rake build:css`, `bundle exec rake build:sitemap`)
- `build:all` cleans `dist/` first, then builds assets + HTML + CSS + sitemap
- Development server (`bundle exec rake dev:server`) with live reload
- Example pages and layouts
- Sitemap configuration

### Requirements

- Ruby 3.0+
- Bundler


