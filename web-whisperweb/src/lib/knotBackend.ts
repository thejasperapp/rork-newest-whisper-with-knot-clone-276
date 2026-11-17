// Knot-only routing to this clone's verified managed deployment. The hosted
// /~api alias returned 404 during cutover; never fall back to an old authority.
// Supabase, billing, Jasper and Meet keep their separate configuration.
export const knotBackendOrigin = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
export const knotBackendIdentity = 'mayokn2749ag072e3uvbh';
