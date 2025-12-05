# Setting Up ESBuild

## Installation

```bash
npm install --save-dev esbuild
```

## Configuration

Create `esbuild.config.js`:

```js
require('esbuild').build({
  entryPoints: ['app/javascript/application.js'],
  bundle: true,
  outdir: 'dist/assets/javascripts',
  format: 'esm',
  minify: true,
}).catch(() => process.exit(1))
```

## Rake Tasks

Add to your Rakefile:

```ruby
task :build_js do
  sh "node esbuild.config.js"
end
```

## Usage in Templates

In your page templates, use `content_for :javascript`:

```erb
<% content_for :javascript do %>
  <script type="module" src="/assets/javascripts/application.js"></script>
<% end %>
```

