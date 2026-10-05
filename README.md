# Synthetic NIDS Dataset 2026

Blueprint and tooling for generating an isolated, synthetic network intrusion
dataset across Linux and Windows client phases.

## Repository map

- `docs/`: topology, blueprint, threat references, and scenario template.
- `infra/`: virtual lab provisioning and Windows configuration.
- `scenarios/`: twelve self-contained traffic-generation scenarios.
- `capture/`: capture filters and local raw PCAP storage.
- `pipeline/`: Zeek/Tranalyzer processing, merging, and labeling.
- `dataset/`: processed data and schema documentation.
- `ml/`: baseline training script, notebook, and result outputs.
- `validation/`: Windows-phase execution checklist.

## Safety

Run all scenarios only in an isolated lab with synthetic credentials and data.
Raw PCAP files and generated datasets are ignored by Git; publish them through
an appropriate release asset or Git LFS.