#!/usr/bin/env python3
"""Fetch and validate free Wikimedia topic summaries for editorial review.

Uses the same named-topic seeds as the native app. No keys or third-party Python
packages are required. This script saves evidence; it never invents or publishes
culture cards. Wikipedia extracts are CC BY-SA: retain links and attribution.

  python3 Scripts/refresh_culture_sources.py --output work/culture-evidence.json
  python3 Scripts/refresh_culture_sources.py --country FR --refresh --output work/fr.json

Successful entries resume from --output by default. Use --refresh to re-fetch.
HTTP429 responses honor Retry-After (bounded to60 seconds), then back off. Requests
are paced at least1 second apart. Disambiguation pages and empty summaries fail
validation instead of silently becoming country facts.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TOPICS = ROOT / 'WorldNiche/Resources/culture-topics.json'
COUNTRIES = ROOT / 'WorldNiche/Resources/countries.json'
USER_AGENT = 'WorldNiche/1.0 (portfolio cultural-discovery app; editorial source refresh)'
BASE = 'https://en.wikipedia.org/api/rest_v1/page/summary/'


def fetch_summary(topic: str) -> dict:
    url = BASE + urllib.parse.quote(topic.replace(' ', '_'), safe='')
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={
                'User-Agent': USER_AGENT, 'Accept': 'application/json'})
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.load(response)
            if payload.get('type') != 'standard':
                raise ValueError(f"Rejected summary type: {payload.get('type', 'missing')}")
            extract = payload.get('extract', '').strip()
            if len(extract) < 50:
                raise ValueError('Summary is missing or too short for editorial review')
            source = payload.get('content_urls', {}).get('desktop', {}).get('page')
            if not source or urllib.parse.urlparse(source).scheme != 'https':
                raise ValueError('Summary has no HTTPS source URL')
            return {'requestedTopic': topic, 'topic': payload.get('title', topic),
                    'type': 'standard', 'description': payload.get('description', ''),
                    'sourceURL': source, 'extract': extract,
                    'fetchedAt': datetime.now(timezone.utc).isoformat()}
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 3:
                raise
            retry = error.headers.get('Retry-After', '')
            delay = float(retry) if retry.isdigit() else 5 * (2 ** attempt)
            time.sleep(max(1, min(delay, 60)))
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError('No summary returned')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--country', help='Optional ISO alpha-2 country ID')
    parser.add_argument('--refresh', action='store_true', help='Replace cached successful evidence')
    parser.add_argument('--delay', type=float, default=1, help='Seconds between requests, minimum1')
    args = parser.parse_args()
    topics = json.loads(TOPICS.read_text())
    countries = json.loads(COUNTRIES.read_text())
    expected = {country['id'] for country in countries}
    if set(topics) != expected or len(expected) != 195:
        raise SystemExit('Topic manifest must exactly cover the195-country catalog')
    if any(not isinstance(value, list) or not value or not all(isinstance(t, str) and t.strip() for t in value)
           for value in topics.values()):
        raise SystemExit('Every country needs at least one nonempty topic title')
    if args.country:
        country_id = args.country.upper()
        if country_id not in topics:
            raise SystemExit(f'Unknown country ID: {country_id}')
        topics = {country_id: topics[country_id]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    cache = json.loads(args.output.read_text()) if args.output.exists() else {}
    unique_topics = list(dict.fromkeys(topic for values in topics.values() for topic in values))
    for index, topic in enumerate(unique_topics, start=1):
        previous = cache.get(topic, {})
        if previous.get('type') == 'standard' and not args.refresh:
            print(f'{index}/{len(unique_topics)} cached: {topic}', flush=True)
            continue
        try:
            cache[topic] = fetch_summary(topic)
            print(f'{index}/{len(unique_topics)} verified: {topic}', flush=True)
        except Exception as error:
            cache[topic] = {'requestedTopic': topic, 'error': str(error),
                            'checkedAt': datetime.now(timezone.utc).isoformat()}
            print(f'{index}/{len(unique_topics)} needs review: {topic}: {error}', flush=True)
        args.output.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + '\n')
        time.sleep(max(1, args.delay))
    failures = [topic for topic in unique_topics if cache.get(topic, {}).get('type') != 'standard']
    print(f'Validated {len(unique_topics) - len(failures)}/{len(unique_topics)} unique topic summaries.')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
