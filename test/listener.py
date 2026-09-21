#!/usr/bin/env python3
"""ocs test harness listener.

Accepts TCP connections on one or more ports and immediately closes them.
Used by `ocs test` as the positive target for the egress allow-rules:

  HARNESS_EP_IP:HARNESS_EP_PORT        (intranet-endpoints positive)
  HARNESS_EP_IP:(HARNESS_EP_PORT+1)    (intranet-endpoints contrast — the
                                          firewall has NO rule for this port,
                                          so the connect is dropped)
  docker.host:HARNESS_HOST_PORT        (host-ports positive)
  docker.host:(HARNESS_HOST_PORT+1)    (host-ports contrast)

The runner bakes only the *positive* ports into the test image's allow-lists
(via build args, Dockerfile.test). If a case's "contrast" probe ever succeeds,
that means the firewall rule is too broad (allows more than the listed port)
and the case fails — i.e. the listener being live on the contrast port is
what makes the test a true detector of a too-broad rule.

A connection that connects (then closes) is exactly what the cases'
/dev/tcp probes check.
"""
import select
import socket
import sys


def main() -> int:
    ports = [int(p) for p in sys.argv[1:]] or [8765]
    srvs = []
    for port in ports:
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", port))
        srv.listen(64)
        srvs.append(srv)
    # Accept on whichever port has a pending connection, close it, repeat.
    while True:
        r, _, _ = select.select(srvs, [], [], 3600)
        for srv in r:
            try:
                conn, _ = srv.accept()
                conn.close()
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
