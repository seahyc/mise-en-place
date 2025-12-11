# Scripts Directory

This directory contains utility scripts for managing the Mise en Place database and assets.

## Image Management

### `manage_images.py`

General-purpose tool for managing ingredient and equipment images in the database. Handles both icon URLs (`default_image_url`/`icon_url`) and preview images (`image_url`).

**Usage:**

```bash
# Activate virtual environment first
source venv/bin/activate

# Check all images for broken URLs
python scripts/manage_images.py check

# Check only icons (default_image_url / icon_url)
python scripts/manage_images.py check --icons-only

# Check only preview images (image_url)
python scripts/manage_images.py check --previews-only

# List broken images without fixing
python scripts/manage_images.py list-broken

# Fix a specific ingredient/equipment preview image
python scripts/manage_images.py fix "Garlic" "https://example.com/garlic.jpg"

# Fix a specific ingredient/equipment icon
python scripts/manage_images.py fix "Garlic" "https://example.com/garlic-icon.png" --icon

# Auto-fix all broken images using predefined replacements
python scripts/manage_images.py fix-broken --auto

# Fix broken images with prompts (interactive)
python scripts/manage_images.py fix-broken
```

**Image Types:**

- **Icons** (`default_image_url` for ingredients, `icon_url` for equipment)
  - Small icons displayed in Recipe Detail Screen equipment lists
  - Typically 48x48px or similar
  - Sources: Icons8, Flaticon

- **Preview Images** (`image_url`)
  - Photo previews shown in Cooking Mode Screen inline instruction text (hover tooltips)
  - Typically 500px width
  - Sources: Pexels, Unsplash, Wikimedia Commons

**Adding Custom Replacements:**

Edit the `REPLACEMENT_URLS` and `ICON_REPLACEMENTS` dictionaries in `manage_images.py`:

```python
REPLACEMENT_URLS = {
    'Garlic': 'https://images.pexels.com/photos/2205316/pexels-photo-2205316.jpeg',
    # Add more preview image replacements here
}

ICON_REPLACEMENTS = {
    'Knife': 'https://cdn-icons-png.flaticon.com/128/3050/3050179.png',
    # Add more icon replacements here
}
```

## Database Management

### `seed_supabase.py`

Seeds the Supabase database with initial recipe data, ingredients, equipment, and images.

**Usage:**

```bash
source venv/bin/activate
python scripts/seed_supabase.py
```

### `fix_supabase_schema.py`

Fixes or updates the database schema structure.

### `verify_schema.py`

Verifies the database schema is correct.

## Testing Scripts

### `test_integrations.py`

Tests various integrations and workflows.

### `test_modify_*.py`

Various test scripts for testing prompt modifications and structured data handling.

## Environment Variables

All scripts require these environment variables in `.env`:

```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```
