---
name: wikipedia
type: tool
description: Identify subjects from text or images, fetch Wikipedia leads, and support follow-up detail requests.
icon: globe.americas.fill
color: cyan
capabilities: [camera, scan_image, chatbot]
urlTemplate: https://en.wikipedia.org/wiki/{topic}
suggestedPrompts: [Quantum Computing, Renaissance Art, Deep Ocean Exploration, Ancient Pompeii]
keywords: [wiki, wikipedia, search, fact, encyclopedia]
---

You identify the strongest Wikipedia-ready subject from the user's text or image, fetch the article lead, and support deeper follow-up questions about the same topic.

## Fields

| Field | Type | Required |
|-------|------|----------|
| topic | text | yes |
| question | text | no |
| answer | text | no |
| _action | text | no |

## Rules

- Identify the single most significant named subject from the user's input.
- Return the shortest canonical topic suitable for a Wikipedia page.
- Do not add generic suffixes like document, image, photo, logo, sign, label, or text.
- If you can answer the user's question directly using information present in the current chat history, populate the 'answer' field and do not provide an '_action'.
- Use _action 'fetch_wiki' for new topic lookups, and 'wiki_research' ONLY when actual external research is required to find new facts.

## Prompt

Evaluate the user request and act accordingly. Return ONLY valid JSON. Options: 1. New lookup -> {"topic": "Name", "_action": "fetch_wiki"}. 2. Perform deep research for missing info -> {"topic": "Name", "question": "search query", "_action": "wiki_research"}. 3. Answer directly from context -> {"topic": "Name", "answer": "My response."}.

## State

| Key | Type | Description |
|-----|------|-------------|
| last_topic | text | The most recently looked up topic |

## State Bridges

```yaml
- field: topic
  stateKey: last_topic
  fallbackToState: true
  persistToState: true
  sanitizer: subject
```

## Actions

```yaml
fetch_wiki:
  topicField: topic
  fallbackStateKey: last_topic
  request:
    endpoint: https://en.wikipedia.org/api/rest_v1/page/summary/{topic}
    responseMode: text_path
    textPath: extract
    imageURLPath: thumbnail.source
wiki_research:
  topicField: topic
  questionField: question
  fallbackStateKey: last_topic
  request:
    endpoint: https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={topic}%20{question}&format=json
    responseMode: ranked_html_sections
    sectionsPath: query.search
    sectionTitleKey: title
    sectionBodyKey: snippet
    maxSections: 4
    introTemplate: Search results for {topic}{question_clause}:
```
