// Retired: process-inherited toolkit values are not authoritative managed keys.
// rork env run excludes protected managed keys; an inherited value can survive
// rotations. Copying it into a private binding can override a valid runtime key.
// Kept as a safety guard and record of the corrected propagation mistake.
// No arguments can enable a mutation. Do not restore this credential-copy path.
console.error('Retired credential propagation: no configuration changed. Process credentials cannot establish the current managed runtime key.');
process.exitCode = 1;
export {};
