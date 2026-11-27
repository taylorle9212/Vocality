import { defineConfig } from "vite";
import wgsl from "@vgpu/wgsl/loader-vite";

export default defineConfig(({ command }) => ({
  // GitHub Pages serves the site from /Vocality/; local dev stays at /.
  base: command === "build" ? "/Vocality/" : "/",
  plugins: [wgsl()],
  server: { host: "127.0.0.1", port: 5180, strictPort: true },
}));
