import { createApp } from './app.js';
import { config } from './config.js';

createApp().listen(config.port, () => console.log(`⛽ Fuel Station API on http://localhost:${config.port}/api/v1`));
