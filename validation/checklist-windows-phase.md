# Windows Phase Checklist

- [ ] Lab network is isolated from production networks.
- [ ] OPNsense routes and host overrides are applied.
- [ ] Windows client users and services are configured.
- [ ] Firewall logging is enabled.
- [ ] Clock sync confirmed on every VM against OPNsense (blueprint v3 section 5 point 9).
- [ ] VMs restored to their `golden` snapshot before the run (blueprint v3 section 5 point 3).
- [ ] Sensor capture is running before the scenario starts.
- [ ] Scenario start/end timestamps are recorded.
- [ ] Zeek and Argus outputs are generated (offline, from the saved pcap).
- [ ] Flow merge and labeling complete without missing timestamps.
- [ ] Dataset schema and class counts are reviewed.
- [ ] Raw captures are archived outside Git.
