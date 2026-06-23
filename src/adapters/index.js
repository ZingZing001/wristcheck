import { appleWatchAdapter } from './apple-watch.js';

const adapters = new Map();

export function registerWatchAdapter(adapter) {
  if (!adapter?.type || typeof adapter.shapeRequest !== 'function') {
    throw new TypeError('watch adapter must include type and shapeRequest(request)');
  }

  adapters.set(adapter.type, adapter);
}

export function getWatchAdapter(type = 'apple-watch') {
  return adapters.get(type) || adapters.get('apple-watch');
}

export function listWatchAdapters() {
  return Array.from(adapters.values()).map(({ type, displayName }) => ({ type, displayName }));
}

registerWatchAdapter(appleWatchAdapter);
