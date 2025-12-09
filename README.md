# Static Site Builder

> **⚠️ Active Development**: This project is currently in active development. APIs may change between versions.

A Ruby-based generator and builder for creating static HTML sites with working JavaScript. **No backend required** - just compile your ERB files to static HTML and deploy anywhere.

📖 **Learn more**: [Demo](https://lukaszczapiewski.com) | [Project Overview](https://lukaszczapiewski.com/projects/static-site-builder) | [Getting Started Guide](https://lukaszczapiewski.com/blog/getting-started-with-static-site-builders)

## Why This Exists

Uses **ActionView** to render ERB files - get Rails-like layouts, pages, and partials compiled to static HTML. Uses standard Ruby gems and familiar patterns.

**Note**: This gem generates standalone static sites. While it uses ActionView (like Rails), it's designed for static site generation without a full Rails application, allowing you to host it for free directly on Cloudflare CDNs and other static hosting services.

## Why Choose This Over Other Approaches

**Better SEO & Search Rankings**: Unlike Single Page Applications (SPAs) that rely on client-side JS rendering, static HTML is immediately crawlable by search engines. Your content is fully indexed from the first request, leading to better search rankings and significantly faster page loads.

**Simplicity Over Complexity**: No need for complex JavaScript frameworks, hydration, or server-side rendering setups. Create .html.erb files that compile to clean, static HTML. Add JavaScript only where you need interactivity, not as a requirement for rendering.

**Developer Experience**: Work with familiar Rails patterns (layouts, pages, partials) without a full Rails application, allowing you to host it for free directly on Cloudflare CDNs and other static hosting services.

**Version Control & Mobile Editing**: Your entire site is code in a Git repository. Track changes, collaborate, and edit from anywhere - even your phone with tools like Cursor Agents. No database migrations or CMS interfaces needed. Lightning fast.

## Main Objective

Generate static HTML pages using ERB files. Simple and flexible - add your own JavaScript bundling and CSS processing as needed.

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

Generated sites use:
- `static-site-builder` gem for compilation
- ERB files for HTML generation

## What Gets Generated

A clean project structure that depends on gems:

```
my-site/
├── Gemfile              # Dependencies (static-site-builder, sitemap_generator, etc.)
├── Rakefile            # Build tasks (includes sitemap generation)
├── config/
│   └── sitemap.rb      # Sitemap generation config
├── app/
│   ├── views/
│   │   ├── layouts/
│   │   ├── pages/
│   │   └── components/     # Reusable components/partials
│   ├── javascript/
│   └── assets/
│       └── stylesheets/
└── lib/
    └── site_builder.rb   # Compiles your site
```

## How It Works

1. **Generator** (`static-site-generator`) - Creates the project structure
2. **Builder Gem** (`static-site-builder`) - Handles ERB compilation
3. **Build Tools** - Rake tasks that use the builder gem
4. **Your Tools** - Add Tailwind CSS CLI, ESBuild, or any other tools you need

## Features

- 🎯 **Static HTML output** - No server-side rendering needed
- 🔧 **Simple & flexible** - ERB files, add your own tools
- 📦 **Gem-based** - Uses existing Ruby gems, not custom code
- 🚀 **Fast builds** - Compile once, deploy everywhere
- 🎨 **Component support** - ERB components and partials

## Building Powerful Websites

### Layouts and Partials

ERB files use **ActionView** with support for layouts and partials.

#### Layouts

Create a layout in `app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <%= display_meta_tags site: 'Site', title: 'Site' %>
  <link rel="stylesheet" href="/assets/stylesheets/application.css">
</head>
<body>
  <main>
    <%= yield %>
  </main>

  <% if content_for?(:javascript) %>
    <%= yield(:javascript) %>
  <% end %>
</body>
</html>
```

The `<%= yield %>` tag yields the content from your page ERB files, just like in Rails.

#### Partials

Use partials for reusable components. Partials are resolved relative to your page template's directory:

```erb
<%# In app/views/pages/about.html.erb %>
<h1>About</h1>
<%= render partial: 'shared/team_member', locals: { name: 'John', role: 'Developer' } %>
```

This looks for `app/views/pages/shared/_team_member.html.erb` or `app/views/shared/_team_member.html.erb`.

### SEO / Meta Tags

The layout includes app-wide defaults:

```erb
<%= display_meta_tags site: 'Site', title: 'Site' %>
```

To minimize code duplication, define default meta tags in `app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  def default_meta_tags
    {
      site: 'My Awesome Site',
      title: 'Default Title',
      description: 'A default description for my awesome site.',
      keywords: 'static site, ruby, erb, seo',
      separator: '&mdash;'.html_safe
    }
  end
end
```

Then in your layout, use:

```erb
<%= display_meta_tags(default_meta_tags) %>
```

Override in individual pages:

```erb
<% set_meta_tags title: 'Page Title', description: 'Page description' %>
```

You can also set Open Graph and Twitter Card tags:

```erb
<% set_meta_tags og: { title: 'OG Title', type: 'website', image: 'https://example.com/image.jpg' } %>
<% set_meta_tags twitter: { card: 'summary', site: '@username' } %>
```

See the [meta-tags gem documentation](https://github.com/kpumuk/meta-tags) for all available options.

### Adding JavaScript

Include JavaScript files in your pages:

```erb
<% content_for :javascript do %>
  <script src="/assets/javascripts/application.js"></script>
<% end %>
```

Set up your own bundler if needed and output to `dist/assets/javascripts/`. See setup guides:
- [ESBuild](guides/setup-esbuild.md)
- [Webpack](https://webpack.js.org/) - see webpack documentation
- [Vite](https://github.com/ElMassimo/vite_ruby) - see vite-plugin-ruby

### Adding CSS

Write CSS in `app/assets/stylesheets/application.css`. Use any CSS tool you prefer:

- [Tailwind CSS](guides/setup-tailwind.md)
- PostCSS, Sass, Less, or any other CSS processor - just compile your CSS files to `dist/assets/stylesheets/` before building HTML.

### Generating Sitemaps

Sitemap generation is automatically configured when you generate a new site. The `sitemap_generator` gem is included in the Gemfile, and `config/sitemap.rb` is automatically created.

The sitemap is automatically generated from all pages in `app/views/pages/` during `rake build:all`. Update `config/sitemap.rb` to set your domain:

```ruby
SitemapGenerator::Sitemap.default_host = 'https://yourdomain.com'
```

You can customize priority, changefreq, and lastmod in `config/sitemap.rb`. The sitemap will be generated in `dist/sitemaps/sitemap.xml.gz` during the build process.

## Examples

### Basic ERB Site
```bash
static-site-builder new my-site
```

## Notable Projects

Sites built with Static Site Builder:

- **[lukaszczapiewski.com](https://lukaszczapiewski.com)** - Personal portfolio and blog

**Your website?** Built with Static Site Builder? [Submit a PR](https://github.com/Ancez/static-site-builder) to add it here!

## Requirements

- Ruby 3.0+
- Bundler

Optional (if you want to use Tailwind CSS or JavaScript bundlers):
- Node.js and npm

## Development

### Running Your Site Locally

After generating a site, you can run it locally with auto-rebuild and live reload:

```bash
cd my-site
bundle install

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

1. **Create `wrangler.toml`** in your project root:
   ```toml
   name = 'your-worker-name'
   compatibility_date = '2025-01-22'
   ```
   
   Replace `your-worker-name` with your desired Worker name (must match your Cloudflare Pages project name).

2. **Connect your repository** to Cloudflare Pages in the Cloudflare dashboard

3. **Build settings**:
   - **Build command**: `rake build:all`
   - **Deploy command**: `npx wrangler deploy --assets=./dist`
   - **Version command**: `npx wrangler versions upload`
   - **Root directory**: `/`

4. **Deploy**: Cloudflare Pages will automatically build and deploy on every push to your main branch

**Note**: Ensure your `Gemfile` and `package.json` are properly configured. The build process will install dependencies automatically.

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
- Documentation improvements
- New features and improvements

## License

MIT
