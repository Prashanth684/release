# Setup Guide: Automated User-Facing Release Notes

This guide explains how to set up the automated release notes generator for your repository.

## Overview

This tool uses Claude AI (via Vertex AI) to analyze PR changes and automatically generate user-facing release notes. No external services like CodeRabbit are required.

## What It Does

- **Analyzes** PR diffs, descriptions, and metadata
- **Uses** repository context (`.release-notes-context.md`) to understand your product
- **Generates** user-facing documentation (not developer-focused)
- **Updates** a rolling RELEASE_NOTES.md file
- **Commits** changes back to the PR branch automatically

## Prerequisites

### Step 1: Add Repository Context File (Highly Recommended)

Before setting up the CI job, add `.release-notes-context.md` to your repository root.

**Why?** Without this file, Claude has to guess:
- What your product is and who uses it
- What changes are user-facing vs. internal
- What terminology to use

**How:**
1. Copy `EXAMPLE.release-notes-context.md` from this step-registry
2. Customize it for your product (5-10 minutes)
3. Commit it to your repository root as `.release-notes-context.md`

This dramatically improves release note accuracy and relevance.

### Step 2: Create Credentials Secret

You need a secret in the `test-credentials` namespace with 4 components:

```
pr-release-notes-bot/
├── claude-prow          # GCP service account JSON for Vertex AI
├── app-id               # GitHub App ID
├── installation-id      # GitHub App installation ID for your repo
└── private-key          # GitHub App private key PEM
```

### Step 2A: Reuse HyperShift's Vertex AI ⭐ **RECOMMENDED**

The HyperShift team already has Vertex AI set up. You can reuse their infrastructure:

**Steps:**
1. Contact HyperShift team or OpenShift CI admins
2. Request access to copy the `claude-prow` GCP service account credential
3. Create GitHub App for your repository (see Step 3)
4. Create combined secret (see Step 4)

**Advantages:**
- No new GCP setup needed
- Shared quota/billing
- Proven to work
- Faster setup

### Step 2B: Set Up Your Own Vertex AI

If you need separate Vertex AI access:

**1. Get GCP Access:**
```bash
# Contact OpenShift CI team for access to:
# Project: itpc-gcp-hybrid-pe-eng-claude
# Or create your own GCP project with Vertex AI enabled
```

**2. Create/Get Service Account:**
```bash
# Create service account with Vertex AI User role
gcloud iam service-accounts create release-notes-bot \
  --display-name="PR Release Notes Bot"

# Grant Vertex AI permissions
gcloud projects add-iam-policy-binding itpc-gcp-hybrid-pe-eng-claude \
  --member="serviceAccount:release-notes-bot@itpc-gcp-hybrid-pe-eng-claude.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# Download key
gcloud iam service-accounts keys create claude-prow.json \
  --iam-account=release-notes-bot@itpc-gcp-hybrid-pe-eng-claude.iam.gserviceaccount.com
```

### Step 3: Create GitHub App

**Why GitHub App?** More secure than PATs, fine-grained permissions, auditable

**Steps:**

1. **Create the App:**
   - Go to https://github.com/settings/apps/new
   - Name: `PR Release Notes Bot` (or your preference)
   - Homepage URL: `https://github.com/openshift/release`
   - Webhook: Disable (not needed)

2. **Set Permissions:**
   - Repository permissions:
     - Contents: `Read and write` (to commit release notes)
     - Pull requests: `Read-only` (to fetch PR data)
     - Metadata: `Read-only` (automatic)

3. **Install the App:**
   - Click "Install App" tab
   - Select your target repository
   - Note the **Installation ID** from the URL:
     `https://github.com/settings/installations/12345678` → Installation ID is `12345678`

4. **Get Credentials:**
   - Note the **App ID** (shown on app settings page)
   - Generate a **Private Key** (click button, download PEM file)

### Step 4: Create the Kubernetes Secret

Now create the secret with all components:

```bash
# Navigate to your secret files directory
cd /tmp/release-notes-secrets

# You should have:
# - claude-prow.json (GCP service account)
# - private-key.pem (GitHub App private key)

# Create the secret
oc create secret generic pr-release-notes-bot \
  -n test-credentials \
  --from-file=claude-prow=claude-prow.json \
  --from-literal=app-id=YOUR_GITHUB_APP_ID \
  --from-literal=installation-id=YOUR_INSTALLATION_ID \
  --from-file=private-key=private-key.pem

# Verify
oc get secret pr-release-notes-bot -n test-credentials
```

**Example:**
```bash
oc create secret generic pr-release-notes-bot \
  -n test-credentials \
  --from-file=claude-prow=claude-prow.json \
  --from-literal=app-id=123456 \
  --from-literal=installation-id=78901234 \
  --from-file=private-key=release-notes-bot-private-key.pem
```

## Add to Repository CI Configuration

Edit `ci-operator/config/<org>/<repo>/<org>-<repo>-<branch>.yaml`:

```yaml
tests:
# ... your existing tests ...

# Add this:
- as: pr-release-notes
  optional: true  # Won't block PR merges
  skip_if_only_changed: "^docs/|\\.md$|^(?:.*\\/)?(?:OWNERS|LICENSE)$"
  steps:
    test:
    - ref: pr-release-notes
```

## Generate Prow Jobs

Run make update to generate the Prow job configs:

```bash
cd /path/to/openshift/release
make update
```

This will create the corresponding job in `ci-operator/jobs/<org>/<repo>/`.

## Test the Configuration

Create a test PR in your repository:

1. Make a user-facing change (e.g., add a feature)
2. Open a PR with a clear description
3. Wait for the `pr-release-notes` job to run
4. If successful, you should see a commit updating `RELEASE_NOTES.md`

## Troubleshooting

### Job doesn't appear in Prow

**Check:**
- Did you run `make update`?
- Did you commit both the config and generated job files?
- Is the PR merged to master?

**Fix:**
```bash
make update
git add ci-operator/config/ ci-operator/jobs/
git commit -m "Add automated release notes job"
```

### "GitHub App credentials not found"

**Check:**
- Secret exists: `oc get secret pr-release-notes-bot -n test-credentials`
- Secret has all 4 keys: `oc get secret pr-release-notes-bot -n test-credentials -o yaml`

**Fix:**
```bash
# Re-create secret with all keys
oc delete secret pr-release-notes-bot -n test-credentials
oc create secret generic pr-release-notes-bot -n test-credentials \
  --from-file=claude-prow=claude-prow.json \
  --from-literal=app-id=123456 \
  --from-literal=installation-id=78901234 \
  --from-file=private-key=private-key.pem
```

### "Failed to generate GitHub App installation token"

**Check:**
- Is the `installation-id` correct for your repository?
- Is the GitHub App installed on your repository?
- Is the private key valid and matches the app-id?

**Debug:**
```bash
# Check installation ID in GitHub:
# Go to: https://github.com/settings/installations
# Click on your app installation
# URL will be: https://github.com/settings/installations/YOUR_ID
```

### Vertex AI / Claude errors

**Check job logs for specific errors:**

- **"Permission denied"**: Service account needs `roles/aiplatform.user`
- **"Project not found"**: Check `ANTHROPIC_VERTEX_PROJECT_ID` env var
- **"Region not available"**: Claude may not be available in `us-east5`, try `us-central1`

**Fix:**
```yaml
# Override region in your config:
- as: pr-release-notes
  optional: true
  steps:
    test:
    - ref: pr-release-notes
      env:
      - name: CLOUD_ML_REGION
        value: "us-central1"  # Try different region
```

### No release notes generated

**This is expected behavior if:**
- PR only has internal/developer changes (tests, refactors, code cleanup)
- Changes don't affect end users
- PR is documentation-only

**The tool intentionally skips:**
- Code refactoring
- Test infrastructure changes
- Developer tooling updates
- Internal API changes

**To verify:**
- Check job logs for "No changes to release notes"
- Review the PR - are there user-visible changes?

## Cost Estimates

- **Vertex AI**: ~$0.01-0.05 per PR (depends on PR size)
- **Compute**: Negligible (< 2 min runtime)
- **Storage**: None (temporary git clone)

For a repo with 50 PRs/month: ~$0.50-2.50/month

## Security Notes

- ✅ GitHub App permissions are minimal (read PRs, write one file)
- ✅ Installation tokens are short-lived (10 minutes)
- ✅ GCP service account has limited scope (Vertex AI only)
- ✅ All credentials in Kubernetes secrets (never in code)
- ✅ Jobs run in isolated containers

## Next Steps

1. ✅ Add `.release-notes-context.md` to your repository (see Step 1)
2. ✅ Create credentials secret (see Step 2)
3. ✅ Add test configuration to your repo's CI config
4. ✅ Run `make update` in openshift/release
5. ✅ Commit and merge changes
6. ✅ Test with a user-facing PR

## Questions?

- Check `README.md` for detailed documentation
- Check `EXAMPLE.yaml` for configuration examples
- See `ci-operator/step-registry/hypershift/jira-agent/` for similar implementation
- Contact step owners (see `OWNERS` file)
