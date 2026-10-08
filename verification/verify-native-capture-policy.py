#!/usr/bin/env python3
"""Fail before UI execution if the selected scheme enables automatic screen capture."""
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET

project, scheme = Path(sys.argv[1]), sys.argv[2]
action = ET.parse(project / 'xcshareddata' / 'xcschemes' / (scheme + '.xcscheme')).getroot().find('TestAction')
if action is None or action.get('systemAttachmentLifetime') != 'keepNever' or action.find('TestPlans') is not None:
    raise SystemExit('Native UI execution requires the documented automatic-capture-off scheme without a test-plan override')
print(scheme + ': automatic screen capture disabled')
if len(sys.argv) > 3:
    configurations = list((Path(sys.argv[3]) / 'Build' / 'Products').glob(scheme + '_*.xctestrun'))
    if not configurations:
        raise SystemExit('Build-for-testing did not produce the selected scheme configuration')

    def targets(value):
        if isinstance(value, dict):
            if 'TestBundlePath' in value:
                yield value
            else:
                for child in value.values():
                    yield from targets(child)
        elif isinstance(value, list):
            for child in value:
                yield from targets(child)

    for configuration in configurations:
        built_targets = list(targets(plistlib.loads(configuration.read_bytes())))
        if not built_targets or any(target.get('SystemAttachmentLifetime') != 'keepNever' for target in built_targets):
            raise SystemExit('Effective XCTest configuration enables automatic capture: ' + str(configuration))
        print(configuration.name + ': effective automatic capture disabled')
