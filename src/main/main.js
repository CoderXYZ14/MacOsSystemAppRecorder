const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const { spawn } = require("child_process");

let mainWindow;
let recordingProcess = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      sandbox: true,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "../../src/renderer/index.html"));
}

app.whenReady().then(() => {
  // Fix PATH for spawned processes
  require("fix-path")();

  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("start-recording", async (_, outputPath) => {
  return new Promise((resolve) => {
    const nativePath = path.join(
      process.resourcesPath,
      "native",
      "SystemAudioRecorder"
    );

    recordingProcess = spawn(nativePath, [outputPath], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    recordingProcess.stdout.on("data", (data) => {
      console.log(`Native: ${data}`);
    });

    recordingProcess.stderr.on("data", (data) => {
      console.error(`Native Error: ${data}`);
    });

    recordingProcess.on("error", (err) => {
      resolve({ success: false, error: err.message });
    });

    recordingProcess.on("close", (code) => {
      resolve({
        success: code === 0,
        error: code !== 0 ? `Process exited with code ${code}` : null,
      });
    });

    // Give process time to start
    setTimeout(() => {
      resolve({ success: true });
    }, 500);
  });
});

ipcMain.handle("stop-recording", () => {
  if (recordingProcess) {
    recordingProcess.kill("SIGINT");
    recordingProcess = null;
    return { success: true };
  }
  return { success: false, error: "No active recording" };
});

ipcMain.handle("check-permissions", () => {
  // On macOS, we'll assume permissions are granted if the app runs
  return { hasPermission: true };
});
