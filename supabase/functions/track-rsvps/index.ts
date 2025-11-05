import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { generateObject, openai, z } from '../_shared/deps.ts';
import {
  createAuthenticatedClient,
  createServiceClient,
  getUserId,
  checkRateLimit,
  logUsage,
  verifyConversationAccess,
  fetchMessages,
  corsHeaders,
  generateRequestId,
  logRequest,
} from '../_shared/utils.ts';

// Zod schema for RSVP extraction
const RSVPSchema = z.object({
  messageId: z.string().describe('ID of the message requesting RSVP (MSG-0, MSG-1, etc.)'),
  eventName: z.string().describe('Name or description of the event'),
  requestedBy: z.string().optional().describe('Who is asking for the RSVP'),
  deadline: z.string().optional().describe('RSVP deadline in ISO 8601 format'),
  eventDate: z.string().optional().describe('Event date/time in ISO 8601 format'),
  recipientMentions: z.array(z.string()).optional().describe('Names of people being asked to RSVP'),
});

const RSVPResultSchema = z.object({
  rsvps: z.array(RSVPSchema),
});

// Request schema
// RSVPs are now conversation-scoped (shared), not user-scoped
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  daysBack: z.number().min(1).max(14).optional().default(7),
});

serve(async (req) => {
  const requestId = generateRequestId();

  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }

  try {
    logRequest(requestId, 'start', { method: req.method });

    // Authenticate user
    const supabase = createAuthenticatedClient(req);
    const authUserId = await getUserId(supabase);

    logRequest(requestId, 'authenticated', { userId: authUserId });

    // Parse and validate request
    const body = await req.json();
    const { conversationId, daysBack } = RequestSchema.parse(body);

    // Verify conversation access (use authenticated user)
    const hasAccess = await verifyConversationAccess(supabase, authUserId, conversationId);
    if (!hasAccess) {
      return new Response(
        JSON.stringify({ error: 'Access denied to conversation' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit
    const { allowed, count } = await checkRateLimit(supabase, authUserId, 'track-rsvps', 30);
    if (!allowed) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded', count }),
        { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'rate_check', { count, allowed });

    // Fetch messages
    const messages = await fetchMessages(supabase, conversationId, {
      daysBack,
      limit: 100,
    });

    if (messages.length === 0) {
      return new Response(
        JSON.stringify({ rsvps: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'messages_fetched', { count: messages.length });

    // Get user's profile to understand context (for AI prompt)
    const { data: userProfile } = await supabase
      .from('users')
      .select('display_name, username')
      .eq('id', authUserId)
      .single();

    const userName = userProfile?.display_name || userProfile?.username || 'User';

    // Build context for AI
    const conversationContext = messages
      .map((m: any, idx: number) => `[MSG-${idx}] [${m.created_at}] ${m.content}`)
      .join('\n');

    const messageIdMap = messages.reduce((acc: any, m: any, idx: number) => {
      acc[`MSG-${idx}`] = m.id;
      return acc;
    }, {});

    // Extract RSVP requests using AI
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: RSVPResultSchema,
      prompt: `You are an AI assistant helping a busy parent/caregiver track RSVP requests.

The user's name is: ${userName}

Analyze the following conversation and identify any RSVP requests directed at the user. Look for:
- Birthday party invitations
- Event invitations (school events, social gatherings, etc.)
- Activity signups (sports, classes, field trips)
- Meeting confirmations
- Any request for attendance confirmation

For each RSVP request, extract:
- The message ID (MSG-0, MSG-1, etc.) where the request appears
- Event name
- Who is requesting the RSVP
- RSVP deadline if mentioned
- Event date/time if mentioned
- Who is being asked (look for direct mentions or context)

Only flag RSVPs that:
1. Haven't clearly been responded to yet
2. Are directed at the user or their family
3. Actually require a response

Conversation:
${conversationContext}

Extract all pending RSVP requests:`,
    });

    const rsvps = result.object.rsvps.map(rsvp => ({
      messageId: messageIdMap[rsvp.messageId] || rsvp.messageId,
      eventName: rsvp.eventName,
      requestedBy: rsvp.requestedBy,
      deadline: rsvp.deadline,
      eventDate: rsvp.eventDate,
    }));

    logRequest(requestId, 'rsvps_extracted', { count: rsvps.length });

    // Persist RSVP tracking records
    const serviceClient = createServiceClient();

    if (rsvps.length > 0) {
      // Check for existing RSVPs (conversation-scoped, not user-scoped)
      const { data: existing } = await serviceClient
        .from('rsvp_tracking')
        .select('message_id, conversation_id')
        .eq('conversation_id', conversationId)
        .in('message_id', rsvps.map(r => r.messageId));

      const existingKeys = new Set(
        (existing || []).map((e: any) => `${e.message_id}-${e.conversation_id}`)
      );

      const newRSVPs = rsvps.filter(
        r => !existingKeys.has(`${r.messageId}-${conversationId}`)
      );

      if (newRSVPs.length > 0) {
        const { data: inserted, error: insertError } = await serviceClient
          .from('rsvp_tracking')
          .insert(
            newRSVPs.map(rsvp => ({
              message_id: rsvp.messageId,
              conversation_id: conversationId,
              user_id: null, // Shared RSVP - no specific user until someone responds
              event_name: rsvp.eventName,
              requested_by: null, // Will need user mapping in production
              deadline: rsvp.deadline || null,
              event_date: rsvp.eventDate || null,
              status: 'pending',
            }))
          )
          .select();

        if (insertError) {
          console.error('Failed to insert RSVPs:', insertError);
          throw new Error('Failed to save RSVP tracking');
        }

        logRequest(requestId, 'rsvps_stored', { count: inserted?.length || 0 });
      }
    }

    // Get summary of all pending RSVPs for this conversation (shared)
    const { data: pendingRSVPs } = await supabase
      .from('rsvp_tracking')
      .select('*')
      .eq('conversation_id', conversationId)
      .eq('status', 'pending')
      .order('deadline', { ascending: true, nullsFirst: false });

    // Log usage
    await logUsage(supabase, authUserId, 'track-rsvps');

    logRequest(requestId, 'complete', { newRSVPs: rsvps.length, totalPending: pendingRSVPs?.length || 0 });

    return new Response(
      JSON.stringify({
        rsvps: rsvps,
        summary: {
          newCount: rsvps.length,
          totalPending: pendingRSVPs?.length || 0,
          pendingRSVPs: pendingRSVPs || [],
        }
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );

  } catch (error) {
    console.error('Error:', error);
    logRequest(requestId, 'error', { error: error.message });

    const status = error.message.includes('Unauthorized') ? 401 :
                   error.message.includes('Access denied') ? 403 : 500;

    return new Response(
      JSON.stringify({ error: error.message }),
      { status, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );
  }
});
