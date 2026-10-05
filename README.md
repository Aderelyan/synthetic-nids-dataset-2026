# Synthetic NIDS Dataset 2026

Blueprint and tooling for generating an isolated, synthetic network intrusion
dataset across Linux and Windows client phases.

## Repository map

- `docs/`: topology, blueprint, threat references, and scenario template.
- `infra/`: virtual lab provisioning and Windows configuration.
- `scenarios/`: twelve self-contained traffic-generation scenarios.
- `capture/`: local raw PCAP storage (the old per-phase filter note is superseded; the sensor does full capture, see `docs/phase5-sensor.md` section 7).
- `pipeline/`: Zeek/Argus offline extraction from saved PCAPs, merging, and labeling.
- `dataset/`: processed data and schema documentation.
- `ml/`: baseline training script, notebook, and result outputs.
- `validation/`: execution checklist (written for the Windows phase; a Linux-phase equivalent is still to be added before Phase 6).

## Safety

Run all scenarios only in an isolated lab with synthetic credentials and data.
Raw PCAP files and generated datasets are ignored by Git; publish them through
an appropriate release asset or Git LFS.