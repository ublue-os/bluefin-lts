# Weekly LTS Promotion Workflow - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automate weekly LTS releases with smart retry mechanism, ensuring changes bake in -testing for 24h before promoting to stable.

**Architecture:** GitHub Actions workflow on `main` branch with aggressive 6-hour polling Tuesday-Friday. Merges pullapp PR (main→lts) when conditions met, triggering automatic stable image builds.

**Tech Stack:**
- GitHub Actions (scheduled workflows)
- GitHub CLI (`gh`) for PR operations
- Bash scripting for condition checks
- Branch protection bypass configuration

**Status:** ✅ Plan reviewed and corrected (2026-02-14, round 2)

**Fixes Applied (Round 1):**
- Fixed tracking issue week calculation (handles Tuesday edge case correctly)
- Added error handling for commit timestamp parsing
- Added force mode audit trail (logs who forced promotion)
- Fixed all relative URLs to absolute paths (PR/issue comments, workflow links)
- Enhanced verification command to show both apps and users

**Fixes Applied (Round 2 - Code Review):**
- **C1:** Removed `--auto` from `gh pr merge` (merge immediately, not deferred)
- **C2:** Defaulted FORCE_PROMOTE to `'false'` for scheduled runs
- **C3:** Guarded `statusCheckRollup` against null (PRs with no checks)
- **I1:** Simplified 13 cron entries to single `0 */6 * * TUE-FRI`
- **I3:** Removed dead Monday/Sunday branches from week calculation
- **I5:** Fixed misleading security claim about bypass scope
- **R3:** Added concurrency group to prevent overlapping runs
- **R5:** Added fork guard (`if: github.repository == 'ublue-os/bluefin-lts'`)
- **M1:** Removed unnecessary checkout step (workflow only uses `gh` CLI)
- **M3:** Removed `promotion-override` label (YAGNI, kept in Future Enhancements)
- **M4:** Moved PR comment before merge command (PR may close on merge)

---

## Problem Statement

**Current State:**
- Changes merge to `main` → auto-publish `lts-testing` images
- Pull app bot creates PR #1100 (main → lts) automatically
- **Manual step:** Maintainer reviews and merges pullapp PR weekly
- Merge to `lts` → auto-publish stable `lts` images

**Issues:**
1. Manual merge required every week (toil)
2. Timing inconsistent (last promotions: Feb 2, Jan 26, Jan 18 - irregular)
3. No enforcement of testing time in -testing images
4. Cron in workflow files removed (complicates branch management)

**Goal:**
- Weekly LTS releases on Tuesdays
- Automatic promotion when ready
- Mandatory 24h baking time in -testing
- Smart retry if Tuesday blocked by timing

---

## Solution Design

### Workflow Schedule (6-Hour Polling, Tuesday-Friday)

**Schedule:** `cron: '0 */6 * * TUE-FRI'` — runs at 00:00, 06:00, 12:00, 18:00 UTC each day, Tuesday through Friday (up to 16 attempts per week).

**Rationale:**
- Normal case: Promotes on first Tuesday attempt
- Monday night merges: Caught by early Tuesday check (after 24h baking)
- Continuous updates: Eventually oldest commits age past 24h threshold
- Maximum delay: 5 days (Friday → next Tuesday)
- Most weekly runs are no-ops that exit in seconds after detecting a recent promotion

### Promotion Conditions (All Must Pass)

1. **No recent promotion:** Last merge to `lts` was ≥7 days ago
2. **Pullapp PR exists:** Active PR from `main` to `lts` by pull[bot]
3. **Has changes:** PR contains at least 1 commit
4. **No hold:** PR does not have `promotion-hold` label
5. **CI passing:** All status checks succeeded or skipped
6. **24h baking:** Newest commit in PR is ≥24 hours old (strictest check)

### Behavior

**On Success:**
- Adds comment explaining automated promotion (before merge)
- Merges pullapp PR immediately with `--merge` strategy
- Closes tracking issue (if exists)
- Workflow skips remaining attempts until next Tuesday

**On Block:**
- Logs reason to workflow output
- Creates/updates tracking issue (first block only)
- Waits 6 hours for next attempt
- Retries until Friday final attempt

**On Permanent Block:**
- Tracking issue remains open with status
- Next Tuesday starts new cycle
- Manual intervention available via labels

---

## Prerequisites

### 1. Branch Protection Configuration (REQUIRED)

**Current State:**
- `lts` branch requires 2 approving reviews before merge
- No bypass allowances configured
- Default `GITHUB_TOKEN` cannot auto-merge

**Required Change (Repository Admin):**

1. Navigate to repository settings
   ```
   https://github.com/ublue-os/bluefin-lts/settings/branch_protection_rules
   ```

2. Edit `lts` branch protection rule

3. Under "Require pull request reviews before merging":
   - Enable: "Allow specified actors to bypass pull request requirements"
   - Add actor: `github-actions[bot]` or the GitHub Actions app
   - Save changes

**Security Note:** Adding `github-actions[bot]` to the bypass list allows ANY workflow using `GITHUB_TOKEN` to bypass reviews on `lts`. The promote-lts workflow restricts itself via the pullapp author check (software guard), but the platform-level bypass is broader. Consider this acceptable given the `lts` branch only receives merges from the pull app.

**Verification:**
```bash
gh api repos/ublue-os/bluefin-lts/branches/lts/protection/required_pull_request_reviews \
  --jq '{apps: [.bypass_pull_request_allowances.apps[]? | .slug], users: [.bypass_pull_request_allowances.users[]? | .login]}'
# Should show github-actions in the apps array
```

### 2. Labels Creation

Create repository labels:
```bash
gh label create "promotion-tracking" \
  --description "Tracks weekly LTS promotion status" \
  --color "0E8A16"

gh label create "promotion-hold" \
  --description "Blocks automated LTS promotion" \
  --color "D93F0B"
```

---

## Task 1: Create Promotion Workflow

**Files:**
- Create: `.github/workflows/promote-lts.yml`

**Step 1: Create workflow file with schedule**

Create `.github/workflows/promote-lts.yml`:

```yaml
name: Promote LTS Release

on:
  schedule:
    # Every 6 hours Tuesday-Friday. Most weeks promote on the first
    # Tuesday attempt; the remaining runs are no-ops that exit early.
    - cron: '0 */6 * * TUE-FRI'
    
  workflow_dispatch:
    inputs:
      force:
        description: 'Skip 24h age check (emergency use only)'
        type: boolean
        default: false
        required: false

permissions:
  contents: write
  pull-requests: write
  issues: write

concurrency:
  group: promote-lts
  cancel-in-progress: false

jobs:
  promote:
    # Only run in the upstream repo, not in forks
    if: github.repository == 'ublue-os/bluefin-lts'
    runs-on: ubuntu-latest
    steps:
      - name: Check Promotion Conditions
        id: check
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          FORCE_PROMOTE: ${{ inputs.force || 'false' }}
        run: |
          set -euo pipefail
          
          echo "::group::Check 1: Already promoted this week?"
          LAST_MERGE=$(gh api repos/${{ github.repository }}/branches/lts --jq '.commit.commit.committer.date')
          LAST_MERGE_TS=$(date -d "$LAST_MERGE" +%s)
          NOW_TS=$(date +%s)
          HOURS_SINCE=$(( ($NOW_TS - $LAST_MERGE_TS) / 3600 ))
          
          echo "Last promotion: $LAST_MERGE ($HOURS_SINCE hours ago)"
          
          if [ $HOURS_SINCE -lt 168 ]; then
            echo "result=skip" >> $GITHUB_OUTPUT
            echo "reason=Already promoted this week ($HOURS_SINCE hours ago)" >> $GITHUB_OUTPUT
            echo "✓ Already promoted recently"
            exit 0
          fi
          echo "✓ Last promotion was $HOURS_SINCE hours ago (>168h threshold)"
          echo "::endgroup::"
          
          echo "::group::Check 2: Find pullapp PR"
          PULLAPP_PR=$(gh pr list --base lts --author "app/pull" --state open --limit 1 --json number --jq '.[0].number // empty')
          
          if [ -z "$PULLAPP_PR" ]; then
            echo "result=skip" >> $GITHUB_OUTPUT
            echo "reason=No pullapp PR found (main → lts)" >> $GITHUB_OUTPUT
            echo "⚠️ No pullapp PR exists"
            exit 0
          fi
          
          echo "pr_number=$PULLAPP_PR" >> $GITHUB_OUTPUT
          echo "✓ Found pullapp PR #$PULLAPP_PR"
          echo "::endgroup::"
          
          echo "::group::Check 3: PR has commits?"
          COMMIT_COUNT=$(gh pr view $PULLAPP_PR --json commits --jq '.commits | length')
          
          if [ $COMMIT_COUNT -eq 0 ]; then
            echo "result=skip" >> $GITHUB_OUTPUT
            echo "reason=PR #$PULLAPP_PR is empty (no changes)" >> $GITHUB_OUTPUT
            echo "⏭️ PR is empty"
            exit 0
          fi
          
          echo "✓ PR has $COMMIT_COUNT commits"
          echo "::endgroup::"
          
          echo "::group::Check 4: promotion-hold label?"
          if gh pr view $PULLAPP_PR --json labels --jq '.labels[].name' | grep -q "promotion-hold"; then
            echo "result=blocked" >> $GITHUB_OUTPUT
            echo "reason=Blocked by 'promotion-hold' label" >> $GITHUB_OUTPUT
            echo "🛑 Promotion on hold"
            exit 0
          fi
          echo "✓ No hold label"
          echo "::endgroup::"
          
          echo "::group::Check 5: CI status"
          FAILED_CHECKS=$(gh pr view $PULLAPP_PR --json statusCheckRollup --jq '[(.statusCheckRollup // [])[] | select(.conclusion != "SUCCESS" and .conclusion != "SKIPPED" and .conclusion != null)] | length')
          
          if [ $FAILED_CHECKS -gt 0 ]; then
            echo "result=blocked" >> $GITHUB_OUTPUT
            echo "reason=CI checks failing ($FAILED_CHECKS failures)" >> $GITHUB_OUTPUT
            echo "⛔ CI failing"
            exit 0
          fi
          echo "✓ All CI checks passing"
          echo "::endgroup::"
          
          echo "::group::Check 6: Newest commit age (24h requirement)"
          NEWEST_COMMIT=$(gh pr view $PULLAPP_PR --json commits --jq '.commits[-1].committedDate')
          
          if [ -z "$NEWEST_COMMIT" ] || [ "$NEWEST_COMMIT" == "null" ]; then
            echo "result=blocked" >> $GITHUB_OUTPUT
            echo "reason=Could not determine newest commit timestamp" >> $GITHUB_OUTPUT
            echo "⚠️ No commit timestamp found"
            exit 0
          fi
          
          COMMIT_TS=$(date -d "$NEWEST_COMMIT" +%s)
          AGE_HOURS=$(( ($NOW_TS - $COMMIT_TS) / 3600 ))
          
          echo "Newest commit: $NEWEST_COMMIT"
          echo "Age: $AGE_HOURS hours"
          echo "commit_age=$AGE_HOURS" >> $GITHUB_OUTPUT
          
          if [ "$FORCE_PROMOTE" != "true" ] && [ $AGE_HOURS -lt 24 ]; then
            echo "result=blocked" >> $GITHUB_OUTPUT
            echo "reason=Newest commit only ${AGE_HOURS}h old (requires 24h)" >> $GITHUB_OUTPUT
            echo "⏳ Too recent"
            exit 0
          fi
          
          if [ "$FORCE_PROMOTE" == "true" ]; then
            echo "⚠️ Force mode: Skipping age check"
            echo "force_used=true" >> $GITHUB_OUTPUT
          else
            echo "✓ Commit age ${AGE_HOURS}h (≥24h)"
            echo "force_used=false" >> $GITHUB_OUTPUT
          fi
          echo "::endgroup::"
          
          echo "result=promote" >> $GITHUB_OUTPUT
          echo "reason=All conditions met" >> $GITHUB_OUTPUT
          echo "✅ Ready to promote!"
      
      - name: Promote to LTS
        if: steps.check.outputs.result == 'promote'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ steps.check.outputs.pr_number }}
          COMMIT_AGE: ${{ steps.check.outputs.commit_age }}
          FORCE_USED: ${{ steps.check.outputs.force_used }}
        run: |
          set -euo pipefail
          
          echo "🚀 Promoting PR #$PR_NUMBER to lts branch"
          
          # Add force mode audit comment if applicable
          if [ "$FORCE_USED" == "true" ]; then
            gh pr comment $PR_NUMBER --body "⚠️ **FORCED PROMOTION**

Initiated by: @${{ github.actor }}  
Age check bypassed via workflow_dispatch force parameter.

[View workflow run](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})"
          fi
          
          # Add explanatory comment before merge (PR may close on merge,
          # preventing post-merge comments)
          gh pr comment $PR_NUMBER --body "🎉 **Automated LTS Promotion**

Promoted to stable \`lts\` tag after passing all conditions:
- ✅ Commits baked in \`lts-testing\` for ${COMMIT_AGE}+ hours
- ✅ All CI checks passing
- ✅ Weekly promotion window (Tuesday-Friday)

Stable images will publish shortly via push trigger to \`lts\` branch.

---
*Automated by [Promote LTS Release workflow](https://github.com/${{ github.repository }}/actions/workflows/promote-lts.yml)*  
*Run: [#${{ github.run_number }}](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})*"
          
          # Merge immediately (not --auto). All conditions already verified above.
          # NOTE: Using --merge (merge commit). The pull app uses hardreset to sync
          # main→lts, so the next sync will force-push regardless of merge strategy.
          gh pr merge $PR_NUMBER --merge
          
          echo "✅ Promotion complete"
      
      - name: Create/Update Tracking Issue
        if: steps.check.outputs.result == 'blocked'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          BLOCK_REASON: ${{ steps.check.outputs.reason }}
          PR_NUMBER: ${{ steps.check.outputs.pr_number }}
        run: |
          set -euo pipefail
          
          # Calculate current week's Tuesday
          # Cron only fires Tue-Fri, so DAY_OF_WEEK is always 2-5
          DAY_OF_WEEK=$(date +%u)  # 1=Mon, 2=Tue, ..., 7=Sun
          if [ $DAY_OF_WEEK -eq 2 ]; then
            # Today is Tuesday, use today
            WEEK_START=$(date +%Y-%m-%d)
          else
            # Wed-Fri - calculate days back to Tuesday
            DAYS_BACK=$(( $DAY_OF_WEEK - 2 ))
            WEEK_START=$(date -d "$DAYS_BACK days ago" +%Y-%m-%d)
          fi
          
          ISSUE_TITLE="LTS Promotion Tracking: Week of $WEEK_START"
          
          # Check if tracking issue exists for this week
          EXISTING=$(gh issue list --label "promotion-tracking" --state open --search "$WEEK_START" --json number --jq '.[0].number // empty')
          
          CURRENT_TIME=$(date -u '+%Y-%m-%d %H:%M UTC')
          NEXT_CHECK=$(date -u -d '+6 hours' '+%Y-%m-%d %H:%M UTC')
          
          if [ -z "$EXISTING" ]; then
            # Create new tracking issue
            echo "Creating tracking issue for week of $WEEK_START"
            gh issue create \
              --title "$ISSUE_TITLE" \
              --label "promotion-tracking" \
              --body "## LTS Promotion Status

**Target:** Weekly promotion (Tuesdays)  
**Status:** ⏳ Waiting for conditions

### Current Blocker
- **$CURRENT_TIME:** $BLOCK_REASON

### Retry Schedule
Automatic checks every 6 hours (00:00, 06:00, 12:00, 18:00 UTC):
- **Tuesday-Friday:** Up to 16 attempts per week

### Manual Override
- **Pause promotion:** Add \`promotion-hold\` label to [PR #$PR_NUMBER](https://github.com/${{ github.repository }}/pull/$PR_NUMBER)
- **Force promote:** Run workflow manually with force option
- **See details:** [Latest run](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})

---
*Auto-managed by [Promote LTS Release workflow](https://github.com/${{ github.repository }}/actions/workflows/promote-lts.yml)*"
          else
            # Update existing issue
            echo "Updating tracking issue #$EXISTING"
            gh issue comment $EXISTING --body "**$CURRENT_TIME:** ⏳ Still waiting
- **Blocker:** $BLOCK_REASON
- **Next check:** $NEXT_CHECK
- **Details:** [Run #${{ github.run_number }}](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})"
          fi
      
      - name: Close Tracking Issue
        if: steps.check.outputs.result == 'promote'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ steps.check.outputs.pr_number }}
        run: |
          set -euo pipefail
          
          # Find and close tracking issue (same week calculation as above)
          DAY_OF_WEEK=$(date +%u)
          if [ $DAY_OF_WEEK -eq 2 ]; then
            WEEK_START=$(date +%Y-%m-%d)
          else
            DAYS_BACK=$(( $DAY_OF_WEEK - 2 ))
            WEEK_START=$(date -d "$DAYS_BACK days ago" +%Y-%m-%d)
          fi
          
          EXISTING=$(gh issue list --label "promotion-tracking" --state open --search "$WEEK_START" --json number --jq '.[0].number // empty')
          
          if [ -n "$EXISTING" ]; then
            echo "Closing tracking issue #$EXISTING"
            CURRENT_TIME=$(date -u '+%Y-%m-%d %H:%M UTC')
            
            gh issue comment $EXISTING --body "**$CURRENT_TIME:** ✅ **Promoted!**

PR #$PR_NUMBER merged to \`lts\` branch.  
Stable images will publish via automatic build triggers.

[View promotion run](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})"
            
            gh issue close $EXISTING
          fi
      
      - name: Summary
        if: always()
        env:
          RESULT: ${{ steps.check.outputs.result }}
          REASON: ${{ steps.check.outputs.reason }}
        run: |
          echo "### Promotion Result: ${RESULT:-unknown}" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Reason:** ${REASON:-No reason provided}" >> $GITHUB_STEP_SUMMARY
          
          if [ "$RESULT" == "promote" ]; then
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "✅ LTS promotion successful!" >> $GITHUB_STEP_SUMMARY
          elif [ "$RESULT" == "blocked" ]; then
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "⏳ Will retry in 6 hours" >> $GITHUB_STEP_SUMMARY
          fi
```

**Step 2: Validate workflow syntax**

```bash
# Check YAML syntax
yamllint .github/workflows/promote-lts.yml

# Or use actionlint if available
actionlint .github/workflows/promote-lts.yml
```

Expected: No syntax errors

**Step 3: Commit the workflow**

```bash
git add .github/workflows/promote-lts.yml
git commit -m "feat(ci): add weekly LTS promotion workflow

Automates weekly promotion of main → lts with:
- 6-hour polling Tuesday-Friday via single cron entry
- 24h minimum baking time in lts-testing
- Smart retry mechanism for timing edge cases
- Tracking issues for blocked promotions
- Fork guard and concurrency control

Requires: GitHub Actions bypass on lts branch protection

Assisted-by: Claude 3.5 Sonnet via GitHub Copilot"
```

---

## Task 2: Create Repository Labels

**Step 1: Create promotion-tracking label**

```bash
gh label create "promotion-tracking" \
  --description "Tracks weekly LTS promotion status" \
  --color "0E8A16" \
  || echo "Label already exists"
```

**Step 2: Create promotion-hold label**

```bash
gh label create "promotion-hold" \
  --description "Blocks automated LTS promotion" \
  --color "D93F0B" \
  || echo "Label already exists"
```

**Step 3: Verify labels created**

```bash
gh label list | grep promotion
```

Expected output:
```
promotion-hold       Blocks automated LTS promotion
promotion-tracking   Tracks weekly LTS promotion status
```

**Step 4: Commit label creation documentation**

Update or create `.github/labels.md`:

```markdown
# Repository Labels

## Promotion Labels

- **promotion-tracking**: Automatically applied to weekly promotion tracking issues
- **promotion-hold**: Apply to pullapp PR to pause automated promotion
```

```bash
git add .github/labels.md
git commit -m "docs: document promotion workflow labels"
```

---

## Task 3: Request Branch Protection Bypass

**Step 1: Create issue for admin action**

```bash
gh issue create \
  --title "Configure branch protection bypass for automated LTS promotion" \
  --label "infrastructure" \
  --assignee castrojo \
  --body "## Required Configuration

To enable the automated LTS promotion workflow, we need to configure branch protection bypass.

### Action Required (Repository Admin)

1. Navigate to [Branch Protection Settings](https://github.com/ublue-os/bluefin-lts/settings/branches)
2. Edit the \`lts\` branch protection rule
3. Under **\"Require pull request reviews before merging\"**:
   - ✅ Enable: \"Allow specified actors to bypass pull request requirements\"
   - ➕ Add actor: \`github-actions[bot]\`
   - 💾 Save changes

### Why This Is Needed

- The \`lts\` branch currently requires 2 approving reviews
- The promotion workflow needs to auto-merge the pullapp PR (main → lts)
- Without bypass, workflow cannot merge despite passing all conditions

### Security

- Adding \`github-actions[bot]\` to bypass allows any workflow using GITHUB_TOKEN to bypass reviews on \`lts\`
- The promote-lts workflow restricts itself to pullapp PRs via author check (software guard)
- All other PRs from humans still require reviews
- Acceptable risk: \`lts\` branch only receives merges from the pull app

### Verification

After configuration, verify with:
\`\`\`bash
gh api repos/ublue-os/bluefin-lts/branches/lts/protection/required_pull_request_reviews \\
  --jq '.bypass_pull_request_allowances.apps[] | select(.slug == \"github-actions\")'
\`\`\`

Should return GitHub Actions app details.

### Related

- Workflow: \`.github/workflows/promote-lts.yml\`
- Implementation plan: \`docs/plans/2026-02-14-weekly-lts-promotion.md\`"
```

**Step 2: Document current configuration**

```bash
echo "Documenting current branch protection state..."

gh api repos/ublue-os/bluefin-lts/branches/lts/protection \
  --jq '{
    required_reviews: .required_pull_request_reviews.required_approving_review_count,
    bypass_actors: .required_pull_request_reviews.bypass_pull_request_allowances
  }' > docs/branch-protection-lts-before.json

git add docs/branch-protection-lts-before.json
git commit -m "docs: snapshot lts branch protection before bypass config"
```

---

## Task 4: Testing Strategy

### Manual Testing (Before First Tuesday)

**Test 1: Workflow syntax and basic execution**

```bash
# Trigger workflow manually (dry run)
gh workflow run promote-lts.yml
```

Check workflow output for:
- All condition checks execute
- No script errors
- Appropriate skip/block reason

**Test 2: Simulate conditions with test PR**

Option A: Use existing pullapp PR
```bash
# Check current PR state
gh pr view 1100 --json number,commits,statusCheckRollup,labels

# Workflow will skip if:
# - Last promotion was <7 days ago (expected)
# - Will log reason and exit cleanly
```

Option B: Create test label scenario
```bash
# Add promotion-hold label
gh pr edit 1100 --add-label "promotion-hold"

# Run workflow
gh workflow run promote-lts.yml

# Should detect label and block
# Check run output

# Remove label
gh pr edit 1100 --remove-label "promotion-hold"
```

**Test 3: Force promotion (if bypass configured)**

```bash
# ONLY IF: Admin has configured bypass AND you want to test merge
gh workflow run promote-lts.yml --field force=true

# WARNING: This will actually merge the PR!
# Only use if:
# - Bypass is configured
# - PR is ready to promote
# - You understand this publishes stable images
```

### Monitoring First Scheduled Run

**Next Tuesday 10am UTC:**

1. Watch workflow execution:
```bash
gh run watch
```

2. Check for tracking issue creation:
```bash
gh issue list --label "promotion-tracking"
```

3. Verify behavior matches expectations:
   - If conditions met: PR merges, images build
   - If blocked: Issue created, will retry 4pm

4. Monitor lts branch builds:
```bash
gh run list --branch lts --limit 5
```

---

## Task 5: Documentation Updates

**Step 1: Update CONTRIBUTING.md (if exists)**

Add section about automated releases:

```markdown
## Automated LTS Releases

### Release Schedule

LTS stable images are automatically promoted **weekly on Tuesdays** (or within that week if delayed).

### How It Works

1. Changes merge to `main` → `-testing` images published
2. Changes "bake" in testing for minimum 24 hours
3. Weekly promotion workflow checks conditions Tuesday-Friday
4. When ready, pullapp PR auto-merges → stable `lts` images publish

### Blocking a Release

If you need to hold a release:

```bash
gh pr edit <pullapp-pr-number> --add-label "promotion-hold"
```

Remove the label when ready to resume:

```bash
gh pr edit <pullapp-pr-number> --remove-label "promotion-hold"
```

### Monitoring

Track promotion status via:
- Tracking issues labeled `promotion-tracking`
- [Promote LTS Release workflow runs](../actions/workflows/promote-lts.yml)
```

**Step 2: Create operational runbook**

Create `docs/runbooks/lts-promotion.md`:

```markdown
# LTS Promotion Runbook

## Normal Operations

The LTS promotion workflow runs automatically Tuesday-Friday every 6 hours.

**Schedule:** Every 6 hours (00:00, 06:00, 12:00, 18:00 UTC), Tuesday through Friday.

## Common Scenarios

### Scenario: Promotion Delayed by Recent Commits

**Symptom:** Tracking issue shows "newest commit only Xh old"

**Expected Behavior:** Workflow will automatically retry every 6 hours until 24h threshold met

**Action:** None required, monitor tracking issue for updates

### Scenario: Need to Hold Promotion

**Use Case:** Critical bug found in -testing images

**Action:**
```bash
# Find pullapp PR
gh pr list --base lts --author "app/pull"

# Add hold label
gh pr edit <PR#> --add-label "promotion-hold"
```

**Result:** Workflow will skip until label removed

### Scenario: Force Promotion (Emergency)

**Use Case:** Critical fix needs immediate deployment

**Action:**
```bash
gh workflow run promote-lts.yml --field force=true
```

**Warning:** Bypasses 24h age check. Use sparingly.

### Scenario: Workflow Not Running

**Check 1:** Verify workflow exists and is enabled
```bash
gh workflow view promote-lts.yml
```

**Check 2:** Check for workflow errors
```bash
gh run list --workflow=promote-lts.yml --limit 5
```

**Check 3:** Verify branch protection configured
```bash
gh api repos/ublue-os/bluefin-lts/branches/lts/protection/required_pull_request_reviews \
  --jq '.bypass_pull_request_allowances.apps'
```

Should show github-actions app.

## Metrics

### Success Rate

```bash
# Count successful promotions per month
gh run list --workflow=promote-lts.yml --status success --created ">=YYYY-MM-01" --json conclusion --jq 'length'
```

### Average Promotion Time

```bash
# Time from PR creation to merge
# Manual analysis of tracking issues
```

## Troubleshooting

### Workflow Runs But Doesn't Merge

**Possible Causes:**
1. Branch protection bypass not configured
2. GitHub Actions doesn't have write permissions
3. PR conflicts exist
4. PR was closed/merged manually

**Check:**
```bash
# View latest run logs
gh run view --log

# Check PR status
gh pr view <PR#> --json mergeable,mergeStateStatus
```

### Tracking Issue Not Created

**Expected:** Only created on first block attempt

**Check:** Look for existing open issue with `promotion-tracking` label

### Too Many Retries

**If Friday final attempt still blocked:**
- Promotion deferred to next Tuesday
- Review tracking issue for persistent blockers
- Consider manual intervention if urgent
```

**Step 3: Commit documentation**

```bash
git add docs/runbooks/lts-promotion.md
git add CONTRIBUTING.md  # if modified
git commit -m "docs: add LTS promotion runbook and update contributing guide"
```

---

## Verification Checklist

After full implementation:

- [ ] Workflow file `.github/workflows/promote-lts.yml` exists and is valid
- [ ] Labels created: `promotion-tracking`, `promotion-hold`
- [ ] Issue created for admin to configure branch protection bypass
- [ ] Branch protection bypass configured (admin action)
- [ ] Workflow tested manually with `workflow_dispatch`
- [ ] Documentation updated (CONTRIBUTING.md, runbooks)
- [ ] Team notified of new automated promotion process
- [ ] First Tuesday run monitored and successful

---

## Rollback Plan

If automation causes issues:

**Step 1: Disable workflow**

```bash
gh workflow disable promote-lts.yml
```

**Step 2: Close open tracking issues**

```bash
gh issue list --label "promotion-tracking" --state open --json number \
  | jq -r '.[].number' \
  | xargs -I {} gh issue close {} --comment "Promotion workflow disabled, reverting to manual process"
```

**Step 3: Remove branch protection bypass**

Admin action: Remove `github-actions[bot]` from lts branch bypass list

**Step 4: Return to manual promotion**

Resume manual merging of pullapp PRs as before

---

## Success Metrics

**Week 1-2 (Validation Phase):**
- Workflow runs on schedule
- Tracking issues created/closed appropriately
- At least one successful auto-promotion
- No false merges (promoting when conditions not met)

**Week 3-4 (Optimization Phase):**
- 90%+ promotions happen Tuesday or Wednesday
- <5% require manual intervention
- Team reports reduced toil

**Month 2+ (Steady State):**
- Weekly promotions occur automatically
- Tracking issues rare (most promote first try)
- Zero missed promotions
- Clear audit trail of promotion history

---

## Future Enhancements

**Phase 2 Improvements:**

1. **Slack/Discord notifications** on promotion success/failure
2. **Promotion override label** for emergency bypasses
3. **Metrics dashboard** showing promotion timing trends
4. **Automatic changelog** generation from promoted commits
5. **Dry-run mode** for testing changes to workflow
6. **Smarter retry logic** based on CI completion time

**Phase 3 Considerations:**

1. **Multiple promotion tracks** (stable, beta, etc.)
2. **Staged rollout** with canary deployments
3. **Integration with release notes** generation
4. **Automatic issue triage** for build failures

---

## References

- GitHub Actions: https://docs.github.com/en/actions
- Branch Protection: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches
- Pull App Bot: https://github.com/apps/pull
- Bluefin LTS repo: https://github.com/ublue-os/bluefin-lts

---

**Plan created:** 2026-02-14  
**Estimated implementation time:** 2-3 hours + admin config + 1 week monitoring  
**Risk level:** Low-Medium (can disable anytime, manual override available)  
**Complexity:** Medium (workflow logic, branch protection, testing)

---

## Implementation Notes

### Execution Approach

This plan can be executed in two ways:

**Option A: Sequential (Recommended for first time)**
- Implement Task 1 → Test → Implement Task 2 → etc.
- Allows validation at each step
- Easier to debug issues

**Option B: Parallel (Faster, requires coordination)**
- Task 1 & Task 2 (workflow + labels) can be done in parallel
- Task 3 (bypass config) is blocking for actual promotion
- Task 4 (testing) depends on Tasks 1-3
- Task 5 (docs) can be done anytime

**Recommended:** Sequential approach, especially for initial implementation.

### Key Decision Points

**Before Task 3:**
- Confirm team agrees with 24h baking requirement
- Review schedule (every 6 hours Tue-Fri appropriate?)
- Verify label names match team conventions

**Before First Tuesday:**
- Ensure at least one maintainer understands the workflow
- Document emergency contact if workflow fails
- Have rollback plan ready

### Coordination Required

**With Repository Admins:**
- Task 3 requires admin action (branch protection)
- Can't proceed to production without this
- Estimated time: 5 minutes for admin

**With Team:**
- Notify team of automation start date
- Share runbook and emergency procedures
- Set expectations for first few weeks (monitoring period)

---

## Appendix: Example Timeline

**Week 0 (Implementation):**
- Monday: Implement Tasks 1-2, create admin request (Task 3)
- Tuesday: Admin configures bypass, testing (Task 4)
- Wednesday: Documentation (Task 5), team notification
- Thursday-Friday: Buffer for issues

**Week 1 (First Run):**
- Tuesday 10am: First automatic attempt (likely succeeds)
- Monitor throughout week
- Document any issues

**Week 2-3 (Validation):**
- Continue monitoring
- Adjust schedule/conditions if needed
- Gather feedback from team

**Week 4+ (Steady State):**
- Automation running smoothly
- Weekly promotions happen automatically
- Manual intervention only for holds or emergencies
