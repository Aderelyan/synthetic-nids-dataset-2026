#!/usr/bin/env bash
# Compute sha256 of all sensor pcap files and diff against host raw-pcap
export PATH="/c/msys64/usr/bin:$PATH"
OUT=/c/Users/Aderelyan/Documents/Project/synthetic-nids-dataset-2026/sensor_hashes.txt
sshpass -p sensor ssh -o StrictHostKeyChecking=no sensor@192.168.56.20 '
cd /home/sensor/pcap-archive
for TAG in linux-20261015-103811 linux-20261014-092351 windows-20261014-061544; do
  for IF in enp0s8 enp0s9 enp0s10; do
    for f in "$TAG/$IF/"*.pcap; do
      [ -f "$f" ] || continue
      echo "$(sha256sum "$f" | cut -d" " -f1)  $TAG/$IF/$(basename "$f")"
    done
  done
done
' > "$OUT"
cat "$OUT"
