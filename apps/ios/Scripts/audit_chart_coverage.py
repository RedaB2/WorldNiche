#!/usr/bin/env python3
"""Audit Apple's key-free chart coverage. Read-only; at most two requests at once."""
import argparse, concurrent.futures, datetime, json, pathlib, time, urllib.error, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]

def check(country):
    url = f"https://rss.marketingtools.apple.com/api/v2/{country['id'].lower()}/music/most-played/10/songs.json?format=json"
    result = {'id': country['id'], 'country': country['name']}
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'WorldNiche/1.0 chart-coverage-audit'})
        with urllib.request.urlopen(request, timeout=18) as response:
            payload = json.load(response)
            tracks = payload.get('feed', {}).get('results', [])
            result.update(status='available' if tracks else 'empty', count=len(tracks))
    except urllib.error.HTTPError as error:
        result.update(status='unavailable' if error.code in [400, 404] else 'error', http=error.code)
    except Exception as error:
        result.update(status='error', error=type(error).__name__)
    time.sleep(0.5)
    return result

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--output', default=str(ROOT.parents[1]/'docs/chart-coverage.json')); args = parser.parse_args()
    countries = json.loads((ROOT/'WorldNiche/Resources/countries.json').read_text())
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for row in pool.map(check, countries):
            rows.append(row)
            if row.get('http') == 429:
                pool.shutdown(wait=False, cancel_futures=True)
                raise SystemExit('Rate limited; stop the audit and retry later.')
            if len(rows) % 25 == 0: print(f'Checked {len(rows)}/{len(countries)}', flush=True)
    report = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'provider':'Apple Music RSS', 'scope':'A successful chart is a storefront ranking, not a national listening census.', 'counts': {state: sum(x['status']==state for x in rows) for state in ['available','empty','unavailable','error']}, 'countries': rows}
    pathlib.Path(args.output).write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report['counts']))
if __name__ == '__main__': main()
