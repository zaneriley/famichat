import { describe, expect, it, vi } from "vitest";
import MessageChannelHook from "../../js/hooks/message_channel_hook.js";

type HookContext = {
  el: {
    dataset: {
      conversationType?: string;
      conversationId?: string;
      userId?: string;
    };
  };
  connected: boolean;
  conversationType: string;
  conversationId: string;
  userId: string;
  disconnect: ReturnType<typeof vi.fn>;
  connect: ReturnType<typeof vi.fn>;
  topicFor: typeof MessageChannelHook.topicFor;
};

function buildContext(
  overrides: Partial<HookContext> = {},
  dataset: HookContext["el"]["dataset"] = {},
): HookContext {
  return {
    el: {
      dataset: {
        conversationType: dataset.conversationType ?? "direct",
        conversationId: dataset.conversationId ?? "conv-1",
        userId: dataset.userId ?? "user-1",
      },
    },
    connected: false,
    conversationType: "direct",
    conversationId: "conv-1",
    userId: "user-1",
    disconnect: vi.fn(),
    connect: vi.fn(),
    topicFor: MessageChannelHook.topicFor,
    ...overrides,
  };
}

describe("MessageChannelHook", () => {
  it("formats self topic using actor user id", () => {
    const context = buildContext();

    expect(MessageChannelHook.topicFor.call(context, "self", "ignored")).toBe(
      "message:self:user-1",
    );
  });

  it("syncs latest dataset params even when disconnected", () => {
    const context = buildContext();
    context.connected = false;
    context.el.dataset.conversationType = "group";
    context.el.dataset.conversationId = "group-42";
    context.el.dataset.userId = "user-2";

    MessageChannelHook.updated.call(context);

    expect(context.conversationType).toBe("group");
    expect(context.conversationId).toBe("group-42");
    expect(context.userId).toBe("user-2");
    expect(context.disconnect).not.toHaveBeenCalled();
    expect(context.connect).not.toHaveBeenCalled();
  });

  it("reconnects when connected and topic changed", () => {
    const context = buildContext({ connected: true });
    context.el.dataset.conversationType = "direct";
    context.el.dataset.conversationId = "conv-2";

    MessageChannelHook.updated.call(context);

    expect(context.disconnect).toHaveBeenCalledTimes(1);
    expect(context.connect).toHaveBeenCalledTimes(1);
    expect(context.conversationId).toBe("conv-2");
  });
});
