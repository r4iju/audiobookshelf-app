"""Local baseline/candidate gate. Synthetic contracts are not live-server release certification."""
import argparse
import json
import subprocess
import threading
from pathlib import Path

from verification.fixture import make_server

ROOT = Path(__file__).resolve().parents[1]


def http_journey(auth_mode='modern', scenario='baseline'):
    server, prefix = make_server(0, scenario=scenario, auth_mode=auth_mode)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run(['swift', 'run', '--package-path', str(ROOT / 'verification/ClientJourney'), 'client-journey', f'http://127.0.0.1:{server.server_port}{prefix}'], capture_output=True, text=True, timeout=90)
        stream = result.stdout if result.returncode == 0 else result.stderr
        return json.loads(stream.strip().splitlines()[-1])
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def realtime_journey(scenario='baseline'):
    result = subprocess.run(['node', str(ROOT / 'verification/realtime/journey.mjs'), scenario], capture_output=True, text=True, timeout=20)
    return json.loads(result.stdout.strip().splitlines()[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', choices=['modern-auth', 'library-schema-change', 'progress-event-change'], default='modern-auth')
    args = parser.parse_args()
    try:
        baseline = [http_journey(auth_mode='legacy'), realtime_journey()]
        candidate = [http_journey(scenario='library-schema-change' if args.candidate == 'library-schema-change' else 'baseline'),
                     realtime_journey(scenario='progress-event-change' if args.candidate == 'progress-event-change' else 'baseline')]
        failures = [row for row in candidate if row['result'] != 'passed']
        accepted = not failures and all(row['result'] == 'passed' for row in baseline)
        report = {'evidenceKind': 'synthetic-contract-journeys', 'candidateContract': args.candidate,
                  'baseline': baseline, 'candidate': candidate, 'adoptCandidate': accepted,
                  'affectedWorkflows': sorted({row['workflow'] for row in failures}),
                  'alignmentRequired': sorted({row['client'] for row in failures})}
        print(json.dumps(report, indent=2))
        return 0 if accepted else 1
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError, IndexError):
        print(json.dumps({'adoptCandidate': False, 'error': 'Local verification could not complete. Verify the local toolchain and fixture dependencies.'}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
