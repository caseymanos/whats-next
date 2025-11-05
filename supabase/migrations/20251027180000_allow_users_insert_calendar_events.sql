-- Allow users to insert calendar events in their conversations
-- This enables RSVP responses to create calendar events from the iOS app
-- Date: 2025-10-27

-- Drop the overly restrictive service-role-only INSERT policy
DROP POLICY IF EXISTS "Service role can insert calendar events" ON calendar_events;

-- Allow service role to insert (for Edge Functions like parse-message-ai)
CREATE POLICY "Service role can insert calendar events" ON calendar_events
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Allow users to insert calendar events in conversations they participate in
CREATE POLICY "Users can insert calendar events in their conversations" ON calendar_events
    FOR INSERT
    WITH CHECK (
        -- User must be a participant in the conversation
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = calendar_events.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
        -- And the user_id must match the authenticated user
        AND user_id = auth.uid()
    );

COMMENT ON POLICY "Users can insert calendar events in their conversations" ON calendar_events IS
    'Allows users to create calendar events (e.g., from RSVP responses) in conversations they participate in';
