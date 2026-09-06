import { handle } from "hono/vercel";
import { createApp } from "../src/app.js";

export const runtime = "nodejs";
export default handle(createApp());
