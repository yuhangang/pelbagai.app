---
name: receipt
type: tool
description: Extract key information from receipt images.
icon: receipt
color: green
capabilities: [camera, scan_image, export_csv]
chainTo: [expense_report]
keywords: [receipt, bill, invoice, payment, store, expense]
---

Use this tool for retail, dining, or service receipts to track spending, itemized purchases, and taxes.

## Fields

| Field | Type | Required |
|-------|------|----------|
| Store Name | text | yes |
| Address | text | no |
| Date | date | yes |
| Time | text | no |
| Currency | text | yes |
| Total | currency | yes |
| Tax | currency | no |
| Payment Method | text | no |
| Items | list | yes |

## Rules

- Return ONLY a valid JSON object.
- Extract individual line items into the 'Items' array.
- For each item, include the name and price if possible (e.g., 'Apple - $1.50').
- Identify the currency symbol or code.
- Capture both Date and Time if visible.
- Do NOT include any text before or after the JSON object.

## Prompt

You are a specialized financial OCR assistant. Your task is to digitize this receipt. Extract the merchant name, full address, date/time, and a detailed list of all items purchased. Ensure the Total accurately reflects the final amount paid including taxes and tips.

## Examples

### Example 1

| Field | Value |
|-------|-------|
| Store Name | Whole Foods Market |
| Address | 2501 Pennsylvania Ave NW, Washington, DC 20037 |
| Date | 2024-05-12 |
| Time | 14:35 |
| Currency | USD |
| Total | $42.15 |
| Tax | $2.15 |
| Payment Method | Visa ****1234 |
| Items | Organic Bananas - $2.50, Almond Milk - $4.99, Whole Wheat Bread - $3.50, Avocados (3) - $6.00 |
