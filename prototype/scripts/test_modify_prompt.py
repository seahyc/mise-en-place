#!/usr/bin/env python3
"""
Test the modify_instructions prompt directly with OpenAI.
"""
import os
import json
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# System message from n8n workflow
system_message = """You are a cooking session modifier. Analyze the issue or request and return atomic operations to adjust the recipe. Consider what's already been done (completed steps) when making decisions.

You MUST always respond with valid JSON matching the exact schema structure. Never include explanations outside the JSON."""

# Test data matching our seeded Supabase data
test_input = {
    "issue_type": "burnt_ingredient",
    "details": "I burnt the onions while sautéing",
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

# User prompt matching n8n workflow template
user_prompt = f"""ISSUE TYPE: {test_input['issue_type']}
DETAILS: {test_input['details']}
AFFECTED INGREDIENT: {test_input['affected_ingredient']}
AFFECTED EQUIPMENT: {test_input['affected_equipment']}
CURRENT STEP INDEX: {test_input['current_step_index']}
SESSION ID: {test_input['session_id']}

COMPLETED STEPS (already done, cannot change):
{json.dumps(test_input['completed_steps'], indent=2)}

REMAINING STEPS (can modify):
{json.dumps(test_input['remaining_steps'], indent=2)}

---
ISSUE TYPES:
- burnt_ingredient: User burnt/overcooked something
- missing_ingredient: User doesn't have an ingredient
- equipment_issue: Equipment broken/missing/malfunctioning
- timing_issue: Something took too long/short
- user_request: User wants to change something (spicier, add veggies, etc.)
- dietary_restriction: User mentions allergy/diet mid-cooking
- portion_change: User wants more/less servings
- other: Anything else

Return atomic operations for REMAINING STEPS ONLY.

OPERATION TYPES:
- insert: Add a new step (requires video generation)
- update: Modify step text/description (may require video)
- skip: Mark a step as skipped
- adjust_quantity: Change ingredient amount (no video needed)
- substitute: Replace ingredient with another (no video needed)

RULES:
1. PREFER adjust_quantity/substitute/skip over insert (saves video generation)
2. Consider what ingredients were already used in completed steps
3. Only modify remaining steps (index >= current_step_index)
4. For equipment_issue: suggest alternative technique or equipment
5. For user_request: be creative but respect the dish's integrity
6. Keep agent_message warm, friendly, and reassuring
7. Always return valid JSON matching the required schema

You MUST respond with JSON matching this schema:
{{
  "operations": [
    {{
      "operation": "insert|adjust_quantity|substitute|skip|update",
      "step_index": <number>,
      "step_id": "<uuid if modifying existing step>",
      "short_text": "<for insert/update>",
      "detailed_description": "<for insert/update>",
      "placeholder_key": "<for adjust_quantity/substitute>",
      "new_amount": <number for adjust_quantity/substitute>,
      "new_ingredient_id": "<uuid for substitute>",
      "substitution_note": "<for substitute>",
      "agent_notes": "<notes for the step>"
    }}
  ],
  "agent_message": "<friendly message to tell the user>",
  "time_impact_minutes": <estimated time impact>
}}"""

print("=" * 60)
print("Testing OpenAI with burnt onion scenario")
print("=" * 60)
print(f"\nSystem Message:\n{system_message[:200]}...")
print(f"\nUser Prompt:\n{user_prompt[:500]}...")
print("\n" + "=" * 60)
print("Calling OpenAI gpt-4o-mini...")
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
print("\n" + "=" * 60)
print("RESPONSE:")
print("=" * 60)
print(result)

# Try to parse as JSON
try:
    parsed = json.loads(result)
    print("\n" + "=" * 60)
    print("PARSED JSON (pretty):")
    print("=" * 60)
    print(json.dumps(parsed, indent=2))
except json.JSONDecodeError as e:
    print(f"\n⚠️  Could not parse as JSON: {e}")
