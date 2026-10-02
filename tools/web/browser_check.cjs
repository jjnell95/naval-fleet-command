// Boots the browser build in headless Chromium and records what a player's browser would show:
// page and console errors, whether the engine started, and screenshots of the operations desk
// and of a running operation. It then plays the save path a browser player relies on: open the
// selected operation with the keyboard, take command, quicksave, reload the page, find the save
// still in the browser's storage (IndexedDB behind user://), and load it from Saved Engagements.
// Usage (from the repository root):
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
if (report.started) {
  await playAndSave(page, report, out);
}
fs.writeFileSync(path.join(out, 'browser-check.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
await browser.close();
server.close();
const saved = report.save && report.save.after_reload.length > 0 && report.save.loaded;
process.exit(report.started && saved && report.errors.length === 0 ? 0 : 1);
})();

// Godot's web build keeps user:// in Emscripten's IDBFS: an IndexedDB database named after the
// mount point, one record per file keyed by its full path.
async function savedFiles(page) {
  return page.evaluate(() => new Promise(resolve => {
    const open = indexedDB.open('/userfs');
    open.onerror = () => resolve([]);
    open.onsuccess = () => {
      const db = open.result;
      if (!db.objectStoreNames.contains('FILE_DATA')) { resolve([]); return; }
      const keys = db.transaction('FILE_DATA').objectStore('FILE_DATA').getAllKeys();
      keys.onsuccess = () => resolve(keys.result.map(String).filter(k => k.endsWith('.nfcsave')));
      keys.onerror = () => resolve([]);
    };
  }));
}

async function shot(page, report, out, name) {
  const file = path.join(out, name);
  await page.screenshot({ path: file });
  report.screenshots.push(file);
}

async function waitForEngine(page) {
  await page.waitForFunction(() => document.getElementById('status') === null, null, { timeout: 180000 });
  await page.waitForTimeout(8000);
}

async function playAndSave(page, report, out) {
  report.save = { before: await savedFiles(page), after_save: [], after_reload: [], loaded: false };
  await page.click('canvas', { position: { x: 5, y: 5 } }).catch(() => {});
  // The desk's operation list has focus with its first operation selected; Enter opens its
  // briefing, whose TAKE COMMAND button then has focus.
  await page.keyboard.press('Enter');
  await page.waitForTimeout(4000);
  await shot(page, report, out, 'browser-briefing.png');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(6000);
  await page.keyboard.press('Space');
  await page.waitForTimeout(5000);
  await page.keyboard.press('Space');
  await shot(page, report, out, 'browser-command.png');
  await page.keyboard.press('Control+Shift+S');
  // The engine syncs IDBFS shortly after a file closes.
  await page.waitForTimeout(4000);
  report.save.after_save = await savedFiles(page);
  await page.reload();
  try {
    await waitForEngine(page);
  } catch (e) {
    report.errors.push('engine did not restart after the reload');
    return;
  }
  report.save.after_reload = await savedFiles(page);
  await page.click('canvas', { position: { x: 5, y: 5 } }).catch(() => {});
  await page.keyboard.press('Control+Shift+O');
  await page.waitForTimeout(2500);
  await shot(page, report, out, 'browser-saved-engagements.png');
  // The newest save is selected; Enter loads it.
  const before = await page.screenshot();
  await page.keyboard.press('Enter');
  await page.waitForTimeout(6000);
  await shot(page, report, out, 'browser-restored.png');
  const after = await page.screenshot();
  // The restored command screen replaces the dialog over the desk; an unchanged frame means the
  // load never happened.
  report.save.loaded = Buffer.compare(before, after) !== 0;
}
