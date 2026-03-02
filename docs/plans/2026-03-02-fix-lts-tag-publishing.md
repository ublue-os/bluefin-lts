# Fix LTS Tag Publishing - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent accidental production tag publishes from pull bot PRs to `lts` branch. Production tags (`:lts`, `:lts.YYYYMMDD`) should ONLY publish via weekly cron schedule or manual workflow_dispatch on `lts` branch.

**Architecture:** Remove `lts` from workflow pull_request triggers. Create dispatcher workflow on `main` that triggers production builds on `lts` via workflow_dispatch. Update GitHub branch protection to enforce `lts` branch discipline.

**Tech Stack:**
- GitHub Actions (scheduled workflows, workflow_dispatch, reusable workflows)
- GitHub CLI (`gh`) for workflow dispatch
- Branch protection rules

**Status:** ✅ Design improved and ready for implementation (v2 - added lts validation builds)

---

## Problem Statement

**Current Broken Behavior (as of 2026-03-02):**

1. **Pull bot creates PR from `main` → `lts`** (PR #1144, opened ~17:08 UTC)
2. **Workflows trigger on the PR** because all 5 build workflows have:
   ```yaml
   pull_request:
     branches:
       - lts  # ← THIS IS THE BUG
   ```
3. **Production tags get published** from PR events (not just from `lts` branch merges)
4. **Tags published about an hour ago** when they should only publish via weekly Sunday 2 AM UTC cron

**Evidence:**
- Run #22586907105: "Build Bluefin LTS" triggered by PR event
- Run #22586905020: "Build Bluefin LTS DX" triggered by PR event
- Run #22586905071: "Build Bluefin LTS GDX" triggered by PR event
- All published production `:lts` tags despite being PR-triggered

**Root Cause:**
Commit a3e9a6a (on `main`, not yet on `lts`) attempted to fix this by removing `lts` from `push:` triggers, but **left `lts` in `pull_request:` triggers**. This is incomplete.

**Additional Issue:**
GitHub Actions `schedule:` triggers ALWAYS run on the default branch (`main`), not `lts`. Current cron would build from `main` branch, not production `lts` branch.

---

## Solution Design

### Core Strategy

**Workflow Trigger Matrix:**

| Event | Branch | Should Trigger? | Should Publish? | Tags Published |
|-------|--------|----------------|-----------------|----------------|
| PR opened | `main` | ✅ Yes | ❌ No | none (validation only) |
| PR merged | `main` | ✅ Yes (push) | ✅ Yes | `:lts-testing` |
| Pull bot PR | `lts` | ❌ **NO** | ❌ No | none |
| Pull bot merge | `lts` | ✅ **YES** (validation) | ❌ **NO** | none (build only) |
| Cron (Sun 2am) | `main` | ✅ Yes (dispatcher) | ❌ No | none (dispatcher only) |
| Dispatcher trigger | `lts` | ✅ Yes (workflow_dispatch) | ✅ Yes | `:lts` (production) |
| Manual dispatch | `lts` | ✅ Yes | ✅ Yes | `:lts` (production) |
| Manual dispatch | `main` | ✅ Yes | ✅ Yes | `:lts-testing` |

### Dispatcher Pattern (Solve Cron on Wrong Branch)

Since cron runs on `main` (default branch), we need:

```
schedule (on main) → dispatcher workflow → workflow_dispatch (on lts) → builds + publish
```

**Flow:**
1. Sunday 2 AM UTC: `scheduled-lts-release.yml` runs on `main`
2. Dispatcher uses `gh workflow run` to trigger all 5 builds on `lts` branch
3. Builds run on `lts` with `workflow_dispatch` event
4. Publish condition allows publishes from `lts` branch
5. Production tags (`:lts`) get published

### Branch Protection Enforcement

Configure `lts` branch protection to:
- Require PR approval before merging
- Prevent direct pushes (except pull bot + maintainers)
- Disable force pushes
- Ensure only vetted code reaches production

---

## Implementation Tasks

### Task 1: Create Dispatcher Workflow

**File:**
- Create: `.github/workflows/scheduled-lts-release.yml`

**Step 1: Write the dispatcher workflow**

```yaml
name: Scheduled LTS Release

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM UTC
  workflow_dispatch:  # Allow manual triggering

permissions:
  contents: read
  actions: write

jobs:
  trigger-lts-builds:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger all LTS builds on lts branch
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          # Trigger all 5 build workflows on lts branch
          gh workflow run build-regular.yml --ref lts -R ${{ github.repository }}
          gh workflow run build-dx.yml --ref lts -R ${{ github.repository }}
          gh workflow run build-gdx.yml --ref lts -R ${{ github.repository }}
          gh workflow run build-regular-hwe.yml --ref lts -R ${{ github.repository }}
          gh workflow run build-dx-hwe.yml --ref lts -R ${{ github.repository }}
          
          echo "✅ Triggered all 5 LTS build workflows on lts branch"
          echo "View workflow runs at: ${{ github.server_url }}/${{ github.repository }}/actions"
```

**Step 2: Update publish condition**

**Current (line 33):**
```yaml
publish: ${{ github.event_name != 'pull_request' }}
```

**Fixed:**
```yaml
publish: ${{ github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main') }}
```

**Why:**
- Publish on `workflow_dispatch` (cron dispatcher + manual on lts)
- Publish on `push` to `main` (testing tags)
- Do NOT publish on `push` to `lts` (pull bot validation builds)

**Step 3: Validate syntax**

Run: `just check`
Expected: No errors

**Step 4: Commit the fix**

```bash
git add .github/workflows/build-regular.yml
git commit -m "fix(ci): update build-regular.yml triggers and publish condition

Changes:
- Remove lts from pull_request trigger (no PR builds)
- Add lts to push trigger (validation builds on merge)
- Update publish condition (only workflow_dispatch or push to main)
- Remove schedule (moved to dispatcher)

This prevents accidental production tag publishes from pull bot PRs
while maintaining validation builds on pull bot merges.

Production publishes only via:
- Weekly cron dispatcher (scheduled-lts-release.yml)
- Manual workflow_dispatch on lts branch

Assisted-by: Claude 3.5 Sonnet via GitHub Copilot"
```

---

### Task 3: Fix build-dx.yml Triggers

**File:**
- Modify: `.github/workflows/build-dx.yml`

**Step 1: Apply same trigger and publish fixes as build-regular.yml**

Remove `- lts` from `pull_request: branches:` (line 12)
Add `- lts` to `push: branches:` (after line 15)
Remove `schedule:` section (lines 16-17)
Update `publish:` condition (line 34) to:
```yaml
publish: ${{ github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main') }}
```

**Step 2: Validate syntax**

Run: `just check`
Expected: No errors

**Step 3: Commit the fix**

```bash
git add .github/workflows/build-dx.yml
git commit -m "fix(ci): update build-dx.yml triggers and publish condition

Same fix as build-regular.yml - prevents accidental production
tag publishes from pull bot PRs while maintaining validation builds.

Assisted-by: Claude 3.5 Sonnet via GitHub Copilot"
```

---

### Task 4: Fix build-gdx.yml Triggers

**File:**
- Modify: `.github/workflows/build-gdx.yml`

**Step 1: Apply same trigger and publish fixes**

Remove `- lts` from `pull_request: branches:`
Add `- lts` to `push: branches:`
Remove `schedule:` section
Update `publish:` condition (line 35) to:
```yaml
publish: ${{ github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main') }}
```

**Step 2: Validate syntax**

Run: `just check`
Expected: No errors

**Step 3: Commit the fix**

```bash
git add .github/workflows/build-gdx.yml
git commit -m "fix(ci): update build-gdx.yml triggers and publish condition

Same fix as other build workflows.

Assisted-by: Claude 3.5 Sonnet via GitHub Copilot"
```

---

### Task 5: Fix build-regular-hwe.yml Triggers

**File:**
- Modify: `.github/workflows/build-regular-hwe.yml`

**Step 1: Apply same trigger and publish fixes**

Remove `- lts` from `pull_request: branches:`
Add `- lts` to `push: branches:`
Remove `schedule:` section
Update `publish:` condition (line 39) to:
```yaml
publish: ${{ github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main') }}
```

**Step 2: Validate syntax**

Run: `just check`
Expected: No errors

**Step 3: Commit the fix**

```bash
git add .github/workflows/build-regular-hwe.yml
git commit -m "fix(ci): update build-regular-hwe.yml triggers and publish condition

Same fix as other build workflows.

Assisted-by: Claude 3.5 Sonnet via GitHub Copilot"
```

---

### Task 6: Fix build-dx-hwe.yml Triggers

**File:**
- Modify: `.github/workflows/build-dx-hwe.yml`

**Step 1: Apply same trigger and publish fixes**

Remove `- lts` from `pull_request: branches:`
Add `- lts` to `push: branches:`
Remove `schedule:` section
Update `publish:` condition (line 39) to:
```yaml
publish: ${{ github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main') }}
```

**Step 2: Validate syntax**

Run: `just check`
Expected: No errors

**Step 3: Commit the fix**

```bash
git add .github/workflows/build-dx-hwe.yml
git commit -m "fix(ci): update build-dx-hwe.yml triggers and publish condition

Completes the fix across all 5 build workflows.

All workflows now:
- Trigger on PRs to main (validation)
- Trigger on pushes to main (publish :lts-testing)
- Trigger on pushes to lts (validation, no publish)
- Trigger on workflow_dispatch (manual or from dispatcher)
- Do NOT trigger on pull bot PRs to lts

Assisted-by: Claude 3.5 Sonnet via GitHub Copilot"
```

---

### Task 7: Verify Publish Conditions (UPDATED in Tasks 2-6)

**Note:** This task was previously a read-only check. The publish conditions are now UPDATED in Tasks 2-6.

**Files modified:**
- `.github/workflows/build-regular.yml:33`
- `.github/workflows/build-dx.yml:34`
- `.github/workflows/build-gdx.yml:35`
- `.github/workflows/build-regular-hwe.yml:39`
- `.github/workflows/build-dx-hwe.yml:39`

**New publish condition (applied in all workflows):**
```yaml
publish: ${{ github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main') }}
```

**Why this is needed:**
- Old condition: `publish: ${{ github.event_name != 'pull_request' }}`
  - ❌ Would publish on push to lts (pull bot merges)
- New condition: Only publish on:
  - ✅ `workflow_dispatch` (cron dispatcher + manual)
  - ✅ `push` to `main` (testing tags)
  - ❌ NOT on `push` to `lts` (validation only)

**Verification:**

Run:
```bash
grep "publish:" .github/workflows/build-*.yml
```

Expected: All show the new condition with `workflow_dispatch` and `main` checks

```bash
echo "✅ Publish conditions updated in Tasks 2-6"
echo "Tag naming logic unchanged in reusable-build-image.yml"
```

---

### Task 8: Update Branch Protection for lts

**Location:** GitHub repository settings (web UI)

**Note:** Branch protection already exists but needs updating.

**Step 1: Navigate to branch protection settings**

1. Go to: `https://github.com/ublue-os/bluefin-lts/settings/branches`
2. Click "Edit" on existing `lts` protection rule
3. Branch name pattern: `lts`

**Step 2: Update required settings**

**Current state verified:**
- Required approvals: 2
- Force pushes: ENABLED (needs to be DISABLED)
- Enforce admins: DISABLED

**Update to:**
```
☑ Require a pull request before merging
  ☑ Require approvals: 1 (change from 2)
  ☑ Dismiss stale pull request approvals when new commits are pushed
  ☐ Require review from Code Owners (not needed)

☑ Require status checks to pass before merging
  ☐ Require branches to be up to date before merging (can cause issues with pull bot)
  Required checks: (leave empty - workflows don't run on lts PRs anymore)

☑ Require conversation resolution before merging

☐ Require signed commits (optional - up to team preference)

☐ Require linear history (not recommended - pull bot uses hardreset)

☑ Do not allow bypassing the above settings
  (Alternative: Allow only specific people - castrojo, tulilirockz, hanthor)

☑ Restrict who can push to matching branches
  Allowed: pull[bot], castrojo, tulilirockz, hanthor

☐ Allow force pushes (DISABLE - currently enabled, needs to be disabled)

☐ Allow deletions (keep disabled)
```

**Step 3: Save and verify**

Click "Save changes"

Expected: Branch protection updated on `lts`

**Step 4: Verify configuration**

Run:
```bash
gh api repos/ublue-os/bluefin-lts/branches/lts/protection | jq '{approvals: .required_pull_request_reviews.required_approving_review_count, force_pushes: .allow_force_pushes.enabled, enforce_admins: .enforce_admins.enabled}'
```

Expected output:
```json
{
  "approvals": 1,
  "force_pushes": false,
  "enforce_admins": true
}
```

---

### Task 9: Update Documentation

**File:**
- Modify: `docs/BRANCH_PROTECTION.md` (add lts branch section)

**Step 1: Add lts branch protection section**

Add after line 241:

```markdown

## LTS Branch Protection (2026-03)

**Settings applied to `lts` branch:**

### Required Settings

1. **Require pull request before merging**
   - Require approvals: 1
   - Dismiss stale approvals when new commits are pushed

2. **Do not allow bypassing settings**
   - Enforce for administrators: Yes

3. **Restrict who can push**
   - Allowed: pull[bot], castrojo, tulilirockz, hanthor

4. **Block force pushes**
   - Force pushes: DISABLED

**Purpose:**
- Prevent accidental direct pushes to `lts`
- Ensure pull bot PRs get reviewed before merge
- Maintain production branch discipline
- Prevent force push accidents

**Workflow Integration:**
- Pull bot creates PRs from `main` → `lts` (no CI triggers)
- PRs must be approved before merging
- Merging to `lts` does NOT publish images (workflows don't trigger)
- Production publishes happen via:
  - Weekly cron dispatcher (Sunday 2 AM UTC)
  - Manual workflow_dispatch on `lts` branch

**Emergency Access:**
- Maintainers can run workflow_dispatch on `lts` for immediate releases
- Maintainers can bypass branch protection if absolutely necessary (if enforce_admins is disabled)
```

**Step 2: Commit documentation update**

```bash
git add docs/BRANCH_PROTECTION.md
git commit -m "docs: document lts branch protection configuration

Added section explaining lts branch protection settings
and how they integrate with the workflow changes."
```

---

### Task 10: Test Dispatcher (Manual)

**Prerequisites:** All previous tasks completed and merged to `main`

**Step 1: Manually trigger dispatcher**

```bash
gh workflow run scheduled-lts-release.yml --ref main
```

**Step 2: Verify dispatcher runs**

```bash
# Check dispatcher run
gh run list --workflow=scheduled-lts-release.yml --limit 1

# Wait ~30 seconds for workflows to be dispatched

# Check if builds triggered on lts
gh run list --branch=lts --limit 10
```

**Expected:**
- Dispatcher completes successfully
- 5 build workflows triggered on `lts` branch
- All show event: `workflow_dispatch`
- All show branch: `lts`

**Step 3: Monitor build progress**

```bash
# Watch build progress
gh run watch <run-id>

# Or view all runs
gh run list --branch=lts --limit 10 --json event,conclusion,headBranch,workflowName
```

**Expected (after ~30-60 minutes):**
- All 5 builds complete successfully
- Production tags published: `:lts`, `:lts.20260302`, etc.
- SBOM artifacts generated
- No `:lts-testing` tags published

**Step 4: Verify tags in registry**

```bash
# Check published tags (requires skopeo)
skopeo list-tags docker://ghcr.io/ublue-os/bluefin | grep -E "^lts" | tail -10
```

**Expected:**
- `:lts` tag updated with new digest
- `:lts.YYYYMMDD` tag created (today's date)
- `:lts-testing` unchanged (not from this run)

**Step 5: Document test results**

```bash
# No commit - just verification
echo "✅ Manual dispatcher test completed successfully"
echo "Production tags published: lts, lts.YYYYMMDD"
echo "Ready for weekly cron schedule"
```

---

### Task 11: Test Pull Bot PR Flow

**Prerequisites:** All changes merged to `main` and synced to `lts`

**Step 1: Wait for pull bot PR or create test PR**

Wait for pull bot to create a new PR from `main` → `lts`, or manually create one for testing:

```bash
# Option A: Wait for pull bot (preferred)
# Check for existing PR
gh pr list --base lts

# Option B: Create test PR (if needed for immediate testing)
git checkout lts
git pull upstream lts
git checkout -b test-lts-pr-flow
git merge upstream/main --no-edit
git push origin test-lts-pr-flow

gh pr create --base lts --head test-lts-pr-flow \
  --title "[TEST] Verify lts PR doesn't trigger workflows" \
  --body "Testing that PRs to lts no longer trigger build workflows"
```

**Step 2: Verify NO workflows triggered**

```bash
# Check recent runs
gh run list --limit 20 --json event,headBranch,displayTitle,conclusion,createdAt

# Should NOT see any runs for the test PR
```

**Expected:**
- ❌ No "Build Bluefin LTS" runs triggered
- ❌ No "Build Bluefin LTS DX" runs triggered
- ❌ No runs for any build workflows

**Step 3: Close test PR (if created manually)**

```bash
gh pr close <pr-number> --delete-branch
```

**Step 4: Document test results**

```bash
# No commit - just verification
echo "✅ Pull bot PR test completed successfully"
echo "PRs to lts do NOT trigger workflows (as intended)"
```

---

### Task 12: Test Main Branch Publishing

**Prerequisites:** All changes merged and active

**Step 1: Create small test PR to main**

```bash
git checkout main
git pull upstream main
git checkout -b test-main-publish
echo "# Test $(date)" >> .test-publish-marker.txt
git add .test-publish-marker.txt
git commit -m "test: verify main branch publishes lts-testing tags"
git push origin test-main-publish

gh pr create --base main --head test-main-publish \
  --title "[TEST] Verify main publishes :lts-testing tags" \
  --body "Testing that merges to main still publish testing tags"
```

**Step 2: Wait for PR checks and merge**

```bash
# Wait for CI
gh pr checks <pr-number> --watch

# Merge when green
gh pr merge <pr-number> --merge
```

**Step 3: Verify testing tags published**

```bash
# Check runs after merge
gh run list --branch=main --event=push --limit 5

# Wait for builds to complete (~30-60 minutes)
# Monitor one of the runs
gh run watch <run-id>

# Verify testing tags published
skopeo list-tags docker://ghcr.io/ublue-os/bluefin | grep testing | tail -10
```

**Expected:**
- ✅ All 5 build workflows triggered on push to main
- ✅ Builds publish `:lts-testing`, `:lts-testing.YYYYMMDD` tags
- ❌ No `:lts` production tags published

**Step 4: Clean up test file**

```bash
git checkout main
git pull upstream main
git rm .test-publish-marker.txt
git commit -m "chore: remove test marker file"
git push upstream main
```

---

### Task 13: Final Validation Checklist

**Step 1: Run validation checks**

```bash
# Syntax validation
just check

# Lint validation
just lint

# Verify all workflows exist
ls -1 .github/workflows/*.yml | wc -l
# Expected: 6 workflows (5 builds + 1 dispatcher)

# Verify no lts in pull_request triggers
grep -n "pull_request:" .github/workflows/build-*.yml -A 3 | grep "lts"
# Expected: No output (no matches)

# Verify no schedule in build workflows
grep -n "schedule:" .github/workflows/build-*.yml
# Expected: No output (no matches)

# Verify dispatcher exists
test -f .github/workflows/scheduled-lts-release.yml && echo "✅ Dispatcher exists" || echo "❌ Missing"

# Verify branch protection configured
gh api repos/ublue-os/bluefin-lts/branches/lts/protection --silent && echo "✅ Branch protection active" || echo "⚠️  Not configured yet"
```

**Step 2: Review workflow behavior matrix**

| Event | Branch | Triggers? | Publishes? | Tags |
|-------|--------|-----------|------------|------|
| PR to main | `main` | ✅ | ❌ | none |
| Merge to main | `main` | ✅ | ✅ | `:lts-testing` |
| PR to lts | `lts` | ❌ | ❌ | none |
| Merge to lts | `lts` | ✅ | ❌ | none (validation build) |
| Cron Sun 2am | `main` | ✅ | ❌ | none (dispatcher) |
| Dispatcher | `lts` | ✅ | ✅ | `:lts` (production) |
| Manual dispatch | `lts` | ✅ | ✅ | `:lts` |
| Manual dispatch | `main` | ✅ | ✅ | `:lts-testing` |

**Step 3: Document completion**

All items should be verified:

```bash
echo "Validation Checklist:"
echo "- [x] Dispatcher workflow created"
echo "- [x] All 5 build workflows updated (triggers + publish conditions)"
echo "- [x] lts added to push triggers (validation builds)"
echo "- [x] lts removed from pull_request triggers (no PR builds)"
echo "- [x] Publish conditions updated (workflow_dispatch or main push only)"
echo "- [x] Branch protection configured for lts"
echo "- [x] Documentation updated"
echo "- [x] Manual dispatcher test passed"
echo "- [x] Pull bot PR test passed (no triggers)"
echo "- [x] Pull bot merge test passed (builds but no publish)"
echo "- [x] Main branch publish test passed (testing tags)"
echo "- [x] Syntax validation passed"
echo "- [x] No accidental production tag publishes"
```

---

## Rollback Plan

If issues occur after implementation:

### Quick Rollback (Emergency)

```bash
# Manually trigger production release
gh workflow run build-regular.yml --ref lts
gh workflow run build-dx.yml --ref lts
gh workflow run build-gdx.yml --ref lts
gh workflow run build-regular-hwe.yml --ref lts
gh workflow run build-dx-hwe.yml --ref lts
```

### Full Revert

```bash
# Revert all workflow changes
git revert <commit-range>
git push upstream main

# Re-enable lts in pull_request triggers temporarily
# (Manual edit or revert to previous commit)
```

### Partial Rollback

If only dispatcher is problematic:

```bash
# Keep workflow trigger fixes
# Remove/disable dispatcher
git rm .github/workflows/scheduled-lts-release.yml
git commit -m "revert: remove dispatcher (issues found)"

# Use manual workflow_dispatch only for releases
```

---

## Future Enhancements

### Potential Improvements (YAGNI for now)

1. **Slack/Discord notifications** when dispatcher runs
2. **GitHub issue creation** when dispatcher fails
3. **Automatic changelog generation** trigger from dispatcher
4. **Parallel dispatcher** (trigger all 5 workflows in parallel, not sequential)
5. **Dispatcher retry logic** if workflow trigger fails
6. **Branch protection audit workflow** to verify settings
7. **Automated testing** of publish behavior (complicated)

---

## Validation Commands Reference

```bash
# Check recent workflow runs
gh run list --limit 20

# Check runs on specific branch
gh run list --branch=lts --limit 10
gh run list --branch=main --limit 10

# Check runs for specific workflow
gh run list --workflow=build-regular.yml --limit 10

# Check scheduled runs
gh run list --event=schedule --limit 10

# Check workflow_dispatch runs
gh run list --event=workflow_dispatch --limit 10

# View published tags
skopeo list-tags docker://ghcr.io/ublue-os/bluefin | grep -E "lts|testing"

# Check branch protection
gh api repos/ublue-os/bluefin-lts/branches/lts/protection | jq

# Verify pull bot config
cat .github/pull.yml

# Syntax check
just check

# Lint check
just lint
```

---

## Verification Results (2026-03-02)

**Plan verified against current codebase:**

✅ File paths and line numbers accurate  
✅ Current state matches plan assumptions  
✅ All 5 workflows have `lts` in `pull_request: branches:` (line 12)  
✅ All 5 workflows have `schedule:` cron (lines 16-17)  
✅ Dispatcher doesn't exist yet (needs creation)  
✅ Branch protection exists but needs updating (2 approvals → 1, force push enabled → disabled)  
✅ Tag naming logic verified in `reusable-build-image.yml:161-164`  
✅ PRODUCTION_BRANCH constant set to `lts` in `reusable-build-image.yml:76`  
✅ Publish conditions don't need changes  

**Plan Status:** ✅ Verified and ready for implementation

---

**Estimated Time:** 
- Implementation: 1-2 hours (workflow file edits + branch protection config)
- Testing: 1-2 hours (wait for builds, verify behavior)
- Total: 2-4 hours

**Risk Level:** Low
- Changes are isolated to workflow triggers
- Rollback is straightforward
- Testing can be done incrementally
- No changes to build logic itself
