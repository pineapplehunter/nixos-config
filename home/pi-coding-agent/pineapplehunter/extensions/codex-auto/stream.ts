import type { AssistantMessageEvent } from "@earendil-works/pi-ai";

/** Keep the selected provider on every live and terminal response message. */
export async function* withProviderIdentity(
  source: AsyncIterable<AssistantMessageEvent>,
  provider: string,
): AsyncGenerator<AssistantMessageEvent> {
  for await (const event of source) {
    const message = event.type === "done" ? event.message : event.type === "error" ? event.error : event.partial;
    // Preserve the shared live partial object and all provider replay metadata.
    message.provider = provider;
    yield event;
  }
}
