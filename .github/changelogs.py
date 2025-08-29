#!/usr/bin/env python3
"""
Changelog generation script for Bluefin LTS container images.

This script generates changelogs by comparing container image manifests
and extracting package differences between versions.
"""

import argparse
import json
import logging
import os
import re
import subprocess
import sys
import time
import yaml
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


@dataclass
class Config:
    """Configuration loaded from YAML file"""
    os_name: str
    targets: List[str]
    registry_url: str
    package_blacklist: List[str]
    image_variants: List[str]
    patterns: Dict[str, str]
    templates: Dict[str, str]
    sections: Dict[str, str]
    defaults: Dict[str, any]


def load_config(config_path: str = ".github/changelog_config.yaml") -> Config:
    """Load configuration from YAML file"""
    try:
        with open(config_path, 'r') as f:
            data = yaml.safe_load(f)
        return Config(**data)
    except FileNotFoundError:
        logging.error(f"Configuration file not found: {config_path}")
        sys.exit(1)
    except yaml.YAMLError as e:
        logging.error(f"Error parsing YAML configuration: {e}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Error loading configuration: {e}")
        sys.exit(1)


class ChangelogError(Exception):
    """Custom exception for changelog generation errors."""
    pass


class ManifestFetchError(ChangelogError):
    """Exception raised when manifest fetching fails."""
    pass


class TagDiscoveryError(ChangelogError):
    """Exception raised when tag discovery fails."""
    pass

# Compiled regex patterns for better performance will be loaded from config

# Templates and patterns will be loaded from config

class GitHubReleaseError(ChangelogError):
    """Error related to GitHub release operations."""
    pass


def check_github_release_exists(tag: str) -> bool:
    """Check if a GitHub release already exists for the given tag."""
    try:
        result = subprocess.run(
            ["gh", "release", "view", tag],
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        logger.warning("GitHub CLI not available or timeout - skipping release check")
        return False


def get_last_published_release_tag() -> Optional[str]:
    """Get the tag of the last published GitHub release."""
    try:
        result = subprocess.run(
            ["gh", "release", "list", "--limit", "1", "--json", "tagName", "--jq", ".[0].tagName"],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        logger.warning("GitHub CLI not available or timeout - cannot get last published release")
        return None


def write_github_output(output_file: str, variables: Dict[str, str]) -> None:
    """Write variables to GitHub Actions output file."""
    try:
        with open(output_file, 'a', encoding='utf-8') as f:
            for key, value in variables.items():
                f.write(f"{key}={value}\n")
        logger.info(f"Written {len(variables)} variables to GitHub output: {output_file}")
    except Exception as e:
        logger.error(f"Failed to write GitHub output: {e}")


class ChangelogGenerator:
    """Main class for generating changelogs from container manifests."""
    
    def __init__(self, config: Optional[Config] = None):
        """Initialize the changelog generator with configuration."""
        self.config = config or load_config()
        self._manifest_cache: Dict[str, Dict[str, Any]] = {}
        
        # Compile regex patterns from config
        self.centos_pattern = re.compile(self.config.patterns["centos"])
        self.start_patterns = {
            target: re.compile(self.config.patterns["start_pattern"].format(target=target))
            for target in self.config.targets
        }
        
    def get_images(self, target: str) -> List[Tuple[str, str]]:
        """Generate image names and experiences for a given target."""
        images = []
        base_name = "bluefin"  # Base image name is always "bluefin"
        
        for experience in self.config.image_variants:
            img = base_name
            
            if "-hwe" in target:
                images.append((img, target))
                break
                
            # Add experience suffix if it's not empty
            if experience:  # experience is like "", "-dx", "-gdx"
                img += experience
                
            images.append((img, target))  # Use target instead of experience
        return images
    
    def _run_skopeo_command(self, image_url: str) -> Optional[bytes]:
        """Run skopeo inspect command with retries."""
        for attempt in range(self.config.defaults["retries"]):
            try:
                result = subprocess.run(
                    ["skopeo", "inspect", image_url],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=self.config.defaults["timeout_seconds"]
                )
                return result.stdout
            except subprocess.CalledProcessError as e:
                logger.warning(f"Failed to get {image_url} (exit code {e.returncode}), "
                              f"retrying in {self.config.defaults['retry_wait']} seconds "
                              f"({attempt + 1}/{self.config.defaults['retries']})")
                if e.stderr:
                    logger.error(f"Error: {e.stderr.decode().strip()}")
            except subprocess.TimeoutExpired:
                logger.warning(f"Timeout getting {image_url}, "
                              f"retrying in {self.config.defaults['retry_wait']} seconds "
                              f"({attempt + 1}/{self.config.defaults['retries']})")
            except Exception as e:
                logger.warning(f"Unexpected error getting {image_url}: {e}, "
                              f"retrying in {self.config.defaults['retry_wait']} seconds "
                              f"({attempt + 1}/{self.config.defaults['retries']})")
            
            if attempt < self.config.defaults["retries"] - 1:
                time.sleep(self.config.defaults["retry_wait"])
        
        return None
    
    def get_manifests(self, target: str) -> Dict[str, Any]:
        """Fetch container manifests for all image variants."""
        # Check cache first
        if target in self._manifest_cache:
            logger.info(f"Using cached manifest for {target}")
            return self._manifest_cache[target]
            
        manifests = {}
        images = self.get_images(target)
        
        logger.info(f"Fetching manifests for {len(images)} images with target '{target}'")
        for i, (img, _) in enumerate(images, 1):
            logger.info(f"Getting {img}:{target} manifest ({i}/{len(images)})")
            image_url = f"docker://{self.config.registry_url}/{img}:{target}"
            
            output = self._run_skopeo_command(image_url)
            if output is None:
                logger.error(f"Failed to get {img}:{target} after {self.config.defaults['retries']} attempts")
                continue
                
            try:
                manifests[img] = json.loads(output)
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse JSON for {img}:{target}: {e}")
                continue
        
        if not manifests:
            raise ManifestFetchError(f"Failed to fetch any manifests for target '{target}'")
                
        # Cache the result
        self._manifest_cache[target] = manifests
        return manifests


    def get_tags(self, target: str, manifests: Dict[str, Any], previous_tag: Optional[str] = None) -> Tuple[str, str]:
        """Extract previous and current tags from manifests."""
        if not manifests:
            raise TagDiscoveryError("No manifests provided for tag discovery")
        
        # Find the current tag from manifests
        tags = set()
        first_manifest = next(iter(manifests.values()))
        
        for tag in first_manifest["RepoTags"]:
            # Tags ending with .0 should not exist
            if tag.endswith(".0"):
                continue
            if re.match(self.start_patterns[target], tag):
                tags.add(tag)
        
        # Filter tags that exist in all manifests
        for manifest in manifests.values():
            tags = {tag for tag in tags if tag in manifest["RepoTags"]}
        
        sorted_tags = sorted(tags)
        if len(sorted_tags) < 1:
            raise TagDiscoveryError(
                f"No tags found for target '{target}'. "
                f"Available tags: {sorted_tags}"
            )
        
        current_tag = sorted_tags[-1]  # Latest tag
        
        # Use provided previous_tag or fall back to automatic detection
        if previous_tag:
            logger.info(f"Using provided previous tag: {previous_tag}")
            prev_tag = previous_tag
        else:
            if len(sorted_tags) < 2:
                raise TagDiscoveryError(
                    f"Insufficient tags found for target '{target}' and no previous tag provided. "
                    f"Found {len(sorted_tags)} tags, need at least 2 or explicit previous tag. "
                    f"Available tags: {sorted_tags}"
                )
            prev_tag = sorted_tags[-2]  # Second latest tag
            logger.info(f"Auto-detected previous tag: {prev_tag}")
            
        logger.info(f"Found {len(sorted_tags)} tags for target '{target}'")
        logger.info(f"Comparing {prev_tag} -> {current_tag}")
        return prev_tag, current_tag
    
    def get_packages(self, manifests: Dict[str, Any]) -> Dict[str, Dict[str, str]]:
        """Extract package information from manifests."""
        packages = {}
        for img, manifest in manifests.items():
            try:
                rechunk_info = manifest["Labels"].get("dev.hhd.rechunk.info")
                if not rechunk_info:
                    logger.warning(f"No rechunk info found for {img}")
                    continue
                    
                packages[img] = json.loads(rechunk_info)["packages"]
                logger.debug(f"Extracted {len(packages[img])} packages for {img}")
            except (KeyError, json.JSONDecodeError, TypeError) as e:
                logger.error(f"Failed to get packages for {img}: {e}")
        return packages


    def get_package_groups(self, target: str, prev: Dict[str, Any], 
                          manifests: Dict[str, Any]) -> Tuple[List[str], Dict[str, List[str]]]:
        """Categorize packages into common and variant-specific groups."""
        common = set()
        others = {k: set() for k in self.config.sections.keys()}
        
        npkg = self.get_packages(manifests)
        ppkg = self.get_packages(prev)
        
        keys = set(npkg.keys()) | set(ppkg.keys())
        pkg = defaultdict(set)
        for k in keys:
            pkg[k] = set(npkg.get(k, {})) | set(ppkg.get(k, {}))
        
        # Find common packages
        first = True
        for img, experience in self.get_images(target):
            if img not in pkg:
                continue
                
            if first:
                common.update(pkg[img])
            else:
                common.intersection_update(pkg[img])
            first = False
        
        # Find other packages
        for t, other in others.items():
            first = True
            for img, experience in self.get_images(target):
                if img not in pkg:
                    continue
                    
                if t == "base" and experience != "base":
                    continue
                if t == "dx" and experience != "dx":
                    continue
                    
                if first:
                    other.update(p for p in pkg[img] if p not in common)
                else:
                    other.intersection_update(pkg[img])
                first = False
        
        return sorted(common), {k: sorted(v) for k, v in others.items()}
    
    def get_versions(self, manifests: Dict[str, Any]) -> Dict[str, str]:
        """Extract package versions from manifests."""
        versions = {}
        pkgs = self.get_packages(manifests)
        for img_pkgs in pkgs.values():
            for pkg, version in img_pkgs.items():
                versions[pkg] = re.sub(self.centos_pattern, "", version)
        return versions


    def calculate_changes(self, pkgs: List[str], prev: Dict[str, str], 
                         curr: Dict[str, str]) -> str:
        """Calculate package changes between versions."""
        added = []
        changed = []
        removed = []
        
        blacklist_ver = {curr.get(v) for v in self.config.package_blacklist if curr.get(v)}
        
        for pkg in pkgs:
            # Clean up changelog by removing mentioned packages
            if pkg in self.config.package_blacklist:
                continue
            if pkg in curr and curr.get(pkg) in blacklist_ver:
                continue
            if pkg in prev and prev.get(pkg) in blacklist_ver:
                continue
                
            if pkg not in prev:
                added.append(pkg)
            elif pkg not in curr:
                removed.append(pkg)
            elif prev[pkg] != curr[pkg]:
                changed.append(pkg)
                
            # Add current versions to blacklist
            if pkg in curr:
                blacklist_ver.add(curr[pkg])
            if pkg in prev:
                blacklist_ver.add(prev[pkg])
        
        logger.info(f"Package changes: {len(added)} added, {len(changed)} changed, {len(removed)} removed")
        
        output = ""
        for pkg in added:
            output += self.config.templates["pattern_add"].format(name=pkg, version=curr[pkg])
        for pkg in changed:
            output += self.config.templates["pattern_change"].format(name=pkg, prev=prev[pkg], new=curr[pkg])
        for pkg in removed:
            output += self.config.templates["pattern_remove"].format(name=pkg, version=prev[pkg])
            
        return output
    
    def get_commits(self, prev_manifests: Dict[str, Any], 
                   manifests: Dict[str, Any], target: str, workdir: Optional[str] = None) -> str:
        """Extract commit information between versions."""
        # Check if commits are enabled in configuration
        if not self.config.defaults.get("enable_commits", False):
            logger.debug("Commit extraction disabled in configuration")
            return ""
            
        if not workdir:
            logger.warning("No workdir provided, skipping commit extraction")
            return ""
            
        try:
            # Get commit hashes from container manifests
            start = self._get_commit_hash(prev_manifests)
            finish = self._get_commit_hash(manifests)
            
            if not start or not finish:
                logger.warning("Missing commit hashes, skipping commit extraction")
                return ""
            
            if start == finish:
                logger.info("Same commit hash for both versions, no commits to show")
                return ""
            
            logger.info(f"Extracting commits from {start[:7]} to {finish[:7]}")
            
            # Use git log with commit hashes from container manifests
            commits = subprocess.run(
                ["git", "-C", workdir, "log", "--pretty=format:%H %h %s", 
                 f"{start}..{finish}"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30
            ).stdout.decode("utf-8")
            
            output = ""
            commit_count = 0
            for commit in commits.split("\n"):
                if not commit.strip():
                    continue
                    
                parts = commit.split(" ", 2)
                if len(parts) < 3:
                    logger.debug(f"Skipping malformed commit line: {commit}")
                    continue
                    
                githash, short, subject = parts
                
                # Skip merge commits and chore commits
                if subject.lower().startswith(("merge", "chore")):
                    continue
                    
                output += self.config.templates["commit_format"].format(
                    short=short, subject=subject, githash=githash
                )
                commit_count += 1
            
            logger.info(f"Found {commit_count} relevant commits")
            return self.config.templates["commits_format"].format(commits=output) if output else ""
            
        except subprocess.CalledProcessError as e:
            # Check if the error is due to unknown revision (commit not in repo)
            stderr_output = e.stderr.decode() if e.stderr else ""
            if "unknown revision" in stderr_output.lower() or "bad revision" in stderr_output.lower():
                logger.warning(f"Container commit hashes not found in git repository - trying timestamp-based approach")
                logger.debug(f"Git error: {stderr_output}")
                return self._get_commits_by_timestamp(prev_manifests, manifests, workdir)
            else:
                logger.warning(f"Git command failed: {stderr_output}")
            return ""
        except subprocess.TimeoutExpired:
            logger.error("Git command timed out")
            return ""
        except Exception as e:
            logger.warning(f"Failed to get commits: {e}")
            return ""
    
    def _get_commits_by_timestamp(self, prev_manifests: Dict[str, Any], 
                                 manifests: Dict[str, Any], workdir: str) -> str:
        """Get commits using container timestamps as fallback."""
        try:
            from datetime import datetime, timedelta
            import re
            
            # Get container creation timestamps
            prev_timestamp = self._get_container_timestamp(prev_manifests)
            curr_timestamp = self._get_container_timestamp(manifests)
            
            logger.debug(f"Container timestamps: prev={prev_timestamp}, curr={curr_timestamp}")
            
            if not prev_timestamp or not curr_timestamp:
                logger.warning("Missing container timestamps for commit correlation")
                return ""
            
            # Parse ISO 8601 timestamps
            def parse_timestamp(ts):
                # Remove microseconds and timezone info for simpler parsing
                ts = re.sub(r'\.\d+', '', ts)  # Remove microseconds
                ts = ts.replace('Z', '+00:00')  # Handle Z timezone
                return datetime.fromisoformat(ts.replace('Z', '+00:00'))
            
            prev_dt = parse_timestamp(prev_timestamp)
            curr_dt = parse_timestamp(curr_timestamp)
            
            logger.info(f"Searching commits between {prev_dt.strftime('%Y-%m-%d %H:%M')} and {curr_dt.strftime('%Y-%m-%d %H:%M')}")
            
            # Add some buffer time to account for build delays
            start_time = prev_dt - timedelta(hours=2)
            end_time = curr_dt + timedelta(hours=2)
            
            logger.debug(f"Git time range: {start_time.strftime('%Y-%m-%d %H:%M')} to {end_time.strftime('%Y-%m-%d %H:%M')}")
            
            # Use git log with date range
            git_cmd = [
                "git", "-C", workdir, "log", 
                "--pretty=format:%H %h %s %ci",
                f"--since={start_time.strftime('%Y-%m-%d %H:%M')}",
                f"--until={end_time.strftime('%Y-%m-%d %H:%M')}",
                "--no-merges"
            ]
            
            logger.debug(f"Git command: {' '.join(git_cmd)}")
            
            commits = subprocess.run(git_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30).stdout.decode("utf-8")
            
            logger.debug(f"Raw git output: {commits}")
            
            output = ""
            commit_count = 0
            for commit in commits.split("\n"):
                if not commit.strip():
                    continue
                    
                # Parse git output format: "hash short_hash subject date timezone"
                parts = commit.split(" ")
                if len(parts) < 4:
                    logger.debug(f"Skipping malformed commit line: {commit}")
                    continue
                    
                githash = parts[0]
                short = parts[1] 
                # Everything from index 2 up to the date (which has format YYYY-MM-DD)
                subject_parts = []
                for i, part in enumerate(parts[2:], 2):
                    if part.startswith("2025-") or part.startswith("2024-"):  # Date part
                        break
                    subject_parts.append(part)
                
                subject = " ".join(subject_parts)
                
                # Skip some chore commits but include dependency updates
                if (subject.lower().startswith("chore") and 
                    not any(keyword in subject.lower() for keyword in ["deps", "update", "bump"])):
                    continue
                    
                output += self.config.templates["commit_format"].format(
                    short=short, subject=subject, githash=githash
                )
                commit_count += 1
            
            logger.info(f"Found {commit_count} commits in timestamp range")
            result = self.config.templates["commits_format"].format(commits=output) if output else ""
            logger.debug(f"Timestamp commit result: {result}")
            return result
            
        except Exception as e:
            logger.warning(f"Timestamp-based commit search failed: {e}")
            return ""
    
    def _get_commit_hash(self, manifests: Dict[str, Any]) -> str:
        """Extract commit hash from manifest labels."""
        if not manifests:
            return ""
            
        manifest = next(iter(manifests.values()))
        labels = manifest.get("Labels", {})
        
        # Try different label keys for commit hash
        commit_hash = (labels.get("org.opencontainers.image.revision") or 
                      labels.get("ostree.commit") or 
                      labels.get("org.opencontainers.image.source") or "")
        
        logger.debug(f"Available labels: {list(labels.keys())}")
        logger.debug(f"Extracted commit hash: {commit_hash}")
        
        return commit_hash
    
    def _get_container_timestamp(self, manifests: Dict[str, Any]) -> str:
        """Extract creation timestamp from manifest."""
        if not manifests:
            return ""
            
        manifest = next(iter(manifests.values()))
        return manifest.get("Labels", {}).get(
            "org.opencontainers.image.created",
            manifest.get("Created", "")
        )

    def get_hwe_kernel_change(self, prev: str, curr: str, target: str) -> Tuple[Optional[str], Optional[str]]:
        """Get HWE kernel version changes."""
        try:
            logger.info(f"Fetching HWE manifests for {curr}-hwe and {prev}-hwe...")
            hwe_curr_manifest = self.get_manifests(curr + "-hwe")
            hwe_prev_manifest = self.get_manifests(prev + "-hwe")
            
            # If either manifest is empty, return None values
            if not hwe_curr_manifest or not hwe_prev_manifest:
                logger.warning("One or both HWE manifests are empty")
                return (None, None)
                
            hwe_curr_versions = self.get_versions(hwe_curr_manifest)
            hwe_prev_versions = self.get_versions(hwe_prev_manifest)
            
            curr_kernel = hwe_curr_versions.get("kernel")
            prev_kernel = hwe_prev_versions.get("kernel")
            logger.debug(f"HWE kernel versions: {prev_kernel} -> {curr_kernel}")
            
            return (curr_kernel, prev_kernel)
        except Exception as e:
            logger.error(f"Failed to get HWE kernel versions: {e}")
            return (None, None)
    
    def _generate_pretty_version(self, manifests: Dict[str, Any], curr: str) -> str:
        """Generate a pretty version string if not provided."""
        try:
            finish = self._get_commit_hash(manifests)
        except Exception as e:
            logger.error(f"Failed to get finish hash: {e}")
            finish = ""
            
        try:
            linux = next(iter(manifests.values()))["Labels"]["ostree.linux"]
            start = linux.find(".el") + 3
            fedora_version = linux[start:start+2]
        except Exception as e:
            logger.error(f"Failed to get linux version: {e}")
            fedora_version = ""
        
        # Remove .0 from curr and target prefix
        curr_pretty = re.sub(r"\.\d{1,2}$", "", curr)
        curr_pretty = re.sub(r"^[a-z]+.|^[0-9]+\.", "", curr_pretty)
        
        pretty = curr_pretty + " (c" + fedora_version + "s"
        if finish:
            pretty += ", #" + finish[:7]
        pretty += ")"
        
        return pretty

    def _process_template_variables(self, changelog: str, prev: str, curr: str, 
                                   hwe_kernel_version: Optional[str], 
                                   hwe_prev_kernel_version: Optional[str],
                                   versions: Dict[str, str], 
                                   prev_versions: Dict[str, str]) -> str:
        """Process all template variable replacements in the changelog."""
        # Handle HWE kernel version
        if hwe_kernel_version == hwe_prev_kernel_version:
            changelog = changelog.replace(
                "{pkgrel:kernel-hwe}", 
                self.config.templates["pattern_pkgrel"].format(version=hwe_kernel_version or "N/A")
            )
        else:
            changelog = changelog.replace(
                "{pkgrel:kernel-hwe}",
                self.config.templates["pattern_pkgrel_changed"].format(
                    prev=hwe_prev_kernel_version or "N/A", 
                    new=hwe_kernel_version or "N/A"
                ),
            )
        
        # Replace package version templates
        for pkg, version in versions.items():
            template = f"{{pkgrel:{pkg}}}"
            if pkg not in prev_versions or prev_versions[pkg] == version:
                replacement = self.config.templates["pattern_pkgrel"].format(version=version)
            else:
                replacement = self.config.templates["pattern_pkgrel_changed"].format(
                    prev=prev_versions[pkg], new=version
                )
            changelog = changelog.replace(template, replacement)
        
        # Replace any remaining unreplaced template variables with "N/A"
        changelog = re.sub(r'\{pkgrel:[^}]+\}', 'N/A', changelog)
        return changelog

    def _generate_changes_section(self, prev_manifests: Dict[str, Any], 
                                 manifests: Dict[str, Any], target: str, workdir: Optional[str],
                                 common: List[str], others: Dict[str, List[str]],
                                 prev_versions: Dict[str, str], 
                                 versions: Dict[str, str]) -> str:
        """Generate the changes section of the changelog."""
        changes = ""
        
        # Add package changes first
        common_changes = self.calculate_changes(common, prev_versions, versions)
        if common_changes:
            changes += self.config.templates["common_pattern"].format(title=self.config.sections["all"], changes=common_changes)
            
        for k, v in others.items():
            chg = self.calculate_changes(v, prev_versions, versions)
            if chg:
                changes += self.config.templates["common_pattern"].format(title=self.config.sections[k], changes=chg)
        
        # Add commits section after all package changes
        commits_result = self.get_commits(prev_manifests, manifests, target, workdir)
        logger.debug(f"Commits result from get_commits: '{commits_result}'")
        changes += commits_result
        
        return changes

    def generate_changelog(self, handwritten: Optional[str], target: str,
                          pretty: Optional[str], workdir: Optional[str],
                          prev_manifests: Dict[str, Any], 
                          manifests: Dict[str, Any], 
                          previous_tag: Optional[str] = None) -> Tuple[str, str]:
        """Generate the complete changelog."""
        logger.info(f"Generating changelog for target '{target}'")
        
        try:
            # Get package data
            common, others = self.get_package_groups(target, prev_manifests, manifests)
            versions = self.get_versions(manifests)
            prev_versions = self.get_versions(prev_manifests)
            
            # Get tags and versions
            prev, curr = self.get_tags(target, manifests, previous_tag)
            logger.info(f"Tags: {prev} -> {curr}")
            
            hwe_kernel_version, hwe_prev_kernel_version = self.get_hwe_kernel_change(
                prev, curr, target
            )
            
            # Generate title
            version = target.capitalize()
            if target in self.config.targets:
                version = version.upper()
                
            if not pretty:
                pretty = self._generate_pretty_version(manifests, curr)
                
            title = self.config.templates["changelog_title"].format_map(
                defaultdict(str, os=self.config.os_name, tag=version, pretty=pretty)
            )
            
            # Process base template
            changelog = self.config.templates["changelog_format"]
            changelog = (
                changelog.replace("{handwritten}", 
                                handwritten if handwritten else self.config.templates["handwritten_placeholder"].format(curr=curr))
                .replace("{target}", target)
                .replace("{prev}", prev)
                .replace("{curr}", curr)
            )
            
            # Process template variables
            changelog = self._process_template_variables(
                changelog, prev, curr, hwe_kernel_version, hwe_prev_kernel_version,
                versions, prev_versions
            )
            
            # Generate and insert changes section
            changes = self._generate_changes_section(
                prev_manifests, manifests, target, workdir, common, others, 
                prev_versions, versions
            )
            changelog = changelog.replace("{changes}", changes)
            
            logger.info("Changelog generated successfully")
            return title, changelog
            
        except Exception as e:
            logger.error(f"Failed to generate changelog: {e}")
            raise ChangelogError(f"Changelog generation failed: {e}") from e


def setup_argument_parser() -> argparse.ArgumentParser:
    """Set up the command line argument parser."""
    parser = argparse.ArgumentParser(
        description="Generate changelogs for Bluefin LTS container images",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Simple usage
  %(prog)s lts
  
  # CI/CD usage (recommended for GitHub Actions)
  %(prog)s lts --ci
  
  # With custom options
  %(prog)s lts --workdir /path/to/git/repo --verbose
  %(prog)s lts --pretty "Custom Version" --handwritten notes.txt
        """
    )
    
    # Required arguments
    parser.add_argument("target", help="Target tag to generate changelog for")
    
    # Optional arguments
    parser.add_argument("--pretty", help="Custom subject for the changelog")
    parser.add_argument("--workdir", help="Git directory for commit extraction")
    parser.add_argument("--handwritten", help="Path to handwritten changelog content")
    parser.add_argument("--previous-tag", help="Previous tag to compare against (overrides automatic detection)")
    
    # Output control
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Enable verbose logging")
    parser.add_argument("--dry-run", action="store_true",
                       help="Generate changelog but don't write files")
    
    # Release management options
    parser.add_argument("--check-release", action="store_true",
                       help="Check if release already exists before generating changelog")
    parser.add_argument("--force", action="store_true",
                       help="Generate changelog even if release already exists")
    parser.add_argument("--github-output", 
                       help="Path to GitHub Actions output file for setting variables")
    parser.add_argument("--ci", action="store_true",
                       help="Enable CI/CD mode (equivalent to --check-release --workdir . --github-output $GITHUB_OUTPUT)")
    
    return parser


def validate_arguments(args: argparse.Namespace) -> None:
    """Validate command line arguments."""
    # Validate workdir if provided
    if args.workdir and not Path(args.workdir).is_dir():
        raise ValueError(f"Workdir does not exist or is not a directory: {args.workdir}")
    
    # Validate handwritten content if provided
    if args.handwritten:
        handwritten_path = Path(args.handwritten)
        if not handwritten_path.exists():
            raise ValueError(f"Handwritten changelog file not found: {args.handwritten}")


def main():
    """Main entry point for the changelog generator."""
    parser = setup_argument_parser()
    args = parser.parse_args()
    
    try:
        # Validate arguments
        validate_arguments(args)
        
        # Handle CI mode - apply common CI/CD defaults
        if args.ci:
            args.check_release = True
            if not args.workdir:
                args.workdir = "."
            if not args.github_output and os.getenv('GITHUB_OUTPUT'):
                args.github_output = os.getenv('GITHUB_OUTPUT')
        
        # Configure logging based on verbosity
        if args.verbose:
            logging.getLogger().setLevel(logging.DEBUG)
        
        # Remove refs/tags, refs/heads, refs/remotes etc.
        target = args.target.split('/')[-1]
        logger.info(f"Processing target: {target}")
        
        # Create configuration with defaults
        config = load_config()
        
        # Load handwritten content if provided
        handwritten = None
        if args.handwritten:
            handwritten_path = Path(args.handwritten)
            handwritten = handwritten_path.read_text(encoding='utf-8')
            logger.info(f"Loaded handwritten content from {args.handwritten}")
        
        # Create generator and process
        generator = ChangelogGenerator(config)
        
        logger.info("Fetching current manifests...")
        manifests = generator.get_manifests(target)
        
        # Determine previous tag - use provided one or auto-detect
        if args.previous_tag:
            prev = args.previous_tag
            logger.info(f"Using provided previous tag: {prev}")
        else:
            prev, curr = generator.get_tags(target, manifests)
            logger.info(f"Auto-detected previous tag: {prev}")
        
        # Always get current tag from manifests
        _, curr = generator.get_tags(target, manifests, prev)
        logger.info(f"Current tag: {curr}")
        
        # Check if release already exists (if requested)
        if args.check_release and not args.force:
            if check_github_release_exists(curr):
                logger.info(f"Release already exists for tag {curr}. Skipping changelog generation.")
                if args.github_output:
                    write_github_output(args.github_output, {
                        "SKIP_CHANGELOG": "true",
                        "CHANGELOG_TAG": curr,
                        "EXISTING_RELEASE": "true"
                    })
                return
            else:
                logger.info(f"No existing release found for {curr}. Generating changelog.")
        
        # Use last published release as previous tag if not specified and check-release is enabled
        if args.check_release and not args.previous_tag:
            last_published = get_last_published_release_tag()
            if last_published:
                prev = last_published
                logger.info(f"Using last published release as previous tag: {prev}")
        
        logger.info("Fetching previous manifests...")
        prev_manifests = generator.get_manifests(prev)
        
        logger.info("Generating changelog...")
        title, changelog = generator.generate_changelog(
            handwritten, target, args.pretty, args.workdir,
            prev_manifests, manifests, args.previous_tag
        )
        
        if not args.verbose:
            print(f"Changelog Title: {title}")
            print(f"Tag: {curr}")
        
        # Write output files unless dry-run
        if not args.dry_run:
            # Use paths from config
            changelog_path = Path(config.defaults["output_file"])
            changelog_path.write_text(changelog, encoding='utf-8')
            logger.info(f"Changelog written to {changelog_path}")
            
            output_path = Path(config.defaults["env_output_file"])
            output_content = f'TITLE="{title}"\nTAG={curr}\n'
            output_path.write_text(output_content, encoding='utf-8')
            logger.info(f"Environment variables written to {output_path}")
            
            # Write GitHub Actions output if requested
            if args.github_output:
                write_github_output(args.github_output, {
                    "SKIP_CHANGELOG": "false",
                    "CHANGELOG_TAG": curr,
                    "CHANGELOG_TITLE": title,
                    "CHANGELOG_PATH": str(changelog_path.absolute()),
                    "EXISTING_RELEASE": "false"
                })
        else:
            logger.info("Dry run - no files written")
            
    except (ChangelogError, TagDiscoveryError, ManifestFetchError) as e:
        logger.error(f"Changelog generation failed: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
