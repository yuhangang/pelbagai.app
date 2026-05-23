---
name: custom
type: tool
description: Extract all readable text and structured information from any image.
icon: sparkles
color: cyan
capabilities: [camera, scan_image, export_csv, persistent_state]
keywords: [receipt, inventory, stock, product, price]
---

Use this tool when the user scans receipts, stock sheets, labels, or product tables. The AI has full flexibility to choose the extraction schema.

## Fields

| Field | Type | Required |
|-------|------|----------|

## Rules

- Return only valid JSON.
- Never include executable code.
- Use _state only for durable cross-scan memory.
- Use _actions only for declarative user-approved actions.

## Prompt

You are an advanced OCR assistant. Extract all readable text and structured information from this image. Return ONLY a valid JSON object. You have full flexibility to choose the schema. REQUIRED META KEYS: _isValid, _validationNotes, _scriptNotes, _state, _actions.

## State

| Key | Type | Description |
|-----|------|-------------|
| lastStore | text | Most recent merchant scanned |
| runningTotal | text | Cumulative spend across scans |
| scanCount | text | Number of scans performed |
