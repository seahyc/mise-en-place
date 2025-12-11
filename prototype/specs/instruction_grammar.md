# Instruction Template Grammar Specification

This document defines the grammar for cooking instruction templates used by the n8n agent to generate structured, readable instructions that can be rendered with highlighted ingredients and equipment in the UI.

## Placeholder Syntax

| Placeholder | Description | Rendered Output Example |
|-------------|-------------|-------------------------|
| `{i:key}` | Ingredient name only | "onion" |
| `{i:key:qty}` | Amount + unit + name | "2 tbsp olive oil" |
| `{e:key}` | Equipment name | "wok" |

### Key Naming Convention
- Lowercase with underscores
- Descriptive but concise
- Examples: `olive_oil`, `dutch_oven`, `kidney_beans`, `bell_pepper`

## Grammar Rules

### Rule 1: First Introduction
Use `{i:key:qty}` when introducing an ingredient for the **first time** in a step.

```
"Heat {i:oil:qty} in the {e:pan}"
→ "Heat 2 tbsp olive oil in the pan"
```

### Rule 2: Subsequent References
Use `{i:key}` for **subsequent** references to the same ingredient.

```
"Sauté {i:onion} until {i:onion} is translucent"
→ "Sauté onion until onion is translucent"
```

### Rule 3: Equipment Always Simple
Always use `{e:key}` for equipment (no quantity modifier).

```
"Bring the {e:pot} to a boil"
→ "Bring the pot to a boil"
```

### Rule 4: Natural Article Usage
Include articles (the, a, an) naturally outside placeholders.

```
"Heat the {e:wok} over high heat"  ✓
"Heat {e:the_wok} over high heat"  ✗
```

## Common Patterns

### Pattern 1: Add Ingredient to Equipment
```
"Heat {i:oil:qty} in the {e:pan}"
"Pour {i:broth:qty} into the {e:pot}"
```

### Pattern 2: Simple Action on Ingredient
```
"Dice {i:onion} finely"
"Mince {i:garlic}"
"Julienne {i:carrots}"
```

### Pattern 3: Multiple Ingredients
```
"Add {i:garlic:qty} and {i:ginger:qty}"
"Combine {i:flour:qty}, {i:sugar:qty}, and {i:salt:qty}"
```

### Pattern 4: Reference with State
```
"Cook until {i:onion} is translucent"
"Stir until {i:sauce} thickens"
```

### Pattern 5: Equipment-Only Action
```
"Preheat the {e:oven} to 375°F"
"Bring the {e:pot} to a boil"
"Heat the {e:wok} over high heat"
```

### Pattern 6: Complex Combination
```
"Toss {i:noodles} in the {e:wok} with {i:sauce:qty}"
"Sear {i:chicken} in the {e:skillet}, then deglaze with {i:wine:qty}"
```

### Pattern 7: Time-Based Instructions
```
"Sauté {i:aromatics} for 2-3 minutes"
"Simmer {i:sauce} for 15 minutes"
```

## Step Data Structure

Each instruction step must include:

```json
{
  "short": "Step Title",
  "detail": "Template text with {i:key} and {e:key} placeholders",
  "step_ingredients": [
    ["placeholder_key", "Ingredient Name", amount, "unit"],
    ...
  ],
  "step_equipment": [
    ["placeholder_key", "Equipment Name"],
    ...
  ]
}
```

### Example Step

```json
{
  "short": "Sauté Aromatics",
  "detail": "Heat {i:oil:qty} in the {e:dutch_oven} over medium heat. Sauté diced {i:onion} until translucent (5-7 mins). Add minced {i:garlic} and {i:jalapeno}, cook 1 min until fragrant.",
  "step_ingredients": [
    ["oil", "Olive Oil", 2, "tbsp"],
    ["onion", "Onion", 1, "large"],
    ["garlic", "Garlic", 6, "clove"],
    ["jalapeno", "Jalapeño", 2, "whole"]
  ],
  "step_equipment": [
    ["dutch_oven", "Dutch Oven"],
    ["wooden_spoon", "Wooden Spoon"]
  ]
}
```

## UI Rendering

The UI should:
1. Parse placeholders using regex: `\{(i|e):(\w+)(?::qty)?\}`
2. Replace `{i:key}` with ingredient name (styled as ingredient)
3. Replace `{i:key:qty}` with "amount unit name" (styled as ingredient)
4. Replace `{e:key}` with equipment name (styled as equipment)
5. Apply distinct styles:
   - **Ingredients**: Highlighted text (e.g., orange/warm color)
   - **Equipment**: Different highlight (e.g., blue/cool color)

## Session Modifications

When the agent modifies instructions during a cooking session:
1. Only modify steps that are NOT completed (`is_completed = false`)
2. Update `session_step_ingredients` with adjusted amounts
3. Set `is_substitution = true` and add `substitution_note` for substitutions
4. Preserve placeholder keys for UI highlighting
