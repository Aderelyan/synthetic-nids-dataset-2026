"""Merge normalized Zeek and Argus flow records."""
from pathlib import Path
import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zeek", type=Path, required=True)
    parser.add_argument("--argus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raise NotImplementedError("Implement schema-aware merge for the selected run")


if __name__ == "__main__":
    main()
