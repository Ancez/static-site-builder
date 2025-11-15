# Architecture

This project is a **generator tool**, similar to `rails new`. It creates static site projects that use standard Ruby gems.

## Structure

```
static-site-generator/
├── lib/
│   └── generator.rb          # Main generator logic
├── bin/
│   └── generate              # CLI entry point
├── exe/
│   └── static-site-generator # Gem executable
└── templates/                # Template files (future)
```

## How It Works

1. **Generator** (`static-site-generator` gem)
   - Creates project structure
   - Generates Gemfile with dependencies
   - Creates config files
   - Sets up build tasks

2. **Builder Gem** (`static-site-builder` gem) - **Separate gem**
   - Handles ERB/Phlex compilation
   - Manages asset copying
   - Generates importmap JSON
   - Outputs static HTML

3. **Standard Gems** - Used by generated sites
   - `importmap-rails` - Importmap support
   - `phlex-rails` - Phlex components
   - `static-site-builder` - Core builder functionality

## Generated Site Structure

```
my-site/
├── Gemfile              # Dependencies
├── package.json         # JS dependencies (if needed)
├── Rakefile            # Build tasks
├── config/
│   └── importmap.rb    # Importmap config
├── app/
│   ├── views/
│   ├── javascript/
│   └── assets/
└── lib/
    └── site_builder.rb  # Thin wrapper using static-site-builder gem
```

## Separation of Concerns

- **Generator** - Creates projects (this repo)
- **Builder** - Compiles sites (`static-site-builder` gem)
- **Standard Gems** - Provide functionality (importmap-rails, etc.)

This keeps the generator lightweight and maintainable.

