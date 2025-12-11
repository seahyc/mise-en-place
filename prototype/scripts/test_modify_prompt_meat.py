#!/usr/bin/env python3
"""
Test: User wants to turn Vegan Chili into a meat-based dish.
"""
import os
import json
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

system_message = """You are a cooking session modifier for a voice-guided cooking app. Analyze cooking issues and return atomic operations to help the user recover and continue successfully.

CRITICAL RECOVERY RULES:
- burnt_ingredient: User needs to REPLACE the burnt ingredient. Insert steps to clean the pot and prep fresh replacement, then re-cook the affected step.
- missing_ingredient: Substitute with a similar ingredient, or skip the step if non-essential.
- equipment_issue: Suggest alternative technique or equipment.
- timing_issue: Adjust subsequent steps to compensate.
- user_request: Be creative but respect the dish's integrity. For major changes (like adding meat to a vegan dish), insert new steps and adjust existing ones.
- dietary_restriction: Remove/substitute problematic ingredients across ALL remaining steps.

NEVER just skip steps unless truly unnecessary. Help the user succeed!

You MUST always respond with valid JSON matching the exact schema structure. Never include explanations outside the JSON."""

test_input = {
    "issue_type": "user_request",
    "details": "Can we make this with ground beef instead? I want it to be a proper meat chili.",
    "affected_ingredient": "none",
    "affected_equipment": "none",
    "current_step_index": 0,  # Starting from the beginning
    "session_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "completed_steps": [],  # Nothing done yet
    "remaining_steps": [
        {
            "id": "4f1927ae-7814-4c8e-b29b-82878c9d3092",
            "index": 0,
            "short_text": "Mise en Place",
            "detailed_description": "Dice {i:onion} (medium). Mince {i:garlic} and {i:jalapeno}. Measure spices ({i:chili_powder:qty}, {i:cumin:qty}, {i:paprika:qty}) into a small bowl. Open cans of {i:kidney_beans} and {i:tomatoes}. Rinse beans.",
            "ingredients": [
                {"placeholder_key": "onion", "name": "Onion", "amount": 1},
                {"placeholder_key": "garlic", "name": "Garlic", "amount": 6},
                {"placeholder_key": "jalapeno", "name": "Jalapeño", "amount": 2},
                {"placeholder_key": "chili_powder", "name": "Chili Powder", "amount": 3},
                {"placeholder_key": "cumin", "name": "Cumin", "amount": 1},
                {"placeholder_key": "paprika", "name": "Smoked Paprika", "amount": 1.5},
                {"placeholder_key": "kidney_beans", "name": "Kidney Beans", "amount": 2},
                {"placeholder_key": "tomatoes", "name": "Crushed Tomatoes", "amount": 28}
            ]
        },
        {
            "id": "daf17d2d-a7c6-4601-bc77-cb74a0207435",
            "index": 1,
            "short_text": "Sauté Aromatics",
            "detailed_description": "Heat {i:oil:qty} in the {e:dutch_oven} over medium heat. Sauté diced {i:onion} until translucent (5-7 mins). Add minced {i:garlic} and {i:jalapeno}, cook 1 min until fragrant.",
            "ingredients": [
                {"placeholder_key": "oil", "name": "Olive Oil", "amount": 2},
                {"placeholder_key": "onion", "name": "Onion", "amount": 1},
                {"placeholder_key": "garlic", "name": "Garlic", "amount": 6},
                {"placeholder_key": "jalapeno", "name": "Jalapeño", "amount": 2}
            ]
        },
        {
            "id": "ff3d5c15-12c9-438f-b29f-303e16d1c0c3",
            "index": 2,
            "short_text": "Bloom Spices",
            "detailed_description": "Stir in {i:tomato_paste:qty} and the spice mixture. Cook stirring constantly with {e:wooden_spoon} for 2 mins until spices darken.",
            "ingredients": [{"placeholder_key": "tomato_paste", "name": "Tomato Paste", "amount": 2}]
        },
        {
            "id": "e4231d23-e919-417d-b90a-1f26ebaa2e73",
            "index": 3,
            "short_text": "Simmer",
            "detailed_description": "Deglaze with a splash of {i:broth}. Add {i:tomatoes:qty}, rinsed {i:kidney_beans} and {i:pinto_beans}, and remaining {i:broth}. Stir well to combine.",
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
            "detailed_description": "Bring to a boil in the {e:dutch_oven}, then reduce heat to low. Simmer uncovered for 45-60 mins until thickened.",
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
The user wants to convert this VEGAN chili into a MEAT-BASED chili with ground beef.

Consider:
1. Need to add ground beef (about 1 lb / 450g)
2. Insert a step to brown the beef BEFORE sautéing aromatics
3. Possibly substitute vegetable broth with beef broth
4. Adjust cooking instructions to incorporate the browned beef

Return atomic operations as JSON. Use 'insert' for new steps and 'substitute' for ingredient swaps.

Schema:
{{
  "operations": [...],
  "agent_message": "<friendly message>",
  "time_impact_minutes": <estimated extra time>
}}"""

print("=" * 60)
print("Testing: Convert Vegan Chili to Meat-Based")
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

try:
    parsed = json.loads(result)
    print(json.dumps(parsed, indent=2))
    
    print("\n" + "=" * 60)
    print("OPERATIONS SUMMARY:")
    print("=" * 60)
    for i, op in enumerate(parsed.get('operations', [])):
        op_type = op['operation'].upper()
        if op_type == 'INSERT':
            print(f"  {i+1}. {op_type} @ index {op.get('step_index')}: {op.get('short_text')}")
        elif op_type == 'SUBSTITUTE':
            print(f"  {i+1}. {op_type}: {op.get('placeholder_key')} -> new ingredient")
        elif op_type == 'UPDATE':
            print(f"  {i+1}. {op_type} step {op.get('step_id', 'N/A')[:8]}...: {op.get('short_text', 'N/A')}")
        else:
            print(f"  {i+1}. {op_type}: {op.get('short_text', op.get('placeholder_key', 'N/A'))}")
    
    print(f"\n  Agent message: {parsed.get('agent_message', 'N/A')}")
    print(f"  Time impact: +{parsed.get('time_impact_minutes', 0)} minutes")
except json.JSONDecodeError as e:
    print(result)
    print(f"\n⚠️  Could not parse as JSON: {e}")
