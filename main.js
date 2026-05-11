const { app, BrowserWindow, ipcMain, Menu } = require('electron');
const path = require('path');
const { autoUpdater } = require('electron-updater');

// ---- auto-update 配置 ----
const UPDATE_FEED_URL = 'http://154.8.213.134:8080/updates';
autoUpdater.autoDownload = true;
autoUpdater.autoInstallOnAppQuit = true;
if (UPDATE_FEED_URL) {
  autoUpdater.setFeedURL(UPDATE_FEED_URL);
}

function createWindow() {
  const iconPath = path.join(__dirname, 'icons', 'icon.png');
  const mainWindow = new BrowserWindow({
    width: 1200,
    height: 750,
    icon: iconPath,
    frame: false,
    backgroundColor: '#667eea',
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      webSecurity: false
    },
    show: true
  });

  mainWindow.loadFile('index.html');
  mainWindow.setMenuBarVisibility(false);

  mainWindow.on('closed', () => {
    app.quit();
  });

  return mainWindow;
}

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  const win = createWindow();
  setupAutoUpdater(win);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

// 窗口控制
ipcMain.on('window-minimize', () => {
  BrowserWindow.getFocusedWindow().minimize();
});

ipcMain.on('window-maximize', () => {
  const win = BrowserWindow.getFocusedWindow();
  if (win.isMaximized()) {
    win.unmaximize();
  } else {
    win.maximize();
  }
});

ipcMain.on('window-close', () => {
  BrowserWindow.getFocusedWindow().close();
});

// ---- auto-update ----
function sendUpdateStatus(win, data) {
  if (win && !win.isDestroyed()) {
    win.webContents.send('update-status', data);
  }
}

function doCheckForUpdates(fromWin) {
  if (!UPDATE_FEED_URL) {
    sendUpdateStatus(fromWin, { status: 'unconfigured' });
    return;
  }

  // dev 模式：electron-updater 不会工作，直接告知用户
  if (!app.isPackaged) {
    sendUpdateStatus(fromWin, { status: 'error', message: '开发模式下不支持自动更新，请打包后测试' });
    return;
  }

  // 已打包模式：正常走 electron-updater
  autoUpdater.checkForUpdates().catch((err) => {
    sendUpdateStatus(fromWin, {
      status: 'error',
      message: (err && err.message) || '检查更新失败'
    });
  });
}

function setupAutoUpdater(mainWindow) {
  autoUpdater.on('checking-for-update', () => {
    sendUpdateStatus(mainWindow, { status: 'checking' });
  });

  autoUpdater.on('update-available', (info) => {
    sendUpdateStatus(mainWindow, { status: 'available', version: info.version });
  });

  autoUpdater.on('update-not-available', () => {
    sendUpdateStatus(mainWindow, { status: 'up-to-date' });
  });

  autoUpdater.on('download-progress', (progress) => {
    sendUpdateStatus(mainWindow, {
      status: 'downloading',
      percent: Math.floor(progress.percent)
    });
  });

  autoUpdater.on('update-downloaded', (info) => {
    sendUpdateStatus(mainWindow, {
      status: 'downloaded',
      version: info.version
    });
  });

  autoUpdater.on('error', (err) => {
    sendUpdateStatus(mainWindow, {
      status: 'error',
      message: (err && err.message) || '更新错误'
    });
  });

  if (!UPDATE_FEED_URL) {
    sendUpdateStatus(mainWindow, { status: 'unconfigured' });
    return;
  }

  if (!app.isPackaged) {
    sendUpdateStatus(mainWindow, { status: 'idle' });
    return;
  }

  // 启动后延迟检查
  setTimeout(() => {
    doCheckForUpdates(mainWindow);
  }, 3000);
}

ipcMain.on('check-for-update', () => {
  const win = BrowserWindow.getFocusedWindow();
  doCheckForUpdates(win);
});

ipcMain.on('quit-and-install', () => {
  autoUpdater.quitAndInstall();
});
