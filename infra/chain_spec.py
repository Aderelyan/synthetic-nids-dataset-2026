"""Attack chain specifications for multi-hop scenarios (S08, S12)."""

ATTACKER_IP = "10.10.30.10"

CHAIN_SPEC = {
    "S08": {
        "ips": {
            "10.10.30.10",   # attacker (hop 1 originator)
            "10.10.20.20",   # client-1 (hop 1 endpoint, hop 2 originator)
            "10.10.20.21",   # client-2 (hop 2 endpoint, hop 3 originator)
            "10.10.10.11",   # srv-file (hop 3 endpoint)
        },
        "ports": {22, 53},
        "description": "3-hop SSH via ProxyJump",
    },
    "S12": {
        "ips": {
            "10.10.20.20",   # client-1 (exfil source)
            "10.10.30.10",   # attacker (exfil destination)
        },
        "ports": {22, 53, 80, 443, 4444, 8080},
        "description": "Direct exfil from client-1 to attacker",
    },
}

DEFAULT_PORTS = None  # None = any port (used for single-hop scenarios)


def get_chain(scenario_id):
    spec = CHAIN_SPEC.get(scenario_id)
    if spec:
        return spec["ips"], spec["ports"]
    return {ATTACKER_IP}, DEFAULT_PORTS