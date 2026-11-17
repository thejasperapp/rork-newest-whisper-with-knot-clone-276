import { seedToUpdate } from './src/lib/meetSeed';

// Entry for the trusted offline WKWebView converter, not part of the Notes app bundle.
Object.defineProperty(globalThis, 'WhisperMeetSeed', {
 value: Object.freeze({ seedToUpdate }), writable: false, configurable: false,
});
