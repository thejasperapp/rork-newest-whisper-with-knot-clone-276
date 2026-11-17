-- Fix RLS policies so the room host can add and remove speakers.
-- The original policies only allowed a user to insert/delete their own speaker
-- row, which meant the host could never approve a speaker request.
-- Apply manually via the Supabase SQL Editor.

-- Drop the old insert policy that blocked host approvals
DROP POLICY IF EXISTS whisper_live_room_speakers_insert ON whisper_live_room_speakers;

-- New insert policy: a user can add themselves OR the room host can add them
CREATE POLICY whisper_live_room_speakers_insert
  ON whisper_live_room_speakers FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    OR auth.uid() IN (SELECT host_id FROM whisper_live_rooms WHERE id = room_id)
  );

-- Drop the old delete policy that blocked host from removing speakers
DROP POLICY IF EXISTS whisper_live_room_speakers_delete ON whisper_live_room_speakers;

-- New delete policy: a user can remove themselves OR the room host can remove them
CREATE POLICY whisper_live_room_speakers_delete
  ON whisper_live_room_speakers FOR DELETE
  USING (
    auth.uid() = user_id
    OR auth.uid() IN (SELECT host_id FROM whisper_live_rooms WHERE id = room_id)
  );

-- Also allow the host to update speaker rows (e.g. toggle can_video)
DROP POLICY IF EXISTS whisper_live_room_speakers_update ON whisper_live_room_speakers;
CREATE POLICY whisper_live_room_speakers_update
  ON whisper_live_room_speakers FOR UPDATE
  USING (
    auth.uid() = user_id
    OR auth.uid() IN (SELECT host_id FROM whisper_live_rooms WHERE id = room_id)
  );
