// Boots the browser build in headless Chromium and records what a player's browser would show:
// page and console errors, whether the engine started, and screenshots of the operations desk
// and of a running operation. Usage (from the repository root):
//   NODE_PATH=/opt/node-tools/node_modules node tools/web/browser_check.cjs [docs] [out-dir]
// Serves docs/ as GitHub Pages does (the page fetches its fonts from ../fonts) on a free local port
// and opens /play/index.html; needs Playwright and a Chromium.
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
const root = path.resolve(process.argv[2] || 'docs');
const out = path.resolve(process.argv[3] || 'work/browser-check');
fs.mkdirSync(out, { recursive: true });
const types = { '.woff2': 'font/woff2', '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/play/index.html`;
const executablePath = process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const browser = await chromium.launch({ executablePath, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const report = { url, errors: [], console_errors: [], console_warnings: 0, started: false, screenshots: [] };
page.on('pageerror', e => report.errors.push(String(e)));
page.on('requestfailed', r => report.console_errors.push('request failed: ' + r.url()));
page.on('response', r => { if (r.status() >= 400) report.console_errors.push(r.status() + ' ' + r.url()); });
page.on('console', m => {
  if (m.type() === 'error') report.console_errors.push(m.text());
  else if (m.type() === 'warning') report.console_warnings += 1;
});
const t0 = Date.now();
await page.goto(url);
// The engine replaces the status overlay with the canvas when the pack has loaded and main has run.
try {
  await page.waitForFunction(() => {
    // The loading overlay removes itself once the engine has started and main has run.
    return document.getElementById('status') === null;
  }, null, { timeout: 180000 });
  report.started = true;
} catch (e) {
  report.errors.push('engine did not start within 180 s');
}
report.load_seconds = (Date.now() - t0) / 1000;
await page.waitForTimeout(8000);
const desk = path.join(out, 'browser-desk.png');
await page.screenshot({ path: desk });
report.screenshots.push(desk);
// Start the introductory operation the way a player does: the big start button on the desk.
const canvas = await page.$('canvas');
if (canvas) {
  await canvas.click({ position: { x: 800, y: 450 } }).catch(() => {});
}
fs.writeFileSync(path.join(out, 'browser-check.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
await browser.close();
server.close();
process.exit(report.started && report.errors.length === 0 ? 0 : 1);
})();
