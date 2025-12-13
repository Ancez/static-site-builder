# Deploying to Netlify

## Setup

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


