# Deploying to Other Static Hosts

For any static hosting provider (AWS S3, Azure Static Web Apps, etc.):

## Build Locally

```bash
bundle install
npm install
bundle exec rake build:all
```

## Deploy

1. **Upload `dist/` directory** to your hosting provider
2. **Configure** your host to serve from the `dist` directory

## CI/CD Considerations

- **Vendor files**: Vendor files are automatically copied from `node_modules` to `dist/` during build - no vendor folder needed
- **Dependencies**: Both Ruby (`Gemfile`) and Node.js (`package.json`) dependencies are needed for the build
- **Build order**: Install dependencies → Build assets → Build HTML
- **Ruby/Node versions**: Specify versions in your CI/CD configuration to ensure consistent builds


