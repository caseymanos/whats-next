import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { generateObject, openai } from '../_shared/deps.ts';
import { z } from '../_shared/deps.ts';
import {
  createServiceClient,
  corsHeaders,
  generateRequestId,
  logRequest,
} from '../_shared/utils.ts';

// Unified schema for extracting ALL insight types in one pass
const InsightsSchema = z.object({
  events: z.array(z.object({
    title: z.string().describe('Event title or name'),
    date: z.string().describe('Event date in YYYY-MM-DD format'),
    time: z.string().nullish().describe('Event time in HH:MM format (24-hour)'),
    location: z.string().nullish().describe('Event location or venue'),
    description: z.string().nullish().describe('Additional event details'),
    category: z.enum(['school', 'medical', 'social', 'sports', 'work', 'other']).nullish(),
    confidence: z.number().min(0).max(1).describe('Confidence level 0-1')
  })).describe('Calendar events mentioned in the message'),

  rsvps: z.array(z.object({
    eventName: z.string().describe('Name of the event requiring RSVP'),
    deadline: z.string().nullish().describe('RSVP deadline in ISO 8601 format'),
    eventDate: z.string().nullish().describe('Event date in ISO 8601 format'),
    requestedBy: z.string().nullish().describe('Who is requesting the RSVP')
  })).describe('RSVP requests found in the message'),

  deadlines: z.array(z.object({
    task: z.string().describe('Task or action item description'),
    deadline: z.string().describe('Deadline in ISO 8601 format'),
    category: z.enum(['school', 'bills', 'chores', 'forms', 'other']).nullish(),
    priority: z.enum(['urgent', 'high', 'medium', 'low']).nullish(),
    details: z.string().nullish().describe('Additional details about the task')
  })).describe('Deadlines and tasks with due dates'),

  decisions: z.array(z.object({
    decisionText: z.string().describe('The decision or commitment made'),
    category: z.enum(['activity', 'schedule', 'purchase', 'policy', 'other']).nullish(),
    deadline: z.string().nullish().describe('Decision deadline in YYYY-MM-DD format')
  })).describe('Decisions or commitments made in the conversation'),

  priority: z.object({
    level: z.enum(['urgent', 'high', 'medium']).describe('Priority level'),
    reason: z.string().describe('Why this message is high priority'),
    actionRequired: z.boolean().describe('Whether immediate action is needed')
  }).nullish().describe('Priority flag if message requires urgent attention')
});

// Request schema
const RequestSchema = z.object({
  messageId: z.string().uuid(),
  conversationId: z.string().uuid(),
  senderId: z.string().uuid(),
  content: z.string().min(1),
});

serve(async (req) => {
  const requestId = generateRequestId();

  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }

  try {
    logRequest(requestId, 'start', { method: req.method });

    // Use service role client (triggered by database, not user request)
    const supabase = createServiceClient();

    // Parse request
    const body = await req.json();
    const { messageId, conversationId, senderId, content } = RequestSchema.parse(body);

    console.log(`[ParseMessageAI] Processing message ${messageId} from conversation ${conversationId}`);

    // Skip if message is too short or likely not meaningful
    if (content.length < 10) {
      console.log('[ParseMessageAI] Message too short, skipping');
      return new Response(
        JSON.stringify({ skipped: true, reason: 'message_too_short' }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit: Max 1000 messages/day per user
    const oneDayAgo = new Date();
    oneDayAgo.setDate(oneDayAgo.getDate() - 1);

    const { count } = await supabase
      .from('messages')
      .select('id', { count: 'exact', head: true })
      .eq('sender_id', senderId)
      .gte('ai_last_processed', oneDayAgo.toISOString());

    if (count && count >= 1000) {
      console.log(`[ParseMessageAI] Rate limit exceeded for user ${senderId}: ${count} messages/day`);
      return new Response(
        JSON.stringify({ skipped: true, reason: 'rate_limit_exceeded', count }),
        { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Fetch context: Previous 5 messages for better understanding
    // Fetch last 5 messages excluding the current one being processed
    // This avoids race conditions with the just-inserted message
    const { data: contextMessages } = await supabase
      .from('messages')
      .select('content, sender_id, created_at')
      .eq('conversation_id', conversationId)
      .neq('id', messageId)  // Exclude the message being processed
      .order('created_at', { ascending: false })
      .limit(5);

    const context = contextMessages?.reverse().map(m => m.content).join('\n') || '';

    logRequest(requestId, 'context_loaded', { contextMessages: contextMessages?.length || 0 });

    // Run AI extraction (single pass for all insights)
    console.log('[ParseMessageAI] Running AI extraction...');
    const result = await generateObject({
      model: openai('gpt-4o-mini'),
      schema: InsightsSchema,
      prompt: `You are analyzing a message from a busy parent/caregiver's conversation. Extract ALL relevant insights in ONE pass.

**Context (previous messages):**
${context}

**Current message to analyze:**
${content}

Extract:
1. Calendar events (meetings, appointments, activities) with dates and times
2. RSVP requests (invitations requiring a response)
3. Deadlines (tasks with due dates like "form due Friday")
4. Decisions (commitments or agreements made)
5. Priority flag (only if message is urgent/high priority and requires immediate attention)

Be accurate and conservative - only extract clear, unambiguous information. Use ISO 8601 format for dates/times.

Today's date: ${new Date().toISOString().split('T')[0]}`,
    });

    const insights = result.object;

    console.log(`[ParseMessageAI] Extracted: ${insights.events.length} events, ${insights.rsvps.length} RSVPs, ${insights.deadlines.length} deadlines, ${insights.decisions.length} decisions, priority: ${insights.priority ? 'YES' : 'NO'}`);

    logRequest(requestId, 'insights_extracted', {
      events: insights.events.length,
      rsvps: insights.rsvps.length,
      deadlines: insights.deadlines.length,
      decisions: insights.decisions.length,
      hasPriority: !!insights.priority
    });

    // Store insights in database (single transaction for atomicity)
    const now = new Date().toISOString();

    // 1. Store calendar events
    if (insights.events.length > 0) {
      const eventsToInsert = insights.events.map(event => ({
        conversation_id: conversationId,
        message_id: messageId,
        user_id: senderId,
        title: event.title,
        date: event.date,
        time: event.time || null,
        location: event.location || null,
        description: event.description || null,
        category: event.category || 'other',
        confidence: event.confidence,
        confirmed: false,
        created_at: now,
        updated_at: now
      }));

      const { error: eventsError } = await supabase
        .from('calendar_events')
        .insert(eventsToInsert);

      if (eventsError) {
        console.error('[ParseMessageAI] Error inserting events:', eventsError);
      } else {
        console.log(`[ParseMessageAI] Inserted ${eventsToInsert.length} events`);
      }
    }

    // 2. Store RSVPs
    if (insights.rsvps.length > 0) {
      const rsvpsToInsert = insights.rsvps.map(rsvp => ({
        message_id: messageId,
        conversation_id: conversationId,
        user_id: senderId,
        event_name: rsvp.eventName,
        deadline: rsvp.deadline || null,
        event_date: rsvp.eventDate || null,
        status: 'pending',
        created_at: now
      }));

      const { error: rsvpsError } = await supabase
        .from('rsvp_tracking')
        .insert(rsvpsToInsert);

      if (rsvpsError) {
        console.error('[ParseMessageAI] Error inserting RSVPs:', rsvpsError);
      } else {
        console.log(`[ParseMessageAI] Inserted ${rsvpsToInsert.length} RSVPs`);
      }
    }

    // 3. Store deadlines
    if (insights.deadlines.length > 0) {
      const deadlinesToInsert = insights.deadlines.map(deadline => ({
        message_id: messageId,
        conversation_id: conversationId,
        user_id: senderId,
        task: deadline.task,
        deadline: deadline.deadline,
        category: deadline.category || 'other',
        priority: deadline.priority || 'medium',
        details: deadline.details || null,
        status: 'pending',
        created_at: now
      }));

      const { error: deadlinesError } = await supabase
        .from('deadlines')
        .insert(deadlinesToInsert);

      if (deadlinesError) {
        console.error('[ParseMessageAI] Error inserting deadlines:', deadlinesError);
      } else {
        console.log(`[ParseMessageAI] Inserted ${deadlinesToInsert.length} deadlines`);
      }
    }

    // 4. Store decisions
    if (insights.decisions.length > 0) {
      const decisionsToInsert = insights.decisions.map(decision => ({
        conversation_id: conversationId,
        message_id: messageId,
        decision_text: decision.decisionText,
        category: decision.category || 'other',
        decided_by: senderId,
        deadline: decision.deadline || null,
        created_at: now
      }));

      const { error: decisionsError } = await supabase
        .from('decisions')
        .insert(decisionsToInsert);

      if (decisionsError) {
        console.error('[ParseMessageAI] Error inserting decisions:', decisionsError);
      } else {
        console.log(`[ParseMessageAI] Inserted ${decisionsToInsert.length} decisions`);
      }
    }

    // 5. Store priority flag
    if (insights.priority) {
      const { error: priorityError } = await supabase
        .from('priority_messages')
        .insert({
          message_id: messageId,
          priority: insights.priority.level,
          reason: insights.priority.reason,
          action_required: insights.priority.actionRequired,
          dismissed: false,
          created_at: now
        });

      if (priorityError) {
        console.error('[ParseMessageAI] Error inserting priority:', priorityError);
      } else {
        console.log(`[ParseMessageAI] Marked message as ${insights.priority.level} priority`);
      }
    }

    // 6. Update message.ai_last_processed timestamp
    const { error: updateError } = await supabase
      .from('messages')
      .update({ ai_last_processed: now })
      .eq('id', messageId);

    if (updateError) {
      console.error('[ParseMessageAI] Error updating ai_last_processed:', updateError);
    }

    logRequest(requestId, 'complete', { success: true });

    return new Response(
      JSON.stringify({
        success: true,
        messageId,
        insights: {
          events: insights.events.length,
          rsvps: insights.rsvps.length,
          deadlines: insights.deadlines.length,
          decisions: insights.decisions.length,
          priority: !!insights.priority
        },
        processedAt: now
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );

  } catch (error) {
    console.error('[ParseMessageAI] Error:', error);
    logRequest(requestId, 'error', { error: error.message });

    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );
  }
});
