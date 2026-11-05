# ADR-0001: Hub-and-spoke network with centralized egress

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Platform engineering, network engineering, security
- **Related:** [Network design](../day-01/network-design.md), [Network diagram](../../diagrams/network-topology.png)

## Context

The platform needs public API ingress, private PaaS access, management access without public SSH, hybrid connectivity to an ERP/WMS, and controlled internet egress for AKS, App Service, Functions, and build agents. A flat VNet would be simple but would provide weak blast-radius containment and no central inspection point. A full mesh would create many peering rules and inconsistent policy.

## Decision

Use a hub-and-spoke topology:

- **Hub `10.0.0.0/16`:** Azure Firewall, Azure Bastion, VPN/ExpressRoute gateway, Private DNS Resolver, shared NSGs and route tables.
- **Ingress spoke `10.1.0.0/16`:** Application Gateway WAF_v2.
- **Workload spoke `10.2.0.0/16`:** AKS, APIM, App Service, Functions, private endpoints.
- **Data spoke `10.3.0.0/16`:** SQL, Redis, Blob, Key Vault, Service Bus private endpoints.
- **Management spoke `10.4.0.0/16`:** self-hosted agents, Ansible control node, Terraform state, ACR.

Spokes peer only with the hub. Private application traffic uses explicit peering paths; internet-bound traffic uses a `0.0.0.0/0` UDR to Azure Firewall. East-west traffic is controlled by NSGs, private endpoints, mTLS, and network policy. If policy requires east-west inspection, add a destination-specific route through the firewall and record the change here.

## Consequences

### Positive

- Central egress logging, FQDN allow-listing, and IDPS.
- Clear ownership boundaries between network, application, data, and DevOps.
- New spokes can be added without re-architecting the hub.
- Private DNS and hybrid connectivity are centralized.
- Easier to apply Azure Policy at the network boundary.

### Negative / trade-offs

- More VNets, peerings, route tables, and NSGs to operate.
- Firewall cost and throughput become a shared dependency.
- Misconfigured UDRs or DNS links can break many workloads at once.
- Cross-spoke traffic adds a small latency and troubleshooting hop.
- The hub becomes a high-value target; it needs its own monitoring and change control.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Single flat VNet | No central egress, weak segmentation, difficult to scale teams |
| Full mesh | Many peerings, inconsistent policy, hard to audit |
| Azure Virtual WAN | Strong option at enterprise scale, but overkill and more expensive for a one-week lab |
| No firewall, NAT Gateway only | Cheaper, but no FQDN filtering, IDPS, or central deny logging |

## Review trigger

- More than 10 spokes or multi-region expansion.
- A requirement for east-west inspection or regulated traffic.
- Firewall throughput or cost becomes a bottleneck.
- The organization adopts Azure Virtual WAN.
