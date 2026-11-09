"""Acquire a user token for the logistics API with the device-code flow.

This uses the dedicated public client app, not Azure CLI. Azure CLI cannot
request a token for an arbitrary custom API (AADSTS650057).

Required environment variables:
    ENTRA_TENANT_ID
    ENTRA_CLIENT_ID     # logistics-cli app client ID
Optional:
    ENTRA_SCOPE         # defaults to api://logistics-api/access_as_user
"""

import os
import sys

import msal
from dotenv import load_dotenv

load_dotenv()

tenant_id = os.environ.get("ENTRA_TENANT_ID", "")
client_id = os.environ.get("ENTRA_CLIENT_ID", "")
scope = os.environ.get("ENTRA_SCOPE", "api://logistics-api/access_as_user")

if not tenant_id or not client_id:
    sys.exit("Set ENTRA_TENANT_ID and ENTRA_CLIENT_ID (the logistics-cli client ID).")

app = msal.PublicClientApplication(
    client_id,
    authority=f"https://login.microsoftonline.com/{tenant_id}",
)

flow = app.initiate_device_flow(scopes=[scope])
if "user_code" not in flow:
    sys.exit(f"Device flow failed: {flow}")

print(flow["message"], file=sys.stderr)
result = app.acquire_token_by_device_flow(flow)

if "access_token" not in result:
    sys.exit(f"Token acquisition failed: {result}")

print(result["access_token"])
