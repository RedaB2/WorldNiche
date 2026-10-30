#!/usr/bin/env python3
"""Build a credential-free Sites source snapshot from an exact Git commit."""
import argparse
import io
import json
from pathlib import Path
import subprocess
import tarfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ref', default='HEAD', help='Committed source to package')
parser.add_argument('--output', required=True, type=Path, help='New, empty destination')
args = parser.parse_args()
commit = subprocess.check_output(['git', 'rev-parse', '--verify', args.ref + '^{commit}'], cwd=root, text=True).strip()
output = args.output.resolve()
if output.exists():
    raise SystemExit('Choose a new output directory; existing files are never overwritten.')
archive = subprocess.check_output(['git', 'archive', commit, 'apps/web', 'ops/production.json'], cwd=root)
output.mkdir(parents=True)
with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
    bundle.extractall(output, filter='data')
production = json.loads((output / 'ops/production.json').read_text())
hosting = output / 'apps/web/invite-hosting'
manifest = {'project_id': production['website']['sitesProjectID']}
association = {'applinks': {'details': [{
    'appIDs': [production['apple']['teamID'] + '.' + production['apple']['bundleID']],
    'components': [{'/': '/invite/*', 'comment': 'WorldNiche friend invitations only'}]
}]}}
# These IDs are public routing configuration. No local overrides enter this snapshot.
(hosting / 'hosting.example.json').write_text(json.dumps(manifest, indent=2) + '\n')
(hosting / 'association.example.json').write_text(json.dumps(association, indent=2) + '\n')
(output / '.openai').mkdir()
(output / '.openai/hosting.json').write_text(json.dumps(manifest, indent=2) + '\n')
(output / '.gitignore').write_text('dist/\nnode_modules/\napps/web/invite-hosting/dist/\napps/web/invite-hosting/content/\n')
(output / 'provenance.json').write_text(json.dumps({
    'repository': 'https://github.com/RedaB2/WorldNiche', 'commit': commit,
    'projectID': manifest['project_id'], 'configuration': 'ops/production.json'
}, indent=2) + '\n')
# The root command also works after cloning the Sites source repository.
(output / 'package.json').write_text(json.dumps({
    'name': 'worldniche-site-delivery', 'private': True,
    'scripts': {
        'test': 'npm --prefix apps/web test',
        'build': 'npm --prefix apps/web run build && node build-output.mjs',
        'validate': 'npm --prefix apps/web run validate'
    }
}, indent=2) + '\n')
(output / 'build-output.mjs').write_text(
    "import {cp, rm} from 'node:fs/promises';\n"
    "await rm(new URL('./dist/', import.meta.url), {recursive:true, force:true});\n"
    "await cp(new URL('./apps/web/invite-hosting/dist/', import.meta.url), new URL('./dist/', import.meta.url), {recursive:true});\n"
)
for command in [['npm', 'test'], ['npm', 'run', 'build'], ['npm', 'run', 'validate']]:
    subprocess.run(command, cwd=output, check=True)
print(f'Prepared {commit} at {output}. No deployment was performed.')
