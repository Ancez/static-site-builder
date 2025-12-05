# Upgrading from Previous Versions

If you have an existing site generated with an older version that included JavaScript bundler and CSS framework options, here's how to upgrade:

## 1. Update Builder Configuration

Remove `js_bundler` and `importmap_config` parameters from `lib/site_builder.rb`:

**Before:**
```ruby
builder = StaticSiteBuilder::Builder.new(
  root: Dir.pwd,
  template_engine: "erb",
  js_bundler: "importmap",
  importmap_config: "config/importmap.rb"
)
```

**After:**
```ruby
builder = StaticSiteBuilder::Builder.new(
  root: Dir.pwd,
  template_engine: "erb"
)
```

## 2. Update Layouts

Replace importmap-based JavaScript loading with `content_for :javascript`:

**Before:**
```erb
<% if importmap_json %>
  <script type="importmap">
    <%= raw importmap_json %>
  </script>
<% end %>

<% modules_to_import = (@js_modules || []).dup %>
<% modules_to_import.each do |module_name| %>
  <script type="module">import "<%= module_name %>";</script>
<% end %>
```

**After:**
```erb
<% if content_for?(:javascript) %>
  <%= yield(:javascript) %>
<% end %>
```

## 3. Update Pages

Remove `@js_modules` assignments and use `content_for :javascript` instead:

**Before:**
```erb
<% @js_modules = ['application'] %>
<!-- page content -->
```

**After:**
```erb
<% content_for :javascript do %>
  <script type="module" src="/assets/javascripts/application.js"></script>
<% end %>
<!-- page content -->
```

## 4. Handle JavaScript Bundling

If you were using importmap, you can:
- Continue using importmap manually (keep `config/importmap.rb` and handle it yourself)
- Switch to ESBuild, Webpack, or Vite (see setup guides in the generated README)
- Use vanilla JavaScript without bundling

## 5. Handle CSS Processing

If you were using Tailwind CSS via the generator:
- Keep your `tailwind.config.js` and `package.json` scripts
- Continue using `npm run build:css` and `npm run watch:css`
- The generator no longer creates these automatically, but your existing setup will continue working

## 6. Update Rakefile (Optional)

The generated Rakefile is now simpler. If you have custom build tasks, you can keep them. The basic structure is:

```ruby
namespace :build do
  task :all => [:html, :sitemap] do
    # Your custom tasks here
  end
end
```

## Summary

The generator is now simpler and more flexible. You keep full control over JavaScript bundling and CSS processing, while the generator focuses on ERB template compilation. Your existing projects will continue to work - just update the Builder configuration and layouts as shown above.

