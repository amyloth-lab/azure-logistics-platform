# Network Design - Hub-and-Spoke, Private by Default

**Status:** Proposed for Day 1 review
**Region:** Australia East (`australiaeast`)
**Diagrams:** [Logical architecture](../../diagrams/logical-architecture.png) | [Network topology](../../diagrams/network-topology.png)

---

## 1. Design goals

1. One public application entry point: Application Gateway WAF_v2.
2. No public IP addresses on workload or data services.
3. All PaaS data access over private endpoints and private DNS.
4. Controlled, logged internet egress through Azure Firewall.
5. Management access through Azure Bastion, never public SSH.
6. Hub owns shared connectivity; spokes own workloads and data.
7. Address space is large enough for growth and does not overlap on-premises, AKS services/pods, or App Service worker infrastructure.
8. The design can be built with Terraform and tested with Ansible.

## 2. Why hub-and-spoke

| Option | Trade-off |
|---|---|
| Flat VNet | Simple, but no central egress control, weak blast-radius containment, hard to scale teams |
| Full mesh | Low latency, but many peering rules and no central inspection |
| Hub-and-spoke | Central firewall/DNS/Bastion, clear ownership, controlled growth; slightly more latency and peering management |

The hub does **not** host business workloads. It hosts shared network security and connectivity. If the hub becomes a workload VNet, it stops being a control point and becomes another blast radius.

## 3. Address plan

### 3.1 VNets

| VNet | CIDR | Owner | Purpose |
|---|---|---|---|
| `vnet-hub` | `10.0.0.0/16` | Network platform | Firewall, Bastion, VPN/ER, Private DNS Resolver |
| `vnet-ingress` | `10.1.0.0/16` | Network platform | Application Gateway WAF_v2 |
| `vnet-workload` | `10.2.0.0/16` | Application platform | AKS, APIM, App Service, Functions, private endpoints |
| `vnet-data` | `10.3.0.0/16` | Data platform | SQL, Redis, Storage, Key Vault, Service Bus private endpoints |
| `vnet-management` | `10.4.0.0/16` | DevOps platform | Agents, Ansible, Terraform state, ACR |
| `10.5.0.0/16` - `10.15.0.0/16` | Reserved | Future | Future spokes; do not allocate |
| `192.168.0.0/16` | On-premises | Network team | ERP/WMS; confirm with network team |
| `100.64.0.0/16` | AKS pods | Platform | Azure CNI Overlay pod CIDR |
| `10.60.0.0/16` | AKS services | Platform | Kubernetes service CIDR |

### 3.2 Why these choices

- **`/16` per VNet:** room for subnet growth without re-addressing. VNet peering does not charge by address space.
- **`/22` per AKS node subnet:** with Azure CNI Overlay, only node IPs come from the subnet. A `/22` supports roughly 1,000 nodes, which is more than enough; the extra room avoids a rebuild if the cluster grows.
- **`/24` for APIM outbound and App Service/Functions integration:** these services consume IPs during scale operations and platform upgrades. A `/24` is the recommended comfortable size for APIM; App Service can use `/26`, but `/24` avoids surprises.
- **`/26` for Bastion:** required minimum. Do not use `/27`; it is too small for some operations.
- **`/27` for GatewaySubnet:** minimum; acceptable for a lab VPN/ER gateway.
- **`/28` for DNS Resolver endpoints:** each endpoint needs a small number of IPs; separate inbound and outbound.
- **`/27` for internal ingress:** enough for the internal load balancer frontend IP and future ingress replicas.

### 3.3 Reserved addresses

Azure reserves the first four and last IP address of each subnet. Do not assign them. Plan for at least 20% headroom beyond peak scale.

## 4. Subnet details

### 4.1 Hub VNet

| Subnet | CIDR | Delegation | NSG | Route table | Notes |
|---|---|---|---|---|---|
| `AzureFirewallSubnet` | `10.0.0.0/26` | None | Not supported | None | Azure Firewall |
| `AzureFirewallManagementSubnet` | `10.0.0.64/26` | None | Not supported | None | Forced tunneling only |
| `AzureBastionSubnet` | `10.0.1.0/26` | None | Required | None | Azure Bastion |
| `GatewaySubnet` | `10.0.2.0/27` | None | Not supported | None | VPN/ExpressRoute |
| `snet-dns-inbound` | `10.0.3.0/28` | None | Required | None | Private DNS Resolver inbound |
| `snet-dns-outbound` | `10.0.3.16/28` | None | Required | None | Private DNS Resolver outbound |
| `snet-shared` | `10.0.4.0/24` | None | Required | `rt-hub-default` | Future shared services |

### 4.2 Ingress VNet

| Subnet | CIDR | Delegation | NSG | Route table | Notes |
|---|---|---|---|---|---|
| `snet-appgw` | `10.1.0.0/24` | None | `nsg-appgw` | `rt-ingress` | Dedicated; no other resources |

App Gateway v2 requires its own subnet. Do not place a jump box, private endpoint, or firewall in this subnet.

### 4.3 Workload VNet

| Subnet | CIDR | Delegation | NSG | Route table | Notes |
|---|---|---|---|---|---|
| `snet-aks-system` | `10.2.0.0/22` | None | `nsg-aks` | `rt-workload` | AKS system node pool |
| `snet-aks-user` | `10.2.4.0/22` | None | `nsg-aks` | `rt-workload` | AKS user node pool |
| `snet-apim-outbound` | `10.2.8.0/24` | `Microsoft.Web/serverFarms` | `nsg-apim-outbound` | `rt-workload` | APIM outbound integration |
| `snet-appservice-outbound` | `10.2.9.0/24` | `Microsoft.Web/serverFarms` | `nsg-appservice-outbound` | `rt-workload` | App Service VNet integration |
| `snet-functions-outbound` | `10.2.10.0/24` | `Microsoft.Web/serverFarms` | `nsg-functions-outbound` | `rt-workload` | Functions VNet integration |
| `snet-private-endpoints` | `10.2.11.0/24` | None | `nsg-private-endpoints` | None | APIM, App Service, Functions private endpoints |
| `snet-aks-ingress` | `10.2.12.0/27` | None | `nsg-aks` | `rt-workload` | Internal ingress load balancer |

> **Tier-specific delegation — do not apply a classic-injection rule to Standard v2:**
>
> | APIM networking mode | Tiers | Subnet delegation |
> |---|---|---|
> | Classic VNet injection | Developer, Premium | **None** |
> | VNet injection | Premium v2 | `Microsoft.ApiManagement/service` |
> | Outbound VNet integration | Standard v2 | `Microsoft.Web/serverFarms` |
> | Inbound private endpoint | Developer/Basic/Standard/Standard v2/Premium/Premium v2 | Private endpoint subnet, no delegation |
>
> This design uses **Standard v2 outbound VNet integration**, so `snet-apim-outbound` is correctly delegated to `Microsoft.Web/serverFarms`. The subnet is still dedicated to a single APIM instance. The delegation does **not** mean App Service can share the subnet; it is how the Standard v2 outbound integration is implemented. If you switch to classic Developer/Premium injection, remove the delegation and set it to **None**. If you switch to Premium v2 injection, use `Microsoft.ApiManagement/service`. App Service and Functions use separate integration subnets.

### 4.4 Data VNet

| Subnet | CIDR | Delegation | NSG | Route table | Notes |
|---|---|---|---|---|---|
| `snet-private-endpoints` | `10.3.1.0/24` | None | `nsg-private-endpoints` | None | SQL, Redis, Blob, Key Vault, Service Bus private endpoints |

Private endpoints do not need a default route to the firewall. Their traffic stays on the Azure backbone. The NSG should allow 443 only from the workload and management subnets that need the service.

### 4.5 Management VNet

| Subnet | CIDR | Delegation | NSG | Route table | Notes |
|---|---|---|---|---|---|
| `snet-devops-agents` | `10.4.0.0/24` | None | `nsg-agents` | `rt-management` | Self-hosted Azure DevOps agents |
| `snet-ansible` | `10.4.1.0/28` | None | `nsg-ansible` | `rt-management` | Ansible control node |
| `snet-private-endpoints` | `10.4.2.0/24` | None | `nsg-private-endpoints` | None | Terraform state, ACR |
| Reserved | `10.4.3.0/24` - `10.4.15.0/24` | - | - | - | Future |

## 5. Traffic flows

### 5.1 Ingress path

```text
Internet
  -> App Gateway public IP :443
  -> WAF policy (OWASP 3.2, bot, custom rules, rate limit)
  -> APIM private endpoint :443 (TLS re-encryption)
  -> APIM policy (JWT, scopes/roles, quota, correlation ID)
  -> AKS internal ingress :443 (mTLS)
       or
  -> App Service private endpoint :443
```

**Important:** App Gateway and APIM are in different spokes. The path uses VNet peering for private traffic. The UDR default route sends internet-bound traffic to the firewall, but the more-specific `10.2.0.0/16` peering route keeps App Gateway -> APIM traffic on the private path. Verify this with `az network watcher show-next-hop` after deployment.

### 5.2 Egress path

```text
AKS node / App Service / Functions / agent
  -> UDR 0.0.0.0/0
  -> Azure Firewall private IP 10.0.0.4
  -> FQDN / network rules
  -> internet or on-premises
```

- AKS uses `outboundType=userDefinedRouting`. It does **not** get a public outbound load balancer.
- App Service and Functions use route-all VNet integration. Their outbound traffic is subject to the integration subnet NSG and UDR.
- Agents and Ansible use the management route table. They must reach Azure DevOps, GitHub, ACR, Azure Resource Manager, Terraform registry, PyPI, Ubuntu repositories, Key Vault, and Azure Monitor.
- Azure Firewall logs allowed and denied flows to Log Analytics. Review denied flows during Day 3 troubleshooting.

### 5.3 East-west path

- Spokes are peered to the hub, not to each other by default.
- The explicit exceptions are:
  - Ingress -> workload private endpoint (App Gateway -> APIM).
  - Workload -> data private endpoints (AKS/App Service/Functions -> SQL/Redis/Blob/Key Vault/Service Bus).
  - Management -> workload AKS API and ACR.
- NSGs and private endpoint policy enforce these exceptions.
- If your security policy requires inspection of east-west traffic, add a specific UDR for the destination prefix through Azure Firewall. Do not route all RFC1918 traffic through the firewall by default in the lab; it adds cost and latency and can break private endpoint health.

### 5.4 Hybrid path

```text
On-premises 192.168.0.0/16
  -> VPN or ExpressRoute
  -> GatewaySubnet in hub
  -> Azure Firewall policy for on-prem destinations
  -> spoke workload
```

- Advertise only the required on-prem prefixes.
- On-prem DNS forwards `privatelink.*` zones to the Private DNS Resolver inbound IP.
- Do not allow on-prem to bypass the firewall to reach workload subnets.
- This course documents the hybrid path but does not require a live VPN/ExpressRoute.

### 5.5 Management path

```text
Engineer
  -> Microsoft Entra ID + MFA + Conditional Access
  -> Azure Bastion (public IP, managed)
  -> private Linux VM (agents or Ansible)
  -> private endpoints / AKS API
```

- No public IP on the agent or Ansible VM.
- No public SSH.
- Bastion is the only interactive path.
- Azure DevOps agents use a managed identity for Azure deployment and a short-lived registration token from Key Vault for agent registration; rotate the token.

## 6. NSG intent

NSGs are not the primary identity control, but they reduce blast radius and create useful logs. The following is intent, not a complete rule export.

| Source | Destination | Port | Action | Purpose |
|---|---|---|---|---|
| Internet | App Gateway public IP | 443 | Allow | Public API |
| `GatewayManager` | App Gateway subnet | 65200-65535 | Allow | App Gateway v2 infrastructure |
| `AzureLoadBalancer` | App Gateway subnet | 65503-65534 | Allow | Health probes |
| App Gateway subnet | APIM private endpoint | 443 | Allow | API traffic |
| APIM outbound subnet | AKS ingress | 443 | Allow | Backend API |
| APIM outbound subnet | App Service private endpoint | 443 | Allow | Partner webhook |
| APIM outbound subnet | Key Vault private endpoint | 443 | Allow | Certificate read |
| AKS node subnets | Data private endpoints | 443 | Allow | SQL/Redis/Blob/Key Vault/Service Bus |
| App Service outbound | Data private endpoints | 443 | Allow | Service Bus/Key Vault |
| Functions outbound | Data private endpoints | 443 | Allow | SQL/Blob/Service Bus |
| Management subnets | AKS API private endpoint | 443 | Allow | kubectl/Helm |
| Management subnets | ACR private endpoint | 443 | Allow | Image push/pull |
| Management subnets | Terraform state blob | 443 | Allow | State read/write |
| Bastion subnet | Management VMs | 22 | Allow | SSH via Bastion |
| Any | Any | Any | Deny | Default deny, logged |

**Do not** hand-edit AKS-managed NSG rules without understanding the AKS network model. AKS adds required control-plane and node rules. Test with the AKS network checker after changes.

**Do not** attach an NSG to `AzureFirewallSubnet` or `GatewaySubnet`; those subnets do not support it.

## 7. Private DNS

### 7.1 Zone links

Link each zone to:

- Hub VNet (for the resolver and shared services).
- Ingress VNet (App Gateway resolves APIM).
- Workload VNet (APIM, AKS, App Service, Functions).
- Data VNet (private endpoint records).
- Management VNet (agents, Ansible, state, ACR).

Disable auto-registration. Use explicit A records created by private endpoint DNS zone groups.

### 7.2 Zone table

| Service | Zone | Record owner |
|---|---|---|
| APIM | `privatelink.azure-api.net` | APIM private endpoint |
| App Service | `privatelink.azurewebsites.net` | App Service private endpoint |
| Functions | `privatelink.azurewebsites.net` | Functions private endpoint (if used) |
| Azure SQL | `privatelink.database.windows.net` | SQL private endpoint |
| Azure Managed Redis | `privatelink.redis.azure.net` | Redis private endpoint |
| Blob Storage | `privatelink.blob.core.windows.net` | Storage private endpoint |
| Key Vault | `privatelink.vaultcore.azure.net` | Key Vault private endpoint |
| Service Bus | `privatelink.servicebus.windows.net` | Service Bus private endpoint |
| ACR | `privatelink.azurecr.io` | ACR private endpoint |
| AKS API | `privatelink.australiaeast.azmk8s.io` | AKS private cluster |
| Azure Monitor (optional) | `privatelink.monitor.azure.com`, `privatelink.oms.opinsights.azure.com`, `privatelink.ods.opinsights.azure.com`, `privatelink.agentsvc.azure-automation.net` | Azure Monitor private link scope |

### 7.3 On-premises DNS

- Deploy Azure Private DNS Resolver in the hub.
- On-prem DNS conditionally forwards `privatelink.*` zones to the resolver inbound endpoint.
- Do not create public A records for private endpoints.
- Test from on-prem with `nslookup <resource>` and `Test-NetConnection`.

## 8. AKS networking specifics

| Setting | Value | Why |
|---|---|---|
| Cluster mode | Private cluster | No public API server |
| Network plugin | Azure CNI Overlay | Conserves VNet IPs; pods use `100.64.0.0/16` |
| Pod CIDR | `100.64.0.0/16` | Does not overlap VNets or on-prem |
| Service CIDR | `10.60.0.0/16` | Does not overlap VNets |
| DNS service IP | `10.60.0.10` | Inside service CIDR |
| Network policy | Azure Network Policy or Calico | Pod-to-pod segmentation |
| Outbound type | `userDefinedRouting` | All egress via firewall |
| Load balancer | Internal only | No public IP on the cluster |
| API server access | Private endpoint + Entra RBAC | No local accounts |
| Workload identity | OIDC issuer + federated credential | No pod secrets |
| Key Vault | CSI driver + workload identity | Mount certs/secrets if needed |
| Pod security | Restricted standard | No privileged pods |
| Ingress | NGINX internal load balancer | APIM backend |

AKS requires outbound access to Microsoft Container Registry, Azure Resource Manager, Entra ID, Ubuntu repositories, and the AKS FQDN tag. Use Azure Firewall FQDN rules and the `AzureKubernetesService` tag. Validate with `az aks check-acr` and the AKS network checker.

## 9. APIM networking specifics

APIM Standard v2 uses two different networking features:

1. **Inbound private endpoint** in `snet-private-endpoints` (workload VNet) for the gateway endpoint.
2. **Outbound VNet integration** in `snet-apim-outbound` (workload VNet), delegated to `Microsoft.Web/serverFarms` **for Standard v2**.

Implications:

- The APIM gateway is reachable only through the private endpoint after public network access is disabled.
- APIM can reach AKS and App Service private endpoints over the workload VNet.
- APIM cannot use classic VNet injection in this tier. Do not design a `/24` "APIM injection subnet" and expect it to work.
- The `Microsoft.Web/serverFarms` delegation is required for Standard v2 outbound integration per [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/api-management/integrate-vnet-outbound). It does not mean App Service shares the subnet; the subnet remains dedicated to one APIM instance.
- Classic Developer/Premium injection requires a subnet with **no delegation** (`None`). Premium v2 injection uses `Microsoft.ApiManagement/service`. If you change APIM tier/mode, change the delegation with it.
- The `snet-apim-outbound` NSG must allow outbound 443 to Key Vault (APIM dependency) and to the backends.
- APIM custom domain names in v2 tiers require a publicly resolvable DNS name. The recommended pattern here is:
  - Clients use `api.logistics.example.com` at App Gateway.
  - App Gateway routes to the APIM default gateway hostname over the private endpoint.
  - APIM policy uses the incoming host and correlation ID, not a hard-coded custom domain.
  - If you need an APIM custom domain, create the public DNS record and certificate even though public network access is disabled.

## 10. App Service and Functions networking

### App Service

- Linux, Python 3.12, Premium v3 for production (deployment slots), Basic for lab.
- VNet integration in `snet-appservice-outbound` with route-all.
- Private endpoint in `snet-private-endpoints` for inbound.
- Public network access disabled.
- Access restrictions default-deny; private endpoint traffic is not blocked by access restrictions, but public access is disabled.
- System-assigned managed identity for Service Bus and Key Vault.
- Deployment slots: staging slot for warm-up and swap; verify private endpoint behavior for slots during Day 3.

### Functions

- Flex Consumption plan.
- VNet integration for outbound; private endpoint for inbound only if an HTTP trigger is added.
- `public_network_access_enabled=false` for the function app and its deployment storage.
- System-assigned managed identity for Service Bus, SQL, Blob.
- Service Bus trigger with `maxConcurrentCalls` and retry policy; dead-letter handling.
- Blob trigger via Event Grid; private endpoint DNS for the storage account.
- If Flex Consumption private-endpoint support is not available in your region, use a Premium plan or keep the app outbound-only with no HTTP trigger. Record the deviation; do not expose an HTTP endpoint to the internet.

## 11. WAF, DDoS, and TLS

### WAF

- OWASP Core Rule Set 3.2 or later, in prevention mode after tuning.
- Bot protection managed rules.
- Custom rules:
  - Block requests with invalid host headers.
  - Rate limit by client IP and by `sub` claim where available.
  - Block oversized bodies.
  - Allow only expected HTTP methods per path.
- Start in detection mode for 24 hours in dev; review false positives; then prevention.
- Log matched rules to Log Analytics. Alert on a spike in blocked requests.

### DDoS

- Azure platform DDoS protection is always on for public IPs.
- **DDoS IP Protection** (per public IP) or **DDoS Network Protection** (a plan, significantly more expensive) is an optional paid upgrade. Decide based on risk and budget; do not add the Network Protection plan to a lab without checking the price.
- If you enable a plan, associate it with the App Gateway public IP and the firewall public IP, and enable DDoS diagnostic logs.
- Do not rely on DDoS alone; WAF and APIM rate limits handle application-layer floods.

### TLS

- App Gateway listener: TLS 1.2 minimum, strong cipher suite, HSTS at the edge if appropriate.
- Certificate stored in Key Vault; App Gateway managed identity has `Key Vault Secrets User`.
- Backend TLS to APIM: HTTPS on 443, trusted root, SNI enabled.
- APIM to AKS: mTLS with a client certificate stored in Key Vault; NGINX ingress verifies the client CA.
- No TLS termination at APIM without re-encryption to the backend.

## 12. Validation commands for Day 3

```powershell
# Address space and subnets
az network vnet list --query "[].{name:name,space:addressSpace.addressPrefixes}" -o table
az network vnet subnet list --vnet-name vnet-workload -g rg-logistics-dev --output table

# Private endpoints and DNS
az network private-endpoint list --query "[].{name:name,subnet:subnet.id,status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table
az network private-endpoint dns-zone-group show --endpoint-name <pe-name> -g <rg> --name default

# Route and NSG
az network route-table route list --route-table-name rt-workload -g rg-logistics-dev -o table
az network watcher show-next-hop --resource-group rg-logistics-dev --vm <vm> --source-ip 10.2.4.4 --dest-ip 10.3.1.4

# Public exposure check
az resource list --query "[?type=='Microsoft.Network/publicIPAddresses'].{name:name,rg:resourceGroup}" -o table

# AKS
az aks get-credentials -g rg-logistics-dev -n aks-logistics-dev --overwrite-existing
kubectl get nodes -o wide
kubectl get svc -A | Select-String "LoadBalancer"
az aks check-acr -g rg-logistics-dev -n aks-logistics-dev --acr <acr-name>
```

DNS test from an AKS debug pod:

```bash
kubectl run dns-test --rm -it --image=<acr>/netshoot:latest --restart=Never -- \
  sh -c "nslookup <sql>.database.windows.net; nslookup <apim>.azure-api.net; nslookup <kv>.vault.azure.net"
```

Use an image from your private ACR, not Docker Hub, because AKS has no direct internet egress.

## 13. Common network pitfalls

| Pitfall | Symptom | Prevention |
|---|---|---|
| CIDR overlap with on-prem | VPN/ER routes fail or traffic blackholes | Confirm on-prem ranges before Terraform |
| Subnet too small for App Service scale | Deployment fails or outbound IPs exhausted | Use `/24` and reserve headroom |
| APIM tier mismatch | No private endpoint or no outbound integration | Confirm Standard v2 feature set before coding |
| Private DNS zone not linked to a spoke | `nslookup` returns public IP or NXDOMAIN | Link every zone to every VNet that needs it |
| Private endpoint in a delegated subnet | Deployment fails | Keep private endpoints in a non-delegated subnet |
| UDR sends private endpoint traffic to firewall | Latency, dropped health probes | Use more-specific system/peering routes; don't force RFC1918 unless required |
| App Gateway backend probe fails | 502 from App Gateway | Check host header, TLS SNI, APIM health path, NSG |
| AKS egress blocked | Nodes NotReady, image pull failures | Allow AKS FQDN tag and required FQDNs; check firewall logs |
| ACR private endpoint DNS missing | `ImagePullBackOff` | Link `privatelink.azurecr.io`; check kubelet identity AcrPull |
| Public access left enabled | Data exposure | Azure Policy deny + verification script |
| WAF blocks legitimate JSON | 403 from App Gateway | Tune rules in detection mode; exclude only specific rule IDs |
| Certificate in Key Vault inaccessible | App Gateway listener fails | Grant managed identity `Key Vault Secrets User`; check private DNS |

## 14. Decision to revisit on Day 2

The design uses direct VNet peering for private application traffic and Azure Firewall for internet egress. If the security review requires east-west inspection, add a specific route for the workload/data prefixes and size the firewall throughput accordingly. Record the change in ADR-0001 rather than silently changing the Terraform.

## 15. References to verify before Terraform

Azure networking features and SKU capabilities change. Verify these before encoding them:

- [Azure API Management virtual network concepts](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)
- [APIM Standard v2 outbound VNet integration](https://learn.microsoft.com/en-us/azure/api-management/integrate-vnet-outbound)
- [APIM inbound private endpoint](https://learn.microsoft.com/en-us/azure/api-management/private-endpoint)
- [App Service VNet integration](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
- [Private endpoint DNS zone values](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Azure Firewall features by SKU](https://learn.microsoft.com/en-us/azure/firewall/features-by-sku)
- [Azure Managed Redis Entra authentication](https://learn.microsoft.com/en-us/azure/redis/entra-for-authentication)
- [Azure API Management feature comparison](https://learn.microsoft.com/en-us/azure/api-management/api-management-features)

If your tenant, region, or subscription does not support a feature, record the deviation in the relevant ADR and adjust the Terraform before Day 2.
