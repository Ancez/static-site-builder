# Setting Up Tailwind CSS

## Installation

```bash
npm install -D tailwindcss
npx tailwindcss init
```

This creates `tailwind.config.js` and `postcss.config.js`.

## Configuration

Configure `tailwind.config.js` to scan your ERB and JS files:

```js
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/views/**/*.{html,erb}",
    "./app/javascript/**/*.js",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

## Add Tailwind Directives

Add Tailwind directives to `app/assets/stylesheets/application.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

## Build CSS

Compile CSS for production:

```bash
tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --minify
```

For watch mode during development:

```bash
tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --watch
```

## Rake Tasks (Optional)

Add to your Rakefile for easier building:

```ruby
task :build_css do
  sh "tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --minify"
end

task :watch_css do
  sh "tailwindcss -i ./app/assets/stylesheets/application.css -o ./dist/assets/stylesheets/application.css --watch"
end
```

