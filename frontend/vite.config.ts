import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The dev server proxies /api to the Flask backend so the browser talks to one
// origin in development and in production alike. Crucially `changeOrigin` plus
// no buffering keeps the SSE stream working through the proxy -- without this
// the realtime channel silently stalls in `npm run dev` only, which is a
// miserable thing to debug.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: true,
    chunkSizeWarningLimit: 900,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:5050',
        changeOrigin: true,
        ws: false,
      },
    },
  },
})
