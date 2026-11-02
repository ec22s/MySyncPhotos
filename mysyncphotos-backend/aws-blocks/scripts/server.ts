import { startDevServer } from '@aws-blocks/blocks/scripts';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

startDevServer({
  backendPath: join(__dirname, '..', 'index.ts'),
  // --host 0.0.0.0 makes Vite (and the API server) accept connections on all
  // network interfaces, including the LAN IP 192.168.11.10, so a real iOS
  // device on the same Wi-Fi network can reach the backend.
  frontendCommand: 'npx vite --port 3100 --strictPort --host 0.0.0.0',
  frontendPort: 3100,
  host: '0.0.0.0',
});
