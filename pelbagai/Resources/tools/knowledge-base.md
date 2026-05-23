---
name: knowledge_base
type: tool
description: Perform semantic search across vectorized local documents.
icon: magnifyingglass.circle.fill
color: indigo
capabilities: [vector_search]
keywords: [search, rag, vector, find, document, survival, guide, text, desert, arctic, jungle, alpine, weather]
---

Use this tool to find reliable survival tips, technical guides, or historical facts from local indexed text documents. Supports diverse terrains (desert, arctic, jungle) and weather conditions.

## Fields

| Field | Type | Required |
|-------|------|----------|
| Subject | text | yes |
| Results | list | yes |
| Source | text | no |

## Rules

- Identify the user's core question.
- Search the knowledge base for the most relevant sections.
- Summarize the findings clearly, citing the source if available.
- If the information is not in the knowledge base, state that clearly.

## Prompt

You are a retrieval assistant. Search for the user's query in the local knowledge base and return the most relevant structured information. For survival queries, prioritize clear, actionable steps.

## State

| Key | Type | Description |
|-----|------|-------------|
| last_query | text | The most recent search query |

## Examples

### Example 1

| Field | Value |
|-------|-------|
| Subject | Wilderness Survival: Essential Tips |
| Results | S.T.O.P. Protocol: Sit down Think Observe and Plan immediately upon realizing you are lost to prevent panic., Shelter Selection: Avoid dead man's zones like lone trees or dry ravines; prioritize insulation using 2-3 feet of debris., Water Purification: Boiling is the gold standard; alternative methods include solar stills and transpiration bags from leafy branches., Friction Fire: Master the Bow Drill method using a spindle hearth board and tinder bundle to create a sustainable ember., Signaling: The Rule of Three (3 fires 3 whistles) is the universal distress signal visible to rescuers. |
| Source | survival_tips_archive.txt |
