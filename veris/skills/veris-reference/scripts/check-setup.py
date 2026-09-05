#!/usr/bin/env python3
"""Check the local handoff consumed by build/fix; never run builds or vendor calls."""
import argparse
import glob
import json
from pathlib import Path


def check(project: Path, scripts: Path):
    errors = []
    for name in ('.veris/twin.yaml', '.veris/NOTES.md', '.gitignore'):
        path = project / name
        try:
            present = bool(path.read_text().strip())
        except (OSError, UnicodeError):
            present = False
        if not present:
            errors.append(f'{name}: missing or empty; finish the setup handoff even without Git')
    path = project / '.veris/setup.json'
    unavailable = object()
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError, UnicodeError):
        errors.append('.veris/setup.json: missing or invalid JSON; record the build facts and artifact policy')
        data = unavailable
    if data is not unavailable:
        if not isinstance(data, dict):
            errors.append('.veris/setup.json: expected an object')
        else:
            roots = data.get('source_roots')
            if not isinstance(roots, list) or not roots or not all(isinstance(x, str) and x.strip() for x in roots):
                errors.append('source_roots: expected a nonempty list of source paths')
            else:
                for root in roots:
                    try:
                        pattern = str(project / root)
                        exists = (project / root).exists() or any(glob.iglob(pattern))
                    except (OSError, ValueError):
                        exists = False
                    if not exists:
                        errors.append('source_roots: a declared source path does not exist')
            command = data.get('build_command')
            if not isinstance(command, str) or not command.strip():
                errors.append('build_command: record the actual build command')
            outputs = data.get('build_outputs')
            if not isinstance(outputs, list) or not all(isinstance(x, str) and x.strip() for x in outputs):
                errors.append('build_outputs: expected a list of paths; [] is valid when no directory is produced')
            if data.get('artifact_policy') not in ('local', 'pr-body', 'commit'):
                errors.append('artifact_policy: choose local, pr-body, or commit from the engineer\'s preference')
    for name in ('record.sh', 'ledger.sh'):
        target = project / '.veris/bin' / name
        source = scripts / name
        try:
            if target.read_bytes() != source.read_bytes():
                errors.append(f'.veris/bin/{name}: differs from this plugin; refresh the staged helper')
        except OSError:
            errors.append(f'.veris/bin/{name}: unavailable; copy the plugin helper from this installation')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path.cwd())
    args = parser.parse_args()
    errors = check(args.project, Path(__file__).resolve().parent)
    if errors:
        for error in errors:
            print(f'Incomplete setup: {error}')
        return 1
    print('Setup handoff files and metadata are present. Review the recorded commands and runtime evidence before declaring setup complete.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
