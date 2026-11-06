# Glossary for the First DevOps Week

Short definitions in the context of this project. If a term is not here, check Microsoft Learn before trusting a blog post.

## Network

| Term | Meaning here |
|---|---|
| **VNet** | An isolated private network in Azure with its own address space. |
| **Subnet** | A range inside a VNet where resources get private IPs. |
| **Peering** | A private connection between two VNets. It is not transitive by default. |
| **Hub-and-spoke** | A central VNet (hub) provides shared security/connectivity; workload VNets (spokes) peer to it. |
| **UDR** | User-defined route. A route table entry that overrides Azure's default routing, often `0.0.0.0/0 -> firewall`. |
| **NSG** | Network security group. Stateful allow/deny rules applied to subnets or NICs. |
| **ASG** | Application security group. A logical grouping of NICs used in NSG rules to avoid IP lists. |
| **Azure Firewall** | Managed network firewall for centralized egress, FQDN rules, threat intelligence, and (Premium) IDPS/TLS inspection. |
| **WAF** | Web application firewall. Inspects HTTP(S) for attacks such as SQL injection and XSS. |
| **DDoS Protection** | Azure protection for public IPs against volumetric attacks. |
| **Private endpoint** | A private IP in your VNet that connects to a PaaS service over Azure Private Link. |
| **Private DNS** | DNS zones such as `privatelink.database.windows.net` that resolve a PaaS FQDN to its private endpoint IP. |
| **Bastion** | Managed jump service that provides RDP/SSH through the Azure portal without public IPs on VMs. |
| **ExpressRoute / VPN** | Private connectivity from on-premises to Azure. |

## Identity and access

| Term | Meaning here |
|---|---|
| **Microsoft Entra ID** | Microsoft's cloud identity provider (formerly Azure AD). |
| **OIDC** | OpenID Connect. An identity layer on OAuth 2.0 used to authenticate users and obtain tokens. |
| **OAuth 2.0** | Authorization framework used for delegated and app-only access tokens. |
| **JWT** | JSON Web Token. The signed token format used by Entra access tokens. |
| **Access token** | Token presented to an API. It has an audience, scopes/roles, and an expiry. |
| **ID token** | Token for the client that describes the authenticated user. Do not send it to the API. |
| **Scope** | Permission requested by a client, such as `Orders.Read`. |
| **App role** | A role defined by an API app registration and assigned to users/groups/apps, such as `Logistics.Manager`. |
| **RBAC** | Role-based access control. Azure RBAC controls cloud resources; app roles control business actions. |
| **PIM** | Privileged Identity Management. Just-in-time, approval-based activation of privileged roles. Requires Entra ID P2; **not available in this Free-tier project**. |
| **Conditional Access** | Entra policy that grants access only if conditions (MFA, device compliance, location) are met. Requires Entra ID P1; **not available here**. |
| **Security defaults** | Free Entra baseline that requires MFA for users and blocks legacy authentication. All-or-nothing; used instead of Conditional Access. |
| **Managed identity** | An Azure-managed identity for a workload, so it can get tokens without a secret. |
| **Workload identity** | AKS feature that federates a Kubernetes service account to an Entra identity. |
| **Service principal** | An identity for an application/service in Entra. |
| **Federated credential** | A trust relationship that lets an external workload (AKS, GitHub, Azure DevOps) get tokens without a secret. |

## Application and data

| Term | Meaning here |
|---|---|
| **AKS** | Azure Kubernetes Service. Managed Kubernetes control plane. |
| **Node pool** | A group of VMs in an AKS cluster with the same size/config. |
| **Pod** | The smallest deployable Kubernetes unit, usually one container. |
| **CNI Overlay** | AKS networking mode where pods get IPs from an overlay CIDR, conserving VNet IPs. |
| **Ingress** | Kubernetes resource/controller that routes HTTP(S) traffic to services. |
| **HPA** | Horizontal Pod Autoscaler. Scales pod replicas based on metrics. |
| **PDB** | Pod Disruption Budget. Limits voluntary disruptions during upgrades. |
| **APIM** | Azure API Management. Gateway for API policies, tokens, quotas, and versioning. |
| **App Service** | Managed PaaS for web apps and APIs. |
| **Azure Functions** | Serverless compute triggered by events, timers, or HTTP. |
| **Service Bus** | Managed messaging with queues/topics, subscriptions, and dead-letter queues. |
| **Topic / subscription** | Publish/subscribe pattern: a topic receives messages, subscriptions filter/receive copies. |
| **DLQ** | Dead-letter queue. Holds messages that could not be processed after retries. |
| **Outbox** | A table written in the same DB transaction as a business change; a relay publishes it later. |
| **Redis** | In-memory cache. Used here for cache-aside and idempotency keys, never as source of truth. |
| **ACR** | Azure Container Registry. Private registry for container images. |
| **SBOM** | Software bill of materials. Inventory of components in an artifact. |

## Delivery and operations

| Term | Meaning here |
|---|---|
| **Terraform state** | Mapping of Terraform resources to real Azure resources. Store remotely with locking. |
| **State lock** | Prevents two Terraform runs from modifying the same state concurrently. |
| **Ansible** | Agentless configuration management over SSH. Used for VM hardening and Kubernetes baseline. |
| **Idempotence** | Running the same automation twice produces the same result; the second run reports no changes. |
| **CI** | Continuous integration. Build, test, scan, and package on every change. |
| **CD** | Continuous delivery/deployment. Promote a tested artifact through environments with gates. |
| **Build pipeline** | Produces the artifact. Should not deploy. |
| **Release pipeline** | Deploys a specific artifact with approvals and verification. |
| **SAST** | Static application security testing. Scans source code. |
| **DAST** | Dynamic application security testing. Tests a running app. |
| **SLO** | Service-level objective, such as 99.9% availability. |
| **RTO** | Recovery time objective. How long recovery may take. |
| **RPO** | Recovery point objective. How much data loss is acceptable, measured in time. |
| **Zero trust** | Security model that verifies every request explicitly and assumes breach; network location is not trust. |
| **Break-glass** | Emergency access path for when normal identity systems fail; heavily monitored and rarely used. |
