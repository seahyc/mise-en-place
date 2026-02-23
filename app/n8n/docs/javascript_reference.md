# n8n JavaScript Expression Reference

## Expression Format

All expressions use double curly braces: `{{ your expression here }}`

## Referencing Nodes

### $() Syntax - Access data from previous nodes

```javascript
// First item from a node
$('Node Name').first().json.property

// Last item from a node
$('Node Name').last().json.output

// Current item in loops
$('Node Name').item.json.value

// All items from a node
$('Node Name').all()

// Map over all items
$('Node Name').all().map(item => item.json.fieldName)
```

## Current Node Input - $input

### Accessing items sent to current node

```javascript
// First item
$input.first().json.property

// Last item
$input.last().json.data

// All items
$input.all()

// Current item (in loops/iterations)
$input.item.json.value

// Map over all input items
$input.all().map(x => x.json.Data)
```

## Current Item Data

### $json - Direct access to current item's data

```javascript
// Access current item JSON
$json

// Access specific field
$json.fieldName

// Nested property
$json.user.email
```

### Other Current Item Variables

```javascript
// Item index (zero-based)
$itemIndex

// Binary data (files/images)
$binary
```

## Common Patterns

### String Manipulation

```javascript
// Trim whitespace
$json.text.trim()

// Replace text
$json.message.replace('old', 'new')

// Split string
$json.csv.split(',')

// Uppercase/Lowercase
$json.name.toUpperCase()
$json.name.toLowerCase()
```

### Array Operations

```javascript
// Map array
$json.items.map(item => item.name)

// Filter array
$json.users.filter(user => user.age > 18)

// Join array
$json.tags.join(', ')

// Find item
$json.products.find(p => p.id === 123)

// Some/Every
$json.items.some(item => item.active)
$json.items.every(item => item.valid)
```

### Conditional Logic

```javascript
// Ternary operator
$json.status === 'active' ? 'Yes' : 'No'

// Nullish coalescing
$json.value ?? 'default'

// Logical OR for fallback
$json.title || 'Untitled'
```

### Type Conversion

```javascript
// String to number
Number($json.count)
parseInt($json.id)
parseFloat($json.price)

// Number to string
String($json.amount)
$json.value.toString()

// Boolean
Boolean($json.flag)
```

## Built-in Libraries

### Luxon - Date/Time manipulation

```javascript
// Current date
{{ DateTime.now() }}

// Parse date
{{ DateTime.fromISO($json.timestamp) }}

// Format date
{{ DateTime.now().toFormat('yyyy-MM-dd') }}
```

### JMESPath - JSON querying

```javascript
// Query JSON
{{ $jmespath($json, 'users[?age > `18`].name') }}
```

## Workflow Execution Context

```javascript
// Workflow metadata
$workflow.id
$workflow.name
$workflow.active

// Execution metadata
$execution.id
$execution.mode
$execution.resumeUrl
```

## Debugging Tips

```javascript
// Type $ to see available methods/variables
$

// Check data structure
{{ JSON.stringify($json, null, 2) }}

// Log to console (in Code node)
console.log($json);
```

## Common Issues

### Node Reference Returns Undefined

**Problem**: `$('Node Name').first()` returns undefined

**Causes**:
1. Node name typo (case-sensitive!)
2. Node hasn't executed yet in the workflow
3. Node is on a different execution branch

**Solution**:
- Use exact node name with correct capitalization
- Check workflow connections
- Use `$input` if data comes from direct connection

### Array Methods Fail

**Problem**: "first() is only callable on type 'Array'"

**Cause**: The referenced data is not an array

**Solution**:
```javascript
// Check if data exists first
{{ $('Node').first()?.json.value ?? 'default' }}

// Or use try-catch in Code node
try {
  return $('Node').first().json.value;
} catch (e) {
  return 'fallback';
}
```

## Examples from Our Workflow

### Accessing Parse & Split Operations data in Respond node

```javascript
{{
  {
    success: true,
    session_id: $('Parse & Split Operations').first().json.session_id,
    operations_count: $('Parse & Split Operations').first().json._totalOps || 0,
    agent_message: $('Parse & Split Operations').first().json._agentMessage || "Default message",
    operations_attempted: $('Parse & Split Operations').all().map(op => ({
      operation: op.json.operation,
      step_id: op.json.step_id,
      error: op.json.error || null
    }))
  }
}}
```

### Using $input in Respond node

```javascript
{{
  {
    success: true,
    // Get metadata from specific node
    count: $('Parse & Split Operations').first().json._totalOps,
    // Get operation results from input
    results: $input.all().map(item => ({
      id: item.json.id,
      status: item.json.status
    }))
  }
}}
```

## Architecture Patterns

### Cross-Branch Data Aggregation

**Problem**: After a routing split (e.g., Switch/IF/Route nodes), downstream nodes cannot access nodes before the split using `$('Node Name')`.

**Example**:
```
AI Agent → Parse & Split → Route by Operation → Adjust Quantity → Collect Results
                                                                        ↑
                                        Can't access Parse & Split from here!
```

**Why**: n8n nodes can only reference nodes in their direct execution chain. After routing splits execution into different branches, nodes on one branch can't access nodes on other branches.

**Solution**: Use a **Merge node** to combine data from multiple paths before final processing:

```
Parse & Split → Route → Operations → Merge → Collect Results
       ↓                                ↑
  Extract Metadata ────────────────────┘
```

**Implementation**:
1. Create a separate "Extract Metadata" Code node before the split
2. Have it extract only metadata fields (agent_message, counts, etc.)
3. Route metadata directly to Merge node (input 0)
4. Route operation results to Merge node (input 1)
5. Merge node combines both inputs using "Combine All" mode
6. Downstream nodes receive merged data containing both metadata AND results

**Key Insight**: Merge node with "combineAll" mode merges all fields into single items, not separate items. Handle merged structure in downstream Code nodes.

### Manual Field Mapping vs Auto-Mapping (Supabase/Database nodes)

**Problem**: Auto-mapping (`dataToSend: "autoMapInputData"`) sends ALL JSON fields to database, including metadata fields that don't exist as columns.

**Error**: `"Could not find the '_agentMessage' column in the schema cache"`

**Solution**: Use manual field mapping with `fieldsUi`:
```json
{
  "fieldsUi": {
    "fieldValues": [
      {"fieldId": "adjusted_amount", "fieldValue": "={{ $json.adjusted_amount }}"}
    ]
  }
}
```

**Benefit**: Metadata fields (_agentMessage, _timeImpact, etc.) can remain in JSON for downstream nodes without being sent to database.

## References

- [n8n Expressions Documentation](https://docs.n8n.io/code/expressions/)
- [n8n Code Node Documentation](https://docs.n8n.io/code/code-node/)
- [n8n Expression Cheat Sheet](https://n8narena.com/guides/n8n-expression-cheatsheet/)
- [Current Node Input Documentation](https://docs.n8n.io/code/builtin/current-node-input/)
- [n8n Merge Node Documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.merge/)
