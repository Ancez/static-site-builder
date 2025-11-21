# Static Site Builder

A Ruby-based generator and builder for creating static HTML sites with working JavaScript. **No backend required** - just compile your templates to static HTML and deploy anywhere.

## Main Objective

Generate static HTML pages with JavaScript files that work. Choose your own stack:

- **Template Engine**: ERB or Phlex
- **JavaScript Bundler**: Importmap, ESBuild, Webpack, Vite, or none
- **CSS Framework**: TailwindCSS, shadcn/ui, or plain CSS
- **JavaScript Framework**: Stimulus, React, Vue, Alpine.js, or vanilla JS

## Installation

```bash
gem install static-site-builder
# or
git clone https://github.com/Ancez/static-site-builder
cd static-site-builder
bundle install
```

## Quick Start

### Option 1: Install as a gem
```bash
gem install static-site-builder
static-site-builder new my-site
```

### Option 2: Use directly from repo
```bash
git clone https://github.com/Ancez/static-site-builder
cd static-site-builder
bundle install
ruby bin/generate my-site
```

You'll be prompted to choose your stack using an interactive menu with arrow key navigation. Generated sites use:
- `static-site-builder` gem for compilation
- Standard gems (importmap-rails, phlex-rails, etc.) for functionality
- npm packages for JS bundlers and frameworks

## What Gets Generated

A clean project structure that depends on gems:

```
my-site/
├── Gemfile              # Dependencies (static-site-builder, importmap-rails, etc.)
├── package.json         # JS dependencies (if needed)
├── Rakefile            # Build tasks
├── config/
│   └── importmap.rb    # Importmap config (if using importmap)
├── app/
│   ├── views/
│   │   ├── layouts/
│   │   ├── pages/
│   │   └── components/     # Reusable components/partials
│   ├── javascript/
│   └── assets/
└── lib/
    └── site_builder.rb   # Compiles your site
```

## How It Works

1. **Generator** (`static-site-generator`) - Creates the project structure
2. **Builder Gem** (`static-site-builder`) - Handles ERB/Phlex compilation
3. **Standard Gems** - importmap-rails, phlex-rails, etc. for functionality
4. **Build Tools** - Rake tasks that use the builder gem

## Features

- 🎯 **Static HTML output** - No server-side rendering needed
- 🔧 **Flexible stack** - Choose what works for you
- 📦 **Gem-based** - Uses existing Ruby gems, not custom code
- 🚀 **Fast builds** - Compile once, deploy everywhere
- 🎨 **Component support** - ERB or Phlex components
- 📱 **Modern JS** - ES modules, importmaps, or bundlers

## Supported Stacks

### Template Engines
- **ERB** - Ruby's embedded Ruby templates
- **Phlex** - Ruby component library (via phlex-rails gem)

### JavaScript Bundlers
- **Importmap** - No bundling, use ES modules directly (via importmap-rails gem)
- **ESBuild** - Fast JavaScript bundler
- **Webpack** - Powerful bundler with plugins
- **Vite** - Next-generation frontend tooling
- **None** - Vanilla JavaScript, no bundling

### CSS Frameworks
- **TailwindCSS** - Utility-first CSS framework
- **shadcn/ui** - Re-usable components built with Tailwind
- **Plain CSS** - Write your own styles

### JavaScript Frameworks
- **Stimulus** - Modest JavaScript framework
- **React** - Popular UI library
- **Vue** - Progressive JavaScript framework
- **Alpine.js** - Minimal framework for HTML
- **Vanilla JS** - No framework

## Building Powerful Websites

### Using ERB Templates

Create pages in `app/views/pages/` with frontmatter:

```erb
---
title: My Page
description: A great page
---

<h1><%= @title %></h1>
<p><%= @description %></p>
```

Use layouts in `app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html>
<head>
  <title><%= @title || "My Site" %></title>
</head>
<body>
  <%= yield %>
</body>
</html>
```

### Using Phlex Components

Create reusable components in `app/views/components/`:

```ruby
class Button < Phlex::HTML
  def initialize(text:, href:, variant: "primary")
    @text = text
    @href = href
    @variant = variant
  end

  def template
    a(href: @href, class: "btn btn-#{@variant}") { @text }
  end
end
```

Use in pages:

```ruby
class HomePage < Phlex::HTML
  def template
    div do
      h1 { "Welcome" }
      render Button.new(text: "Get Started", href: "/about")
    end
  end
end
```

### JavaScript with Importmap

No bundling needed - use ES modules directly:

```javascript
// app/javascript/application.js
import { Application } from "@hotwired/stimulus"
import HelloController from "./controllers/hello_controller"

window.Stimulus = Application.start()
Stimulus.register("hello", HelloController)
```

### JavaScript with Bundlers

Use ESBuild, Webpack, or Vite for modern tooling:

```javascript
// app/javascript/index.js
import React from 'react'
import { createRoot } from 'react-dom/client'

function App() {
  return <h1>Hello from React!</h1>
}

const root = createRoot(document.getElementById('app'))
root.render(<App />)
```

### CSS with TailwindCSS

Use utility classes directly in templates:

```erb
<div class="container mx-auto px-4">
  <h1 class="text-4xl font-bold text-gray-900">Hello World</h1>
</div>
```

### CSS with shadcn/ui

Install components and use them in your templates:

```bash
npx shadcn-ui@latest add button
```

## Examples

### ERB + Importmap + Stimulus + TailwindCSS
```bash
static-site-builder new my-site
# Choose: ERB, Importmap, TailwindCSS, Stimulus
```

### Phlex + ESBuild + React + shadcn
```bash
static-site-builder new my-site
# Choose: Phlex, ESBuild, shadcn/ui, React
```

## Requirements

### For Importmap Projects

When using **Importmap** as your JavaScript bundler:

1. **Install npm dependencies**:
   ```bash
   npm install
   ```

2. **Build your site** - vendor files are automatically copied from `node_modules` to `dist/assets/javascripts/` during the build:
   ```bash
   rake build:all
   ```

The build process automatically copies required vendor JavaScript files directly from `node_modules` to `dist/assets/javascripts/` based on your importmap configuration. No intermediate `vendor/javascript/` folder is needed.

## Development

### Running Your Site Locally

After generating a site, you can run it locally with auto-rebuild and live reload:

```bash
cd my-site
bundle install
npm install  # Required for importmap projects and JS frameworks

# Start development server (auto-rebuilds on file changes)
rake dev:server
```

This will:
- Build your site to `dist/`
- Start a web server at `http://localhost:3000`
- Watch for file changes and rebuild automatically
- Auto-refresh your browser when files change

You can change the port with:
```bash
PORT=8080 rake dev:server
```

### Building for Production

```bash
# Build everything (assets + HTML)
rake build:all

# Or just HTML
rake build:html

# Output is in dist/ directory
```

## Deployment

The `dist/` directory contains your complete static site and can be deployed to any static hosting provider.

### Cloudflare Pages

1. **Connect your repository** to Cloudflare Pages in the Cloudflare dashboard

2. **Build settings**:
   - **Build command**: `bundle install && npm install && bundle exec rake build:all`
   - **Build output directory**: `dist`
   - **Root directory**: (leave empty or set to repository root)

3. **Environment variables** (if needed):
   - `RUBY_VERSION`: Set to your Ruby version (e.g., `3.4`)
   - `NODE_VERSION`: Set to your Node.js version (e.g., `24`)

4. **Deploy**: Cloudflare Pages will automatically build and deploy on every push to your main branch

**Note**: Cloudflare Pages supports Ruby and Node.js builds. Ensure your `Gemfile` and `package.json` are properly configured.

### Vercel

1. **Install Vercel CLI** (optional):
   ```bash
   npm i -g vercel
   ```

2. **Deploy**:
   ```bash
   # Build locally first
   bundle install && npm install && bundle exec rake build:all
   
   # Deploy
   vercel --prod
   ```

   Or connect your repository in the Vercel dashboard with these settings:
   - **Build Command**: `bundle install && npm install && bundle exec rake build:all`
   - **Output Directory**: `dist`
   - **Install Command**: `bundle install && npm install`

3. **Configuration file** (optional `vercel.json`):
   ```json
   {
     "buildCommand": "bundle install && npm install && bundle exec rake build:all",
     "outputDirectory": "dist",
     "installCommand": "bundle install && npm install"
   }
   ```

### Netlify

1. **Create `netlify.toml`** in your project root:
   ```toml
   [build]
     command = "bundle install && npm install && bundle exec rake build:all"
     publish = "dist"
   
   [build.environment]
     RUBY_VERSION = "3.4"
     NODE_VERSION = "24"
   ```

2. **Deploy**:
   - Connect your repository in Netlify dashboard
   - Netlify will automatically detect `netlify.toml` and use those settings
   - Or use Netlify CLI: `netlify deploy --prod`

### GitHub Pages

1. **Using GitHub Actions** (recommended):

   Create `.github/workflows/deploy.yml`:
   ```yaml
   name: Deploy to GitHub Pages
   
   on:
     push:
       branches: [ main ]
   
   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         
         - name: Set up Ruby
           uses: ruby/setup-ruby@v1
           with:
             ruby-version: 3.4
             bundler-cache: true
         
         - name: Set up Node.js
           uses: actions/setup-node@v4
           with:
             node-version: '24'
             cache: 'npm'
         
         - name: Install dependencies
           run: |
             bundle install
             npm install
         
        - name: Build site
          run: bundle exec rake build:all
          # Note: Vendor files will be automatically copied from node_modules during build
         
         - name: Deploy to GitHub Pages
           uses: peaceiris/actions-gh-pages@v4
           with:
             github_token: ${{ secrets.GITHUB_TOKEN }}
             publish_dir: ./dist
   ```

2. **Enable GitHub Pages** in your repository settings:
   - Go to Settings → Pages
   - Source: GitHub Actions

### Other Static Hosts

For any static hosting provider (AWS S3, Azure Static Web Apps, etc.):

1. **Build locally**:
   ```bash
   bundle install
   npm install
   bundle exec rake build:all
   ```

2. **Upload `dist/` directory** to your hosting provider

3. **Configure** your host to serve from the `dist` directory

### CI/CD Considerations

- **Vendor files**: Vendor files are automatically copied from `node_modules` to `dist/` during build - no vendor folder needed
- **Dependencies**: Both Ruby (`Gemfile`) and Node.js (`package.json`) dependencies are needed for the build
- **Build order**: Install dependencies → Build assets → Build HTML
- **Ruby/Node versions**: Specify versions in your CI/CD configuration to ensure consistent builds

### Generator Development

```bash
# Clone the repo
git clone https://github.com/Ancez/static-site-builder
cd static-site-builder

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Build the gem
gem build static-site-builder.gemspec
```

## Testing

The project includes comprehensive test coverage:

- Unit tests for Generator and Builder classes
- Integration tests for full build workflows
- End-to-end tests for complete workflows
- Tests for all stack combinations

Run tests with:
```bash
bundle exec rspec
```

View coverage report:
```bash
open coverage/index.html
```

## Architecture

This generator follows the Rails pattern:
- **Generator gem** - Creates project structure
- **Builder gem** - Handles compilation (separate gem: `static-site-builder`)
- **Standard gems** - Reuse existing Ruby gems
- **Generated code** - Minimal, uses gem dependencies

## Contributing

Contributions welcome! Especially:
- New template engine support
- New bundler integrations
- New CSS framework setups
- Documentation improvements

## License

MIT
