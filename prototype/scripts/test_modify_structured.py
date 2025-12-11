#!/usr/bin/env python3
"""
Test using OpenAI Structured Outputs - all fields required but nullable.
"""
import os
import json
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# Schema with all fields required (use null when not applicable)
json_schema = {
    "name": "modify_instructions_response",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "operations": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "operation": {
                            "type": "string",
                            "enum": ["insert", "substitute", "adjust_quantity", "skip", "update"]
                        },
                        "step_index": {"type": ["integer", "null"]},
                        "step_id": {"type": ["string", "null"]},
                        "short_text": {"type": ["string", "null"]},
                        "detailed_description": {"type": ["string", "null"]},
                        "placeholder_key": {"type": ["string", "null"]},
                        "new_ingredient_id": {"type": ["string", "null"]},
                        "new_amount": {"type": ["number", "null"]},
                        "substitution_note": {"type": ["string", "null"]},
                        "agent_notes": {"type": ["string", "null"]}
                    },
                    "required": ["operation", "step_index", "step_id", "short_text", "detailed_description", 
                                 "placeholder_key", "new_ingredient_id", "new_amount", "substitution_note", "agent_notes"],
                    "additionalProperties": False
                }
            },
            "agent_message": {"type": "string"},
            "time_impact_minutes": {"type": "integer"}
        },
        "required": ["operations", "agent_message", "time_impact_minutes"],
        "additionalProperties": False
    }
}

system_message = """You are a cooking session modifier. Convert a vegan dish to meat-based when requested.

For vegan-to-meat conversion:
1. INSERT a step to brown the meat (usually at index 1, after prep)
2. SUBSTITUTE vegetable broth with beef/chicken broth where applicable
3. UPDATE any steps that need to incorporate the cooked meat

Operations:
- insert: step_index + short_text + detailed_description required
- substitute: step_id + placeholder_key + new_ingredient_id required
- update: step_id + short_text + detailed_description required
- skip: step_id required
- adjust_quantity: step_id + placeholder_key + new_amount required

Set unused fields to null."""

test_input = {
    "issue_type": "user_request",
    "details": "Can we make this with ground beef instead? I want a proper meat chili.",
    "remaining_steps": [
        {"id": "4f1927ae-7814-4c8e-b29b-82878c9d3092", "index": 0, "short_text": "Mise en Place"},
        {"id": "daf17d2d-a7c6-4601-bc77-cb74a0207435", "index": 1, "short_text": "Sauté Aromatics"},
        {"id": "ff3d5c15-12c9-438f-b29f-303e16d1c0c3", "index": 2, "short_text": "Bloom Spices"},
        {"id": "e4231d23-e919-417d-b90a-1f26ebaa2e73", "index": 3, "short_text": "Simmer", 
         "ingredients": [{"placeholder_key": "broth", "name": "Vegetable Broth"}]},
        {"id": "1e859b12-42d5-4bd8-8bf0-88b6bda24852", "index": 4, "short_text": "Cook"},
        {"id": "d9b65d6a-c526-43cb-9434-8dd86f9ef1e1", "index": 5, "short_text": "Finish"}
    ]
}

user_prompt = f"""Convert this VEGAN chili to MEAT-BASED with ground beef.

Remaining steps:
{json.dumps(test_input['remaining_steps'], indent=2)}

Please:
1. INSERT a "Brown Ground Beef" step at index 1 (after mise en place)
2. SUBSTITUTE the vegetable broth in step "e4231d23-e919-417d-b90a-1f26ebaa2e73" with beef broth (use id "beef-broth-new")
3. UPDATE the Sauté Aromatics step (id: daf17d2d-a7c6-4601-bc77-cb74a0207435) to mention adding the browned beef back"""

print("=" * 60)
print("Testing: Structured Outputs (all fields nullable)")
print("=" * 60)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "system", "content": system_message},
        {"role": "user", "content": user_prompt}
    ],
    response_format={
        "type": "json_schema",
        "json_schema": json_schema
    },
    temperature=0.3
)

result = response.choices[0].message.content
parsed = json.loads(result)

print("\nRESPONSE:")
print("=" * 60)
print(json.dumps(parsed, indent=2))

print("\n" + "=" * 60)
print("OPERATIONS SUMMARY:")
print("=" * 60)
for i, op in enumerate(parsed.get('operations', [])):
    op_type = op.get('operation', '?').upper()
    if op_type == 'INSERT':
        print(f"  {i+1}. {op_type} @ index {op.get('step_index')}: \"{op.get('short_text')}\"")
    elif op_type == 'SUBSTITUTE':
        print(f"  {i+1}. {op_type}: {op.get('placeholder_key')} → {op.get('new_ingredient_id')}")
    elif op_type == 'UPDATE':
        print(f"  {i+1}. {op_type} step {op.get('step_id', '?')[:8]}...: \"{op.get('short_text')}\"")
    elif op_type == 'SKIP':
        print(f"  {i+1}. {op_type} step {op.get('step_id', '?')[:8]}...")
    elif op_type == 'ADJUST_QUANTITY':
        print(f"  {i+1}. {op_type}: {op.get('placeholder_key')} = {op.get('new_amount')}")

print(f"\n  💬 \"{parsed.get('agent_message')}\"")
print(f"  ⏱️  +{parsed.get('time_impact_minutes')} minutes")
