#!/bin/bash
# Push local agent configuration to ElevenLabs
# This script is the SOURCE OF TRUTH:
# 1. Clears agent's tool_ids
# 2. Deletes matching shared tools by name
# 3. Creates fresh shared tools from our config
# 4. Updates agent with new tool_ids

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -E '^(ELEVENLABS_API_KEY|ELEVENLABS_AGENT_ID)=' "$PROJECT_ROOT/.env" | xargs)
fi

if [ -z "$ELEVENLABS_API_KEY" ] || [ -z "$ELEVENLABS_AGENT_ID" ]; then
    echo "Error: ELEVENLABS_API_KEY and ELEVENLABS_AGENT_ID must be set in .env"
    exit 1
fi

INPUT_FILE="${1:-$SCRIPT_DIR/agent_config.json}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Config file not found: $INPUT_FILE"
    echo "Run ./pull_agent.sh first to get the current configuration"
    exit 1
fi

echo "Pushing agent configuration from: $INPUT_FILE"
echo "Target agent: $ELEVENLABS_AGENT_ID"
echo ""

# Get inline tools from our config (source of truth)
INLINE_TOOLS=$(jq -c '.conversation_config.agent.prompt.tools // []' "$INPUT_FILE")
INLINE_TOOL_COUNT=$(echo "$INLINE_TOOLS" | jq 'length')

# Build list of tool names we want (excluding system tools)
TOOL_NAMES=$(echo "$INLINE_TOOLS" | jq -r '.[] | select(.type != "system") | .name')
TOOL_COUNT=$(echo "$TOOL_NAMES" | grep -c . || echo 0)

echo "Tools defined in config: $TOOL_COUNT"
echo "$TOOL_NAMES" | sed 's/^/  - /'
echo ""

# Confirm before proceeding
read -p "This will delete and recreate these $TOOL_COUNT shared tools. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Clear agent's tool_ids (clean slate)
echo ""
echo "Step 1: Clearing agent's tool references..."
curl -s -X PATCH "https://api.elevenlabs.io/v1/convai/agents/$ELEVENLABS_AGENT_ID" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"conversation_config":{"agent":{"prompt":{"tool_ids":[]}}}}' > /dev/null
echo "  ✓ Cleared"

# Step 2: Get existing shared tools
echo ""
echo "Step 2: Fetching existing shared tools..."
SHARED_TOOLS=$(curl -s "https://api.elevenlabs.io/v1/convai/tools" \
    -H "xi-api-key: $ELEVENLABS_API_KEY")

# Step 3: Delete matching shared tools by name
echo ""
echo "Step 3: Deleting existing tools with matching names..."
for name in $TOOL_NAMES; do
    EXISTING_ID=$(echo "$SHARED_TOOLS" | jq -r --arg name "$name" '.tools[] | select(.tool_config.name == $name) | .id')
    if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
        echo "  Deleting: $name ($EXISTING_ID)"
        curl -s -X DELETE "https://api.elevenlabs.io/v1/convai/tools/$EXISTING_ID" \
            -H "xi-api-key: $ELEVENLABS_API_KEY"
    fi
done
echo "  ✓ Done"

# Step 4: Create fresh shared tools
echo ""
echo "Step 4: Creating fresh shared tools..."
TOOL_IDS=()
for row in $(echo "$INLINE_TOOLS" | jq -r '.[] | @base64'); do
    TOOL=$(echo "$row" | base64 --decode)
    TOOL_NAME=$(echo "$TOOL" | jq -r '.name')
    TOOL_TYPE=$(echo "$TOOL" | jq -r '.type')

    # Skip system tools
    if [ "$TOOL_TYPE" = "system" ]; then
        continue
    fi

    echo "  Creating: $TOOL_NAME"

    # Create shared tool - API expects {"tool_config": {...}}
    CREATE_RESPONSE=$(curl -s -X POST "https://api.elevenlabs.io/v1/convai/tools" \
        -H "xi-api-key: $ELEVENLABS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(echo "$TOOL" | jq '{tool_config: .}')")

    NEW_TOOL_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id // empty')
    if [ -n "$NEW_TOOL_ID" ]; then
        echo "    ✓ $NEW_TOOL_ID"
        TOOL_IDS+=("$NEW_TOOL_ID")
    else
        echo "    ✗ Failed: $(echo "$CREATE_RESPONSE" | jq -r '.detail // "unknown error"')"
    fi
done

echo ""
echo "Created ${#TOOL_IDS[@]} tools"

# Step 5: Build agent payload with new tool_ids
# IMPORTANT: We only send tool_ids, NOT inline tools
# The local config keeps inline tools as source of truth for syncing to shared tools
TOOL_IDS_JSON=$(printf '%s\n' "${TOOL_IDS[@]}" | jq -R . | jq -s .)

# Build payload: remove inline tools completely, only set tool_ids
# Note: Cannot send both tools and tool_ids - API restriction
PAYLOAD=$(jq --argjson tool_ids "$TOOL_IDS_JSON" '{
    conversation_config: (
        .conversation_config |
        .agent.prompt.tool_ids = $tool_ids |
        del(.agent.prompt.tools)
    ),
    platform_settings: .platform_settings,
    name: .name
}' "$INPUT_FILE")

# Step 6: Update agent
echo ""
echo "Step 5: Updating agent with new tool references..."
RESPONSE=$(curl -s -X PATCH "https://api.elevenlabs.io/v1/convai/agents/$ELEVENLABS_AGENT_ID" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if echo "$RESPONSE" | jq -e '.detail' > /dev/null 2>&1; then
    echo "✗ Failed to update agent:"
    echo "$RESPONSE" | jq '.detail'
    exit 1
else
    echo "✓ Agent updated with ${#TOOL_IDS[@]} tools"
    echo ""
    # Pull the latest to confirm and sync
    echo "Pulling updated configuration..."
    "$SCRIPT_DIR/pull_agent.sh"
fi
