const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const path = require("path");
const { spawn, execSync } = require("child_process");
const fs = require("fs");
const os = require("os");

let mainWindow;
let recordingProcess = null;
let currentOutputPath = null;
let isRecordingActive = false;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
    },
  });

  // Load renderer index.html from src/renderer/
  mainWindow.loadFile(path.join(__dirname, "../renderer/index.html"));

  // Only open DevTools in development
  if (process.env.NODE_ENV === "development") {
    mainWindow.webContents.openDevTools({ mode: "detach" });
  }
}

function getNativeBinaryPath() {
  const paths = [
    path.join(__dirname, "../../native/SystemAudioRecorder"),
    path.join(process.resourcesPath, "native/SystemAudioRecorder"),
    path.join(__dirname, "../../../native/SystemAudioRecorder"),
  ];

  for (const binPath of paths) {
    try {
      fs.accessSync(binPath, fs.constants.X_OK);
      return binPath;
    } catch {
      continue;
    }
  }
  throw new Error("SystemAudioRecorder binary not found or not executable");
}

app.whenReady().then(() => {
  try {
    // Fix PATH for spawned processes on macOS
    if (process.platform === "darwin") {
      require("fix-path")();
    }

    createWindow();
  } catch (error) {
    console.error("App initialization failed:", error);
    dialog.showErrorBox(
      "Initialization Error",
      `Failed to start application: ${error.message}`
    );
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

app.on("before-quit", () => {
  if (recordingProcess && isRecordingActive) {
    console.log("App quitting - stopping recording process");
    recordingProcess.kill("SIGTERM");
  }
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

// Handler for home directory resolution
ipcMain.handle("get-home-dir", () => {
  return os.homedir();
});

ipcMain.handle("start-recording", async (_, outputPath) => {
  try {
    console.log(
      `[Main] Starting recording request. Current state: isRecordingActive=${isRecordingActive}, recordingProcess=${!!recordingProcess}`
    );

    if (isRecordingActive) {
      return {
        success: false,
        error: "Recording already in progress",
      };
    }

    const nativePath = getNativeBinaryPath();
    const outputDir = path.dirname(outputPath);
    currentOutputPath = outputPath;

    // Create output directory if needed
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    return await new Promise((resolve) => {
      console.log(`[Main] Spawning Swift binary: ${nativePath}`);

      recordingProcess = spawn(nativePath, [outputPath], {
        stdio: ["ignore", "pipe", "pipe"],
        detached: false,
        shell: false,
      });

      // Process output handlers
      recordingProcess.stdout.on("data", (data) => {
        const output = data.toString().trim();
        console.log(`[Native Recorder]: ${output}`);

        // Send updates to renderer if needed
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("recording-output", output);
        }
      });

      recordingProcess.stderr.on("data", (data) => {
        const error = data.toString().trim();
        console.error(`[Native Recorder Error]: ${error}`);

        // Send error to renderer
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("recording-error", error);
        }
      });

      // Event handlers
      recordingProcess.on("error", (err) => {
        console.error("[Main] Process spawn error:", err);
        isRecordingActive = false;
        recordingProcess = null;
        resolve({
          success: false,
          error: `Failed to start recorder: ${err.message}`,
        });
      });

      recordingProcess.on("exit", (code, signal) => {
        console.log(
          `[Main] Recorder process exited with code ${code}, signal ${signal}`
        );

        // Only set to null if the process was intentionally stopped or crashed
        if (signal === "SIGINT" || signal === "SIGTERM" || code !== 0) {
          console.log(
            `[Main] Process exited intentionally or crashed. Cleaning up.`
          );
          isRecordingActive = false;
          recordingProcess = null;
        } else {
          console.log(
            `[Main] Process exited unexpectedly but cleanly. Keeping references.`
          );
        }

        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("recording-stopped", { code, signal });
        }
      });

      // Verify process started successfully
      setTimeout(() => {
        if (recordingProcess && !recordingProcess.killed) {
          console.log(
            `[Main] Recording process started successfully with PID: ${recordingProcess.pid}`
          );
          isRecordingActive = true;
          resolve({ success: true, outputPath: currentOutputPath });
        } else {
          console.log(`[Main] Recording process failed to start or was killed`);
          isRecordingActive = false;
          recordingProcess = null;
          resolve({
            success: false,
            error: "Audio recorder failed to start",
          });
        }
      }, 1000);
    });
  } catch (error) {
    console.error("[Main] Recording startup failed:", error);
    isRecordingActive = false;
    return {
      success: false,
      error: error.message,
    };
  }
});

ipcMain.handle("stop-recording", () => {
  try {
    console.log(
      `[Main] Stop recording request. Current state: isRecordingActive=${isRecordingActive}, recordingProcess=${!!recordingProcess}, PID=${
        recordingProcess?.pid
      }`
    );

    if (recordingProcess && isRecordingActive) {
      console.log(
        `[Main] Sending SIGINT to process PID: ${recordingProcess.pid}`
      );
      recordingProcess.kill("SIGINT");

      // Don't set to null immediately - let the exit handler do it
      const outputPath = currentOutputPath;
      currentOutputPath = null;
      isRecordingActive = false;

      return {
        success: true,
        outputPath: outputPath,
      };
    } else {
      console.log(`[Main] No active recording session to stop`);
      return {
        success: false,
        error: "No active recording session",
      };
    }
  } catch (error) {
    console.error("[Main] Failed to stop recording:", error);
    return {
      success: false,
      error: `Error stopping recording: ${error.message}`,
    };
  }
});

ipcMain.handle("check-permissions", async () => {
  if (process.platform !== "darwin") return { hasPermission: true };

  try {
    // Check for Screen Recording permission (required for system audio on macOS 13+)
    const screenPermissionCheck = `
      tell application "System Events"
        set hasScreenRecording to true
        try
          set frontmostApp to name of first application process whose frontmost is true
        on error
          set hasScreenRecording to false
        end try
      end tell
      return hasScreenRecording
    `;

    // Check for Microphone permission (fallback for older systems)
    execSync("ioreg -r -c AppleHDAEngineInput", { stdio: "ignore" });

    return { hasPermission: true };
  } catch {
    return {
      hasPermission: false,
      help: "Please enable Screen Recording and Microphone access in System Settings > Privacy & Security",
    };
  }
});

// Global error handling
process.on("uncaughtException", (error) => {
  console.error("Unhandled Error:", error);
  if (recordingProcess && isRecordingActive) {
    recordingProcess.kill("SIGTERM");
  }
  dialog.showErrorBox(
    "Application Error",
    `An unexpected error occurred: ${error.message}`
  );
});
