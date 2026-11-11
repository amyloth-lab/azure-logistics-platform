# Day 1 Architecture Review Notes

> **This file is the committed template. Do not put real subscription IDs, tenant IDs, or other account identifiers in it.**
>
> Copy it to `review-notes.local.md` and fill that file in. The local file is gitignored. If you already filled this tracked file, copy your answers to the local file and restore this file to the blank template before committing.

Fill this in before End Of Day 1. Keep it short. The goal is to prove you can explain the design, not to write an essay.

## 1. Scope and assumptions

- Azure subscription:
- Entra tenant / license tier (this project: Free):
- Region:
- Domain (public API hostname, not the Entra tenant domain):
- Lab or production-shaped budget:
- On-prem CIDR confirmed by (person/team + date, or `N/A - no hybrid connection`):
- Open questions:

> `Domain` is the hostname clients call, for example `api.logistics.example.com`. `example.com` is only a design placeholder; use a domain you control before configuring a real TLS certificate. If you have no on-premises connection in this lab, write `N/A - no hybrid connection; 192.168.0.0/16 is a placeholder assumption`.

## 2. Architecture review answers

1. What is the only public application entry point?
2. Which subnet does APIM use for inbound, and which for outbound?
3. Where does AKS get its egress, and what happens if the firewall is down?
4. Which identity reads the TLS certificate for App Gateway?
5. Which identity writes the order event to Service Bus?
6. Which role can delete an order, and where is that enforced?
7. What stops a reader from reading another user's order?
8. Where is the Terraform state stored, and who can read it?
9. What is the rollback plan for a bad API deployment?
10. What would you monitor to know the API is unhealthy before users call the help desk?

## 3. Decisions I changed or want to challenge

| ADR | Change | Why |
|---|---|---|
| | | |

## 4. Risks I am carrying into Day 2

| Risk | Impact | Mitigation | Owner |
|---|---|---|---|
| | | | |

## 5. Cost guardrails

- Monthly budget:
- Alert thresholds:
- Resources to destroy nightly:
- Most expensive component:

## 6. Evidence

- [ ] Logical diagram reviewed
- [ ] Network diagram reviewed
- [ ] CIDR table checked
- [ ] RBAC matrix checked
- [ ] STRIDE table checked
- [ ] ADRs reviewed
- [ ] GitHub repo pushed and protected
- [ ] Gitleaks clean
- [ ] Azure Boards backlog created
- [ ] Prerequisite script run
- [ ] No Azure resources created

## 7. EOD declaration

I have completed the Day 1 checklist and have not run `terraform apply`.

Signature/date:
