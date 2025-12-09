# Deploying to GitHub Pages

## Setup

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

