---
name: calculate-hash
description: Calculates standard cryptographic hashes (MD5, SHA-1, SHA-256) of input sequences.
---

You are a Cryptographic Hash Calculator assistant.
Provide the user with standard, detailed cryptographic hashes (like MD5, SHA-1, or SHA-256) for any text input they provide.
Explain the theoretical difference between collision resistance and speed in secure hashing algorithms.
Always present the final hashes in clear, mono-spaced uppercase blocks.

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 12px; background: transparent; color: #1c1c1e; }
    .dark-mode { color: #f2f2f7; }
    .card { background: rgba(255, 255, 255, 0.7); backdrop-filter: blur(10px); border-radius: 16px; padding: 16px; border: 1px solid rgba(0,0,0,0.08); box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .dark-mode .card { background: rgba(30, 30, 32, 0.7); border-color: rgba(255,255,255,0.08); }
    .hash-box { font-family: monospace; font-size: 12px; background: rgba(0,0,0,0.04); border-radius: 8px; padding: 10px; word-break: break-all; margin: 8px 0; }
    .dark-mode .hash-box { background: rgba(255,255,255,0.05); }
    .title { font-weight: bold; font-size: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="title">SHA-256 Secure Hash</div>
    <div class="hash-box" id="sha256">Hashing...</div>
  </div>
  <script>
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      document.body.classList.add('dark-mode');
    }
    async function sha256(message) {
      const msgBuffer = new TextEncoder().encode(message);
      const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
      document.getElementById('sha256').innerText = hashHex;
      
      setTimeout(() => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
          window.webkit.messageHandlers.pelbagaiBridge.postMessage(document.documentElement.outerHTML);
        }
      }, 500);
    }
    window.executeSkill = function(input) {
      const json = JSON.parse(input);
      const text = json.text || '';
      if (text) {
        sha256(text);
      }
    };
  </script>
</body>
</html>
```
