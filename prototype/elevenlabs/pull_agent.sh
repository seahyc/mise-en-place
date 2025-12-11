#!/bin/bash
# Pull the latest ElevenLabs agent configuration
# NOTE: This preserves local inline tools (source of truth) while updating other fields

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

OUTPUT_FILE="$SCRIPT_DIR/agent_config.json"

echo "Pulling agent configuration for: $ELEVENLABS_AGENT_ID"

# Get remote config
REMOTE_CONFIG=$(curl -s -X GET "https://api.elevenlabs.io/v1/convai/agents/$ELEVENLABS_AGENT_ID" \
    -H "xi-api-key: $ELEVENLABS_API_KEY")

if [ -z "$REMOTE_CONFIG" ] || echo "$REMOTE_CONFIG" | jq -e '.detail' > /dev/null 2>&1; then
    echo "✗ Failed to pull agent configuration"
    echo "$REMOTE_CONFIG" | jq '.detail' 2>/dev/null
    exit 1
fi

# If local config exists, preserve our inline tools (source of truth)
if [ -f "$OUTPUT_FILE" ]; then
    LOCAL_TOOLS=$(jq -c '.conversation_config.agent.prompt.tools // []' "$OUTPUT_FILE")
    LOCAL_TOOL_COUNT=$(echo "$LOCAL_TOOLS" | jq 'length')

    if [ "$LOCAL_TOOL_COUNT" -gt 0 ]; then
        echo "Preserving $LOCAL_TOOL_COUNT local inline tools (source of truth)"
        # Merge: take remote config but keep local inline tools
        echo "$REMOTE_CONFIG" | jq --argjson local_tools "$LOCAL_TOOLS" '
            .conversation_config.agent.prompt.tools = $local_tools
        ' > "$OUTPUT_FILE"
    else
        echo "$REMOTE_CONFIG" | jq '.' > "$OUTPUT_FILE"
    fi
else
    echo "$REMOTE_CONFIG" | jq '.' > "$OUTPUT_FILE"
fi

echo "✓ Agent configuration saved to: $OUTPUT_FILE"
echo ""
echo "Agent: $(jq -r '.name' "$OUTPUT_FILE")"
echo "Updated: $(date -r $(jq -r '.metadata.updated_at_unix_secs' "$OUTPUT_FILE") '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"
echo "Tool IDs: $(jq '.conversation_config.agent.prompt.tool_ids | length' "$OUTPUT_FILE")"
echo "Inline tools: $(jq '.conversation_config.agent.prompt.tools | length' "$OUTPUT_FILE")"
