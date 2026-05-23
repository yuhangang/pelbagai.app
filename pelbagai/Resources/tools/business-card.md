---
name: business_card
type: tool
description: Extract contact information from business card images.
icon: person.crop.rectangle.fill
color: blue
capabilities: [camera, scan_image, export_csv]
keywords: [business card, contact, person, email, phone, linkedin]
---

Use this tool to capture professional contact details from physical or digital business cards with high precision.

## Fields

| Field | Type | Required |
|-------|------|----------|
| Name | text | yes |
| Title | text | no |
| Company | text | no |
| Department | text | no |
| Email | text | no |
| Mobile | text | no |
| Work Phone | text | no |
| Address | text | no |
| Website | url | no |
| Social Media | list | no |

## Rules

- Return ONLY a valid JSON object.
- Identify the primary person's name (usually the largest text).
- Clean phone numbers to a standard format (e.g., +1 555-123-4567).
- If multiple phone numbers exist, use 'Mobile' and 'Work Phone' appropriately.
- List social media handles or profile URLs in the 'Social Media' array.
- Use empty string "" for missing fields.
- Do NOT include any text before or after the JSON object.

## Prompt

You are a professional contact extraction assistant. Carefully analyze the business card image. Your goal is to extract ALL professional details with maximum accuracy. Pay close attention to the hierarchy of text to distinguish between the Name, Title, and Company. Extract small details like extensions, department names, and social media icons.

## Examples

### Example 1

| Field | Value |
|-------|-------|
| Name | Sarah Jenkins |
| Title | Senior Account Manager |
| Company | Global Logistics Solutions |
| Department | Sales & Marketing |
| Email | s.jenkins@globallogistics.com |
| Mobile | +1 202-555-0198 |
| Work Phone | +1 202-555-0100 ext. 402 |
| Address | 450 Industrial Way, Suite 200, Seattle, WA 98101 |
| Website | www.globallogistics.com |
| Social Media | linkedin.com/in/sjenkins-logistics, @sjenkins_sales |
