#!/usr/bin/env python3
"""Add LabSmoke stage after Build in CodePipeline JSON (stdin → stdout)."""
import json
import os
import sys

data = json.load(sys.stdin)
pipe = data["pipeline"]
lab_project = os.environ["LAB_SMOKE_PROJECT"]

pipe["stages"] = [s for s in pipe["stages"] if s["name"] != "LabSmoke"]

lab_stage = {
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
}

stages = pipe["stages"]
insert_at = next((i + 1 for i, s in enumerate(stages) if s["name"] == "Build"), len(stages))
stages.insert(insert_at, lab_stage)
pipe["stages"] = stages

print(json.dumps({"pipeline": pipe}))
