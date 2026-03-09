#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo "=== Automated Release Notes Generator ==="

# Validate required Prow environment variables
: "${REPO_OWNER:?REPO_OWNER must be set}"
: "${REPO_NAME:?REPO_NAME must be set}"
: "${PULL_NUMBER:?PULL_NUMBER must be set}"
: "${PULL_BASE_REF:?PULL_BASE_REF must be set}"
: "${PULL_HEAD_REF:?PULL_HEAD_REF must be set}"

REPO_FULL="${REPO_OWNER}/${REPO_NAME}"

# Helper function for base64url encoding (used in JWT)
b64url() {
  openssl base64 -e \
    | tr '/+' '_-' \
    | tr -d '=' \
    | tr -d '\n'
}

echo "🔐 Generating GitHub App token..."
# GitHub App credentials
APP_ID_FILE="${GITHUB_APP_CREDS_DIR}/app-id"
INSTALLATION_ID_FILE="${GITHUB_APP_CREDS_DIR}/installation-id"
PRIVATE_KEY_FILE="${GITHUB_APP_CREDS_DIR}/private-key"

# Check if all required credentials exist
if [ ! -f "$APP_ID_FILE" ] || [ ! -f "$INSTALLATION_ID_FILE" ] || [ ! -f "$PRIVATE_KEY_FILE" ]; then
  echo "❌ ERROR: GitHub App credentials not found in ${GITHUB_APP_CREDS_DIR}" >&2
  echo "Available files:" >&2
  ls -la "${GITHUB_APP_CREDS_DIR}/" || echo "Directory does not exist" >&2
  echo ""
  echo "Required files:" >&2
  echo "  - app-id: GitHub App ID" >&2
  echo "  - installation-id: Installation ID for ${REPO_FULL}" >&2
  echo "  - private-key: GitHub App private key" >&2
  exit 1
fi

APP_ID=$(cat "$APP_ID_FILE")
INSTALLATION_ID=$(cat "$INSTALLATION_ID_FILE")

# Generate JWT for GitHub App authentication
NOW=$(date +%s)
IAT=$((NOW - 60))
EXP=$((NOW + 600))
HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
PAYLOAD=$(printf '{"iat":%d,"exp":%d,"iss":%s}' "$IAT" "$EXP" "$APP_ID" | b64url)
SIG_INPUT="$HEADER.$PAYLOAD"

echo "🖋 Signing JWT..."
SIGNATURE=$(
  printf '%s' "$SIG_INPUT" \
    | openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" \
    | b64url
)
JWT="$HEADER.$PAYLOAD.$SIGNATURE"

echo "🔗 Exchanging JWT for installation token..."
GITHUB_TOKEN=$(curl -sS \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  -X POST \
  "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens" \
  | jq -r '.token')

if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
  echo "❌ ERROR: Failed to generate GitHub App installation token" >&2
  exit 1
fi
echo "✅ GitHub App token generated successfully"

export GITHUB_TOKEN

echo "📋 Fetching PR details from #${PULL_NUMBER}..."
# Fetch PR metadata
PR_DATA=$(gh api "/repos/${REPO_FULL}/pulls/${PULL_NUMBER}")
PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
PR_BODY=$(echo "$PR_DATA" | jq -r '.body // ""')
PR_LABELS=$(echo "$PR_DATA" | jq -r '.labels[].name' | tr '\n' ', ' | sed 's/,$//')

echo "  Title: $PR_TITLE"
echo "  Labels: ${PR_LABELS:-none}"

echo "📥 Cloning repository and checking out PR branch..."
WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

# Clone the repository using GitHub App token
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_FULL}" repo
cd repo

# Configure git
git config user.name "${GIT_USER_NAME}"
git config user.email "${GIT_USER_EMAIL}"

# Fetch and checkout the PR branch
git fetch origin "pull/${PULL_NUMBER}/head:pr-${PULL_NUMBER}"
git checkout "pr-${PULL_NUMBER}"

# Get the base branch for comparison
git fetch origin "${PULL_BASE_REF}"

echo "📊 Analyzing PR changes..."
# Get list of changed files
CHANGED_FILES=$(git diff --name-only "origin/${PULL_BASE_REF}...HEAD" | head -50)
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l)
echo "  Changed files: $FILE_COUNT"

# Get diff summary (stats only, not full diff to avoid overwhelming Claude)
DIFF_STATS=$(git diff --stat "origin/${PULL_BASE_REF}...HEAD")

# Get a concise diff (limit size to avoid token limits)
# Focus on added/removed lines, limit context
DIFF_SUMMARY=$(git diff --unified=1 --no-color "origin/${PULL_BASE_REF}...HEAD" \
  | head -1000 \
  | grep -E "^\+|\^-|^diff|^index|^@@" \
  || echo "No diff content available")

echo "📖 Reading existing release notes file..."
if [[ -f "${RELEASE_NOTES_FILE}" ]]; then
  EXISTING_NOTES=$(cat "${RELEASE_NOTES_FILE}")
  echo "✅ Found existing release notes (${#EXISTING_NOTES} characters)"
else
  EXISTING_NOTES=""
  echo "ℹ️  No existing release notes file found. Will create new one."
fi

echo "📚 Reading repository context file..."
if [[ -f "${RELEASE_NOTES_CONTEXT_FILE}" ]]; then
  REPO_CONTEXT=$(cat "${RELEASE_NOTES_CONTEXT_FILE}")
  echo "✅ Found repository context (${#REPO_CONTEXT} characters)"
else
  REPO_CONTEXT="No repository-specific context provided. Use general best practices for user-facing release notes."
  echo "⚠️  No ${RELEASE_NOTES_CONTEXT_FILE} found. Consider adding one for more accurate release notes."
fi

echo "🤖 Preparing user-facing release notes prompt for Claude..."
# Create a temporary file for the prompt
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" <<EOF
You are writing USER-FACING release notes for a software product. Your audience is end users, administrators, and customers - NOT developers.

REPOSITORY CONTEXT:
${REPO_CONTEXT}

CRITICAL GUIDELINES:
1. Focus ONLY on what users will see, experience, or need to know
2. Ignore internal code changes, refactoring, and developer-focused improvements
3. Use clear, non-technical language that users understand
4. Emphasize user value and product impact
5. Organize by user impact: New Features, Improvements, Bug Fixes, Breaking Changes, Deprecations
6. Skip changes that don't affect users (test updates, internal refactors, code cleanup)
7. Avoid duplication - merge similar changes in existing notes

PR INFORMATION:
- PR #${PULL_NUMBER}: ${PR_TITLE}
- Labels: ${PR_LABELS:-none}

PR DESCRIPTION:
${PR_BODY}

CHANGED FILES:
${CHANGED_FILES}

DIFF STATISTICS:
${DIFF_STATS}

DIFF PREVIEW (first 1000 lines):
${DIFF_SUMMARY}

EXISTING RELEASE NOTES:
\`\`\`markdown
${EXISTING_NOTES:-No existing notes yet.}
\`\`\`

TASK:
Analyze the PR changes and update the release notes with USER-FACING information only.

For each change, ask yourself:
- Will users notice this change?
- Does it affect what users can do?
- Does it change user workflows or experience?
- Do users need to know about this?

If the answer is NO to all questions, skip it.

OUTPUT FORMAT:
Provide ONLY the complete updated release notes in markdown format. No preamble, no explanation.

Structure:
# Release Notes
Last updated: $(date +%Y-%m-%d)

## New Features
[User-visible new capabilities]

## Improvements
[Enhancements to existing features users will notice]

## Bug Fixes
[User-impacting bugs that are fixed]

## Breaking Changes
[Changes that require user action or break existing workflows]

## Deprecations
[Features being phased out that users should know about]

Skip any section that has no user-facing changes.
EOF

echo "🤖 Calling Claude via Vertex AI to generate user-facing release notes..."
# Use claude CLI (from claude-ai-helpers image) with Vertex AI authentication
UPDATED_NOTES=$(claude -p "$(cat "$PROMPT_FILE")" \
  --model "$CLAUDE_MODEL" \
  --max-turns 1 \
  --output-format text 2>&1 | tail -n +2)  # Skip first line (usually a status message)

# Clean up prompt file
rm -f "$PROMPT_FILE"

if [[ -z "$UPDATED_NOTES" ]]; then
  echo "❌ ERROR: Failed to get valid response from Claude" >&2
  exit 1
fi

echo "✅ Received updated release notes from Claude (${#UPDATED_NOTES} characters)"

echo "💾 Writing updated release notes to ${RELEASE_NOTES_FILE}..."
echo "$UPDATED_NOTES" > "${RELEASE_NOTES_FILE}"

echo "🔍 Checking if file changed..."
if git diff --quiet "${RELEASE_NOTES_FILE}"; then
  echo "ℹ️  No changes to release notes. Exiting."
  exit 0
fi

echo "📝 Committing updated release notes..."
git add "${RELEASE_NOTES_FILE}"
git commit -m "Update release notes with PR #${PULL_NUMBER}

User-facing changes from: ${PR_TITLE}

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

echo "📤 Pushing to PR branch..."
git push origin "pr-${PULL_NUMBER}:${PULL_HEAD_REF}"

echo "✅ Successfully updated release notes!"
echo "📄 Updated file: ${RELEASE_NOTES_FILE}"
echo "🎯 Focus: User-facing changes only"
