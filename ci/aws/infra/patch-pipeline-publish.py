#!/usr/bin/env python3
"""Add Publish stage after LabSmoke in CodePipeline JSON (stdin → stdout)."""
import json
import os
import sys

data = json.load(sys.stdin)
pipe = data["pipeline"]
publish_project = os.environ["PUBLISH_PROJECT"]

pipe["stages"] = [s for s in pipe["stages"] if s["name"] != "Publish"]

publish_stage = {
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
}

stages = pipe["stages"]
insert_at = next((i + 1 for i, s in enumerate(stages) if s["name"] == "LabSmoke"), len(stages))
stages.insert(insert_at, publish_stage)
pipe["stages"] = stages

print(json.dumps({"pipeline": pipe}))
