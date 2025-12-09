# Changelog

## 1.0.0 (Current)

First stable release of Static Site Builder.

### Features

- Generate static HTML sites from ERB templates
- Uses ActionView for Rails-like layouts, pages, and partials
- Development server with auto-rebuild and live reload
- Sitemap generation from pages
- Simple and flexible - add your own JavaScript bundling and CSS processing
- Meta tags support via meta-tags gem
- Helper support from `app/helpers/` directory

### What Gets Generated

- Clean project structure with `app/views/`, `app/javascript/`, `app/assets/stylesheets/`
- Rakefile with build tasks (`rake build:all`, `rake build:html`)
- Development server (`rake dev:server`)
- Example pages and layouts
- Sitemap configuration

### Requirements

- Ruby 3.0+
- Bundler

