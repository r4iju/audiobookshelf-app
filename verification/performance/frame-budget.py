#!/usr/bin/env python3
"""Check main-thread frame callback gaps from the temporary UI profiling probe."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('report', type=Path)
parser.add_argument('--p95', type=float, default=25)
parser.add_argument('--p99', type=float, default=50)
args = parser.parse_args()
data = json.loads(args.report.read_text())
assert data['samples'] >= 100, 'Insufficient frame samples'
print(json.dumps(data, sort_keys=True))
if data['p95_ms'] > args.p95 or data['p99_ms'] > args.p99:
    raise SystemExit(f"FAIL: frame callback budget p95 <= {args.p95}ms, p99 <= {args.p99}ms")
print('PASS: frame callback budget')
