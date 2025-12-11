# n8n Workflows

This directory contains n8n workflow definitions, tests, and documentation for the Mise en Place cooking app.

## Directory Structure

```
n8n/
├── workflows/          # n8n workflow JSON definitions
├── tests/             # Test scripts for workflow validation
├── docs/              # Documentation and reference guides
└── README.md          # This file
```

## Workflows

### `generate_image.json`
**Purpose**: General-purpose image generation utility. Generates images via OpenAI and uploads to Cloudflare R2.

**Trigger**: Execute Workflow Trigger (called by other workflows)

**Input**:
```json
{
  "prompt": "Hand-drawn watercolor illustration of dicing onions...",
  "filename": "sessions/abc123/step_2.png",
  "options": {
    "model": "gpt-image-1",
    "size": "1024x1024",
    "quality": "standard"
  }
}
```

**Output**:
```json
{
  "success": true,
  "url": "https://r2.yourdomain.com/sessions/abc123/step_2.png",
  "filename": "sessions/abc123/step_2.png",
  "model_used": "gpt-image-1",
  "revised_prompt": "..."
}
```

**Usage from other workflows**:
```javascript
// Execute Workflow node
const result = await executeWorkflow('generate_image', {
  prompt: 'Watercolor illustration of slicing tomatoes',
  filename: `recipes/${recipeId}/main.png`,
  options: { quality: 'hd' }
});

// Caller decides what to do with result.url
await supabase.update('recipes', { main_image_url: result.url });
```

**Models supported**:
- `dall-e-3` (default) - Higher quality, larger resolutions, style options
- `dall-e-2` - Lower cost, concurrent requests
- `gpt-image-1` - Best instruction following (may need HTTP node if not yet in native node)

**Nodes Used** (all native, no community nodes):
- `@n8n/n8n-nodes-langchain.openai` - OpenAI node (image generation)
- `n8n-nodes-base.httpRequest` - HTTP Request with AWS S3 auth (R2 is S3-compatible)
- `n8n-nodes-base.code` - Data transformation

**Required Credentials**:
1. `openAiApi` - OpenAI API credentials
2. `aws` - Create as "AWS" credential with:
   - Access Key ID: `fb520a4f90a4d365e705dba2310b3d25` (your R2 access key)
   - Secret Access Key: your R2 secret key
   - Region: `auto`
   - Custom Endpoint: `https://b6fb17d8164be6988c26d3c2960c9705.r2.cloudflarestorage.com`

**Required Environment Variables** (set in n8n Settings → Variables):
- `R2_ACCOUNT_ID` - `b6fb17d8164be6988c26d3c2960c9705`
- `R2_BUCKET_NAME` - `mise-en-place`
- `R2_PUBLIC_URL` - `https://pub-ff44dab9301f402da0492478da2c9cfb.r2.dev`

---

### `modify_instructions.json`
**Purpose**: Handles dynamic recipe instruction modifications during active cooking sessions.

**Triggers**:
- HTTP webhook: `POST /webhook/session/modify`
- Test endpoint: `POST /webhook-test/session/modify`

**Operations Supported**:
- `adjust_quantity`: Change ingredient amounts
- `substitute_ingredient`: Replace ingredients
- `substitute_equipment`: Replace equipment
- `skip`: Skip optional steps
- `update`: Modify step text/duration
- `insert`: Add new recovery/adjustment steps

**Key Features**:
- AI-powered (Anthropic Claude Sonnet 4.5) instruction analysis
- Structured output parsing for atomic operations
- Manual field mapping to prevent metadata leakage to database
- Cross-branch data aggregation using Merge node
- Database verification with Supabase

**Architecture**:
```
Webhook → AI Agent → Parse & Split → Route by Operation → Operations → Merge → Collect Results → Respond
                            ↓                                            ↑
                      Extract Metadata ────────────────────────────────┘
```

**See**: [Architecture Patterns](docs/javascript_reference.md#architecture-patterns) for detailed explanation.

## Testing

### Run All Tests
```bash
cd tests
PROD=1 ./test_modify_instructions.sh    # Test against production
./test_modify_instructions.sh            # Test against test endpoint
```

### Test Coverage
- ✅ adjust_quantity (reduce/increase amounts)
- ✅ substitute_ingredient with database verification
- ✅ substitute_equipment
- ✅ Multiple operations in single request
- ✅ skip operations
- ✅ update operations
- ✅ insert operations (burnt ingredient recovery)
- ✅ Edge cases (zero amounts, scaling)
- ✅ Database state verification

## Documentation

### [JavaScript Reference](docs/javascript_reference.md)
- n8n expression syntax (`$()`, `$input`, `$json`)
- Node referencing and execution context
- Common patterns and debugging
- **Architecture patterns** (cross-branch aggregation, manual field mapping)

## Development Workflow

### 1. Making Changes
- Edit workflows in n8n UI
- Export as JSON to `workflows/`
- Update tests if operations change
- Update documentation if architecture changes

### 2. Testing
```bash
cd tests
./test_modify_instructions.sh  # Test against staging
PROD=1 ./test_modify_instructions.sh  # Verify production
```

### 3. Database Verification
Tests automatically verify database state for critical operations:
```bash
# Example: Check if ingredient was adjusted
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \
  "SELECT adjusted_amount FROM session_step_ingredients WHERE placeholder_key='chili_powder';"
```

## Key Learnings

### Cross-Branch Data Aggregation
**Problem**: After routing splits (Switch/IF/Route nodes), downstream nodes cannot access nodes before the split using `$('Node Name')`.

**Solution**: Use Merge node with "append" mode to combine metadata and operation results:
1. Extract metadata before routing split
2. Route metadata directly to Merge (input 0)
3. Route operation results to Merge (input 1)
4. Merge appends all items together
5. Downstream Code node separates metadata from results

### Manual Field Mapping
**Problem**: Auto-mapping sends ALL JSON fields to database, including metadata fields that don't exist as columns.

**Solution**: Use `fieldsUi` with explicit field mappings. Metadata fields remain in JSON for downstream processing without being sent to database.

## Environment Variables

Required for database verification in tests:
```bash
export PGPASSWORD="your_password"
DB_HOST="your_host"
DB_USER="your_user"
DB_NAME="your_database"
```

## Adding New Workflows

1. Create workflow in n8n UI
2. Export JSON to `workflows/your_workflow.json`
3. Create test script in `tests/test_your_workflow.sh`
4. Document in this README
5. Add architecture patterns to `docs/` if novel

## Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Merge Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.merge/)
- [Anthropic Claude API](https://docs.anthropic.com/)
- [Supabase PostgreSQL](https://supabase.com/docs)
