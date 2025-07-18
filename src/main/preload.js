const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("electronAPI", {
  startRecording: (outputPath) =>
    ipcRenderer.invoke("start-recording", outputPath),
  stopRecording: () => ipcRenderer.invoke("stop-recording"),
  checkPermissions: () => ipcRenderer.invoke("check-permissions"),
  getHomeDir: () => ipcRenderer.invoke("get-home-dir"),
});
