"""Compare the installed SQL edition with the offline app edition and the sourced catalog."""
import datetime
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2] / "apps/ios/WorldNiche/Resources"
edition = json.loads((root / "daily-quiz.json").read_text())
countries = {row["id"] for row in json.loads((root / "countries.json").read_text())}
facts = json.loads((root / "historical-facts.json").read_text())["countries"]
assert json.load(sys.stdin) == edition
assert len(edition) >= 200
assert len({q["id"] for q in edition}) == len(edition)
assert len({q["prompt"].strip().casefold() for q in edition}) == len(edition)
for offset, q in enumerate(edition):
    expected_day = datetime.date.fromisoformat(edition[0]["day"]) + datetime.timedelta(days=offset)
    assert q["day"] == expected_day.isoformat()
    options = set(q["options"])
    assert len(q["options"]) == len(options) == 4 and options <= countries and q["answer"] in options
    assert q["id"] == "capital-" + q["answer"].lower() or any(f["id"] == q["id"] for f in facts[q["answer"]])
print(f"Validated {len(edition)} unique daily quizzes through {edition[-1]['day']}.")
