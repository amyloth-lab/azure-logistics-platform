"""
Render the Day 1 architecture diagrams as PNGs.

The diagrams are generated code so that a learner can change a label or a CIDR
and regenerate them without a drawing tool. Requires Pillow.

Run:
    python diagrams/render_diagrams.py

Outputs:
    diagrams/logical-architecture.png
    diagrams/network-topology.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
FONT_DIR = Path(r"C:\Windows\Fonts")

# Palette
BG = "#F5F7FB"
CARD = "#FFFFFF"
INK = "#14213D"
MUTED = "#5B6577"
LINE = "#94A3B8"
NAVY = "#0B1F3A"
BLUE = "#1D4ED8"
BLUE_FILL = "#E8EFFF"
TEAL = "#0F766E"
TEAL_FILL = "#E6F7F3"
PURPLE = "#6D28D9"
PURPLE_FILL = "#F1EBFF"
ROSE = "#BE123C"
ROSE_FILL = "#FFF1F5"
AMBER = "#B45309"
AMBER_FILL = "#FFF7E6"
GREEN = "#15803D"
GREEN_FILL = "#EAF8EF"
GRAY = "#374151"
GRAY_FILL = "#F3F4F6"
SLATE = "#334155"
SLATE_FILL = "#F8FAFC"


def _font(size: int, bold: bool = False, mono: bool = False) -> ImageFont.FreeTypeFont:
    if mono:
        candidates = [FONT_DIR / "consola.ttf", FONT_DIR / "cour.ttf"]
    elif bold:
        candidates = [FONT_DIR / "segoeuib.ttf", FONT_DIR / "arialbd.ttf"]
    else:
        candidates = [FONT_DIR / "segoeui.ttf", FONT_DIR / "arial.ttf"]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def _text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    box = draw.multiline_textbbox((0, 0), text, font=font, spacing=5, align="center")
    return box[2] - box[0], box[3] - box[1]


def _wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_width: int) -> str:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        trial = word if not current else f"{current} {word}"
        if _text_size(draw, trial, font)[0] <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return "\n".join(lines)


def rounded(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    radius: int = 18,
    fill: str = CARD,
    outline: str = LINE,
    width: int = 2,
    shadow: bool = True,
) -> None:
    x1, y1, x2, y2 = xy
    if shadow:
        draw.rounded_rectangle((x1 + 5, y1 + 6, x2 + 5, y2 + 6), radius=radius, fill="#E2E8F0")
    draw.rounded_rectangle((x1, y1, x2, y2), radius=radius, fill=fill, outline=outline, width=width)


def card(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    title: str,
    subtitle: str = "",
    *,
    fill: str = CARD,
    outline: str = LINE,
    accent: str = BLUE,
    title_size: int = 25,
    sub_size: int = 18,
    badge: str | None = None,
    badge_fill: str = "#FFFFFF",
    badge_ink: str = MUTED,
    dashed: bool = False,
) -> None:
    x1, y1, x2, y2 = xy
    radius = 16
    shadow = not dashed
    if shadow:
        draw.rounded_rectangle((x1 + 4, y1 + 5, x2 + 4, y2 + 5), radius=radius, fill="#E2E8F0")
    if dashed:
        draw.rounded_rectangle((x1, y1, x2, y2), radius=radius, fill=fill, outline=outline, width=2)
        # simple dashed accent line at top
        for x in range(x1 + 12, x2 - 12, 18):
            draw.line((x, y1 + 1, min(x + 9, x2 - 10), y1 + 1), fill=accent, width=3)
    else:
        draw.rounded_rectangle((x1, y1, x2, y2), radius=radius, fill=fill, outline=outline, width=2)
        draw.rounded_rectangle((x1, y1, x2, y1 + 7), radius=4, fill=accent)

    inner_w = (x2 - x1) - 34
    title_font = _font(title_size, bold=True)
    wrapped_title = _wrap(draw, title, title_font, inner_w)
    title_h = _text_size(draw, wrapped_title, title_font)[1]

    sub_font = _font(sub_size)
    wrapped_sub = _wrap(draw, subtitle, sub_font, inner_w) if subtitle else ""
    sub_h = _text_size(draw, wrapped_sub, sub_font)[1] if wrapped_sub else 0

    total = title_h + (10 if wrapped_sub else 0) + sub_h
    start_y = y1 + ((y2 - y1) - total) // 2 + 2
    if wrapped_sub:
        start_y -= 2

    if badge:
        bf = _font(13, bold=True)
        bw = _text_size(draw, badge, bf)[0] + 18
        bh = 25
        bx2 = x2 - 12
        bx1 = bx2 - bw
        draw.rounded_rectangle((bx1, y1 + 12, bx2, y1 + 12 + bh), radius=10, fill=badge_fill, outline="#E2E8F0")
        draw.text((bx1 + 9, y1 + 12 + bh / 2 - 1), badge, font=bf, fill=badge_ink, anchor="lm")

    draw.multiline_text(
        ((x1 + x2) / 2, start_y),
        wrapped_title,
        font=title_font,
        fill=INK,
        anchor="ma",
        align="center",
        spacing=5,
    )
    if wrapped_sub:
        draw.multiline_text(
            ((x1 + x2) / 2, start_y + title_h + 9),
            wrapped_sub,
            font=sub_font,
            fill=MUTED,
            anchor="ma",
            align="center",
            spacing=5,
        )


def zone(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    title: str,
    subtitle: str = "",
    *,
    fill: str = "#FBFCFE",
    outline: str = "#CBD5E1",
    accent: str = BLUE,
    title_size: int = 20,
) -> None:
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle((x1, y1, x2, y2), radius=22, fill=fill, outline=outline, width=2)
    # title tab
    tf = _font(title_size, bold=True)
    tw = _text_size(draw, title, tf)[0] + 34
    draw.rounded_rectangle((x1 + 18, y1 - 16, x1 + 18 + tw, y1 + 18), radius=10, fill=accent)
    draw.text((x1 + 35, y1 + 2), title, font=tf, fill="#FFFFFF", anchor="lm")
    if subtitle:
        sf = _font(16)
        draw.text((x1 + 22, y1 + 32), subtitle, font=sf, fill=MUTED, anchor="la")


def arrow(
    draw: ImageDraw.ImageDraw,
    start: tuple[float, float],
    end: tuple[float, float],
    *,
    color: str = SLATE,
    width: int = 3,
    dashed: bool = False,
    head: bool = True,
    label: str | None = None,
    label_offset: tuple[int, int] = (0, -14),
    label_size: int = 15,
) -> None:
    x1, y1 = start
    x2, y2 = end
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    if length < 1:
        return
    ux, uy = dx / length, dy / length
    if head:
        head_len = 15
        ex, ey = x2 - ux * head_len, y2 - uy * head_len
    else:
        ex, ey = x2, y2

    if dashed:
        dash, gap = 12, 9
        dist = 0.0
        while dist < math.hypot(ex - x1, ey - y1):
            a = (x1 + ux * dist, y1 + uy * dist)
            b_dist = min(dist + dash, math.hypot(ex - x1, ey - y1))
            b = (x1 + ux * b_dist, y1 + uy * b_dist)
            draw.line((a, b), fill=color, width=width)
            dist += dash + gap
    else:
        draw.line((x1, y1, ex, ey), fill=color, width=width)

    if head:
        left = (x2 - ux * head_len - uy * 7, y2 - uy * head_len + ux * 7)
        right = (x2 - ux * head_len + uy * 7, y2 - uy * head_len - ux * 7)
        draw.polygon([ (x2, y2), left, right ], fill=color)

    if label:
        lf = _font(label_size, bold=True)
        tw, th = _text_size(draw, label, lf)
        cx = (x1 + x2) / 2 + label_offset[0]
        cy = (y1 + y2) / 2 + label_offset[1]
        pad = 6
        draw.rounded_rectangle(
            (cx - tw / 2 - pad, cy - th / 2 - 4, cx + tw / 2 + pad, cy + th / 2 + 4),
            radius=7,
            fill=BG,
            outline="#E2E8F0",
        )
        draw.text((cx, cy - 1), label, font=lf, fill=color, anchor="mm")


def elbow(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    *,
    color: str = SLATE,
    width: int = 3,
    dashed: bool = False,
    label: str | None = None,
    label_at: tuple[float, float] | None = None,
    label_offset: tuple[int, int] = (0, 0),
    label_size: int = 15,
) -> None:
    for i in range(len(points) - 1):
        if i == len(points) - 2:
            arrow(draw, points[i], points[i + 1], color=color, width=width, dashed=dashed, label=label,
                  label_offset=label_offset, label_size=label_size)
        else:
            draw.line((points[i], points[i + 1]), fill=color, width=width)


def pill(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    text: str,
    *,
    fill: str = "#FFFFFF",
    outline: str = "#CBD5E1",
    ink: str = MUTED,
    size: int = 14,
    bold: bool = True,
) -> None:
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle((x1, y1, x2, y2), radius=12, fill=fill, outline=outline, width=1)
    draw.text(((x1 + x2) / 2, (y1 + y2) / 2 - 1), text, font=_font(size, bold=bold), fill=ink, anchor="mm")


def logical_architecture() -> Path:
    W, H = 2800, 1780
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # Header
    d.text((50, 40), "Azure Logistics Platform - Logical Architecture", font=_font(46, bold=True), fill=NAVY)
    d.text(
        (52, 103),
        "Two business APIs | Entra identity | private data plane | event-driven fulfilment | separate build and release paths",
        font=_font(22),
        fill=MUTED,
    )
    pill(d, (2180, 46, 2750, 100), "PRODUCTION-SHAPED / LAB-SIZED", fill="#E8FFF4", outline="#A7E3C3", ink=GREEN, size=17)

    # Outer Azure boundary
    zone(
        d,
        (620, 150, 2770, 1280),
        "AZURE LANDING ZONE",
        "Hub-and-spoke | private endpoints | policy + observability",
        fill="#FBFCFE",
        outline="#B8C4D6",
        accent=NAVY,
        title_size=22,
    )

    # Sub-zones
    zone(d, (650, 220, 1010, 1120), "EDGE", "public entry only", fill="#F8FBFF", outline="#BFD0EA", accent=BLUE, title_size=19)
    zone(d, (1050, 220, 1660, 1120), "WORKLOAD SPOKE", "compute + private ingress", fill="#F7FCFA", outline="#BFE3D7", accent=TEAL, title_size=19)
    zone(d, (1700, 220, 2380, 1120), "DATA SPOKE", "no public data plane", fill="#FFF8FA", outline="#F1C6D2", accent=ROSE, title_size=19)
    zone(d, (2420, 220, 2740, 1120), "SECURITY + OPS", "verify, observe, respond", fill="#F8F7FF", outline="#D6CCF5", accent=PURPLE, title_size=18)

    # Left external boxes
    zone(d, (40, 170, 580, 540), "CONSUMERS", "who calls the API", fill="#FFFDF7", outline="#EBD6A8", accent=AMBER, title_size=19)
    card(d, (65, 220, 555, 305), "Operations users", "inventory readers / contributors | order creators", fill=AMBER_FILL, outline="#E8C98E", accent=AMBER, title_size=22, sub_size=16)
    card(d, (65, 320, 555, 395), "Managers", "read all | delete inventory / orders | approve", fill=AMBER_FILL, outline="#E8C98E", accent=AMBER, title_size=22, sub_size=16)
    card(d, (65, 410, 555, 500), "Partners", "client credentials | carrier webhooks", fill=AMBER_FILL, outline="#E8C98E", accent=AMBER, title_size=22, sub_size=16)

    card(
        d,
        (40, 580, 580, 760),
        "Microsoft Entra ID",
        "OIDC/OAuth 2.0 | app roles\nMFA (Security Defaults)\nmanual JIT",
        fill=BLUE_FILL,
        outline="#AFC4F5",
        accent=BLUE,
        title_size=27,
        sub_size=17,
    )
    card(
        d,
        (40, 800, 580, 950),
        "GitHub + Azure DevOps",
        "GitHub source + PRs | Azure Boards\nBuild + release pipelines | OIDC service connections",
        fill=GRAY_FILL,
        outline="#CBD5E1",
        accent=GRAY,
        title_size=24,
        sub_size=16,
    )
    card(
        d,
        (40, 990, 580, 1130),
        "On-premises ERP / WMS",
        "192.168.0.0/16 | site-to-site VPN or ExpressRoute",
        fill=SLATE_FILL,
        outline="#CBD5E1",
        accent=SLATE,
        title_size=23,
        sub_size=16,
    )

    # Edge cards
    card(
        d,
        (675, 270, 985, 410),
        "Application Gateway",
        "WAF_v2 | public IP | TLS 1.2+ | OWASP 3.2\nbot + custom rules | DDoS protection",
        fill=BLUE_FILL,
        outline="#AFC4F5",
        accent=BLUE,
        title_size=23,
        sub_size=15,
        badge="PUBLIC",
        badge_fill="#FFF1F2",
        badge_ink=ROSE,
    )
    card(
        d,
        (675, 445, 985, 605),
        "API Management",
        "Standard v2 | inbound private endpoint\nJWT validation | quotas | versioning",
        fill=BLUE_FILL,
        outline="#AFC4F5",
        accent=BLUE,
        title_size=23,
        sub_size=15,
        badge="PRIVATE",
        badge_fill="#E8FFF4",
        badge_ink=GREEN,
    )
    card(
        d,
        (675, 640, 985, 750),
        "Azure DNS + TLS",
        "api.logistics.example.com\nCA certificate stored in Key Vault",
        fill="#FFFFFF",
        outline="#CBD5E1",
        accent=BLUE,
        title_size=21,
        sub_size=15,
    )
    card(
        d,
        (675, 785, 985, 890),
        "WAF + DDoS policy",
        "default deny | managed rules | rate limits\nonly public endpoint in the design",
        fill="#FFFFFF",
        outline="#CBD5E1",
        accent=BLUE,
        title_size=20,
        sub_size=15,
    )
    card(
        d,
        (675, 925, 985, 1080),
        "APIM policy chain",
        "validate-jwt | check scopes / roles\nrate-limit-by-key | correlation ID\nbackend mTLS | no token logging",
        fill="#FFFFFF",
        outline="#CBD5E1",
        accent=BLUE,
        title_size=20,
        sub_size=14,
    )

    # AKS card (large) with inner labels
    card(
        d,
        (1080, 270, 1630, 570),
        "Azure Kubernetes Service",
        "private cluster | Azure CNI Overlay | network policy\nworkload identity | Key Vault CSI | HPA + PDB | PSS restricted",
        fill=TEAL_FILL,
        outline="#9FD8C8",
        accent=TEAL,
        title_size=25,
        sub_size=16,
        badge="CORE API",
        badge_fill="#FFFFFF",
        badge_ink=TEAL,
    )
    pill(d, (1105, 470, 1370, 510), "NGINX ingress (internal)", fill="#FFFFFF", outline="#9FD8C8", ink=TEAL, size=14)
    pill(d, (1390, 470, 1605, 510), "logistics-api pods", fill="#FFFFFF", outline="#9FD8C8", ink=TEAL, size=14)
    pill(d, (1105, 520, 1605, 555), "inventory + orders routes | async outbox relay", fill="#FFFFFF", outline="#9FD8C8", ink=TEAL, size=14)

    card(
        d,
        (1080, 610, 1630, 750),
        "Azure App Service",
        "partner-webhook | Linux Python | VNet integration\nprivate endpoint inbound | deployment slots",
        fill=TEAL_FILL,
        outline="#9FD8C8",
        accent=TEAL,
        title_size=23,
        sub_size=15,
        badge="WEB APP",
        badge_fill="#FFFFFF",
        badge_ink=TEAL,
    )
    card(
        d,
        (1080, 790, 1630, 930),
        "Azure Functions",
        "Flex Consumption | Service Bus trigger\ntimer reconciliation | blob audit archiver",
        fill=TEAL_FILL,
        outline="#9FD8C8",
        accent=TEAL,
        title_size=23,
        sub_size=15,
        badge="EVENT-DRIVEN",
        badge_fill="#FFFFFF",
        badge_ink=TEAL,
    )
    card(
        d,
        (1080, 970, 1630, 1070),
        "Azure Container Registry",
        "Premium | private endpoint | admin disabled\nimage scan + retention | immutable tags",
        fill=TEAL_FILL,
        outline="#9FD8C8",
        accent=TEAL,
        title_size=21,
        sub_size=15,
    )

    # Data cards
    card(
        d,
        (1730, 270, 2350, 385),
        "Azure SQL Database",
        "GP serverless (dev) / GP zone-redundant (prod)\nEntra-only auth | TDE + CMK | PITR + LTR | auditing",
        fill=ROSE_FILL,
        outline="#F1C6D2",
        accent=ROSE,
        title_size=23,
        sub_size=15,
        badge="PE",
        badge_fill="#FFFFFF",
        badge_ink=ROSE,
    )
    card(
        d,
        (1730, 415, 2350, 520),
        "Azure Managed Redis",
        "Balanced B0/B1 | Entra auth | TLS\ncache-aside + idempotency keys | never source of truth",
        fill=ROSE_FILL,
        outline="#F1C6D2",
        accent=ROSE,
        title_size=22,
        sub_size=15,
        badge="PE",
        badge_fill="#FFFFFF",
        badge_ink=ROSE,
    )
    card(
        d,
        (1730, 550, 2350, 655),
        "Blob Storage",
        "RA-GRS | private endpoint | public access off\nversioning + soft delete + immutability | CMK",
        fill=ROSE_FILL,
        outline="#F1C6D2",
        accent=ROSE,
        title_size=22,
        sub_size=15,
        badge="PE",
        badge_fill="#FFFFFF",
        badge_ink=ROSE,
    )
    card(
        d,
        (1730, 685, 2350, 805),
        "Azure Service Bus",
        "Standard (dev) / Premium (prod) | topics + subscriptions\nDLQ + duplicate detection | managed identity",
        fill=ROSE_FILL,
        outline="#F1C6D2",
        accent=ROSE,
        title_size=22,
        sub_size=15,
        badge="PE",
        badge_fill="#FFFFFF",
        badge_ink=ROSE,
    )
    card(
        d,
        (1730, 835, 2350, 945),
        "Azure Key Vault",
        "RBAC | private endpoint | purge protection\nTLS cert + CMK | secrets only as a last resort",
        fill=ROSE_FILL,
        outline="#F1C6D2",
        accent=ROSE,
        title_size=22,
        sub_size=15,
        badge="PE",
        badge_fill="#FFFFFF",
        badge_ink=ROSE,
    )
    card(
        d,
        (1730, 980, 2350, 1065),
        "Zero-trust data access",
        "No public network access. No shared keys.\nEvery call: managed identity -> private endpoint -> least privilege.",
        fill="#FFFFFF",
        outline="#F1C6D2",
        accent=ROSE,
        title_size=18,
        sub_size=14,
        dashed=True,
    )

    # Security / ops cards
    card(d, (2445, 270, 2715, 390), "Azure Monitor", "Log Analytics + App Insights\nOTel traces | alerts | SLOs", fill=PURPLE_FILL, outline="#D6CCF5", accent=PURPLE, title_size=18, sub_size=13)
    card(d, (2445, 405, 2715, 525), "Defender for Cloud", "CSPM + containers / SQL /\nstorage / App Service", fill=PURPLE_FILL, outline="#D6CCF5", accent=PURPLE, title_size=18, sub_size=13)
    card(d, (2445, 540, 2715, 660), "Microsoft Sentinel", "SIEM | analytics rules\nincident response", fill=PURPLE_FILL, outline="#D6CCF5", accent=PURPLE, title_size=18, sub_size=13)
    card(d, (2445, 675, 2715, 795), "Azure Policy", "deny public IP / public data\nrequire tags + TLS + PE", fill=PURPLE_FILL, outline="#D6CCF5", accent=PURPLE, title_size=18, sub_size=13)
    card(d, (2445, 810, 2715, 930), "Terraform state", "blob lease lock | private endpoint\nversioning + immutability", fill=PURPLE_FILL, outline="#D6CCF5", accent=PURPLE, title_size=18, sub_size=13)
    card(d, (2445, 945, 2715, 1080), "Ansible + agents", "self-hosted pool | Linux hardening\nK8s baseline | idempotent", fill=PURPLE_FILL, outline="#D6CCF5", accent=PURPLE, title_size=18, sub_size=13)

    # Hub strip
    card(
        d,
        (650, 1150, 2380, 1255),
        "Hub VNet 10.0.0.0/16",
        "Azure Firewall (egress + IDPS) | Azure Bastion | VPN / ExpressRoute gateway | Private DNS Resolver | DDoS Protection",
        fill=GREEN_FILL,
        outline="#A7E3C3",
        accent=GREEN,
        title_size=22,
        sub_size=16,
    )

    # Arrows: left to edge
    arrow(d, (555, 470), (675, 340), color=AMBER, width=4, label="HTTPS + JWT", label_offset=(0, -18))
    arrow(d, (580, 650), (675, 525), color=BLUE, width=3, dashed=True, label="JWKS / metadata", label_offset=(0, -16))
    arrow(d, (830, 410), (830, 445), color=BLUE, width=4, label="private TLS", label_offset=(70, 0))

    # Edge to compute
    arrow(d, (985, 485), (1080, 420), color=BLUE, width=4, label="mTLS + private", label_offset=(0, -20))
    arrow(d, (985, 540), (1080, 675), color=BLUE, width=4, label="private", label_offset=(0, -18))

    # Compute -> data trunk
    trunk_x = 1690
    d.line((1630, 420, trunk_x, 420), fill=ROSE, width=4)
    d.line((trunk_x, 330, trunk_x, 890), fill=ROSE, width=4)
    for y in (330, 465, 600, 745, 890):
        arrow(d, (trunk_x, y), (1730, y), color=ROSE, width=3)
    pill(d, (1635, 430, 1725, 462), "MI + PE", fill="#FFFFFF", outline="#F1C6D2", ink=ROSE, size=12)

    # App Service -> Service Bus
    arrow(d, (1630, 690), (1730, 735), color=TEAL, width=3, label="events", label_offset=(0, -16))

    # Service Bus -> Functions (route around the right and bottom of Key Vault)
    elbow(
        d,
        [(2350, 805), (2365, 805), (2365, 960), (1350, 960), (1350, 930)],
        color=TEAL,
        width=3,
    )
    pill(d, (1740, 944, 1920, 976), "Service Bus trigger", fill="#FFFFFF", outline="#F1C6D2", ink=TEAL, size=13)
    # Functions -> data trunk (audit / SQL)
    arrow(d, (1630, 860), (1682, 860), color=TEAL, width=3, label="MI", label_offset=(0, -14), label_size=13)

    # On-prem -> hub
    arrow(d, (580, 1060), (650, 1205), color=GREEN, width=4, label="VPN / ER", label_offset=(0, -18))

    # Telemetry dotted bus
    d.line((2380, 300, 2410, 300), fill=PURPLE, width=2)
    d.line((2410, 300, 2410, 1030), fill=PURPLE, width=2)
    for y in (330, 465, 600, 735, 870, 1005):
        arrow(d, (2410, y), (2445, y), color=PURPLE, width=2, dashed=True)
    pill(d, (2320, 205, 2440, 238), "diagnostics", fill="#FFFFFF", outline="#D6CCF5", ink=PURPLE, size=12)

    # Delivery path
    zone(
        d,
        (40, 1320, 2740, 1710),
        "DELIVERY PATH",
        "CI and CD are separate pipelines, separate identities, separate permissions",
        fill="#F9FAFB",
        outline="#CBD5E1",
        accent=GRAY,
        title_size=20,
    )
    y1, y2 = 1400, 1585
    cards = [
        (70, 380, "GitHub", "main + PRs | CODEOWNERS\nbranch protection | Dependabot", GRAY_FILL, GRAY, "#CBD5E1"),
        (420, 730, "Build pipeline", "lint | test | SAST | deps | secrets\nTerraform validate | image scan | SBOM", BLUE_FILL, BLUE, "#AFC4F5"),
        (770, 1080, "Artifacts", "immutable image tag\nHelm chart | SBOM | test results", TEAL_FILL, TEAL, "#9FD8C8"),
        (1120, 1480, "Release pipeline", "dev auto | prod approval\nplan artifact | canary / slot swap", PURPLE_FILL, PURPLE, "#D6CCF5"),
        (1520, 1880, "Terraform + Ansible", "plan -> approve -> apply\nconfiguration baseline | drift check", AMBER_FILL, AMBER, "#E8C98E"),
        (1920, 2280, "Deploy + verify", "AKS Helm | App Service slot\nmigrations | smoke | DAST", GREEN_FILL, GREEN, "#A7E3C3"),
        (2320, 2710, "Observe + improve", "SLOs | alerts | cost\nretro + backlog", GRAY_FILL, GRAY, "#CBD5E1"),
    ]
    for x1, x2, title, sub, fill, accent, outline in cards:
        card(d, (x1, y1, x2, y2), title, sub, fill=fill, outline=outline, accent=accent, title_size=21, sub_size=14)
    for i in range(len(cards) - 1):
        x2 = cards[i][1]
        x1n = cards[i + 1][0]
        arrow(d, (x2 + 8, (y1 + y2) / 2), (x1n - 8, (y1 + y2) / 2), color=SLATE, width=3)
    # OIDC dashed from delivery to Azure
    arrow(d, (1900, 1400), (1900, 1285), color=GREEN, width=3, dashed=True, label="OIDC | no secrets", label_offset=(0, -18))

    # Footer / legend
    lf = _font(16, bold=True)
    d.text((50, 1735), "Solid = request / data flow    Dashed = identity, telemetry, or automation    PE = private endpoint    MI = managed identity",
           font=_font(16), fill=MUTED)
    d.text((2250, 1735), "Day 1 of 5 | v1.0", font=lf, fill=MUTED)

    out = ROOT / "logical-architecture.png"
    img.save(out, "PNG", optimize=True)
    return out


def network_topology() -> Path:
    W, H = 3000, 1940
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # Header
    d.text((50, 40), "Hub-and-Spoke Network Topology", font=_font(46, bold=True), fill=NAVY)
    d.text(
        (52, 103),
        "Production-shaped address plan | private endpoints | forced egress through Azure Firewall | no public workload IPs",
        font=_font(22),
        fill=MUTED,
    )
    pill(d, (2380, 46, 2950, 100), "AUSTRALIA EAST | PRIMARY REGION", fill="#E8FFF4", outline="#A7E3C3", ink=GREEN, size=16)

    # External top
    card(d, (100, 160, 850, 330), "Internet / API consumers", "Entra ID access token over TLS 1.2+\napi.logistics.example.com -> App Gateway public IP",
         fill=AMBER_FILL, outline="#E8C98E", accent=AMBER, title_size=26, sub_size=17)
    card(d, (1100, 160, 1900, 330), "Microsoft Entra ID", "OIDC / OAuth 2.0 | app roles + scopes\nSecurity Defaults | manual JIT | workload identities",
         fill=BLUE_FILL, outline="#AFC4F5", accent=BLUE, title_size=26, sub_size=17)
    card(d, (2150, 160, 2900, 330), "On-premises ERP / WMS", "192.168.0.0/16\nsite-to-site VPN or ExpressRoute",
         fill=SLATE_FILL, outline="#CBD5E1", accent=SLATE, title_size=26, sub_size=17)

    # Hub
    zone(d, (1050, 400, 1950, 850), "HUB VNET 10.0.0.0/16", "shared security + connectivity | no workloads",
         fill="#F4FCF7", outline="#A7E3C3", accent=GREEN, title_size=22)
    card(d, (1080, 470, 1460, 590), "Azure Firewall", "egress | FQDN allow-list | IDPS\nPremium in prod, Basic in lab",
         fill="#FFFFFF", outline="#A7E3C3", accent=GREEN, title_size=21, sub_size=14)
    card(d, (1485, 470, 1670, 590), "Azure Bastion", "no public IPs\non admin VMs", fill="#FFFFFF", outline="#A7E3C3", accent=GREEN, title_size=18, sub_size=13)
    card(d, (1695, 470, 1920, 590), "VPN / ER", "hybrid\nconnectivity", fill="#FFFFFF", outline="#A7E3C3", accent=GREEN, title_size=19, sub_size=13)
    card(d, (1080, 615, 1460, 720), "Private DNS Resolver", "inbound / outbound\non-prem forwarding", fill="#FFFFFF", outline="#A7E3C3", accent=GREEN, title_size=19, sub_size=13)
    card(d, (1485, 615, 1920, 720), "DDoS Protection", "public IP protection\nApp Gateway only", fill="#FFFFFF", outline="#A7E3C3", accent=GREEN, title_size=19, sub_size=13)
    d.text((1080, 745), "AzureFirewallSubnet 10.0.0.0/26  |  AzureFirewallManagementSubnet 10.0.0.64/26\nAzureBastionSubnet 10.0.1.0/26  |  GatewaySubnet 10.0.2.0/27  |  DNS 10.0.3.0/28",
           font=_font(14), fill=MUTED, spacing=5)


    # Ingress spoke
    zone(d, (100, 930, 900, 1390), "INGRESS SPOKE 10.1.0.0/16", "the only public entry point",
         fill="#F5F8FF", outline="#BFD0EA", accent=BLUE, title_size=21)
    card(d, (135, 1000, 865, 1150), "Application Gateway WAF_v2", "public IP | TLS termination | OWASP 3.2\nbot + custom rules | WAF policy | DDoS",
         fill=BLUE_FILL, outline="#AFC4F5", accent=BLUE, title_size=25, sub_size=16, badge="PUBLIC", badge_fill="#FFF1F2", badge_ink=ROSE)
    card(d, (135, 1180, 480, 1290), "Public IP", "DNS A record\nDDoS-protected", fill="#FFFFFF", outline="#BFD0EA", accent=BLUE, title_size=19, sub_size=13)
    card(d, (505, 1180, 865, 1290), "WAF policy", "managed + custom rules\nrate limiting", fill="#FFFFFF", outline="#BFD0EA", accent=BLUE, title_size=19, sub_size=13)
    d.text((135, 1320), "snet-appgw 10.1.0.0/24  |  no management subnet required for WAF_v2", font=_font(15), fill=MUTED)
    pill(d, (135, 1348, 430, 1380), "NO PUBLIC DATA PLANE", fill="#FFF1F2", outline="#F1C6D2", ink=ROSE, size=12)

    # Workload spoke
    zone(d, (980, 930, 2030, 1560), "WORKLOAD SPOKE 10.2.0.0/16", "AKS + APIM + App Service + Functions",
         fill="#F4FCFA", outline="#9FD8C8", accent=TEAL, title_size=21)
    card(d, (1010, 1000, 1490, 1190), "AKS private cluster", "system 10.2.0.0/22 | user 10.2.4.0/22\nCNI Overlay | network policy | workload identity",
         fill=TEAL_FILL, outline="#9FD8C8", accent=TEAL, title_size=22, sub_size=14, badge="CORE API", badge_fill="#FFFFFF", badge_ink=TEAL)
    card(d, (1010, 1215, 1490, 1330), "API Management", "Standard v2 | PE 10.2.11.0/24\noutbound 10.2.8.0/24 | JWT + quotas",
         fill=TEAL_FILL, outline="#9FD8C8", accent=TEAL, title_size=21, sub_size=14)
    card(d, (1520, 1000, 2000, 1100), "App Service", "outbound 10.2.9.0/24\nprivate endpoint inbound",
         fill=TEAL_FILL, outline="#9FD8C8", accent=TEAL, title_size=21, sub_size=14)
    card(d, (1520, 1125, 2000, 1225), "Azure Functions", "outbound 10.2.10.0/24\nprivate endpoint inbound",
         fill=TEAL_FILL, outline="#9FD8C8", accent=TEAL, title_size=21, sub_size=14)
    card(d, (1520, 1250, 2000, 1350), "Private endpoints", "APIM | App Service | Functions\nDNS -> private IP",
         fill=TEAL_FILL, outline="#9FD8C8", accent=TEAL, title_size=21, sub_size=14)
    card(d, (1010, 1360, 2000, 1435), "Internal ingress load balancer", "10.2.12.0/27 | NGINX ingress | APIM backend pool",
         fill="#FFFFFF", outline="#9FD8C8", accent=TEAL, title_size=18, sub_size=14)
    d.text((1010, 1460), "snet-aks-system /22  |  snet-aks-user /22  |  snet-apim-outbound /24  |  snet-appservice-outbound /24\nsnet-functions-outbound /24  |  snet-private-endpoints /24  |  snet-aks-ingress /27",
           font=_font(14), fill=MUTED, spacing=4)

    # Data spoke
    zone(d, (2110, 930, 2900, 1560), "DATA SPOKE 10.3.0.0/16", "private endpoints only | no public access",
         fill="#FFF8FA", outline="#F1C6D2", accent=ROSE, title_size=21)
    card(d, (2140, 1000, 2870, 1090), "Azure SQL Database", "Entra-only auth | TDE + CMK | PITR + LTR", fill=ROSE_FILL, outline="#F1C6D2", accent=ROSE, title_size=21, sub_size=14)
    card(d, (2140, 1105, 2870, 1185), "Azure Managed Redis", "Entra auth | TLS | cache-aside", fill=ROSE_FILL, outline="#F1C6D2", accent=ROSE, title_size=21, sub_size=14)
    card(d, (2140, 1200, 2870, 1280), "Blob Storage", "RA-GRS | versioning | immutability | CMK", fill=ROSE_FILL, outline="#F1C6D2", accent=ROSE, title_size=21, sub_size=14)
    card(d, (2140, 1295, 2495, 1390), "Key Vault", "TLS + CMK | purge protection", fill=ROSE_FILL, outline="#F1C6D2", accent=ROSE, title_size=20, sub_size=13)
    card(d, (2515, 1295, 2870, 1390), "Service Bus", "topics + DLQ | duplicate detection", fill=ROSE_FILL, outline="#F1C6D2", accent=ROSE, title_size=20, sub_size=13)
    d.text((2140, 1420), "snet-private-endpoints 10.3.1.0/24\nprivate DNS zones linked to hub + all spokes",
           font=_font(15), fill=MUTED, spacing=4)
    pill(d, (2140, 1480, 2420, 1515), "NO PUBLIC IPs", fill="#FFF1F2", outline="#F1C6D2", ink=ROSE, size=13)

    # Management spoke
    zone(d, (100, 1430, 900, 1810), "MANAGEMENT SPOKE 10.4.0.0/16", "build + release + state",
         fill="#F9FAFB", outline="#CBD5E1", accent=GRAY, title_size=20)
    card(d, (135, 1500, 470, 1600), "Self-hosted agents", "10.4.0.0/24\nno public IP", fill=GRAY_FILL, outline="#CBD5E1", accent=GRAY, title_size=19, sub_size=13)
    card(d, (495, 1500, 865, 1600), "Ansible control", "10.4.1.0/28\nmanaged identity", fill=GRAY_FILL, outline="#CBD5E1", accent=GRAY, title_size=19, sub_size=13)
    card(d, (135, 1620, 470, 1720), "Terraform state", "10.4.2.0/24\nPE + blob lease", fill=GRAY_FILL, outline="#CBD5E1", accent=GRAY, title_size=19, sub_size=13)
    card(d, (495, 1620, 865, 1720), "ACR Premium", "private endpoint\nadmin disabled", fill=GRAY_FILL, outline="#CBD5E1", accent=GRAY, title_size=19, sub_size=13)
    d.text((135, 1740), "Bastion is the only interactive path to these VMs.", font=_font(15), fill=MUTED)

    # Private DNS strip
    card(
        d,
        (980, 1630, 2900, 1810),
        "Private DNS zones - linked to hub and every spoke",
        "privatelink.azure-api.net  |  privatelink.azurewebsites.net  |  privatelink.database.windows.net  |  privatelink.redis.azure.net\n"
        "privatelink.blob.core.windows.net  |  privatelink.vaultcore.azure.net  |  privatelink.servicebus.windows.net  |  privatelink.azurecr.io\n"
        "privatelink.australiaeast.azmk8s.io  |  Azure Monitor private link scope zones (optional)",
        fill="#FFFFFF",
        outline="#CBD5E1",
        accent=NAVY,
        title_size=21,
        sub_size=14,
    )

    # Peering is represented once, centrally, to avoid drawing lines through cards.
    pill(d, (1390, 858, 1760, 894), "VNet peering: hub <-> every spoke", fill="#FFFFFF", outline="#A7E3C3", ink=GREEN, size=13)

    # Internet -> App Gateway (use the right side of the ingress title to avoid the zone tab)
    arrow(d, (800, 330), (800, 1000), color=AMBER, width=5, label="HTTPS 443", label_offset=(0, -16))

    # Entra -> APIM, routed through the right-hand gutter and the gap above the functions card.
    elbow(d, [(1900, 300), (2050, 300), (2050, 1240), (1490, 1240)], color=BLUE, width=3, dashed=True)
    pill(d, (1925, 560, 2105, 595), "JWT / JWKS", fill="#FFFFFF", outline="#AFC4F5", ink=BLUE, size=13)

    # On-prem -> VPN/ER
    elbow(d, [(2500, 330), (2500, 380), (1800, 380), (1800, 470)], color=SLATE, width=4, label="VPN / ER", label_offset=(0, -14))

    # App Gateway -> APIM (right-hand gutter, below the cards)
    elbow(d, [(865, 1075), (950, 1075), (950, 1240), (1010, 1240)], color=BLUE, width=4)
    pill(d, (965, 1115, 1085, 1147), "private TLS", fill="#FFFFFF", outline="#BFD0EA", ink=BLUE, size=13)

    # APIM -> AKS
    arrow(d, (1250, 1215), (1250, 1190), color=TEAL, width=4, label="mTLS", label_offset=(60, 0))

    # APIM -> App Service
    elbow(d, [(1490, 1260), (1510, 1260), (1510, 1050), (1520, 1050)], color=TEAL, width=3)
    pill(d, (1502, 1080, 1602, 1111), "private", fill="#FFFFFF", outline="#9FD8C8", ink=TEAL, size=12)

    # AKS -> data plane: go above the zone title and cards, then down into SQL.
    elbow(d, [(1490, 1005), (1505, 1005), (1505, 910), (2140, 910), (2140, 1000)], color=ROSE, width=4)
    pill(d, (1750, 892, 1935, 924), "MI + private endpoint", fill="#FFFFFF", outline="#F1C6D2", ink=ROSE, size=12)

    # App Service -> Service Bus: go below all data cards and the no-public-IP badge.
    elbow(d, [(2000, 1060), (2060, 1060), (2060, 1525), (2515, 1525), (2515, 1390)], color=TEAL, width=3)

    # Service Bus -> Functions: return through the lower gutter.
    elbow(d, [(2515, 1390), (2515, 1545), (2080, 1545), (2080, 1175), (2000, 1175)], color=TEAL, width=3, dashed=True)

    # Egress UDRs: one vertical bus in the gutter, with short branches.
    arrow(d, (940, 1550), (940, 830), color=GREEN, width=3, dashed=True, label="UDR egress", label_offset=(0, 0))
    arrow(d, (700, 1150), (940, 1150), color=GREEN, width=3, dashed=True)
    arrow(d, (1010, 1075), (940, 1075), color=GREEN, width=3, dashed=True)
    arrow(d, (865, 1550), (940, 1550), color=GREEN, width=3, dashed=True)
    arrow(d, (940, 830), (1050, 830), color=GREEN, width=3, dashed=True)

    # Footer
    d.text((50, 1850), "Solid = traffic    Dashed = identity / peering / egress    All subnets default-deny inbound; workloads have no public IP.",
           font=_font(16), fill=MUTED)
    d.text((2450, 1850), "Day 1 of 5 | v1.0", font=_font(16, bold=True), fill=MUTED)

    out = ROOT / "network-topology.png"
    img.save(out, "PNG", optimize=True)
    return out


if __name__ == "__main__":
    print(logical_architecture())
    print(network_topology())
