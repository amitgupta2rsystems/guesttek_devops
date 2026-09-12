#!/usr/bin/env python3
"""Normalize pipeline: Source (GitHub) → Build → LabSmoke → Publish."""
import json
import os
import re
import sys

data = json.load(sys.stdin)
pipe = data["pipeline"]
lab_project = os.environ["LAB_SMOKE_PROJECT"]
publish_project = os.environ["PUBLISH_PROJECT"]
build_project = os.environ.get("BUILD_PROJECT", "guesttek-camsuite-edge")
connection_arn = os.environ["CODECONNECTIONS_ARN"]
repo_url = os.environ.get("ORCHESTRATION_REPO", "")
branch = os.environ.get("GITHUB_BRANCH", "main")

repo_match = re.search(r"github\.com[:/]([^/]+/[^/.]+)", repo_url)
repo_id = repo_match.group(1) if repo_match else repo_url

pipe["stages"] = [
    {
        "name": "Source",
        "actions": [{
            "name": "GitHubSource",
            "actionTypeId": {
                "category": "Source",
                "owner": "AWS",
                "provider": "CodeStarSourceConnection",
                "version": "1",
            },
            "runOrder": 1,
            "configuration": {
                "ConnectionArn": connection_arn,
                "FullRepositoryId": repo_id,
                "BranchName": branch,
                "OutputArtifactFormat": "CODE_ZIP",
            },
            "outputArtifacts": [{"name": "SourceOutput"}],
        }],
    },
    {
        "name": "Build",
        "actions": [{
            "name": "BuildAction",
            "actionTypeId": {
                "category": "Build",
                "owner": "AWS",
                "provider": "CodeBuild",
                "version": "1",
            },
            "runOrder": 1,
            "configuration": {"ProjectName": build_project},
            "inputArtifacts": [{"name": "SourceOutput"}],
            "outputArtifacts": [{"name": "BuildOutput"}],
        }],
    },
    {
        "name": "LabSmoke",
        "actions": [{
            "name": "LabSmokeAction",
            "actionTypeId": {
                "category": "Build",
                "owner": "AWS",
                "provider": "CodeBuild",
                "version": "1",
            },
            "runOrder": 1,
            "configuration": {"ProjectName": lab_project},
            "inputArtifacts": [{"name": "BuildOutput"}],
            "outputArtifacts": [],
        }],
    },
    {
        "name": "Publish",
        "actions": [{
            "name": "PublishAction",
            "actionTypeId": {
                "category": "Build",
                "owner": "AWS",
                "provider": "CodeBuild",
                "version": "1",
            },
            "runOrder": 1,
            "configuration": {"ProjectName": publish_project},
            "inputArtifacts": [{"name": "BuildOutput"}],
            "outputArtifacts": [],
        }],
    },
]

print(json.dumps({"pipeline": pipe}))
