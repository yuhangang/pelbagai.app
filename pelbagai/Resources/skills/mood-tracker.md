---
name: mood-tracker
description: Interactive mood logging and supportive emotional reflection guidance.
---

You are a Mood Tracker assistant.
Help the user log their feelings, mood, and reflections.
Be highly empathetic, supportive, and non-judgmental.
Ask clarifying questions about their feelings when they offer vague statements, and guide them in positive mental wellness exercises.

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 12px; background: transparent; color: #1c1c1e; text-align: center; }
    .dark-mode { color: #f2f2f7; }
    .card { background: rgba(255, 255, 255, 0.7); backdrop-filter: blur(10px); border-radius: 16px; padding: 16px; border: 1px solid rgba(0,0,0,0.08); box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .dark-mode .card { background: rgba(30, 30, 32, 0.7); border-color: rgba(255,255,255,0.08); }
    .title { font-weight: bold; font-size: 16px; margin-bottom: 12px; }
    .emoji-row { display: flex; justify-content: space-around; margin: 12px 0; }
    .emoji-btn { font-size: 28px; cursor: pointer; transition: transform 0.2s; border: none; background: none; }
    .emoji-btn:hover { transform: scale(1.25); }
    .status-text { font-size: 13px; opacity: 0.8; margin-top: 8px; font-weight: 500; }
  </style>
</head>
<body>
  <div class="card">
    <div class="title">How are you feeling today?</div>
    <div class="emoji-row">
      <button class="emoji-btn" onclick="selectMood('😃', 'Awesome')">😃</button>
      <button class="emoji-btn" onclick="selectMood('😊', 'Good')">😊</button>
      <button class="emoji-btn" onclick="selectMood('😐', 'Okay')">😐</button>
      <button class="emoji-btn" onclick="selectMood('😔', 'Sad')">😔</button>
      <button class="emoji-btn" onclick="selectMood('😠', 'Angry')">😠</button>
    </div>
    <div class="status-text" id="status">Select an emoji to log mood</div>
  </div>
  <script>
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      document.body.classList.add('dark-mode');
    }
    function selectMood(emoji, label) {
      document.getElementById('status').innerText = 'Logged: ' + emoji + ' ' + label;
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
        window.webkit.messageHandlers.pelbagaiBridge.postMessage({
          type: 'moodLogged',
          emoji: emoji,
          label: label
        });
      }
    }
  </script>
</body>
</html>
```
