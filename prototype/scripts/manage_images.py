#!/usr/bin/env python3
"""
General-purpose tool for managing ingredient and equipment images in the database.

Usage:
    python scripts/manage_images.py check                    # Check all images for broken URLs
    python scripts/manage_images.py check --icons-only        # Check only icons (default_image_url/icon_url)
    python scripts/manage_images.py check --previews-only     # Check only preview images (image_url)
    python scripts/manage_images.py fix <name> <url>          # Fix a specific ingredient/equipment image
    python scripts/manage_images.py fix-broken                # Auto-fix all broken images with replacements
    python scripts/manage_images.py list-broken               # List all broken images without fixing
"""

import os
import sys
import requests
from supabase import create_client
from dotenv import load_dotenv
from concurrent.futures import ThreadPoolExecutor, as_completed

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_ANON_KEY')

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# Common replacement URLs for broken images
# These are known-working URLs for common ingredients/equipment
REPLACEMENT_URLS = {
    # Preview images (image_url)
    'Garlic': 'https://images.pexels.com/photos/2205316/pexels-photo-2205316.jpeg',
    'Mushrooms': 'https://images.pexels.com/photos/5737316/pexels-photo-5737316.jpeg',
}

# Icon replacements (default_image_url / icon_url)
ICON_REPLACEMENTS = {
    # Equipment icons - using alternative icon sources
    'Baking Dish': 'https://cdn-icons-png.flaticon.com/128/3050/3050142.png',
    'Baking Sheet': 'https://cdn-icons-png.flaticon.com/128/3050/3050142.png',
    'Blender': 'https://cdn-icons-png.flaticon.com/128/3050/3050131.png',
    'Food Processor': 'https://cdn-icons-png.flaticon.com/128/3050/3050131.png',
    'Knife': 'https://cdn-icons-png.flaticon.com/128/3050/3050179.png',
    'Ladle': 'https://cdn-icons-png.flaticon.com/128/3050/3050187.png',
    'Oven': 'https://cdn-icons-png.flaticon.com/128/3050/3050161.png',
    'Spatula': 'https://cdn-icons-png.flaticon.com/128/3050/3050187.png',
    'Whisk': 'https://cdn-icons-png.flaticon.com/128/3050/3050146.png',
}

def check_url(url, timeout=5):
    """Check if a URL is accessible."""
    if not url:
        return False, 'NO_URL'

    try:
        response = requests.head(url, timeout=timeout, allow_redirects=True)
        if response.status_code == 200:
            return True, 'OK'
        else:
            return False, f'HTTP {response.status_code}'
    except requests.exceptions.Timeout:
        return False, 'TIMEOUT'
    except requests.exceptions.RequestException as e:
        return False, str(e)

def check_images(icons_only=False, previews_only=False, verbose=True):
    """
    Check all images in the database.

    Args:
        icons_only: Only check icon URLs (default_image_url/icon_url)
        previews_only: Only check preview images (image_url)
        verbose: Print progress messages

    Returns:
        Dictionary with results categorized by status
    """
    if verbose:
        print("="*80)
        print("CHECKING IMAGES")
        print("="*80 + "\n")

    # Fetch data
    ingredients = supabase.table('ingredient_master').select('id, name, default_image_url, image_url').execute().data
    equipment = supabase.table('equipment_master').select('id, name, icon_url, image_url').execute().data

    if verbose:
        print(f"Found {len(ingredients)} ingredients and {len(equipment)} equipment\n")

    results = {
        'icons': {'ok': [], 'broken': [], 'missing': []},
        'previews': {'ok': [], 'broken': [], 'missing': []}
    }

    # Check ingredients
    for ing in ingredients:
        # Check icon (default_image_url)
        if not previews_only:
            icon_url = ing.get('default_image_url')
            is_ok, status = check_url(icon_url)

            item_info = {
                'type': 'ingredient',
                'id': ing['id'],
                'name': ing['name'],
                'url': icon_url,
                'status': status
            }

            if not icon_url:
                results['icons']['missing'].append(item_info)
            elif is_ok:
                results['icons']['ok'].append(item_info)
            else:
                results['icons']['broken'].append(item_info)

        # Check preview image (image_url)
        if not icons_only:
            preview_url = ing.get('image_url')
            is_ok, status = check_url(preview_url)

            item_info = {
                'type': 'ingredient',
                'id': ing['id'],
                'name': ing['name'],
                'url': preview_url,
                'status': status
            }

            if not preview_url:
                results['previews']['missing'].append(item_info)
            elif is_ok:
                results['previews']['ok'].append(item_info)
            else:
                results['previews']['broken'].append(item_info)

    # Check equipment
    for eq in equipment:
        # Check icon (icon_url)
        if not previews_only:
            icon_url = eq.get('icon_url')
            is_ok, status = check_url(icon_url)

            item_info = {
                'type': 'equipment',
                'id': eq['id'],
                'name': eq['name'],
                'url': icon_url,
                'status': status
            }

            if not icon_url:
                results['icons']['missing'].append(item_info)
            elif is_ok:
                results['icons']['ok'].append(item_info)
            else:
                results['icons']['broken'].append(item_info)

        # Check preview image (image_url)
        if not icons_only:
            preview_url = eq.get('image_url')
            is_ok, status = check_url(preview_url)

            item_info = {
                'type': 'equipment',
                'id': eq['id'],
                'name': eq['name'],
                'url': preview_url,
                'status': status
            }

            if not preview_url:
                results['previews']['missing'].append(item_info)
            elif is_ok:
                results['previews']['ok'].append(item_info)
            else:
                results['previews']['broken'].append(item_info)

    if verbose:
        print_results(results, icons_only, previews_only)

    return results

def print_results(results, icons_only=False, previews_only=False):
    """Print check results in a formatted way."""
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)

    if not previews_only:
        total_icons = len(results['icons']['ok']) + len(results['icons']['broken']) + len(results['icons']['missing'])
        print(f"\n📦 Icons (default_image_url / icon_url):")
        print(f"   ✅ Working: {len(results['icons']['ok'])}/{total_icons}")
        print(f"   ❌ Broken:  {len(results['icons']['broken'])}/{total_icons}")
        print(f"   ⚠️  Missing: {len(results['icons']['missing'])}/{total_icons}")

    if not icons_only:
        total_previews = len(results['previews']['ok']) + len(results['previews']['broken']) + len(results['previews']['missing'])
        print(f"\n🖼️  Preview Images (image_url):")
        print(f"   ✅ Working: {len(results['previews']['ok'])}/{total_previews}")
        print(f"   ❌ Broken:  {len(results['previews']['broken'])}/{total_previews}")
        print(f"   ⚠️  Missing: {len(results['previews']['missing'])}/{total_previews}")

    # Print broken items
    if results['icons']['broken'] and not previews_only:
        print("\n" + "="*80)
        print("BROKEN ICONS")
        print("="*80)
        for item in sorted(results['icons']['broken'], key=lambda x: x['name']):
            print(f"\n{item['type'].title()}: {item['name']}")
            print(f"  URL: {item['url']}")
            print(f"  Error: {item['status']}")

    if results['previews']['broken'] and not icons_only:
        print("\n" + "="*80)
        print("BROKEN PREVIEW IMAGES")
        print("="*80)
        for item in sorted(results['previews']['broken'], key=lambda x: x['name']):
            print(f"\n{item['type'].title()}: {item['name']}")
            print(f"  URL: {item['url']}")
            print(f"  Error: {item['status']}")

def fix_image(name, new_url, image_type='preview'):
    """
    Fix a specific ingredient or equipment image.

    Args:
        name: Name of the ingredient or equipment
        new_url: New URL to set
        image_type: 'icon' or 'preview' (default: 'preview')
    """
    # Try ingredient first
    ing_result = supabase.table('ingredient_master').select('id, name').eq('name', name).execute()

    if ing_result.data:
        field = 'default_image_url' if image_type == 'icon' else 'image_url'
        supabase.table('ingredient_master').update({field: new_url}).eq('name', name).execute()
        print(f"✅ Updated ingredient '{name}' {image_type}: {new_url}")
        return True

    # Try equipment
    eq_result = supabase.table('equipment_master').select('id, name').eq('name', name).execute()

    if eq_result.data:
        field = 'icon_url' if image_type == 'icon' else 'image_url'
        supabase.table('equipment_master').update({field: new_url}).eq('name', name).execute()
        print(f"✅ Updated equipment '{name}' {image_type}: {new_url}")
        return True

    print(f"❌ Not found: {name}")
    return False

def fix_broken_images(auto_fix=False):
    """
    Fix all broken images.

    Args:
        auto_fix: If True, automatically use replacement URLs. If False, prompt for each.
    """
    print("="*80)
    print("FIXING BROKEN IMAGES")
    print("="*80 + "\n")

    results = check_images(verbose=False)

    broken_items = results['icons']['broken'] + results['previews']['broken']

    if not broken_items:
        print("✅ No broken images found!")
        return

    print(f"Found {len(broken_items)} broken images\n")

    fixed_count = 0

    for item in broken_items:
        name = item['name']
        is_icon = item in results['icons']['broken']

        # Check appropriate replacement dict
        replacement_dict = ICON_REPLACEMENTS if is_icon else REPLACEMENT_URLS

        if name in replacement_dict:
            new_url = replacement_dict[name]

            # Verify replacement works
            is_ok, status = check_url(new_url)

            if is_ok:
                image_type = 'icon' if is_icon else 'preview'

                if auto_fix:
                    fix_image(name, new_url, image_type)
                    fixed_count += 1
                else:
                    response = input(f"Fix {name} {image_type} with {new_url}? (y/n): ")
                    if response.lower() == 'y':
                        fix_image(name, new_url, image_type)
                        fixed_count += 1
            else:
                print(f"⚠️  Replacement URL also broken for {name}: {status}")
        else:
            image_type = 'icon' if is_icon else 'preview'
            print(f"⚠️  No replacement {image_type} URL defined for: {name}")

    print(f"\n✅ Fixed {fixed_count} images")

def list_broken():
    """List all broken images without fixing."""
    results = check_images(verbose=False)

    broken_icons = results['icons']['broken']
    broken_previews = results['previews']['broken']

    if not broken_icons and not broken_previews:
        print("✅ No broken images found!")
        return

    if broken_icons:
        print("\n📦 BROKEN ICONS:")
        for item in sorted(broken_icons, key=lambda x: x['name']):
            print(f"  - {item['name']} ({item['type']})")

    if broken_previews:
        print("\n🖼️  BROKEN PREVIEW IMAGES:")
        for item in sorted(broken_previews, key=lambda x: x['name']):
            print(f"  - {item['name']} ({item['type']})")

def main():
    """Main CLI interface."""
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == 'check':
        icons_only = '--icons-only' in sys.argv
        previews_only = '--previews-only' in sys.argv
        check_images(icons_only=icons_only, previews_only=previews_only)

    elif command == 'fix':
        if len(sys.argv) < 4:
            print("Usage: python scripts/manage_images.py fix <name> <url> [--icon]")
            sys.exit(1)

        name = sys.argv[2]
        url = sys.argv[3]
        image_type = 'icon' if '--icon' in sys.argv else 'preview'
        fix_image(name, url, image_type)

    elif command == 'fix-broken':
        auto_fix = '--auto' in sys.argv
        fix_broken_images(auto_fix=auto_fix)

    elif command == 'list-broken':
        list_broken()

    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)

if __name__ == '__main__':
    main()
