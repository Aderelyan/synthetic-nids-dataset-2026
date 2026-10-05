"""Train baseline RF/XGBoost models on processed flow records."""
from pathlib import Path
import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=Path("dataset/processed/all_flows.csv"))
    parser.add_argument("--output-dir", type=Path, default=Path("ml/results"))
    parser.parse_args()
    raise NotImplementedError("Implement baseline training and evaluation")


if __name__ == "__main__":
    main()
