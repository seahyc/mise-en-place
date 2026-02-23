# ElevenLabs Agent Management

Scripts to pull and push the ElevenLabs Conversational AI agent configuration.

## Setup

Ensure your `.env` file has:
```
ELEVENLABS_API_KEY=your-api-key
ELEVENLABS_AGENT_ID=your-agent-id
```

## Usage

### Pull latest agent config
```bash
./pull_agent.sh
```
This saves the full agent configuration to `agent_config.json`.

### Push local changes
```bash
./push_agent.sh
```
This updates the remote agent with your local `agent_config.json`.

You can also specify a different file:
```bash
./push_agent.sh my_custom_config.json
```

## What you can edit in agent_config.json

### Quick edits (most common)

**System prompt** - Agent personality and instructions:
```
.conversation_config.agent.prompt.prompt
```

**First message** - What the agent says when conversation starts:
```
.conversation_config.agent.first_message
```

**Dynamic variables** - Default values for placeholders:
```
.conversation_config.agent.dynamic_variables.dynamic_variable_placeholders
```

**LLM settings**:
```
.conversation_config.agent.prompt.llm          # Model (e.g., "claude-sonnet-4-5")
.conversation_config.agent.prompt.temperature  # Creativity (0.0 - 1.0)
```

**Voice settings**:
```
.conversation_config.tts.voice_id         # ElevenLabs voice ID
.conversation_config.tts.speed            # Speech speed (default 1.0)
.conversation_config.tts.stability        # Voice consistency
.conversation_config.tts.similarity_boost # Voice clarity
```

### Tool definitions

Client tools are defined in:
```
.conversation_config.agent.prompt.tools[]
```

Each tool has:
- `name` - Tool identifier
- `description` - What the tool does (shown to LLM)
- `parameters` - JSON schema for parameters
- `expects_response` - Whether tool returns data

## Example: Edit the system prompt

1. Pull latest: `./pull_agent.sh`
2. Edit `agent_config.json` - find `.conversation_config.agent.prompt.prompt`
3. Push changes: `./push_agent.sh`

## Example: Add a new tool

### Option 1: Inline tool definition (recommended for simple additions)

1. Pull latest: `./pull_agent.sh`
2. Add to the `tools` array in `agent_config.json`:
```json
{
  "type": "client",
  "name": "my_new_tool",
  "description": "Description for the LLM",
  "response_timeout_secs": 3,
  "disable_interruptions": true,
  "force_pre_tool_speech": false,
  "parameters": {
    "type": "object",
    "required": ["param1"],
    "properties": {
      "param1": {
        "type": "string",
        "description": "Parameter description"
      }
    }
  },
  "expects_response": true,
  "execution_mode": "immediate"
}
```
3. Update the system prompt to document the new tool in the `## TOOLS - USE THEM` section
4. Push: `./push_agent.sh`

**Note**: The push script automatically handles the conflict between `tool_ids` and inline `tools` by removing `tool_ids` when inline tools are present. ElevenLabs will convert inline tools to proper tool IDs on the server side.

### Option 2: Create via API then reference by ID

For tools shared across multiple agents:
1. Create tool: `POST /v1/convai/tools` with tool_config
2. Add returned tool_id to `tool_ids` array
3. Push: `./push_agent.sh`
