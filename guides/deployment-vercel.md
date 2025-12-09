# Deploying to Vercel

## Setup

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

## Configuration File (Optional)

Create `vercel.json` in your project root:
```json
{
  "buildCommand": "bundle install && npm install && bundle exec rake build:all",
  "outputDirectory": "dist",
  "installCommand": "bundle install && npm install"
}
```

