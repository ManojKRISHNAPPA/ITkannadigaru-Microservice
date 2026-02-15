const express = require("express");
const os = require("os");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8080;
const ENV = process.env.ENV || "dev";
const VERSION = process.env.VERSION || "local";
const BUILD_TIME = process.env.BUILD_TIME || new Date().toISOString();
const SERVICE = process.env.SERVICE || "deployecho-backend";

const startedAt = Date.now();

app.get("/health", (_req, res) => res.status(200).send("ok"));

app.get("/version", (_req, res) => {
  res.status(200).json({
    service: SERVICE,
    version: VERSION,
    env: ENV,
    buildTime: BUILD_TIME
  });
});

app.get("/info", (_req, res) => {
  const uptimeSeconds = Math.floor((Date.now() - startedAt) / 1000);
  res.status(200).json({
    hostname: os.hostname(),
    uptimeSeconds
  });
});

app.listen(PORT, () => {
  console.log(`✅ ${SERVICE} running on port ${PORT} | env=${ENV} | version=${VERSION}`);
});
