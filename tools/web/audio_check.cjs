// Verify audible crew reports in the exported game, with browser speech deliberately unavailable.
// Paused navigation orders isolate the voice from ambience and the very short console click.
// CHROMIUM=/usr/bin/chromium node tools/web/audio_check.cjs [docs] [work/browser-audio]
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const root = path.resolve(process.argv[2] || 'docs');
  const out = path.resolve(process.argv[3] || 'work/browser-audio');
  fs.mkdirSync(out, { recursive: true });
  const report = { checks: {}, page_errors: [], console_errors: [] };
  const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.pck': 'application/octet-stream', '.woff2': 'font/woff2' };
  const server = http.createServer((req, res) => {
    const file = path.resolve(root, '.' + decodeURIComponent(req.url.split('?')[0]));
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({ executablePath: process.env.CHROMIUM || '/usr/bin/chromium', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
    const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
    page.on('pageerror', e => report.page_errors.push(String(e)));
    page.on('console', m => { if (m.type() === 'error') report.console_errors.push(m.text()); });
    page.on('requestfailed', req => report.console_errors.push('request failed: ' + req.url()));
    await page.addInitScript(() => {
      window.audioProbe = { samples: [], tts_calls: 0, contexts: [], errors: [] };
      window.speechSynthesis.speak = () => { window.audioProbe.tts_calls++; };
      // Meter on the audio thread: a slow software-rendered frame must not hide a short report.
      const meterCode = `class Meter extends AudioWorkletProcessor {
        constructor() { super(); this.sum = 0; this.peak = 0; this.count = 0; }
        process(inputs, outputs) {
          const channels = inputs[0];
          for (let c = 0; c < outputs[0].length; c++) {
            if (channels[c]) outputs[0][c].set(channels[c]);
          }
          if (channels[0]) for (const sample of channels[0]) {
            this.sum += sample * sample; this.peak = Math.max(this.peak, Math.abs(sample)); this.count++;
          }
          if (this.count >= 2048) {
            this.port.postMessage({ time: currentTime, rms: Math.sqrt(this.sum / this.count), peak: this.peak, frames: this.count });
            this.sum = 0; this.peak = 0; this.count = 0;
          }
          return true;
        }
      }; registerProcessor('fleet-audio-meter', Meter);`;
      const meterUrl = URL.createObjectURL(new Blob([meterCode], { type: 'text/javascript' }));
      const connect = AudioNode.prototype.connect;
      const modules = new WeakMap();
      AudioNode.prototype.connect = function(destination, ...args) {
        if (destination instanceof AudioDestinationNode) {
          const ctx = this.context;
          const link = ctx.createGain();
          connect.call(this, link);
          connect.call(link, destination);
          if (!modules.has(ctx)) {
            const id = window.audioProbe.contexts.length;
            window.audioProbe.contexts.push({ id, ctx });
            modules.set(ctx, { id, ready: ctx.audioWorklet.addModule(meterUrl) });
          }
          const { id, ready } = modules.get(ctx);
          ready.then(() => {
            const tap = new AudioWorkletNode(ctx, 'fleet-audio-meter');
            tap.port.onmessage = event => audioProbe.samples.push({ ...event.data, context: id });
            link.disconnect(destination);
            connect.call(link, tap);
            connect.call(tap, destination);
          }).catch(e => audioProbe.errors.push(String(e)));
          return destination;
        }
        return connect.call(this, destination, ...args);
      };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/play/index.html`);
    await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 180000 });
    await page.waitForTimeout(7000);
    await page.click('canvas', { position: { x: 5, y: 5 } });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(3000);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(5000);
    // TAKE COMMAND starts the clock. Pause and let the machinery fade before sampling an order.
    await page.keyboard.press('Space');
    await page.waitForTimeout(3500);
    report.before_order = await page.evaluate(() => ({
      samples: audioProbe.samples.length,
      active_windows: audioProbe.samples.filter(s => s.rms > 0.002).length,
      peak: Math.max(0, ...audioProbe.samples.map(s => s.peak)),
    }));
    const before = await page.evaluate(() => Object.fromEntries(audioProbe.contexts.map(({ id, ctx }) => [id, ctx.currentTime])));
    await page.mouse.click(1050, 80, { button: 'right' });
    await page.waitForTimeout(5000);
    await page.screenshot({ path: path.join(out, 'paused-order.png') });
    const first = await page.evaluate(t => ({ samples: audioProbe.samples.filter(s => s.time >= t[s.context]), states: audioProbe.contexts.map(c => c.ctx.state) }), before);
    report.order_audio = { active_windows: first.samples.filter(s => s.rms > 0.002).length, peak: Math.max(0, ...first.samples.map(s => s.peak)), context_states: first.states };
    report.checks['Web Audio runs after player input'] = first.states.length > 0 && first.states.every(s => s === 'running');
    report.checks['a paused order produces a full spoken report'] = report.order_audio.active_windows >= 12;
    await page.keyboard.press('Control+m');
    await page.waitForTimeout(400);
    const mutedAt = await page.evaluate(() => Object.fromEntries(audioProbe.contexts.map(({ id, ctx }) => [id, ctx.currentTime])));
    await page.mouse.click(1030, 100, { button: 'right' });
    await page.waitForTimeout(1500);
    const muted = await page.evaluate(t => audioProbe.samples.filter(s => s.time >= t[s.context]), mutedAt);
    report.muted_peak = Math.max(0, ...muted.map(s => s.peak));
    report.checks['master mute silences orders and speech'] = muted.length > 0 && report.muted_peak < 0.0001;
    await page.keyboard.press('Control+m');
    await page.waitForTimeout(500);
    const restoredAt = await page.evaluate(() => Object.fromEntries(audioProbe.contexts.map(({ id, ctx }) => [id, ctx.currentTime])));
    await page.mouse.click(1070, 100, { button: 'right' });
    await page.waitForTimeout(5000);
    await page.screenshot({ path: path.join(out, 'unmuted-order.png') });
    const restored = await page.evaluate(t => audioProbe.samples.filter(s => s.time >= t[s.context]), restoredAt);
    report.restored_active_windows = restored.filter(s => s.rms > 0.002).length;
    report.checks['unmuting restores recorded crew reports'] = report.restored_active_windows >= 12;
    report.tts_calls = await page.evaluate(() => audioProbe.tts_calls);
    report.probe_errors = await page.evaluate(() => audioProbe.errors);
    report.checks['audio-thread probe installed'] = report.probe_errors.length === 0;
    report.checks['no operating-system speech calls'] = report.tts_calls === 0;
    report.checks['no clipped browser output'] = Math.max(report.order_audio.peak, ...restored.map(s => s.peak)) < 0.99;
    report.checks['no browser errors'] = report.page_errors.length === 0 && report.console_errors.length === 0;
  } catch (error) {
    report.page_errors.push(String(error));
    report.checks['browser audio walkthrough completes'] = false;
  } finally {
    if (browser) await browser.close();
    server.close();
    fs.writeFileSync(path.join(out, 'audio-check.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = Object.values(report.checks).every(Boolean) ? 0 : 1;
  }
})();
