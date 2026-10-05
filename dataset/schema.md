# Dataset Schema

`all_flows.csv` contains flow-level records produced by the Zeek/Tranalyzer
merge and scenario-window labeling steps.

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
