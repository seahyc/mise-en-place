#!/bin/bash

# Test suite for n8n modify_instructions webhook
# Tests all Supabase node operations: insert, update, skip, adjust_quantity, substitute_ingredient, substitute_equipment

PROD_URL="https://miseenplace.app.n8n.cloud/webhook/session/modify"
TEST_URL="https://miseenplace.app.n8n.cloud/webhook-test/session/modify"

URL=${PROD:+$PROD_URL}
URL=${URL:-$TEST_URL}

# Test session ID (Pad Thai session)
SESSION_ID="faf7ea6c-e56f-4e14-aa58-1fb28f12050c"
RECIPE_ID="573c80a0-3d53-4bfc-b57f-b660700f2730"

# Database connection
DB_HOST="aws-1-ap-southeast-1.pooler.supabase.com"
DB_PORT="5432"
DB_USER="postgres.dmhhglsaeqxzwtjaqtdo"
DB_NAME="postgres"
export PGPASSWORD="SPkg09h9subx1aUY"

echo "Testing against: $URL"
echo "Session ID: $SESSION_ID"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

run_test() {
    local test_name="$1"
    local issue_type="$2"
    local details="$3"
    local affected_ingredient="${4:-}"
    local affected_equipment="${5:-}"
    local expected_op="${6:-}"

    echo -e "${YELLOW}━━━ ${test_name} ━━━${NC}"

    # Build payload
    payload=$(jq -n \
        --arg sid "$SESSION_ID" \
        --arg it "$issue_type" \
        --arg d "$details" \
        --arg ai "$affected_ingredient" \
        --arg ae "$affected_equipment" \
        '{session_id: $sid, issue_type: $it, details: $d} +
         (if $ai != "" then {affected_ingredient: $ai} else {} end) +
         (if $ae != "" then {affected_equipment: $ae} else {} end)')

    echo "Payload: $(echo $payload | jq -c '.')"

    response=$(curl -s -X POST "$URL" \
        -H "Content-Type: application/json" \
        -d "$payload")

    success=$(echo "$response" | jq -r '.success // false')
    ops_count=$(echo "$response" | jq -r '.operations_count // 0')
    agent_msg=$(echo "$response" | jq -r '.agent_message // "N/A"')
    ops_attempted=$(echo "$response" | jq -c '.operations_attempted // []')

    echo "Response:"
    echo "  success: $success"
    echo "  operations_count: $ops_count"
    echo "  agent_message: ${agent_msg:0:120}..."
    echo "  operations: $ops_attempted"

    # Verify expected operation type was used
    if [ -n "$expected_op" ]; then
        if echo "$ops_attempted" | grep -q "\"operation\":\"$expected_op\""; then
            echo -e "${BLUE}  ✓ Expected operation '$expected_op' found${NC}"
        else
            echo -e "${RED}  ✗ Expected operation '$expected_op' NOT found${NC}"
        fi
    fi

    if [ "$success" = "true" ]; then
        echo -e "${GREEN}✓ PASSED${NC}\n"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "Full response: $response"
        echo ""
        ((FAILED++))
    fi
}

reset_session() {
    echo -e "${BLUE}Resetting session to fresh state...${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q <<EOF
-- Delete existing session data
DELETE FROM session_step_ingredients WHERE session_step_id IN (SELECT id FROM session_steps WHERE session_id = '$SESSION_ID');
DELETE FROM session_step_equipment WHERE session_step_id IN (SELECT id FROM session_steps WHERE session_id = '$SESSION_ID');
DELETE FROM session_steps WHERE session_id = '$SESSION_ID';
DELETE FROM cooking_sessions WHERE id = '$SESSION_ID';

-- Create fresh session
INSERT INTO cooking_sessions (id, status, pax_multiplier, source_recipe_ids)
VALUES ('$SESSION_ID', 'in_progress', 1.0, ARRAY['$RECIPE_ID']::uuid[]);

-- Copy steps from recipe
INSERT INTO session_steps (session_id, source_step_id, order_index, short_text, detailed_description, media_url)
SELECT '$SESSION_ID', id, order_index, short_text, detailed_description, media_url
FROM instruction_steps WHERE recipe_id = '$RECIPE_ID' ORDER BY order_index;

-- Mark step 0 as completed (Mise en Place done)
UPDATE session_steps SET is_completed = true WHERE session_id = '$SESSION_ID' AND order_index = 0;

-- Copy ingredients
INSERT INTO session_step_ingredients (session_step_id, placeholder_key, ingredient_id, original_amount, adjusted_amount, unit_id)
SELECT ss.id, si.placeholder_key, si.ingredient_id, si.amount, si.amount, si.unit_id
FROM step_ingredients si
JOIN instruction_steps ist ON ist.id = si.step_id
JOIN session_steps ss ON ss.source_step_id = ist.id AND ss.session_id = '$SESSION_ID';

-- Copy equipment
INSERT INTO session_step_equipment (session_step_id, placeholder_key, equipment_id)
SELECT ss.id, se.placeholder_key, se.equipment_id
FROM step_equipment se
JOIN instruction_steps ist ON ist.id = se.step_id
JOIN session_steps ss ON ss.source_step_id = ist.id AND ss.session_id = '$SESSION_ID';
EOF
    echo -e "${GREEN}Session reset complete${NC}\n"
}

show_steps() {
    echo -e "${BLUE}Current step order:${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT order_index, short_text, is_completed, is_skipped FROM session_steps WHERE session_id='$SESSION_ID' ORDER BY order_index;"
    echo ""
}

# Initial reset
reset_session
show_steps

# ============================================
# Test 1: INSERT - burnt_ingredient
# ============================================
echo "=== Test 1: INSERT - Burnt protein recovery ==="
run_test "Insert recovery steps for burnt protein" \
    "burnt_ingredient" \
    "User burnt the protein while searing, its completely black and ruined" \
    "protein" \
    "" \
    "insert"

show_steps

if [ -z "$PROD" ]; then
    echo "Press Enter to continue (re-execute workflow in n8n editor)..."
    read -r
fi

# Reset for next test
reset_session

# ============================================
# Test 2: SUBSTITUTE_INGREDIENT - missing_ingredient
# ============================================
echo "=== Test 2: SUBSTITUTE_INGREDIENT - No tamarind ==="
run_test "Substitute tamarind with lime juice" \
    "missing_ingredient" \
    "User doesnt have tamarind paste, needs a substitute" \
    "tamarind" \
    "" \
    "substitute_ingredient"

# Verify substitution in DB
echo -e "${BLUE}Checking substitution in DB:${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT ssi.placeholder_key, im.name, ssi.is_substitution, ssi.substitution_note
     FROM session_step_ingredients ssi
     JOIN ingredient_master im ON im.id = ssi.ingredient_id
     JOIN session_steps ss ON ss.id = ssi.session_step_id
     WHERE ss.session_id='$SESSION_ID' AND ssi.placeholder_key='tamarind' LIMIT 3;"

if [ -z "$PROD" ]; then
    echo "Press Enter to continue..."
    read -r
fi

# Reset for next test
reset_session

# ============================================
# Test 3: SUBSTITUTE_EQUIPMENT - equipment_issue
# ============================================
echo "=== Test 3: SUBSTITUTE_EQUIPMENT - No wok ==="
run_test "Substitute wok with frying pan" \
    "equipment_issue" \
    "User doesnt have a wok, only has a large frying pan" \
    "" \
    "wok" \
    "substitute_equipment"

# Verify substitution in DB
echo -e "${BLUE}Checking equipment substitution in DB:${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT sse.placeholder_key, em.name, sse.is_substitution, sse.substitution_note
     FROM session_step_equipment sse
     JOIN equipment_master em ON em.id = sse.equipment_id
     JOIN session_steps ss ON ss.id = sse.session_step_id
     WHERE ss.session_id='$SESSION_ID' AND sse.placeholder_key='wok' LIMIT 3;"

if [ -z "$PROD" ]; then
    echo "Press Enter to continue..."
    read -r
fi

# Reset for next test
reset_session

# ============================================
# Test 4: SKIP - dietary_restriction
# ============================================
echo "=== Test 4: SKIP - Egg allergy ==="
run_test "Skip egg step due to allergy" \
    "dietary_restriction" \
    "User is allergic to eggs, need to skip or remove eggs from recipe" \
    "eggs" \
    "" \
    "skip"

# Check if step was skipped
echo -e "${BLUE}Checking skipped steps:${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT order_index, short_text, is_skipped, agent_notes FROM session_steps WHERE session_id='$SESSION_ID' AND is_skipped=true;"

if [ -z "$PROD" ]; then
    echo "Press Enter to continue..."
    read -r
fi

# Reset for next test
reset_session

# ============================================
# Test 5: UPDATE - user_request
# ============================================
echo "=== Test 5: UPDATE - Less spicy ==="
run_test "Update step to remove chili" \
    "user_request" \
    "User wants less spicy, remove the chili flakes from the finish step" \
    "chili" \
    "" \
    "update"

# Check step was updated
echo -e "${BLUE}Checking Finish step description:${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT short_text, LEFT(detailed_description, 100) as description FROM session_steps WHERE session_id='$SESSION_ID' AND short_text ILIKE '%finish%';"

if [ -z "$PROD" ]; then
    echo "Press Enter to continue..."
    read -r
fi

# Reset for next test
reset_session

# ============================================
# Test 6: ADJUST_QUANTITY - portion_change
# ============================================
echo "=== Test 6: ADJUST_QUANTITY - Double servings ==="
run_test "Double all ingredient quantities" \
    "portion_change" \
    "User wants to make this for 8 people instead of 4, double everything" \
    "" \
    "" \
    "adjust_quantity"

# Check quantities were adjusted
echo -e "${BLUE}Checking adjusted quantities:${NC}"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT ssi.placeholder_key, ssi.original_amount, ssi.adjusted_amount
     FROM session_step_ingredients ssi
     JOIN session_steps ss ON ss.id = ssi.session_step_id
     WHERE ss.session_id='$SESSION_ID'
     ORDER BY ssi.placeholder_key LIMIT 10;"

# ============================================
# Summary
# ============================================
echo ""
echo "================================"
echo "Test Results:"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo "================================"

# Final reset
reset_session

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
