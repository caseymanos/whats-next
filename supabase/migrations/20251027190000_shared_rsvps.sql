-- Make RSVPs shared (conversation-scoped) instead of user-scoped
-- This allows both conversation participants to see and respond to RSVPs
-- Date: 2025-10-27

-- Update the SELECT policy (already conversation-scoped, but let's be explicit)
DROP POLICY IF EXISTS "Users can view RSVPs in their conversations" ON rsvp_tracking;
CREATE POLICY "Users can view RSVPs in their conversations" ON rsvp_tracking
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = rsvp_tracking.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Change UPDATE policy from user-scoped to conversation-scoped
-- This allows any conversation participant to respond to RSVPs
DROP POLICY IF EXISTS "Users can update their own RSVPs" ON rsvp_tracking;
CREATE POLICY "Users can update RSVPs in their conversations" ON rsvp_tracking
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = rsvp_tracking.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Service role can still insert RSVPs (no change needed)
DROP POLICY IF EXISTS "Service role can insert RSVPs" ON rsvp_tracking;
CREATE POLICY "Service role can insert RSVPs" ON rsvp_tracking
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

COMMENT ON POLICY "Users can update RSVPs in their conversations" ON rsvp_tracking IS
    'Allows any conversation participant to respond to RSVPs (Yes/No/Maybe). The user_id field records who responded.';
