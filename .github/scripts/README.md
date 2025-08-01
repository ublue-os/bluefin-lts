# Changelog Publishing Fix

This directory contains the solution for issue #607 - "Releases are stuck" where changelogs don't get published because it always detects the same tag (20250602).

## Files

### `publish-changelog.sh`
Main script that implements smart tag detection to prevent duplicate changelog publishing:

- **Tag Detection**: Gets the latest LTS tag from git repository
- **State Tracking**: Compares with last published tag stored in `last_published_tag.txt`
- **Conditional Publishing**: Only generates changelog if a new tag is detected
- **Force Mode**: Allows manual override for republishing
- **Error Handling**: Robust validation of all inputs and outputs

### `last_published_tag.txt`
Simple text file that tracks the last tag for which a changelog was published. This prevents the script from repeatedly processing the same tag.

## Usage

The script is automatically called by the updated `generate-changelog-release.yml` workflow, but can also be run manually:

```bash
# Normal mode - only publish if new tag detected
./.github/scripts/publish-changelog.sh lts "Optional handwritten notes" false

# Force mode - publish regardless of tag status  
./.github/scripts/publish-changelog.sh lts "Optional handwritten notes" true
```

## Workflow Integration

The `generate-changelog-release.yml` workflow has been updated to:

1. Use `fetch-depth: 0` to get all git history for proper tag detection
2. Call the new script instead of directly invoking `changelogs.py`
3. Skip release creation if no new tag is detected
4. Support force publishing via workflow inputs

## How It Fixes The Issue

**Before**: The workflow would always process the same tag because `changelogs.py` looks at container registry manifests to find tags, but doesn't track which ones have already been processed.

**After**: The script tracks the last published tag in a file and compares it with the current latest tag, only generating changelogs when a genuinely new tag is available.

This ensures each new release gets exactly one changelog publication, fixing the "stuck on 20250602" issue.