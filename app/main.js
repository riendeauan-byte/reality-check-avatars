const { app, BrowserWindow, screen, ipcMain, Tray, Menu, nativeImage } = require("electron");
const { execFile } = require("child_process");
const path = require("path");
const fs = require("fs");

const AUDIO_DIR = path.join(__dirname, "..", "audio"); // <repo>/audio (*.opus)
const AVATARS = ["iron", "hustle", "disciple", "topg", "coach"];

// Domains that trigger the nudge.
const SITES = [
  /instagram\.com/i,
  /youtube\.com/i,
  /tiktok\.com/i,
  /\bx\.com/i,
  /twitter\.com/i,
  /reddit\.com/i,
  /facebook\.com/i,
];

const POLL_MS = 1000;
const COOLDOWN_MS = 60000; // don't re-fire within 60s of arriving

// ---------- settings (persisted) ----------
const SETTINGS_PATH = path.join(app.getPath("userData"), "settings.json");
const DEFAULTS = {
  paused: false,
  onSocials: true, // fire when you open a social site
  periodicOn: true, // also fire on a timer (toggle, keeps the minutes value)
  periodicMinutes: 7, // timer interval in minutes (fixed mode)
  periodicMode: "fixed", // fixed = same gap every time | ramp = gap grows each clip
  rampFirst: 1, // ramp: the first clip comes after this many minutes
  rampAdd: 1, // ramp: minutes added to the gap after each clip
  rampMax: 20, // ramp: the gap stops growing here, then stays
  position: "bottom-right", // bottom-right|bottom-left|top-right|top-left|bottom-center|center
  pauseOnMedia: true, // don't fire while the camera or mic is in use (calls)
  visitCount: 0,
};
let settings = { ...DEFAULTS };

function loadSettings() {
  try {
    settings = { ...DEFAULTS, ...JSON.parse(fs.readFileSync(SETTINGS_PATH, "utf8")) };
  } catch (_) {}
}
let saveT = null;
function saveSettings() {
  clearTimeout(saveT);
  saveT = setTimeout(() => {
    try {
      fs.mkdirSync(path.dirname(SETTINGS_PATH), { recursive: true });
      fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
    } catch (_) {}
  }, 150);
}

let overlay = null;
let dash = null;
let tray = null;
let prevMatch = false;
let lastFire = 0;
let isPlaying = false;
let safetyT = null;
let periodicT = null;
let recent = []; // recently played tracks, to avoid repeats
const NO_REPEAT = 20; // don't replay a track seen in the last N fires (degrades to last-(N-1) on small pools)
let lastAvatar = null; // avatar pool is tiny (5): ban only the previous one

// ---------- camera / mic in-use detection ----------
// A tiny Swift helper reports the hardware "running somewhere" state, so this
// catches ANY app using the camera or mic (Zoom, Meet, FaceTime, etc.), not a
// hard-coded list. No camera/mic permission is needed for that state query.
let mediaActive = false;
const MEDIA_BIN = path.join(__dirname, "sensors", "mediastate");
const MEDIA_SRC = path.join(__dirname, "sensors", "mediastate.swift");
const MEDIA_POLL_MS = 3000;

function ensureMediaBin(cb) {
  if (fs.existsSync(MEDIA_BIN)) return cb(true);
  // Best-effort build (needs Xcode Command Line Tools). If swiftc is missing,
  // the feature just stays off and nothing else is affected.
  execFile("swiftc", ["-O", "-o", MEDIA_BIN, MEDIA_SRC], { timeout: 60000 }, (err) =>
    cb(!err && fs.existsSync(MEDIA_BIN))
  );
}
function pollMedia() {
  execFile(MEDIA_BIN, { timeout: 4000 }, (err, stdout) => {
    if (err) return; // helper unavailable -> leave mediaActive off
    mediaActive = /camera=1|mic=1/.test(stdout || "");
    // If a call starts mid-clip, stop it right away so it doesn't disrupt.
    if (mediaActive && isPlaying && settings.pauseOnMedia) stopOverlay();
  });
}
function startMediaWatch() {
  ensureMediaBin((ok) => {
    if (!ok) return;
    pollMedia();
    setInterval(pollMedia, MEDIA_POLL_MS);
  });
}

function activeDisplay() {
  try {
    return screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  } catch (_) {
    return screen.getPrimaryDisplay();
  }
}

// ---------- overlay (full-screen transparent layer; clip placed via CSS) ----------
function createOverlay() {
  const b = activeDisplay().bounds;
  overlay = new BrowserWindow({
    x: b.x,
    y: b.y,
    width: b.width,
    height: b.height,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    movable: false,
    focusable: false,
    hasShadow: false,
    fullscreenable: false,
    enableLargerThanScreen: true, // allow the window into the Dock's region
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      autoplayPolicy: "no-user-gesture-required",
    },
  });
  overlay.setAlwaysOnTop(true, "floating"); // above content, BELOW the Dock
  overlay.setVisibleOnAllWorkspaces(true, {
    visibleOnFullScreen: true,
    skipTransformProcessType: true,
  });
  overlay.setIgnoreMouseEvents(true); // click-through
  overlay.loadFile(path.join(__dirname, "overlay.html"));
}

// Ask Chrome for the active tab URL. `is running` does NOT launch Chrome.
function chromeURL(cb) {
  execFile(
    "osascript",
    [
      "-e", 'if application "Google Chrome" is not running then return ""',
      "-e", 'tell application "Google Chrome"',
      "-e", "if (count of windows) = 0 then return \"\"",
      "-e", "return URL of active tab of front window",
      "-e", "end tell",
    ],
    { timeout: 2500 },
    (err, stdout) => cb(err ? "" : (stdout || "").trim())
  );
}

function fire(trackName) {
  if (isPlaying || !overlay || settings.paused) return;
  if (settings.pauseOnMedia && mediaActive) return; // don't disrupt a call
  let tracks = [];
  try {
    tracks = fs.readdirSync(AUDIO_DIR).filter((f) => f.endsWith(".opus"));
  } catch (_) {}
  if (!tracks.length) return; // tray tooltip points the user at prep/convert_clips.sh
  isPlaying = true;
  lastFire = Date.now();
  // Random, but never repeat a track from the last NO_REPEAT fires (and so never
  // the same one twice in a row). Fall back gracefully for tiny pools.
  const ban = new Set(recent.slice(-Math.min(NO_REPEAT, tracks.length - 1)));
  let pool = tracks.filter((c) => !ban.has(c));
  if (!pool.length) pool = tracks.filter((c) => c !== recent[recent.length - 1]);
  if (!pool.length) pool = tracks;
  let pick = pool[Math.floor(Math.random() * pool.length)];
  // RC_TEST=<name> / explicit request: play that track if it exists
  if (trackName && typeof trackName === "string") {
    const want = tracks.find((t) => t === trackName || t.includes(trackName));
    if (want) pick = want;
  }
  recent.push(pick);
  if (recent.length > NO_REPEAT * 2) recent = recent.slice(-NO_REPEAT * 2);
  // avatar: random from the 5-character roster, never the same twice in a row
  let avatars = AVATARS.filter((a) => a !== lastAvatar);
  if (!avatars.length) avatars = AVATARS;
  const avatar = avatars[Math.floor(Math.random() * avatars.length)];
  lastAvatar = avatar;
  console.log(`fire: ${pick} as ${avatar}`); // lands in agent.log via launchd
  const src = "file://" + path.join(AUDIO_DIR, pick);
  const b = activeDisplay().bounds;
  overlay.setBounds({ x: b.x, y: b.y, width: b.width, height: b.height });
  overlay.setAlwaysOnTop(true, "floating");
  overlay.setVisibleOnAllWorkspaces(true, {
    visibleOnFullScreen: true,
    skipTransformProcessType: true,
  });
  let pos = settings.position;
  if (pos === "random-corners") {
    const corners = ["bottom-right", "bottom-left", "top-right", "top-left"];
    pos = corners[Math.floor(Math.random() * corners.length)];
  }
  overlay.showInactive();
  overlay.webContents.send("play", { src, position: pos, avatar });
  clearTimeout(safetyT);
  safetyT = setTimeout(() => {
    isPlaying = false;
    if (overlay) overlay.hide();
  }, 75000);
}

ipcMain.on("done", () => {
  clearTimeout(safetyT);
  isPlaying = false;
  if (overlay) overlay.hide();
});

// Stop a clip that's playing right now (used by Pause).
function stopOverlay() {
  clearTimeout(safetyT);
  isPlaying = false;
  if (overlay) {
    overlay.webContents.send("stop"); // pause playback + kill audio at once
    overlay.hide();
  }
}

function bumpVisit() {
  settings.visitCount++;
  saveSettings();
  pushToDash();
  updateTray();
}

function startWatcher() {
  setInterval(() => {
    chromeURL((url) => {
      const match = !!url && SITES.some((r) => r.test(url));
      const now = Date.now();
      if (match && !prevMatch) {
        bumpVisit(); // count every arrival on a social site
        if (!settings.paused && settings.onSocials && now - lastFire > COOLDOWN_MS) {
          lastFire = now;
          fire();
        }
      }
      prevMatch = match;
    });
  }, POLL_MS);
}

const MIN_MS = Number(process.env.RC_MIN_MS) || 60000; // 1 minute (overridable for testing)
let rampWait = 1; // ramp mode: minutes to wait before the next fire

function restartPeriodic() {
  clearInterval(periodicT);
  clearTimeout(periodicT);
  periodicT = null;
  // Any settings change (or app restart) starts the ramp over at its first gap.
  rampWait = Math.max(1, Number(settings.rampFirst) || 1);
  if (!settings.periodicOn) return;
  if (settings.periodicMode === "ramp") {
    scheduleRamp();
  } else {
    const m = Number(settings.periodicMinutes) || 0;
    if (m > 0) {
      periodicT = setInterval(() => {
        if (!settings.paused) fire();
      }, m * 60000);
    }
  }
}

// Ramp mode, three knobs: first gap (rampFirst), minutes added after each
// clip (rampAdd), and where the gap stops growing (rampMax).
function scheduleRamp() {
  const add = Math.max(1, Number(settings.rampAdd) || 1);
  const max = Math.max(1, Number(settings.rampMax) || 20);
  const wait = Math.min(rampWait, max);
  periodicT = setTimeout(() => {
    if (!settings.paused) fire();
    rampWait = Math.min(wait + add, max);
    scheduleRamp();
  }, wait * MIN_MS);
}

// ---------- dashboard window ----------
function openDashboard() {
  if (dash) {
    dash.show();
    dash.focus();
    return;
  }
  dash = new BrowserWindow({
    width: 340,
    height: 780,
    resizable: false,
    fullscreenable: false,
    title: "Reality Check Avatars",
    webPreferences: { nodeIntegration: true, contextIsolation: false },
  });
  dash.loadFile(path.join(__dirname, "dashboard.html"));
  dash.on("closed", () => {
    dash = null;
  });
}
function pushToDash() {
  if (dash) dash.webContents.send("settings", settings);
}

ipcMain.on("get-settings", (e) => e.reply("settings", settings));
ipcMain.on("set-settings", (e, patch) => {
  settings = { ...settings, ...patch };
  saveSettings();
  if (settings.paused && isPlaying) stopOverlay(); // pause stops it immediately
  restartPeriodic();
  updateTray();
  pushToDash();
});
ipcMain.on("reset-count", () => {
  settings.visitCount = 0;
  saveSettings();
  pushToDash();
  updateTray();
});
ipcMain.on("preview", () => fire());

// ---------- tray (menu bar) ----------
function trayImage() {
  const img = nativeImage.createFromPath(path.join(__dirname, "trayTemplate.png"));
  img.setTemplateImage(true);
  return img;
}
function updateTray() {
  if (!tray) return;
  const menu = Menu.buildFromTemplate([
    { label: "Settings…", click: openDashboard },
    { label: "Play one now", click: () => fire() },
    { type: "separator" },
    {
      label: settings.paused ? "Resume" : "Pause",
      click: () => {
        settings.paused = !settings.paused;
        if (settings.paused && isPlaying) stopOverlay(); // stop now
        saveSettings();
        updateTray();
        pushToDash();
      },
    },
    { type: "separator" },
    { label: `Social visits: ${settings.visitCount}`, enabled: false },
    { type: "separator" },
    { label: "Quit", click: () => app.exit(0) },
  ]);
  tray.setContextMenu(menu);
  let tip = settings.paused ? "Reality Check Avatars (paused)" : "Reality Check Avatars";
  try {
    if (!fs.readdirSync(AUDIO_DIR).some((f) => f.endsWith(".opus"))) {
      tip = "Reality Check Avatars — no audio yet: run prep/convert_clips.sh";
    }
  } catch (_) {
    tip = "Reality Check Avatars — no audio yet: run prep/convert_clips.sh";
  }
  tray.setToolTip(tip);
}
function createTray() {
  tray = new Tray(trayImage());
  tray.on("click", openDashboard);
  updateTray();
}

app.whenReady().then(() => {
  if (app.dock) app.dock.hide();
  loadSettings();
  createOverlay();
  createTray();
  startWatcher();
  startMediaWatch();
  restartPeriodic();
  if (process.env.RC_DASH) openDashboard(); // RC_DASH=1 -> open dashboard (testing)
  if (process.env.RC_TEST) {
    // RC_TEST=1 -> play one random track; RC_TEST=<name> -> play that track
    const name = process.env.RC_TEST === "1" ? undefined : process.env.RC_TEST;
    setTimeout(() => fire(name), 1500);
  }
});

app.on("window-all-closed", (e) => e.preventDefault()); // stay resident
