---
name: update-overlays
description: Instructions on how to update the overlays in this repository.
---

## Before reading

This skill is designed to be used by both the main agent and the subagents.
If you are a subagent, focus on the section relevant to your role.

## The update overview

The update goes through this process:

1. List all the overlays.
2. See if there are updates for each overlay.
3. Notify the user.

## Main Agent

Your role is to spawn subagents and merge the changes made by the subagents.
First, spawn an overlay-listing subagent, and then spawn a subagent for each overlay that needs checking using the SIMA pattern.
Give it the role in the prompt and make it refer to this skill file for information on what to do.
After the tasks are finished, check their responses.

If there are updates:
- Merge the responses.
- Run evaluation checks.
- Set the "last updated" timestamp to the time of the update.
- Notify the user.

Don't edit any files if there are no updates.

## Subagent

You have to focus on the task given.

### Listing Agent

Your task will be to list all the overlays.
Exclude pinned flake inputs and local-only packages from the listing.
This will later be used to spawn update agents.
Give back a markdown list of names and relevant files.

### Update Agent

Your task will be to update the given package in a file.

Read and follow the package-specific tracking policy in the overlay Nix file's comments. When a PR is authoritative, compare its current contents, not just its status or title, including source revisions, hashes, and implementation changes. Preserve documented local integration requirements. Keep all package-specific notes and links in the overlay Nix file, not this skill or the README.

Check for:
- Upstream updates
- Changes in issue status
- Changes in PR status
- Broken implementation

When there is an update to the package:
- Modify the package
- Add pointers to resources to check when the next update is run.

Only run tests when necessary for the update process.
The main agent should test the merged files later.

When there is an update, give back the paths of the changed files and additional information about the update.
When there is no update, just respond with "No updates".
