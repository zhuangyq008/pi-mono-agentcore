import { startServer } from "./server.js";
import { loadConfig } from "./config/index.js";

const config = loadConfig();

startServer(config).catch((err) => {
  console.error("[fatal]", err);
  process.exit(1);
});
