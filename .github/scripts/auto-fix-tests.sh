#!/bin/bash
# Auto-fix CI Bugs Script
# 
# This script automatically fixes bugs/errors in code by analysing failing RSpec tests.
# It runs tests, extracts failures, identifies the ROOT CAUSE bug/error, uses Cursor CLI
# to generate fixes for the actual bug (not the test), applies them, and repeats until
# tests pass or max iterations is reached.
#
# IMPORTANT: This fixes bugs in the implementation code, not the tests themselves.
# Tests define correct behaviour - the script fixes the code to match.
#
# Required environment variables:
#   CURSOR_API_KEY - Cursor API key (optional if Cursor CLI is authenticated)
#   MAX_ITERATIONS - Maximum number of fix attempts (default: 5)
#
# Usage: ./auto-fix-tests.sh

set -euo pipefail

# Configuration
MAX_ITERATIONS=${MAX_ITERATIONS:-5}
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

# Check if Cursor CLI is available (allow API fallback)
if ! command -v cursor &> /dev/null && [ -z "${CURSOR_API_KEY:-}" ]; then
  log "${RED}Error: Cursor CLI is not installed and CURSOR_API_KEY is not set${NC}"
  log "Please install Cursor CLI or set CURSOR_API_KEY secret"
  exit 1
fi

# Set Cursor API key if provided
if [ -n "${CURSOR_API_KEY:-}" ]; then
  export CURSOR_API_KEY="${CURSOR_API_KEY}"
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
  local error_details=""
  
  if [ -f test-output.json ]; then
    # Extract failure messages using jq if available
    if command -v jq &> /dev/null; then
      # Get detailed failure information including what was expected vs actual
      failures=$(jq -r '.examples[] | select(.status == "failed") | 
        "Test: \(.full_description)\n" +
        "Error: \(.exception.message // "No error message")\n" +
        "Expected: \(.exception.expected // "N/A")\n" +
        "Got: \(.exception.got // "N/A")\n" +
        "Location: \(.file_path):\(.line_number // "unknown")\n" +
        "Backtrace:\n\(.exception.backtrace[0:5] | join("\n"))\n---\n"' test-output.json 2>/dev/null || echo "")
      
      # Also extract the actual error/exception class
      error_details=$(jq -r '.examples[] | select(.status == "failed") | 
        "Exception class: \(.exception.class // "Unknown")\n" +
        "Failure message: \(.exception.message // "No message")\n"' test-output.json 2>/dev/null | head -10 || echo "")
    fi
  fi
  
  # Fallback: extract from test output log
  if [ -z "${failures}" ]; then
    failures=$(grep -A 15 "FAILED\|Failure/Error\|expected:\|got:" "${TEST_LOG}" | tail -80 || echo "")
  fi
  
  # Include error context from test output
  if [ -f "${TEST_LOG}" ]; then
    local error_context=$(grep -B 5 -A 15 "Failure/Error\|expected:\|got:\|Error:" "${TEST_LOG}" | tail -50 || echo "")
    failures="${failures}"$'\n\n'"Error context:"$'\n'"${error_context}"
  fi
  
  # Combine all failure information
  echo "${error_details}"$'\n\n'"${failures}"
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

# Function to call Cursor CLI/API to fix tests
fix_with_cursor() {
  local failures="$1"
  local changed_files="$2"
  local iteration="$3"
  local prompt_file response_file
  
  log "${YELLOW}Attempting to fix tests with Cursor (iteration ${iteration}/${MAX_ITERATIONS})...${NC}"
  
  # Create a prompt file for Cursor
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  
  # Get the actual source files that are being tested to understand what's being verified
  local failing_spec_files=""
  if [ -f test-output.json ] && command -v jq &> /dev/null; then
    failing_spec_files=$(jq -r '.examples[] | select(.status == "failed") | "\(.file_path):\(.line_number // "?") - \(.full_description)"' test-output.json 2>/dev/null | head -10 || echo "")
  fi
  
  # Get relevant source code context for files that might have bugs
  local source_context=""
  if [ -n "${changed_files}" ]; then
    for file in ${changed_files}; do
      if [[ "${file}" =~ ^lib/.*\.rb$ ]] && [ -f "${file}" ]; then
        source_context="${source_context}\n\n=== ${file} ===\n$(head -50 "${file}" 2>/dev/null || echo "Could not read file")"
      fi
    done
  fi
  
  cat > "${prompt_file}" << PROMPT_EOF
CRITICAL: Fix the ROOT CAUSE of the bug/error, not just make tests pass.

Test failures and errors:
${failures}

Failing test files and what they're testing:
${failing_spec_files}

Files that may contain the bug:
${changed_files}

Source code context (first 50 lines of potentially buggy files):
${source_context}

Project structure:
- lib/ contains the main implementation code (generator.rb, static_site_builder/*.rb)
- spec/ contains RSpec tests that verify the implementation
- Uses RSpec for testing with SimpleCov

IMPORTANT INSTRUCTIONS:
1. ANALYSE the actual error/bug first - what is the test trying to verify?
2. Identify the ROOT CAUSE in the implementation code (lib/ files)
3. Fix the BUG in the implementation, not the test
4. The test is likely correct - it's exposing a real bug in the code
5. Only modify test files if they contain actual errors (wrong expectations, typos, etc.)
6. Fix the implementation to match what the test expects (the test defines correct behaviour)

Code style requirements:
- Use single quotes instead of double quotes unless interpolating
- Use British English spelling
- Keep code simple and readable
- Avoid unnecessary abstractions
- Test files use RSpec with expect syntax, no let(:v) blocks

What to fix (ROOT CAUSE ANALYSIS):
- If test expects a method to return X but it returns Y → fix the method implementation (the bug is in the method logic)
- If test expects an exception but none is raised → fix the code to raise the exception when appropriate (missing error handling)
- If test expects a file to be created but it isn't → fix the code that creates files (missing file creation logic)
- If test expects certain output but gets different → fix the code generating the output (wrong output generation)
- If test expects a value but gets nil → fix the code that should return that value (missing return/value assignment)
- If test expects an array/hash with items but gets empty → fix the code that populates it (missing population logic)
- If test fails with NoMethodError → fix the code to define the missing method or fix the method call
- If test fails with ArgumentError → fix the method signature or the way it's called
- Only fix tests if they have wrong expectations, typos, or are testing the wrong thing

ANALYSIS PROCESS:
1. Read the error message carefully - what exactly went wrong?
2. Look at the backtrace - where in the code did it fail?
3. Understand what the test expects - what is the correct behaviour?
4. Find the bug in the implementation code that causes incorrect behaviour
5. Fix the bug to make the code behave correctly (as the test expects)

Provide ONLY the code changes needed to fix the ROOT CAUSE in this exact format:
FILE: lib/path/to/file.rb
---OLD---
[exact code block with the bug, including proper indentation]
---NEW---
[fixed code block with bug resolved, same indentation]
---END---

If multiple files need changes, provide each file separately with the same format.
PROMPT_EOF
  
  # Try using Cursor CLI - check what commands are available
  local response=""
  
  # Method 1: Try cursor chat/compose command
  if cursor --help 2>&1 | grep -q "chat\|compose\|fix"; then
    log "${YELLOW}Using Cursor CLI chat/compose...${NC}"
    # Try different possible command formats
    response=$(cursor chat "$(cat "${prompt_file}")" 2>>"${FIX_LOG}" || \
               cursor compose "$(cat "${prompt_file}")" 2>>"${FIX_LOG}" || \
               cursor fix --input "${prompt_file}" 2>>"${FIX_LOG}" || echo "")
  
  # Method 2: Use Cursor API if CLI doesn't work and API key is available
  elif [ -n "${CURSOR_API_KEY:-}" ]; then
    log "${YELLOW}Using Cursor API...${NC}"
    # Cursor API endpoint (adjust based on actual API)
    response=$(curl -s https://api.cursor.sh/v1/chat \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${CURSOR_API_KEY}" \
      -d "{
        \"messages\": [
          {\"role\": \"system\", \"content\": \"You are an expert Ruby developer. Your job is to ANALYSE test failures, identify the ROOT CAUSE bug/error in the implementation code, and fix the actual bug - NOT just make tests pass. Tests define correct behaviour - fix the code to match.\"},
          {\"role\": \"user\", \"content\": \"$(cat "${prompt_file}" | jq -Rs .)\"}
        ]
      }" 2>>"${FIX_LOG}" | jq -r '.choices[0].message.content // .content // .text // empty' 2>/dev/null || echo "")
  
  # Method 3: Use cursor with file input
  else
    log "${YELLOW}Using Cursor CLI with file input...${NC}"
    # Try passing the prompt file directly
    response=$(cursor < "${prompt_file}" 2>>"${FIX_LOG}" || \
               cursor --input "${prompt_file}" 2>>"${FIX_LOG}" || echo "")
  fi
  
  rm -f "${prompt_file}" "${response_file}"
  
  if [ -z "${response}" ] || [ "${response}" = "null" ]; then
    log "${RED}Error: Failed to get response from Cursor${NC}"
    log "${YELLOW}Attempting to use Cursor's direct editing capabilities...${NC}"
    
    # Alternative: Create .cursorrules file and let Cursor process the workspace
    # This approach relies on Cursor's workspace understanding
    return 1
  fi
  
  log "${YELLOW}Cursor response received, applying fixes...${NC}"
  echo "=== Cursor Response ===" >> "${FIX_LOG}"
  echo "${response}" >> "${FIX_LOG}"
  echo "=======================" >> "${FIX_LOG}"
  
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
  
  # Call Cursor CLI to fix
  if ! fix_with_cursor "${failures}" "${changed_files}" "${ITERATION}"; then
    log "${RED}Failed to get or apply fixes from Cursor CLI${NC}"
    break
  fi
  
  # Commit changes
  if git diff --quiet; then
    log "${YELLOW}No changes to commit${NC}"
  else
    git add -A
    # Create a descriptive commit message about the bug fix
    local commit_msg="Auto-fix: Fix root cause bug/error (attempt ${ITERATION})"
    if [ -f test-output.json ] && command -v jq &> /dev/null; then
      local first_failure=$(jq -r '.examples[] | select(.status == "failed") | .exception.message' test-output.json 2>/dev/null | head -1)
      if [ -n "${first_failure}" ] && [ "${first_failure}" != "null" ]; then
        commit_msg="Auto-fix: Fix bug - ${first_failure:0:100} (attempt ${ITERATION})"
      fi
    fi
    git commit -m "${commit_msg}" || true
    log "${GREEN}Committed bug fixes${NC}"
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
