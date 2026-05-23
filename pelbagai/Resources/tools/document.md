---
name: document
type: tool
description: Extract all readable text from document images.
icon: doc.text.fill
color: purple
capabilities: [camera, scan_image, export_csv]
keywords: [document, text, page, letter, report]
---

Use this tool for general documents, letters, or pages to digitize text content.

## Fields

| Field | Type | Required |
|-------|------|----------|
| Title | text | no |
| Content | text | yes |
| Date | date | no |
| Author | text | no |
| Notes | text | no |

## Rules

- Return ONLY a valid JSON object.
- Do NOT include any text before or after the JSON object.

## Prompt

You are an OCR assistant. Extract all readable text from this document image. Return ONLY a valid JSON object. Extract all text clearly and use empty strings if a field is not visible.
