# Dataset Schema

`all_flows.csv` contains flow-level records produced by the Zeek/Argus
merge and scenario-window labeling steps.

> This table is the initial minimal schema. The target is the 49-column
> UNSW-NB15 layout; the column-to-source mapping (Argus native, Zeek, and the
> `ct_*` columns deferred to Phase 7/8) is in `docs/phase5-sensor.md` section 7.3.
> Update this file when the merge step is implemented.

| Column | Description | UNSW-NB15 relation |
| --- | --- | --- |
| `timestamp` | Flow start time | `stime` |
| `src_ip` | Source address | `srcip` |
| `dst_ip` | Destination address | `dstip` |
| `src_port` | Source port | `sport` |
| `dst_port` | Destination port | `dsport` |
| `protocol` | Transport protocol | `proto` |
| `duration` | Flow duration | `dur` |
| `bytes` | Total observed bytes | `sbytes`/`dbytes` |
| `attack_cat` | Scenario label | `attack_cat` |
| `label` | Benign or attack indicator | `label` |
