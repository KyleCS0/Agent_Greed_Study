#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    cwd = Path.cwd()
    response_path = cwd / "response.json"
    validation_path = cwd / "validation.json"
    errors = []

    if not response_path.exists():
        errors.append("missing response.json")
        validation_path.write_text(json.dumps({"valid": False, "errors": errors}, indent=2) + "\n", encoding="utf-8")
        print("invalid: missing response.json", file=sys.stderr)
        return 1

    try:
        data = json.loads(response_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"invalid JSON: {exc}")
        validation_path.write_text(json.dumps({"valid": False, "errors": errors}, indent=2) + "\n", encoding="utf-8")
        print(errors[0], file=sys.stderr)
        return 1

    if not isinstance(data, list):
        errors.append("response.json must be a JSON array")
    elif len(data) != 5:
        errors.append("response.json must contain exactly 5 plans")

    ranks = []
    if isinstance(data, list):
        for i, item in enumerate(data, start=1):
            if not isinstance(item, dict):
                errors.append(f"item {i} must be an object")
                continue
            extra = sorted(set(item) - {"rank", "plan"})
            missing = sorted({"rank", "plan"} - set(item))
            if extra:
                errors.append(f"item {i} has extra fields: {extra}")
            if missing:
                errors.append(f"item {i} missing fields: {missing}")
            rank = item.get("rank")
            plan = item.get("plan")
            if not isinstance(rank, int):
                errors.append(f"item {i} rank must be an integer")
            else:
                ranks.append(rank)
            if not isinstance(plan, str) or len(plan.strip()) < 80:
                errors.append(f"item {i} plan must be a specific non-empty string, at least 80 chars")

    if sorted(ranks) != [1, 2, 3, 4, 5]:
        errors.append("ranks must be exactly 1 through 5")

    result = {"valid": not errors, "errors": errors}
    validation_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("valid response.json")
    print()
    print("Next command:")
    print("./create_workers.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
