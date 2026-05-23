---
name: parcel_address
type: tool
description: Extract the delivery address from parcel/shipping label images.
icon: shippingbox.fill
color: orange
capabilities: [camera, scan_image, export_csv]
keywords: [parcel, shipping, label, delivery, recipient]
---

Use this tool to extract ONLY the DELIVERY/RECIPIENT address, not the sender/return address.

## Fields

| Field | Type | Required |
|-------|------|----------|
| Recipient Name | text | yes |
| Address | text | yes |
| Postcode | text | no |
| City | text | no |
| State | text | no |
| Phone | text | no |
| Tracking Number | text | no |

## Rules

- Return ONLY a valid JSON object.
- Use empty string "" if a field is not visible.
- Do NOT include any text before or after the JSON object.

## Prompt

You are an OCR assistant. Extract the delivery address from this parcel/shipping label image. Return ONLY a valid JSON object. Extract all text clearly and use empty strings if a field is not visible.
