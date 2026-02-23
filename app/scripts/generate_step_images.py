#!/usr/bin/env python3
"""Generate Japanese watercolor style images for Vegan Chili recipe steps."""

import os
import time

import requests
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.environ['SUPABASE_URL']
SUPABASE_KEY = os.environ['SUPABASE_ANON_KEY']
WEBHOOK_URL = os.environ.get('N8N_WEBHOOK_URL', 'https://miseenplace.app.n8n.cloud/webhook/generate-image')

# Vegan Chili steps with Japanese watercolor style prompts
STEPS = [
    {
        "id": "2a180927-243e-4d59-a81e-b3a8934fb959",
        "short_text": "Mise en Place",
        "prompt": "Japanese watercolor illustration, soft ink washes, cooking prep scene: wooden cutting board with neatly diced onion, small piles of minced garlic and jalapeno, ceramic bowl with vibrant red-orange spices (chili powder, cumin, paprika), opened cans of kidney beans and crushed tomatoes nearby, clean minimal composition, warm earthy tones, delicate black ink outlines, white space, zen aesthetic"
    },
    {
        "id": "73439411-b03a-4038-94f8-251145b4d140",
        "short_text": "Sauté Aromatics",
        "prompt": "Japanese watercolor illustration, soft ink washes, cooking scene: cast iron dutch oven on stovetop with golden olive oil shimmering, translucent onions being sautéed with wooden spoon, aromatic steam rising, minced garlic and jalapeno being added, warm amber and golden tones, delicate black ink outlines, minimal zen composition"
    },
    {
        "id": "6a8d00d4-ce95-4999-89d1-eb4511853878",
        "short_text": "Bloom Spices",
        "prompt": "Japanese watercolor illustration, soft ink washes, cooking scene: wooden spoon stirring deep red tomato paste and colorful spices in dutch oven, rich burgundy and rust colors blooming, aromatic steam swirls, darkening spice mixture, warm earthy palette, delicate black ink outlines, zen minimalist style"
    },
    {
        "id": "e31d8a50-0c92-4e14-a627-4546effd161d",
        "short_text": "Simmer",
        "prompt": "Japanese watercolor illustration, soft ink washes, cooking scene: dutch oven being deglazed with splash of broth, crushed tomatoes and colorful beans (kidney and pinto) being added, rich red sauce forming, steam rising, warm terracotta and amber tones, delicate black ink outlines, zen composition"
    },
    {
        "id": "3919abdc-ef47-4d71-a892-5a49da3a75e1",
        "short_text": "Cook",
        "prompt": "Japanese watercolor illustration, soft ink washes, cooking scene: dutch oven on low heat with bubbling chili, thick rich sauce slowly simmering, gentle steam rising, timer showing 45 minutes, cozy kitchen atmosphere, deep red and brown tones, delicate black ink outlines, peaceful zen aesthetic"
    },
    {
        "id": "8687e2cf-5325-4c87-9931-a33e4c147931",
        "short_text": "Finish",
        "prompt": "Japanese watercolor illustration, soft ink washes, serving scene: beautiful bowl of finished vegan chili, garnished with fresh cilantro and lime wedge, rustic ceramic bowl, steam rising invitingly, warm homey atmosphere, rich reds and greens, delicate black ink outlines, zen minimalist presentation"
    }
]

def generate_image(step):
    """Call n8n webhook to generate image for a step."""
    print(f"\n🎨 Generating image for: {step['short_text']}...")

    try:
        response = requests.post(
            WEBHOOK_URL,
            json={
                "prompt": step["prompt"],
                "step_id": step["id"]
            },
            timeout=120
        )

        if response.status_code == 200:
            data = response.json()
            # Handle both 'url' and 'image_url' response formats
            image_url = data.get('url') or data.get('image_url')
            if image_url:
                print(f"   ✅ Success! URL: {image_url[:60]}...")
                return image_url
            else:
                print(f"   ❌ No url in response: {data}")
                return None
        else:
            print(f"   ❌ HTTP {response.status_code}: {response.text[:100]}")
            return None

    except Exception as e:
        print(f"   ❌ Error: {e}")
        return None

def update_step_media_url(supabase, step_id, media_url):
    """Update the instruction_steps table with the new media_url."""
    try:
        result = supabase.table('instruction_steps').update({
            'media_url': media_url
        }).eq('id', step_id).execute()
        print(f"   📝 Updated database")
        return True
    except Exception as e:
        print(f"   ❌ DB update failed: {e}")
        return False

def main():
    print("=" * 60)
    print("🍲 Vegan Chili Step Image Generator")
    print("   Style: Japanese Watercolor Illustration")
    print("=" * 60)

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

    success_count = 0
    for i, step in enumerate(STEPS):
        print(f"\n[{i+1}/{len(STEPS)}] {step['short_text']}")

        # Generate image
        image_url = generate_image(step)

        if image_url:
            # Update database
            if update_step_media_url(supabase, step["id"], image_url):
                success_count += 1

        # Small delay between requests
        if i < len(STEPS) - 1:
            print("   ⏳ Waiting 2s before next request...")
            time.sleep(2)

    print("\n" + "=" * 60)
    print(f"✨ Complete! {success_count}/{len(STEPS)} images generated")
    print("=" * 60)

if __name__ == "__main__":
    main()
