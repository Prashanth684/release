# Automated User-Facing Release Notes Generator

This step automatically generates user-facing release notes from PR changes using Claude AI, with no external dependencies.

## Features

- 🤖 **AI-Powered Analysis**: Claude analyzes PR diffs, descriptions, and metadata
- 👥 **User-Focused**: Generates documentation for end users, not developers
- 🔄 **Rolling Updates**: Intelligently merges changes without duplication
- 📊 **Impact-Based Organization**: Categorizes by user impact (Features, Bug Fixes, etc.)
- ✅ **Automatic Commits**: Commits updated release notes back to PR branch
- 🚫 **No External Tools**: No CodeRabbit or other third-party services needed

## What Makes This User-Facing?

This tool focuses on **what users care about**:

✅ **Included:**
- New features and capabilities users can access
- Bug fixes that affect user experience
- UI/UX changes users will notice
- Breaking changes requiring user action
- Deprecations of user-facing features
- Performance improvements users experience

❌ **Excluded:**
- Code refactoring and internal restructuring
- Test infrastructure changes
- Developer tooling updates
- Code style and formatting
- Internal API changes (unless user-visible)

## Prerequisites

### 1. Add Repository Context File (Recommended)

Create `.release-notes-context.md` in your repository root to help Claude understand:
- What your product is and who uses it
- What types of changes are user-facing vs. internal
- Product-specific terminology to use

See `EXAMPLE.release-notes-context.md` for a template.

**Without this file**, Claude will use general heuristics but may misclassify changes. With it, release notes will be more accurate and use appropriate terminology.

### 2. Create Credentials Secret

You need a secret in the `test-credentials` namespace containing:
- **GCP Service Account** for Vertex AI (Claude access)
- **GitHub App credentials** for your target repository

#### Option A: Reuse Existing Vertex AI ⭐ **RECOMMENDED**

Reuse the existing Vertex AI setup from the HyperShift team:

1. Contact HyperShift team or OpenShift CI admins
2. Get access to copy the `claude-prow` GCP service account
3. Create a GitHub App for your repository (see SETUP.md)
4. Combine into one secret:

```bash
oc create secret generic pr-release-notes-bot \
  -n test-credentials \
  --from-file=claude-prow=claude-prow.json \
  --from-literal=app-id=YOUR_GITHUB_APP_ID \
  --from-literal=installation-id=YOUR_REPO_INSTALLATION_ID \
  --from-file=private-key=github-app-private-key.pem
```

#### Option B: Set Up Your Own

See **SETUP.md** for complete instructions on creating your own Vertex AI and GitHub App credentials.

## Usage

### Add to CI Configuration

Add this to your repository's CI config in `ci-operator/config/<org>/<repo>/<org>-<repo>-<branch>.yaml`:

```yaml
tests:
- as: pr-release-notes
  optional: true  # Won't block PR merges
  skip_if_only_changed: "^docs/|\\.md$|^(?:.*\\/)?(?:OWNERS|LICENSE)$"
  steps:
    test:
    - ref: pr-release-notes
```

### Run make update

After adding the configuration:

```bash
make update
```

This will generate the corresponding Prow job configuration.

## How It Works

1. **Trigger**: Runs as optional presubmit on PR open/update
2. **Authenticate**: Generates GitHub App token via JWT
3. **Fetch PR Data**: Gets PR title, description, labels via GitHub API
4. **Analyze Changes**: Generates git diff and file statistics
5. **Load Context**: Reads `.release-notes-context.md` if present for product-specific guidance
6. **AI Analysis**: Claude analyzes changes for user-facing impact using repository context
7. **Generate Notes**: Creates/updates user-focused release notes
8. **Commit & Push**: Commits RELEASE_NOTES.md back to PR branch

## Example Output

The generated `RELEASE_NOTES.md` focuses on user impact:

```markdown
# Release Notes
Last updated: 2026-03-05

## New Features

**Enhanced Authentication**
- Added support for multi-factor authentication (MFA) via TOTP
- Users can now enable MFA in account settings
- Supports standard authenticator apps (Google Authenticator, Authy, etc.)

**Dashboard Improvements**
- New customizable widgets for monitoring cluster health
- Drag-and-drop interface for dashboard layout
- Save multiple dashboard configurations

## Improvements

**Faster Deployments**
- Deployment operations now complete 40% faster on average
- Reduced startup time for large applications

## Bug Fixes

**Login Issues**
- Fixed intermittent session timeout errors
- Resolved issue where users were logged out unexpectedly

**UI Fixes**
- Fixed table sorting in resource list views
- Corrected timezone display in activity logs

## Breaking Changes

**API Authentication**
- OAuth2 is now required for all API endpoints
- Legacy API token authentication deprecated (see migration guide)
- Action Required: Update API clients by June 2026
```

## Customization

Customize via environment variables:

```yaml
tests:
- as: pr-release-notes
  optional: true
  steps:
    test:
    - ref: pr-release-notes
      env:
      - name: RELEASE_NOTES_FILE
        value: "CHANGELOG.md"  # Different filename
      - name: CLAUDE_MODEL
        value: "claude-opus-4-5"  # Use Opus for better analysis
```

Available environment variables:
- `RELEASE_NOTES_FILE`: Name of file to update (default: `RELEASE_NOTES.md`)
- `RELEASE_NOTES_CONTEXT_FILE`: Path to repository context file (default: `.release-notes-context.md`)
- `CLAUDE_MODEL`: Claude model to use (default: `claude-sonnet-4-20250514`)
- `GIT_USER_NAME`: Git commit author name (default: `OpenShift CI Bot`)
- `GIT_USER_EMAIL`: Git commit author email (default: `ci-robot@openshift.io`)

## Architecture

This step follows OpenShift CI best practices:

- **Image**: `claude-ai-helpers` (from openshift-eng/ai-helpers)
- **Claude Access**: Vertex AI (shared GCP infrastructure)
- **Authentication**: GitHub Apps with JWT (not PATs)
- **Pattern**: Matches HyperShift Jira Agent implementation

## Troubleshooting

### No release notes generated

**Check:**
- Are the PR changes user-facing? (Claude skips internal changes)
- Check job logs for AI analysis output
- PR might only have developer-focused changes (tests, refactors)
- Does your repository have a `.release-notes-context.md` file?

**Solution:**
- This is expected behavior - not all PRs affect users
- Internal changes won't appear in user-facing release notes
- Add `.release-notes-context.md` to help Claude better understand what's user-facing for your product

### GitHub App authentication errors

**Check:**
- GitHub App is installed on your repository
- `installation-id` matches your repository
- Private key is valid

**Debug:**
```bash
# Verify secret contents
oc get secret pr-release-notes-bot -n test-credentials -o yaml
```

### Vertex AI / Claude errors

**Check logs for:**
- **"Permission denied"**: Service account needs `roles/aiplatform.user`
- **"Project not found"**: Check `ANTHROPIC_VERTEX_PROJECT_ID`
- **"Quota exceeded"**: Contact GCP admin for quota increase

**Fix:**
```yaml
# Try different region if current is unavailable
- as: pr-release-notes
  steps:
    test:
    - ref: pr-release-notes
      env:
      - name: CLOUD_ML_REGION
        value: "us-central1"
```

## Cost Considerations

- **Vertex AI**: ~$0.01-0.05 per PR (varies by PR size)
- **Compute**: < 2 minutes runtime per PR
- **For 50 PRs/month**: ~$0.50-2.50/month total

## Security

- ✅ GitHub App with minimal permissions (read PRs, write to single file)
- ✅ Short-lived tokens (10-minute expiry)
- ✅ Vertex AI via GCP service account (no API keys)
- ✅ All credentials in Kubernetes secrets
- ✅ Isolated container execution

## Comparison with Alternatives

| Approach | This Tool | Manual Updates | CodeRabbit + Tool |
|----------|-----------|---------------|-------------------|
| **Automation** | Fully automatic | Manual effort | Semi-automatic |
| **User Focus** | AI enforces user focus | Depends on author | Developer-focused |
| **Dependencies** | None (built-in) | N/A | Requires CodeRabbit |
| **Cost** | ~$1-2/month | Developer time | CodeRabbit + AI costs |
| **Consistency** | Consistent format | Varies | Varies |

## Related Components

- **HyperShift Jira Agent**: `ci-operator/step-registry/hypershift/jira-agent/`
  - Uses same Vertex AI and GitHub App patterns
- **Claude AI Helpers**: `openshift-eng/ai-helpers`
  - Provides the claude-ai-helpers image

## Maintenance

Owned by the team listed in `OWNERS` file.

For issues or feature requests, contact owners or open an issue in openshift/release.

## References

- [OpenShift CI Documentation](https://docs.ci.openshift.org/)
- [Claude on Vertex AI](https://cloud.google.com/vertex-ai/generative-ai/docs/partner-models/use-claude)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Writing Release Notes](https://www.writethedocs.org/guide/writing/release-notes/)
