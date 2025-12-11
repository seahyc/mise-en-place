#!/usr/bin/env python3
"""
Test the modify_instructions prompt with a more explicit burnt onion scenario.
"""
import os
import json
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# Improved system message
system_message = """You are a cooking session modifier for a voice-guided cooking app. Analyze cooking issues and return atomic operations to help the user recover.

CRITICAL RULES:
1. For burnt_ingredient: The user needs to REPLACE the burnt ingredient. Insert a new prep step to prepare fresh replacement, then continue with the recipe.
2. NEVER just skip steps - help the user recover and continue successfully.
3. Consider what's already been done (completed steps) when making decisions.
4. Return valid JSON matching the schema exactly.

OPERATION TYPES (prefer non-video operations):
- insert: Add a new step (e.g., prep replacement ingredients)
- adjust_quantity: Change ingredient amount
- substitute: Replace ingredient with another
- skip: Mark a step as skipped (ONLY if truly unnecessary)
- update: Modify step text/description"""

# Test data with more context about the burnt onion issue
test_input = {
    "issue_type": "burnt_ingredient",
    "details": "I burnt the onions badly - they're black and bitter. I have more onions, can you help me recover?",
    "affected_ingredient": "onion",
    "affected_equipment": "none",
    "current_step_index": 2,
    "session_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "completed_steps": [
        {
            "id": "4f1927ae-7814-4c8e-b29b-82878c9d3092",
            "index": 0,
            "short_text": "Mise en Place",
            "detailed_description": "Dice {i:onion} (medium). Mince {i:garlic} and {i:jalapeno}. Measure spices..."
        },
        {
            "id": "daf17d2d-a7c6-4601-bc77-cb74a0207435",
            "index": 1,
            "short_text": "Sauté Aromatics",
            "detailed_description": "Heat {i:oil:qty} in the {e:dutch_oven} over medium heat. Sauté diced {i:onion} until translucent...",
            "ingredients": [
                {"placeholder_key": "oil", "name": "Olive Oil", "amount": 2},
                {"placeholder_key": "onion", "name": "Onion", "amount": 1},
                {"placeholder_key": "garlic", "name": "Garlic", "amount": 6},
                {"placeholder_key": "jalapeno", "name": "Jalapeño", "amount": 2}
            ]
        }
    ],
    "remaining_steps": [
        {
            "id": "ff3d5c15-12c9-438f-b29f-303e16d1c0c3",
            "index": 2,
            "short_text": "Bloom Spices",
            "detailed_description": "Stir in {i:tomato_paste:qty} and the spice mixture. Cook stirring constantly...",
            "ingredients": [{"placeholder_key": "tomato_paste", "name": "Tomato Paste", "amount": 2}]
        },
        {
            "id": "e4231d23-e919-417d-b90a-1f26ebaa2e73",
            "index": 3,
            "short_text": "Simmer",
            "detailed_description": "Deglaze with a splash of {i:broth}. Add {i:tomatoes:qty}, rinsed {i:kidney_beans} and {i:pinto_beans}...",
            "ingredients": [
                {"placeholder_key": "broth", "name": "Vegetable Broth", "amount": 2},
                {"placeholder_key": "tomatoes", "name": "Crushed Tomatoes", "amount": 28},
                {"placeholder_key": "kidney_beans", "name": "Kidney Beans", "amount": 2},
                {"placeholder_key": "pinto_beans", "name": "Pinto Beans", "amount": 2}
            ]
        },
        {
            "id": "1e859b12-42d5-4bd8-8bf0-88b6bda24852",
            "index": 4,
            "short_text": "Cook",
            "detailed_description": "Bring to a boil, then reduce heat to low. Simmer uncovered for 45-60 mins.",
            "ingredients": []
        },
        {
            "id": "d9b65d6a-c526-43cb-9434-8dd86f9ef1e1",
            "index": 5,
            "short_text": "Finish",
            "detailed_description": "Season with salt to taste. Serve hot.",
            "ingredients": []
        }
    ]
}

user_prompt = f"""ISSUE TYPE: {test_input['issue_type']}
DETAILS: {test_input['details']}
AFFECTED INGREDIENT: {test_input['affected_ingredient']}
CURRENT STEP INDEX: {test_input['current_step_index']}
SESSION ID: {test_input['session_id']}

COMPLETED STEPS (already done):
{json.dumps(test_input['completed_steps'], indent=2)}

REMAINING STEPS (can modify):
{json.dumps(test_input['remaining_steps'], indent=2)}

---
The user burnt the onions badly and has fresh onions available. Help them recover by:
1. Inserting a step to clean the pot and prep fresh onions
2. Inserting a step to re-sauté the fresh aromatics
3. Continuing with the remaining steps

Return atomic operations as JSON:
{{
  "operations": [
    {{"operation": "insert|adjust_quantity|substitute|skip|update", "step_index": <number>, ...}}
  ],
  "agent_message": "<friendly message>",
  "time_impact_minutes": <estimated extra time>
}}"""

print("=" * 60)
print("Testing with improved prompt (burnt onion recovery)")
print("=" * 60)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "system", "content": system_message},
        {"role": "user", "content": user_prompt}
    ],
    temperature=0.3
)

result = response.choices[0].message.content
print("\nRESPONSE:")
print("=" * 60)
print(result)

try:
    parsed = json.loads(result)
    print("\n" + "=" * 60)
    print("PARSED (pretty):")
    print("=" * 60)
    print(json.dumps(parsed, indent=2))
    
    print("\n" + "=" * 60)
    print("OPERATIONS SUMMARY:")
    print("=" * 60)
    for i, op in enumerate(parsed.get('operations', [])):
        print(f"  {i+1}. {op['operation'].upper()}: {op.get('short_text', op.get('placeholder_key', 'N/A'))}")
    print(f"\n  Agent message: {parsed.get('agent_message', 'N/A')}")
    print(f"  Time impact: +{parsed.get('time_impact_minutes', 0)} minutes")
except json.JSONDecodeError as e:
    print(f"\n⚠️  Could not parse as JSON: {e}")
