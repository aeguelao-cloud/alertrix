const fs = require("fs");
const http = require("http");
const path = require("path");
const { chromium } = require("playwright");

const root = process.cwd();
const webRoot = path.join(root, "build", "web");
const outDir = "F:\\403\\report_screenshots_current_ui";
const port = 18091;

fs.mkdirSync(outDir, { recursive: true });

let scenario = "normal";
let currentTrendRange = "1H";
let currentTrendMetric = "Water Level";
const now = () => new Date();
const iso = (d) => d.toISOString();

function sensorValues() {
  if (scenario === "critical") {
    return {
      waterLevel: 91,
      vibration: 4.4,
      temperature: 38.2,
    };
  }
  if (scenario === "warning") {
    return {
      waterLevel: 74,
      vibration: 3.1,
      temperature: 35.8,
    };
  }
  return {
    waterLevel: 46,
    vibration: 1.2,
    temperature: 29.4,
  };
}

function levelFor(sensorType, value) {
  if (sensorType === "waterLevel") {
    if (value >= 85) return "CRITICAL";
    if (value >= 70) return "WARNING";
    return "NORMAL";
  }
  if (sensorType === "vibration") {
    if (value >= 4.0) return "CRITICAL";
    if (value >= 2.8) return "WARNING";
    return "NORMAL";
  }
  if (sensorType === "temperature") {
    if (value >= 40) return "CRITICAL";
    if (value >= 35) return "WARNING";
    return "NORMAL";
  }
  return "NORMAL";
}

function zoneFor(sensorType) {
  return {
    waterLevel: "Zone A - Pump Station",
    vibration: "Zone D - Motor Room",
    temperature: "Zone C - Generator Bay",
  }[sensorType] || "Unknown Zone";
}

function latestReadings() {
  const values = sensorValues();
  const t = iso(now());
  return {
    siteName: "Pilot Monitoring Site",
    updatedAt: t,
    readings: Object.entries(values).map(([sensorType, value]) => ({
      sensorType,
      value,
      unit:
        sensorType === "waterLevel"
          ? "%"
          : sensorType === "vibration"
            ? "mm/s RMS"
            : "deg C",
      zone: zoneFor(sensorType),
      capturedAt: t,
    })),
  };
}

function alerts() {
  const values = sensorValues();
  const t = now();
  const list = [];
  for (const [sensorType, value] of Object.entries(values)) {
    const sev = levelFor(sensorType, value);
    if (sev === "NORMAL") continue;
    const unit =
      sensorType === "waterLevel"
        ? "%"
        : sensorType === "vibration"
          ? " mm/s RMS"
          : " deg C";
    list.push({
      alertId: `${scenario}-${sensorType}-001`,
      title: `${labelFor(sensorType)} ${sev === "CRITICAL" ? "critical threshold exceeded" : "warning threshold reached"}`,
      severity: sev,
      status: "ACTIVE",
      detectedAt: iso(new Date(t.getTime() - list.length * 90_000)),
      zone: zoneFor(sensorType),
      triggerValue:
        sensorType === "waterLevel"
          ? `${value.toFixed(0)}%`
          : `${value.toFixed(1)}${unit}`,
      updatedAt: iso(t),
      updatedByRole: "System",
    });
  }
  return { items: list };
}

function labelFor(sensorType) {
  return {
    waterLevel: "Water Level",
    vibration: "Vibration",
    temperature: "Temperature",
  }[sensorType] || sensorType;
}

function metricToSensor(metric) {
  return {
    water_level: "waterLevel",
    vibration: "vibration",
    temperature: "temperature",
  }[metric] || "waterLevel";
}

function pointsForRange(range) {
  return {
    "1h": 8,
    "6h": 16,
    "24h": 24,
    "7d": 48,
    "14d": 84,
    "30d": 120,
  }[range] || 8;
}

function durationMs(range) {
  return {
    "1h": 60 * 60_000,
    "6h": 6 * 60 * 60_000,
    "24h": 24 * 60 * 60_000,
    "7d": 7 * 24 * 60 * 60_000,
    "14d": 14 * 24 * 60 * 60_000,
    "30d": 30 * 24 * 60 * 60_000,
  }[range] || 60 * 60_000;
}

function trendSeries(metric, range) {
  const sensor = metricToSensor(metric);
  const count = pointsForRange(range);
  const end = Date.now();
  const span = durationMs(range);
  const cfg = {
    waterLevel: { base: 54, warn: 70, crit: 85, amp: 8, decimals: 0 },
    vibration: { base: 1.45, warn: 2.8, crit: 4.0, amp: 0.48, decimals: 1 },
    temperature: { base: 30.2, warn: 35, crit: 40, amp: 1.65, decimals: 1 },
  }[sensor] || { base: 50, warn: 70, crit: 85, amp: 6, decimals: 0 };
  const sensorPhase = sensor === "waterLevel" ? 0 : sensor === "vibration" ? 0.37 : 0.71;
  const series = [];
  for (let i = 0; i < count; i++) {
    const ratio = count === 1 ? 1 : i / (count - 1);
    const timestamp = new Date(end - span + span * ratio);
    const noise = Math.sin((i + 1) * 1.91 + sensorPhase) * cfg.amp * 0.12;
    const pulse = Math.max(0, 1 - Math.abs(ratio - 0.72) / 0.09) * cfg.amp * 1.15;
    const latePulse = Math.max(0, 1 - Math.abs(ratio - 0.88) / 0.08) * cfg.amp * 0.85;
    let value;
    switch (range) {
      case "1h":
        // Short-window incident: mostly stable, then a sharp late rise.
        value =
          cfg.base +
          cfg.amp * 0.18 * Math.sin(ratio * Math.PI * 3 + sensorPhase) +
          Math.pow(ratio, 5) * (cfg.warn - cfg.base + cfg.amp * 0.8) +
          noise;
        break;
      case "6h":
        // Gradual build-up across several hours.
        value =
          cfg.base +
          ratio * (cfg.warn - cfg.base + cfg.amp * 0.35) +
          cfg.amp * 0.45 * Math.sin(ratio * Math.PI * 2.2 + sensorPhase) +
          noise;
        break;
      case "24h":
        // Day profile: two visible peaks and a warning-level ending.
        value =
          cfg.base +
          cfg.amp * 0.55 * Math.sin(ratio * Math.PI * 4.2 + sensorPhase) +
          pulse +
          latePulse * 0.55 +
          ratio * cfg.amp * 0.35 +
          noise;
        break;
      case "7d":
        // Weekly profile: stepped increase after several normal days.
        value =
          cfg.base +
          Math.floor(ratio * 5) * cfg.amp * 0.38 +
          cfg.amp * 0.35 * Math.sin(ratio * Math.PI * 5 + sensorPhase) +
          (ratio > 0.66 ? cfg.warn - cfg.base - cfg.amp * 0.35 : 0) +
          noise;
        break;
      case "14d":
        // Fortnight profile: slow oscillation, recovery, then renewed warning.
        value =
          cfg.base +
          cfg.amp * 0.75 * Math.sin(ratio * Math.PI * 3.2 + sensorPhase) +
          cfg.amp * 0.42 * Math.sin(ratio * Math.PI * 8.0) +
          ratio * (cfg.warn - cfg.base) * 0.8 +
          (ratio > 0.74 ? cfg.amp * 1.1 : 0) +
          noise;
        break;
      case "30d":
        // Long-window profile: month-long drift with a mid-period dip and late plateau.
        value =
          cfg.base +
          ratio * (cfg.warn - cfg.base + cfg.amp * 0.25) -
          Math.max(0, 1 - Math.abs(ratio - 0.45) / 0.16) * cfg.amp * 0.9 +
          cfg.amp * 0.32 * Math.sin(ratio * Math.PI * 6 + sensorPhase) +
          noise;
        break;
      default:
        value = cfg.base + ratio * (cfg.warn - cfg.base) + noise;
    }
    if (i === count - 1) {
      value = cfg.warn + cfg.amp * 0.24;
    }
    value = Math.min(cfg.crit - cfg.amp * 0.25, Math.max(cfg.base - cfg.amp * 0.8, value));
    series.push({
      timestamp: iso(timestamp),
      value: Number(value.toFixed(cfg.decimals)),
    });
  }
  return { metric, range, series };
}

function workOrders() {
  return {
    items: [
      {
        workOrderId: "WO-403-001",
        alertId: `${scenario === "normal" ? "warning" : scenario}-waterLevel-001`,
        status: "OPEN",
        assignee: "Emergency Team",
        note: "Inspect pump station and verify water level reading.",
        createdAt: iso(new Date(Date.now() - 20 * 60_000)),
        updatedAt: iso(now()),
      },
      {
        workOrderId: "WO-403-002",
        alertId: `${scenario === "critical" ? "critical" : "warning"}-vibration-001`,
        status: "CLOSED",
        assignee: "Maintenance Team",
        note: "Review vibration condition at motor room.",
        createdAt: iso(new Date(Date.now() - 55 * 60_000)),
        updatedAt: iso(new Date(Date.now() - 12 * 60_000)),
      },
    ],
  };
}

function admins() {
  return {
    items: [
      {
        adminId: "admin-001",
        name: "System Administrator",
        email: "admin@alertrix.local",
        role: "admin",
        status: "active",
        active: true,
        createdAt: iso(new Date(Date.now() - 86_400_000)),
        updatedAt: iso(now()),
      },
      {
        adminId: "admin-002",
        name: "Response Coordinator",
        email: "coordinator@alertrix.local",
        role: "admin",
        status: "active",
        active: true,
        createdAt: iso(new Date(Date.now() - 50_400_000)),
        updatedAt: iso(now()),
      },
    ],
  };
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id,X-User-Role",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
  });
  res.end(JSON.stringify(body));
}

function serveStatic(req, res) {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  let filePath = decodeURIComponent(url.pathname);
  if (filePath === "/") filePath = "/index.html";
  const abs = path.normalize(path.join(webRoot, filePath));
  if (!abs.startsWith(webRoot)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  fs.readFile(abs, (err, data) => {
    if (err) {
      fs.readFile(path.join(webRoot, "index.html"), (indexErr, indexData) => {
        if (indexErr) {
          res.writeHead(404);
          res.end("Not found");
        } else {
          res.writeHead(200, { "Content-Type": "text/html" });
          res.end(indexData);
        }
      });
      return;
    }
    const ext = path.extname(abs).toLowerCase();
    const type =
      ext === ".html"
        ? "text/html"
        : ext === ".js"
          ? "application/javascript"
          : ext === ".css"
            ? "text/css"
            : ext === ".wasm"
              ? "application/wasm"
              : ext === ".png"
                ? "image/png"
                : "application/octet-stream";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  if (req.method === "OPTIONS") return sendJson(res, 200, {});
  if (url.pathname === "/__scenario") {
    scenario = url.searchParams.get("name") || "normal";
    return sendJson(res, 200, { scenario });
  }
  if (url.pathname === "/api/readings/latest") return sendJson(res, 200, latestReadings());
  if (url.pathname === "/api/alerts") return sendJson(res, 200, alerts());
  if (url.pathname === "/api/trends") {
    return sendJson(
      res,
      200,
      trendSeries(url.searchParams.get("metric") || "water_level", url.searchParams.get("range") || "1h"),
    );
  }
  if (url.pathname === "/api/work-orders") return sendJson(res, 200, workOrders());
  if (url.pathname === "/api/admins") return sendJson(res, 200, admins());
  if (url.pathname === "/api/settings/notifications") {
    return sendJson(res, 200, {
      pushRule: "Warning + Critical",
      alertSoundEnabled: true,
      notificationEmail: "response.team@alertrix.local",
      emailSubscriptionStatus: "Confirmed",
    });
  }
  if (url.pathname === "/api/settings/device-location") {
    return sendJson(res, 200, { location: "Zone A - Pump Station" });
  }
  if (url.pathname === "/api/auth/login") {
    return sendJson(res, 200, {
      user: {
        username: "operator",
        email: "operator@alertrix.local",
        role: "User",
      },
    });
  }
  if (url.pathname.startsWith("/api/")) return sendJson(res, 200, { ok: true, item: {} });
  return serveStatic(req, res);
});

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function tryClick(locator) {
  try {
    await locator.click({ timeout: 2500 });
    return true;
  } catch (_) {
    return false;
  }
}

async function clickTextOrPoint(page, text, x, y) {
  if (await tryClick(page.getByText(text, { exact: true }).first())) return;
  await page.mouse.click(x, y);
}

async function openDashboard(page, role = "admin") {
  await page.goto(`http://127.0.0.1:${port}/?role=${role}`, { waitUntil: "load" });
  await wait(2600);
  if (!(await page.getByText("Response Overview", { exact: true }).first().isVisible().catch(() => false))) {
    await login(page, role);
  }
}

async function login(page, role) {
  await page.mouse.click(1040, 894);
  await wait(900);

  const email = role === "admin" ? "admin@alertrix.local" : "operator@alertrix.local";
  const password = role === "admin" ? "Admin@123" : "User@123";

  await page.mouse.click(960, 533);
  await page.keyboard.press(process.platform === "darwin" ? "Meta+A" : "Control+A");
  await page.keyboard.type(email);
  await page.mouse.click(960, 599);
  await page.keyboard.press(process.platform === "darwin" ? "Meta+A" : "Control+A");
  await page.keyboard.type(password);

  await page.mouse.click(960, 704);
  await wait(2500);
}

async function setScenario(page, name) {
  await page.evaluate(async (target) => {
    await fetch(`/__scenario?name=${encodeURIComponent(target)}`);
  }, name);
  await wait(300);
  if (!(await tryClick(page.getByRole("button", { name: "Refresh" })))) {
    await page.mouse.click(1818, 37);
  }
  await wait(1200);
}

async function nav(page, label, point) {
  if (!(await tryClick(page.getByText(label, { exact: true }).first()))) {
    await page.mouse.click(point.x, point.y);
  }
  await wait(1000);
  if (label === "Situation Trends") {
    currentTrendRange = "1H";
    currentTrendMetric = "Water Level";
  }
}

async function screenshot(page, name, fullPage = false) {
  await page.screenshot({
    path: path.join(outDir, name),
    fullPage,
  });
}

async function selectRange(page, label) {
  // Click the Time Range field, then choose the requested option from the
  // dropdown. Flutter focuses the currently selected item, so move by relative
  // offset instead of using absolute coordinates.
  await page.mouse.click(1500, 370);
  await wait(500);
  const order = ["1H", "6H", "24H", "7D", "14D", "30D"];
  const currentIndex = Math.max(0, order.indexOf(currentTrendRange));
  const targetIndex = Math.max(0, order.indexOf(label));
  const key = targetIndex >= currentIndex ? "ArrowDown" : "ArrowUp";
  for (let i = 0; i < Math.abs(targetIndex - currentIndex); i++) {
    await page.keyboard.press(key);
    await wait(50);
  }
  await page.keyboard.press("Enter");
  currentTrendRange = label;
  await wait(1300);
}

async function selectMetric(page, label) {
  await page.mouse.click(760, 370);
  await wait(500);
  const order = ["Water Level", "Vibration", "Temperature"];
  const currentIndex = Math.max(0, order.indexOf(currentTrendMetric));
  const targetIndex = Math.max(0, order.indexOf(label));
  const key = targetIndex >= currentIndex ? "ArrowDown" : "ArrowUp";
  for (let i = 0; i < Math.abs(targetIndex - currentIndex); i++) {
    await page.keyboard.press(key);
    await wait(60);
  }
  await page.keyboard.press("Enter");
  currentTrendMetric = label;
  await wait(1300);
}

async function codeScreenshot(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 880 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  const lines = fs
    .readFileSync(path.join(root, "backend", "src", "handlers", "ingestSensorData.js"), "utf8")
    .split(/\r?\n/)
    .slice(0, 34);
  const htmlLines = lines
    .map((line, i) => `<div class="line"><span class="ln">${String(i + 1).padStart(4, "0")}:</span><span>${escapeHtml(line || " ")}</span></div>`)
    .join("");
  await page.setContent(`
    <html>
      <head>
        <style>
          body { margin: 0; padding: 24px; background: #eef3f6; font-family: "Times New Roman", serif; }
          #card { width: 1060px; background: #fbfcfd; border: 1px solid #ccd8df; border-radius: 12px; padding: 22px 24px 24px; }
          h1 { margin: 0 0 16px; font: 700 26px/1.2 "Courier New", monospace; color: #1a2b33; }
          pre { margin: 0; font: 600 17px/1.58 "Courier New", monospace; color: #3e5058; white-space: pre; }
          .line { display: flex; gap: 16px; }
          .ln { color: #63747c; width: 58px; flex: none; }
        </style>
      </head>
      <body>
        <div id="card">
          <h1>SensorIngestLambda Handler and Threshold Processing</h1>
          <pre>${htmlLines}</pre>
        </div>
      </body>
    </html>`);
  await page.locator("#card").screenshot({ path: path.join(outDir, "Figure_4_20_lambda_function_gray.png") });
  await context.close();
}

function escapeHtml(text) {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

async function main() {
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  let browser;
  try {
    browser = await chromium.launch({ channel: "msedge", headless: true });
  } catch (_) {
    browser = await chromium.launch({ headless: true });
  }

  try {
    await codeScreenshot(browser);

    const context = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      deviceScaleFactor: 1,
      permissions: ["notifications"],
    });
    const page = await context.newPage();

    await openDashboard(page, "user");
    await setScenario(page, "normal");
    await screenshot(page, "current_user_response_overview_normal.png");

    await nav(page, "Situation Trends", { x: 125, y: 224 });
    await setScenario(page, "warning");
    await screenshot(page, "current_user_trends_1H.png");
    await selectRange(page, "6H");
    await screenshot(page, "current_user_trends_6H.png");
    await selectRange(page, "24H");
    await screenshot(page, "current_user_trends_24H.png");
    await selectRange(page, "7D");
    await screenshot(page, "current_user_trends_7D.png");
    await selectRange(page, "14D");
    await screenshot(page, "current_user_trends_14D.png");
    await selectRange(page, "30D");
    await screenshot(page, "current_user_trends_30D.png");
    await selectRange(page, "24H");
    await selectMetric(page, "Vibration");
    await screenshot(page, "current_user_trends_vibration_24H.png");
    await selectMetric(page, "Temperature");
    await screenshot(page, "current_user_trends_temperature_24H.png");

    await nav(page, "Incident Queue", { x: 130, y: 274 });
    await setScenario(page, "critical");
    await screenshot(page, "current_user_incident_queue_critical.png");
    await nav(page, "Response Settings", { x: 145, y: 324 });
    await screenshot(page, "current_user_response_settings.png");

    await openDashboard(page, "admin");
    await setScenario(page, "normal");
    await screenshot(page, "current_admin_response_overview_normal.png");

    await nav(page, "Response Overview", { x: 148, y: 199 });
    await setScenario(page, "warning");
    await screenshot(page, "current_admin_response_overview_warning.png");

    await setScenario(page, "critical");
    await screenshot(page, "current_admin_response_overview_critical.png");
    await page.mouse.click(1760, 31);
    await wait(700);
    await screenshot(page, "current_alert_popup_dialog.png");
    await page.keyboard.press("Escape");
    await wait(300);
    await nav(page, "Incident Queue", { x: 130, y: 274 });
    await screenshot(page, "current_admin_incident_queue_critical_warning.png");
    await nav(page, "Work Orders", { x: 145, y: 324 });
    await screenshot(page, "current_admin_work_orders.png");
    await nav(page, "Response Settings", { x: 145, y: 374 });
    await screenshot(page, "current_admin_response_settings.png");
    await nav(page, "Admin Management", { x: 151, y: 424 });
    await screenshot(page, "current_admin_management.png");

    await context.close();
  } finally {
    if (browser) await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
