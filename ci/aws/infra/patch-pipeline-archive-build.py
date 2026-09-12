#!/usr/bin/env python3
"""Insert ArchiveBuild stage after Build (before LabSmoke). Passes BuildOutput through."""
import json
import os
import sys

data = json.load(sys.stdin)
pipe = data["pipeline"]
archive_project = os.environ["ARCHIVE_PROJECT"]

pipe["stages"] = [s for s in pipe["stages"] if s["name"] != "ArchiveBuild"]

archive_stage = {
    "name": "ArchiveBuild",
    "actions": [{
        "name": "ArchiveBuildAction",
        "actionTypeId": {
            "category": "Build",
            "owner": "AWS",
            "provider": "CodeBuild",
            "version": "1",
        },
        "runOrder": 1,
        "configuration": {"ProjectName": archive_project},
        "inputArtifacts": [{"name": "BuildOutput"}],
        "outputArtifacts": [],
    }],
}

stages = pipe["stages"]
insert_at = next((i + 1 for i, s in enumerate(stages) if s["name"] == "Build"), len(stages))
stages.insert(insert_at, archive_stage)
pipe["stages"] = stages

print(json.dumps({"pipeline": pipe}))
