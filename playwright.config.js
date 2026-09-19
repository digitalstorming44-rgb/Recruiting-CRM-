const { defineConfig } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  use: {
    baseURL: "http://127.0.0.1:4173",
    channel: "chrome",
    headless: true,
  },
  webServer: {
    command: "node server.js",
    url: "http://127.0.0.1:4173",
    reuseExistingServer: true,
  },
});
