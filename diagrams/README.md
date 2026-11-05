# Diagrams

| File | Purpose |
|---|---|
| `logical-architecture.png` | Components, trust boundaries, request/event flow, delivery path |
| `network-topology.png` | Hub-and-spoke VNets, subnets, private endpoints, peering, egress |
| `render_diagrams.py` | Editable source for both diagrams |

## Re-render

Requires Python 3.10+ and Pillow.

```powershell
python -m pip install pillow
python diagrams/render_diagrams.py
```

The script writes both PNGs into this directory. Edit labels, CIDRs, or colors in `render_diagrams.py`; do not edit the PNGs by hand.

## Diagram conventions

- Solid line: request or data flow.
- Dashed line: identity, telemetry, peering, or automation.
- `PE`: private endpoint.
- `MI`: managed identity.
- Public entry points are explicitly labeled; everything else should be private.
- CIDRs in the network diagram match `docs/day-01/network-design.md`.

If you change the architecture, update the diagram and the network design in the same pull request.
