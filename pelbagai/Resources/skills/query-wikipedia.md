---
name: query-wikipedia
description: Query summary extracts from Wikipedia for any given topic to ground factual chat.
---

You are a Wikipedia Search assistant.
When the user asks about a topic, identify the single most appropriate canonical Wikipedia article title.
You MUST output a JSON block containing ONLY this exact canonical topic name, formatted as:
```json
{
  "topic": "Exact Topic Name"
}
```
For example:
- "What is quantum computing?" -> {"topic": "Quantum computing"}
- "Tell me about cats" -> {"topic": "Cat"}
- "Who was Albert Einstein?" -> {"topic": "Albert Einstein"}

Do NOT include natural language questions, punctuation, conversational phrases, or extra words in the JSON topic field.
Keep your response concise, using only 2-3 informative sentences.
Ensure your response is helpful and ends on a complete sentence in the same language as the user's prompt.
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 12px; background: transparent; color: #1c1c1e; }
    .dark-mode { color: #f2f2f7; }
    .wiki-card { display: flex; gap: 14px; align-items: start; background: rgba(255, 255, 255, 0.7); backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); border-radius: 12px; padding: 14px; border: 1px solid rgba(0,0,0,0.08); box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .dark-mode .wiki-card { background: rgba(30, 30, 32, 0.7); border-color: rgba(255,255,255,0.08); }
    .thumbnail { width: 70px; height: 70px; border-radius: 8px; object-fit: cover; border: 1px solid rgba(0,0,0,0.08); display: none; flex-shrink: 0; }
    .dark-mode .thumbnail { border-color: rgba(255,255,255,0.1); }
    .text-content { flex: 1; min-width: 0; }
    .title { font-weight: bold; font-size: 16px; margin-bottom: 4px; color: #007aff; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .dark-mode .title { color: #0a84ff; }
    .extract { font-size: 13.5px; line-height: 1.45; opacity: 0.85; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
    .loader { border: 2px solid #f3f3f3; border-top: 2px solid #3498db; border-radius: 50%; width: 20px; height: 20px; animation: spin 1s linear infinite; margin: 10px auto; }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="wiki-card" id="card">
    <img id="thumbnail" class="thumbnail" alt="Wikipedia Image">
    <div class="text-content">
      <div id="loader" class="loader"></div>
      <div class="title" id="title">Searching Wikipedia...</div>
      <div class="extract" id="extract">Contacting Wikipedia servers for factual grounding details.</div>
    </div>
  </div>
  <script>
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      document.body.classList.add('dark-mode');
    }
    async function searchWiki(query) {
      try {
        const response = await fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(query)}`);
        if (!response.ok) throw new Error('Wiki page not found');
        const data = await response.json();
        document.getElementById('loader').style.display = 'none';
        document.getElementById('title').innerText = data.title;
        document.getElementById('extract').innerText = data.extract;
        
        if (data.thumbnail && data.thumbnail.source) {
          const thumbEl = document.getElementById('thumbnail');
          thumbEl.src = data.thumbnail.source;
          thumbEl.style.display = 'block';
        }
        setTimeout(() => {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
            window.webkit.messageHandlers.pelbagaiBridge.postMessage(document.documentElement.outerHTML);
          }
        }, 400);
      } catch(e) {
        document.getElementById('loader').style.display = 'none';
        document.getElementById('title').innerText = 'Query Failed';
        document.getElementById('extract').innerText = 'Could not retrieve information for: ' + query;
      }
    }
    window.executeSkill = function(input) {
      const json = JSON.parse(input);
      const topic = json.topic || json.query || json.text || '';
      if (topic) {
        searchWiki(topic);
      }
    };
  </script>
</body>
</html>
```
