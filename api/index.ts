import { createApp } from "../src/app.js";

export const runtime = "nodejs";

const app = createApp();

export default {
  fetch(request: Request) {
    return app.fetch(request);
  },
};
