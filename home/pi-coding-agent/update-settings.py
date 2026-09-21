#!/usr/bin/env python3

import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
packages = sys.argv[2:]

if settings_path.exists():
    settings = json.loads(settings_path.read_text())
else:
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    settings = {}

settings["packages"] = packages
settings_path.write_text(json.dumps(settings, indent=2) + "\n")
