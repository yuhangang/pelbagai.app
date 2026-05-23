---
name: qr-code
description: Generates QR codes for target URLs, Contact Cards, or custom texts.
---

You are a QR Code Generator assistant.
Help the user formulate custom payload structures (URLs, Contact Cards, Wi-Fi configuration details) to embed in QR codes.
Instruct the user on how the dense matrix barcode format handles error correction levels (L, M, Q, H).

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    body {
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 12px;
      background: transparent;
      color: #1c1c1e;
      text-align: center;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .dark-mode {
      color: #f2f2f7;
    }
    .card {
      background: rgba(255, 255, 255, 0.5);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border-radius: 24px;
      padding: 20px;
      border: 1px solid rgba(255, 255, 255, 0.5);
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.06);
      width: 100%;
      max-width: 280px;
      margin: 0 auto;
      box-sizing: border-box;
      transition: all 0.3s ease;
    }
    .dark-mode .card {
      background: rgba(28, 28, 30, 0.6);
      border-color: rgba(255, 255, 255, 0.08);
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
    }
    .qr-container {
      position: relative;
      width: 150px;
      height: 150px;
      margin: 12px auto;
      background: linear-gradient(135deg, #007aff, #00c6ff);
      padding: 3px;
      border-radius: 20px;
      box-shadow: 0 8px 24px rgba(0, 122, 255, 0.15);
      transition: transform 0.2s ease, box-shadow 0.2s ease;
      cursor: pointer;
      -webkit-tap-highlight-color: transparent;
    }
    .dark-mode .qr-container {
      background: linear-gradient(135deg, #0a84ff, #30d158);
      box-shadow: 0 8px 24px rgba(10, 132, 255, 0.25);
    }
    .qr-container:hover {
      transform: scale(1.03);
      box-shadow: 0 12px 32px rgba(0, 122, 255, 0.25);
    }
    .qr-container:active {
      transform: scale(0.96);
    }
    .qr-img {
      width: 100%;
      height: 100%;
      display: block;
      border-radius: 17px;
      background: white;
      box-sizing: border-box;
      transition: transform 0.15s ease;
    }
    .label {
      font-size: 13px;
      font-weight: 500;
      word-break: break-all;
      opacity: 0.9;
      margin-bottom: 8px;
      color: #3a3a3c;
      line-height: 1.4;
    }
    .dark-mode .label {
      color: #e5e5ea;
    }
    .hint {
      font-size: 10px;
      font-weight: 500;
      color: #8e8e93;
      margin-bottom: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 4px;
    }
    .save-btn {
      background: linear-gradient(135deg, #007aff, #0056b3);
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 12px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      transition: all 0.2s ease;
      box-shadow: 0 4px 12px rgba(0, 122, 255, 0.3);
      width: 100%;
      box-sizing: border-box;
    }
    .save-btn:hover {
      transform: translateY(-1px);
      box-shadow: 0 6px 16px rgba(0, 122, 255, 0.4);
    }
    .save-btn:active {
      transform: translateY(1px) scale(0.98);
    }
    .dark-mode .save-btn {
      background: linear-gradient(135deg, #0a84ff, #0056b3);
      box-shadow: 0 4px 12px rgba(10, 132, 255, 0.3);
    }
    .svg-icon {
      width: 14px;
      height: 14px;
      fill: none;
      stroke: currentColor;
      stroke-width: 2.5;
      stroke-linecap: round;
      stroke-linejoin: round;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="qr-container" id="qrContainer">
      <img class="qr-img" id="qr" onload="onQrLoad()" alt="QR Code" />
    </div>
    <div class="label" id="label">Generating...</div>
    <button class="save-btn" id="saveBtn" onclick="saveQR()" style="display: none; margin-top: 8px;">
      <svg class="svg-icon" viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
      Save QR Code
    </button>
  </div>
  <script>
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      document.body.classList.add('dark-mode');
    }
    
    function onQrLoad() {
      const qrSrc = document.getElementById('qr').src;
      if (!qrSrc || qrSrc === "" || qrSrc === window.location.href) {
        return;
      }
      document.getElementById('saveBtn').style.display = 'inline-flex';
    }
    
    function saveQR() {
      const qrSrc = document.getElementById('qr').src;
      if (!qrSrc || qrSrc === "" || qrSrc === window.location.href) {
        return;
      }
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
        window.webkit.messageHandlers.pelbagaiBridge.postMessage({
          type: 'saveImage',
          url: qrSrc
        });
      }
    }
    
    window.executeSkill = function(input) {
      const json = JSON.parse(input);
      const text = json.text || json.url || 'Hello';
      document.getElementById('qr').src = `https://api.qrserver.com/v1/create-qr-code/?size=1080x1080&data=${encodeURIComponent(text)}`;
      document.getElementById('label').innerText = text;
      
      setTimeout(() => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
          window.webkit.messageHandlers.pelbagaiBridge.postMessage(document.documentElement.outerHTML);
        }
      }, 500);
    };
  </script>
</body>
</html>
```
```
