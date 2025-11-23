#!/bin/bash
# Auto-fix CI Tests Script
# 
# This script automatically fixes failing RSpec tests using an AI API (OpenAI or Anthropic).
# It runs tests, extracts failures, calls an AI API to generate fixes, applies them,
# and repeats until tests pass or max iterations is reached.
#
# Required environment variables:
#   AI_API_KEY - API key for the AI provider
#   AI_PROVIDER - 'openai' or 'anthropic' (default: 'openai')
#   MAX_ITERATIONS - Maximum number of fix attempts (default: 5)
#
# Usage: ./auto-fix-tests.sh

set -euo pipefail

# Configuration
MAX_ITERATIONS=${MAX_ITERATIONS:-5}
AI_PROVIDER=${AI_PROVIDER:-openai}
ITERATION=0
FIX_LOG="fix-attempts.log"
TEST_LOG="test-results.log"

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

log() {
  echo -e "${1}" | tee -a "${FIX_LOG}"
}

log_test() {
  echo -e "${1}" | tee -a "${TEST_LOG}"
}

# Check if AI API key is set
if [ -z "${AI_API_KEY:-}" ]; then
  log "${RED}Error: AI_API_KEY secret is not set${NC}"
  log "Please set AI_API_KEY in your repository secrets"
  exit 1
fi

# Function to run tests and capture output
run_tests() {
  log_test "\n=== Test Run $(date) ==="
  # Use --only-failures if .rspec_status exists, otherwise run all tests
  if [ -f .rspec_status ]; then
    if bundle exec rspec spec --only-failures --format documentation --format json --out test-output.json 2>&1 | tee -a "${TEST_LOG}"; then
      return 0
    else
      return 1
    fi
  else
    if bundle exec rspec --format documentation --format json --out test-output.json 2>&1 | tee -a "${TEST_LOG}"; then
      return 0
    else
      return 1
    fi
  fi
}

# Function to extract test failures from JSON output
extract_failures() {
  local failures=""
  
  if [ -f test-output.json ]; then
    # Extract failure messages using jq if available
    if command -v jq &> /dev/null; then
      failures=$(jq -r '.examples[] | select(.status == "failed") | "\(.full_description)\n\(.exception.message)\n\(.exception.backtrace[0:3] | join("\n"))\n---"' test-output.json 2>/dev/null || echo "")
    fi
  fi
  
  # Fallback: extract from test output log
  if [ -z "${failures}" ]; then
    failures=$(grep -A 10 "FAILED\|Failure/Error\|expected:" "${TEST_LOG}" | tail -50 || echo "")
  fi
  
  # Also include the last 30 lines of test output for context
  if [ -f "${TEST_LOG}" ]; then
    failures="${failures}"$'\n\n'"Recent test output:"$'\n'"$(tail -30 "${TEST_LOG}")"
  fi
  
  echo "${failures}"
}

# Function to get file changes from git
get_changed_files() {
  local files=""
  # Get files changed in last commit
  files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
  
  # If no previous commit, get all tracked files that might be relevant
  if [ -z "${files}" ]; then
    files=$(git diff --name-only 2>/dev/null || echo "")
  fi
  
  # Filter to only lib/ and spec/ files
  echo "${files}" | grep -E "^(lib|spec)/" || echo "${files}"
}

# Function to get relevant source files for context
get_source_context() {
  local file_list=""
  # Get all Ruby files in lib/ that might be relevant
  find lib -name "*.rb" -type f 2>/dev/null | head -20 || echo ""
}

# Function to call AI API to fix tests
fix_with_ai() {
  local failures="$1"
  local changed_files="$2"
  local iteration="$3"
  
  log "${YELLOW}Attempting to fix tests (iteration ${iteration}/${MAX_ITERATIONS})...${NC}"
  
  # Get source context
  local source_context=$(get_source_context)
  
  # Prepare the prompt
  local prompt="You are fixing failing Ruby/RSpec tests in a static site builder project.

Test failures:
${failures}

Files that may need fixing:
${changed_files}

Project structure:
- lib/ contains the main code (generator.rb, static_site_builder/*.rb)
- spec/ contains RSpec tests
- Uses RSpec for testing with SimpleCov
- Follows Ruby best practices

Code style requirements:
- Use single quotes instead of double quotes unless interpolating
- Use British English spelling
- Keep code simple and readable
- Avoid unnecessary abstractions
- Test files use RSpec with expect syntax, no let(:v) blocks

Requirements:
1. Analyse the test failures carefully
2. Fix ONLY the code in lib/ files to make tests pass
3. Do NOT modify test files (spec/) unless absolutely necessary
4. Ensure fixes are minimal and targeted - only change what's needed
5. Follow existing code style exactly
6. Preserve all existing functionality

Provide ONLY the code changes needed in this exact format:
FILE: lib/path/to/file.rb
---OLD---
[exact code block to replace, including proper indentation]
---NEW---
[new code block with same indentation]
---END---

If multiple files need changes, provide each file separately with the same format."

  # Call AI API based on provider
  local response=""
  if [ "${AI_PROVIDER}" = "openai" ]; then
    response=$(curl -s https://api.openai.com/v1/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${AI_API_KEY}" \
      -d "{
        \"model\": \"gpt-4-turbo-preview\",
        \"messages\": [
          {\"role\": \"system\", \"content\": \"You are an expert Ruby developer fixing failing tests.\"},
          {\"role\": \"user\", \"content\": \"${prompt}\"}
        ],
        \"temperature\": 0.1,
        \"max_tokens\": 4000
      }" | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
  elif [ "${AI_PROVIDER}" = "anthropic" ]; then
    response=$(curl -s https://api.anthropic.com/v1/messages \
      -H "Content-Type: application/json" \
      -H "x-api-key: ${AI_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -d "{
        \"model\": \"claude-3-opus-20240229\",
        \"max_tokens\": 4000,
        \"messages\": [
          {\"role\": \"user\", \"content\": \"${prompt}\"}
        ]
      }" | jq -r '.content[0].text' 2>/dev/null || echo "")
  else
    log "${RED}Error: Unknown AI provider: ${AI_PROVIDER}${NC}"
    return 1
  fi
  
  if [ -z "${response}" ]; then
    log "${RED}Error: Failed to get response from AI API${NC}"
    return 1
  fi
  
  log "${YELLOW}AI Response received, applying fixes...${NC}"
  echo "${response}" >> "${FIX_LOG}"
  
  # Parse and apply fixes
  apply_fixes "${response}"
}

# Function to apply fixes from AI response
apply_fixes() {
  local response="$1"
  local current_file=""
  local in_old=false
  local in_new=false
  local old_content=""
  local new_content=""
  local files_changed=0
  
  while IFS= read -r line; do
    if [[ "${line}" =~ ^FILE:\ (.+)$ ]]; then
      # Save previous file if any
      if [ -n "${current_file}" ] && [ -n "${new_content}" ]; then
        apply_file_fix "${current_file}" "${old_content}" "${new_content}"
        ((files_changed++)) || true
      fi
      current_file="${BASH_REMATCH[1]}"
      old_content=""
      new_content=""
      in_old=false
      in_new=false
    elif [[ "${line}" == "---OLD---" ]]; then
      in_old=true
      in_new=false
    elif [[ "${line}" == "---NEW---" ]]; then
      in_old=false
      in_new=true
    elif [[ "${line}" == "---END---" ]] || [[ "${line}" == "---FILE---" ]]; then
      if [ -n "${current_file}" ] && [ -n "${new_content}" ]; then
        apply_file_fix "${current_file}" "${old_content}" "${new_content}"
        ((files_changed++)) || true
      fi
      current_file=""
      old_content=""
      new_content=""
      in_old=false
      in_new=false
    elif [ "${in_old}" = true ]; then
      old_content="${old_content}${line}"$'\n'
    elif [ "${in_new}" = true ]; then
      new_content="${new_content}${line}"$'\n'
    fi
  done <<< "${response}"
  
  # Handle last file
  if [ -n "${current_file}" ] && [ -n "${new_content}" ]; then
    apply_file_fix "${current_file}" "${old_content}" "${new_content}"
    ((files_changed++)) || true
  fi
  
  if [ "${files_changed}" -eq 0 ]; then
    log "${YELLOW}No file changes detected in AI response${NC}"
    return 1
  fi
  
  log "${GREEN}Applied fixes to ${files_changed} file(s)${NC}"
  return 0
}

# Function to apply a single file fix
apply_file_fix() {
  local file="$1"
  local old_content="$2"
  local new_content="$3"
  local old_temp new_temp
  
  if [ ! -f "${file}" ]; then
    log "${YELLOW}Warning: File ${file} does not exist, skipping${NC}"
    return 1
  fi
  
  log "${YELLOW}Applying fix to ${file}...${NC}"
  
  # Check if old content exists in file
  if [ -z "${old_content}" ]; then
    log "${YELLOW}No old content provided for ${file}${NC}"
    return 1
  fi
  
  if ! grep -qF "${old_content}" "${file}" 2>/dev/null; then
    log "${YELLOW}Old content not found exactly in ${file}${NC}"
    return 1
  fi
  
  # Write content to temp files for Python script
  old_temp=$(mktemp)
  new_temp=$(mktemp)
  python_script=$(mktemp)
  echo -n "${old_content}" > "${old_temp}"
  echo -n "${new_content}" > "${new_temp}"
  
  # Create Python script
  cat > "${python_script}" << 'PYTHON_EOF'
import sys

file_path = sys.argv[1]
old_file = sys.argv[2]
new_file = sys.argv[3]

try:
    with open(old_file, 'r', encoding='utf-8') as f:
        old_text = f.read()
    with open(new_file, 'r', encoding='utf-8') as f:
        new_text = f.read()
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if old_text in content:
        content = content.replace(old_text, new_text)
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    sys.stderr.write(f'Error: {e}\n')
    sys.exit(1)
PYTHON_EOF
  
  # Use Python for reliable multi-line replacement
  if python3 "${python_script}" "${file}" "${old_temp}" "${new_temp}" 2>>"${FIX_LOG}"; then
    rm -f "${old_temp}" "${new_temp}" "${python_script}"
    log "${GREEN}Successfully applied fix to ${file}${NC}"
    return 0
  fi
  
  rm -f "${old_temp}" "${new_temp}" "${python_script}"
  
  # Fallback to perl if Python fails
  if perl -i -0pe "s|\Q${old_content}\E|${new_content}|gs" "${file}" 2>/dev/null; then
    log "${GREEN}Successfully applied fix to ${file} (perl)${NC}"
    return 0
  fi
  
  log "${RED}Failed to apply fix to ${file}${NC}"
  return 1
}

# Main loop
log "${GREEN}Starting auto-fix process (max ${MAX_ITERATIONS} iterations)${NC}"

# Initial test run
if run_tests; then
  log "${GREEN}All tests passing! No fixes needed.${NC}"
  exit 0
fi

# Fix loop
while [ "${ITERATION}" -lt "${MAX_ITERATIONS}" ]; do
  ((ITERATION++)) || true
  log "\n${YELLOW}=== Fix Iteration ${ITERATION}/${MAX_ITERATIONS} ===${NC}"
  
  # Get test failures
  failures=$(extract_failures)
  if [ -z "${failures}" ]; then
    failures=$(tail -50 "${TEST_LOG}")
  fi
  
  # Get changed files
  changed_files=$(get_changed_files)
  
  # Call AI to fix
  if ! fix_with_ai "${failures}" "${changed_files}" "${ITERATION}"; then
    log "${RED}Failed to get or apply fixes from AI${NC}"
    break
  fi
  
  # Commit changes
  if git diff --quiet; then
    log "${YELLOW}No changes to commit${NC}"
  else
    git add -A
    git commit -m "Auto-fix: Fix failing tests (attempt ${ITERATION})" || true
    log "${GREEN}Committed fixes${NC}"
  fi
  
  # Re-run tests
  if run_tests; then
    log "${GREEN}✓ All tests passing after ${ITERATION} iteration(s)!${NC}"
    exit 0
  fi
  
  log "${RED}Tests still failing after iteration ${ITERATION}${NC}"
done

log "${RED}✗ Failed to fix all tests after ${MAX_ITERATIONS} iterations${NC}"
exit 1
