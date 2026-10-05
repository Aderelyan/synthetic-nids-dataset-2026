# Capture Filters (SUPERSEDED)

> **Superseded 2026-10-02.** The sensor now does full capture with no host or
> port filter, one tcpdump instance per interface (pcap-first architecture).
> See `docs/phase5-sensor.md` section 7.1. The filters below are kept only as a
> record of the original plan; do not use them for dataset capture.

Capture only on the isolated lab interface and save output under `capture/raw/`.

## Linux phase

```text
host <linux-client-ip> or host <server-ip>
```

## Windows phase

```text
host <windows-client-ip> or tcp port 3389 or tcp port 5985 or tcp port 445
```

Replace placeholders with the run-specific topology values before capture.
