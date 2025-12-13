# Deploying to Cloudflare Pages

## Setup

1. **Create `wrangler.toml`** in your project root:
   ```toml
   name = 'your-worker-name'
   compatibility_date = '2025-01-22'
   ```
   
   Replace `your-worker-name` with your desired Worker name (must match your Cloudflare Pages project name).

2. **Connect your repository** to Cloudflare Pages in the Cloudflare dashboard

3. **Build settings**:
   - **Build command**: `bundle exec rake build:all`
   - **Deploy command**: `npx wrangler deploy --assets=./dist`
   - **Version command**: `npx wrangler versions upload --assets=./dist`
   - **Root directory**: `/`

4. **Deploy**: Cloudflare Pages will automatically build and deploy on every push to your main branch

## Notes

- `bundle exec rake build:all` cleans `dist/` and rebuilds everything into `dist/`
- If you use npm tooling (Tailwind, bundlers), add the relevant `package.json` scripts and they will be picked up by the generated `Rakefile`

