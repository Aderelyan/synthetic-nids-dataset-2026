"""Apply attack categories from recorded scenario time windows."""
from pathlib import Path
import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flows", type=Path, required=True)
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raise NotImplementedError("Implement timestamp-window labeling")


if __name__ == "__main__":
    main()
