# Release Notes Context

This file provides context to Claude AI about your repository to help generate accurate user-facing release notes.
Copy this template to your repository as `.release-notes-context.md` and customize it for your product.

## Product Overview

**What is this component/product?**

Example: "OpenShift OAuth Server - handles authentication and authorization for OpenShift clusters"

Provide a 1-2 sentence description of what this software does from a user perspective.

## Target Audience

**Who are the users of this product?**

Examples:
- **Cluster Administrators**: People who install and configure OpenShift clusters
- **End Users**: Developers and operators who authenticate to use the cluster
- **Platform Engineers**: Teams managing multi-cluster deployments
- **Application Developers**: Users who deploy applications to the cluster

Be specific about who uses your product and in what role.

## What Users Care About

**What types of changes matter to your users?**

Examples:
- New authentication methods and identity providers (LDAP, GitHub, OAuth providers)
- Changes to login experience and session management
- New configuration options or APIs
- Security features and compliance improvements
- Performance improvements to authentication operations
- Breaking changes to OAuth configuration
- Deprecations of authentication methods

List the kinds of changes that affect what users see, experience, or need to configure.

## What's NOT User-Facing

**What types of changes should be ignored in release notes?**

Examples:
- Internal refactoring of authentication logic without behavior changes
- Test infrastructure and CI/CD changes
- Code organization improvements
- Developer tooling updates
- Internal API changes that don't affect user-facing configuration
- Dependency updates (unless they fix a user-visible issue)
- Documentation typo fixes

This helps Claude filter out developer-focused changes.

## Product-Specific Terminology

**What terms and concepts are specific to your product?**

Examples:
- "Identity Provider" - external authentication system (e.g., LDAP, GitHub)
- "OAuth Client" - application requesting authentication from the cluster
- "Cluster Console" - web UI that users log into
- "Service Account" - non-human identity for automated processes

Define key terms so Claude uses consistent, accurate language.

## Examples of User-Facing vs. Internal Changes

### User-Facing Changes (include in release notes):
- Added support for SAML 2.0 authentication
- Fixed bug where users were logged out after 5 minutes
- New API endpoint for managing OAuth clients
- Breaking change: removed support for OAuth 1.0 (users must migrate to OAuth 2.0)
- Improved login page with better error messages

### Internal Changes (exclude from release notes):
- Refactored token validation logic to reduce code duplication
- Updated unit tests to use new testing framework
- Migrated from logrus to zap logging library
- Fixed linter warnings in internal packages
- Updated CI pipeline to use newer base images

## Additional Guidance

**Any other context that helps distinguish user-facing from internal changes?**

Example: "This is a backend service. Users never interact with it directly, but they interact through the web console and CLI. Focus on changes that affect APIs, configuration options, behavior, or performance that administrators would notice."
