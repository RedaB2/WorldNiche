"""Compare the installed SQL edition with the offline app edition and the sourced catalog."""
import datetime
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2] / "apps/ios/WorldNiche/Resources"
edition = json.loads((root / "daily-quiz.json").read_text())
countries = {row["id"]: row["capital"] for row in json.loads((root / "countries.json").read_text())}
assert json.load(sys.stdin) == edition
# The launch edition covers each catalog country once.
launch = edition[:len(countries)]
assert {q["answer"] for q in launch} == countries.keys()
assert all(q["id"] == "capital-" + q["answer"].lower() for q in launch)
assert len({q["id"] for q in edition}) == len(edition)
assert len({q["prompt"].strip().casefold() for q in edition}) == len(edition)
for offset, q in enumerate(edition):
    expected_day = datetime.date.fromisoformat(edition[0]["day"]) + datetime.timedelta(days=offset)
    assert q["day"] == expected_day.isoformat()
    options = set(q["options"])
    assert len(q["options"]) == len(options) == 4 and options <= countries.keys() and q["answer"] in options
    assert "capital" in q["prompt"].casefold()
    if q["prompt"].startswith("Which country has ") and q["prompt"].endswith(" as its capital?"):
        assert q["prompt"] == f"Which country has {countries[q['answer']]} as its capital?"
print(f"Validated {len(edition)} unique daily quizzes through {edition[-1]['day']}.")
