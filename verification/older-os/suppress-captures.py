#!/usr/bin/env python3
"""Disposable test instrumentation for the explicit October 8 screenshot stop.
Only attachment-only capture helpers are replaced. Assertions and app source remain unchanged.
Pixel-measuring contrast journeys must not be run under this mode.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

def suppress(root, evidence):
    records = []
    for relative in ["apple/UITests/NativeJourney.swift", "tvos/UITests/TVJourney.swift", "apple/UITests/ReaderJourney.swift"]:
        path = root / relative
        original = path.read_text()
        if relative.endswith("ReaderJourney.swift"):
            pattern = r'        let screenshot = XCTAttachment\(screenshot: app\.screenshot\(\)\)\n        screenshot\.name = "Native PDF remote page"; screenshot\.lifetime = \.keepAlways; add\(screenshot\)'
            replacement = '        print("CAPTURE-SUPPRESSED Native PDF remote page")'
        else:
            pattern = r'    func capture\(_ name: String\) \{\n.*?\n    \}'
            replacement = '    func capture(_ name: String) { print("CAPTURE-SUPPRESSED " + name) }'
        changed, count = re.subn(pattern, replacement, original, flags=re.S)
        if count != 1:
            raise RuntimeError("Capture helper changed; review exact instrumentation: " + relative)
        backup = evidence / (path.name + ".original")
        backup.write_text(original)
        path.write_text(changed)
        records.append({"file": relative, "originalSHA256": hashlib.sha256(original.encode()).hexdigest(), "executedSHA256": hashlib.sha256(changed.encode()).hexdigest(), "delta": "attachment-only helper suppressed; assertions unchanged"})
    (evidence / "capture-suppression.json").write_text(json.dumps(records, indent=2))

if __name__ == "__main__":
    destination = Path(sys.argv[1]); destination.mkdir(parents=True, exist_ok=True)
    suppress(Path.cwd(), destination)
