export const EVENT_CATALOG = {
  session_started: ["entry_path", "referrer_class"],
  page_viewed: ["path", "page_type"],
  content_viewed: ["content_id", "content_type"],
  content_progressed: ["content_id", "progress_bucket"],
  content_completed: ["content_id", "completion_ratio"],
  program_viewed: ["program_key"],
  tv_started: ["channel_key"],
  tv_stopped: ["channel_key", "watch_seconds_bucket"],
  radio_started: ["station_key"],
  radio_stopped: ["station_key", "listen_seconds_bucket"],
  cta_clicked: ["cta_key", "object_id"],
  contact_started: ["channel"],
  recommendation_shown: ["recommendation_id"],
  recommendation_clicked: ["recommendation_id", "item_rank"],
  recommendation_dismissed: ["recommendation_id"],
  preference_updated: ["topic_key", "preference"],
} as const;

export type EventType = keyof typeof EVENT_CATALOG;
export const EVENT_TYPES = Object.freeze(Object.keys(EVENT_CATALOG) as EventType[]);

export const ALLOWED_CONTEXT_KEYS = new Set([
  "locale",
  "timezone",
  "device_class",
  "platform",
  "app_version",
  "connection_type",
]);
