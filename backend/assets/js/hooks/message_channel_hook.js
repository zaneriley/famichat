import { Socket } from "phoenix";

/**
 * MessageChannelHook - Phoenix LiveView Hook for connecting to MessageChannel
 *
 * This hook establishes a socket connection to the Phoenix MessageChannel from
 * the client side, which is the proper architectural approach. It handles:
 *
 * 1. Socket connection and authentication
 * 2. Channel joining with appropriate params
 * 3. Message sending/receiving
 * 4. Pushing events back to the LiveView
 */
const MessageChannelHook = {
  mounted() {
    console.log("[MessageChannel] Hook mounted", { el: this.el.id });

    try {
      // Get configuration from data attributes
      this.conversationType = this.el.dataset.conversationType || "direct";
      this.conversationId = this.el.dataset.conversationId || "";
      this.userId = this.el.dataset.userId || "";

      // Initialize connection state
      this.channel = null;
      this.connected = false;
      this.seenMessageIds = new Set();
      this.notificationPromptRequested = false;

      // Auto-connect without a server-issued channel token is no longer
      // supported. The LiveView must push connect_channel with the token.
      if (this.el.dataset.autoConnect === "true") {
        console.warn("[MessageChannel] autoConnect requires server-issued token; ignored.");
      }

      // connect_channel now carries the channel bootstrap token in its payload.
      // The token is delivered over the LiveView WebSocket — never in the DOM.
      this.handleEvent("connect_channel", ({ channel_token }) => {
        if (!channel_token) {
          console.error("[MessageChannel] connect_channel received without channel_token");
          this.pushEvent("socket_error", { reason: "missing_channel_token" });
          return;
        }
        this.connect(channel_token);
      });
      this.handleEvent("disconnect_channel", () => this.disconnect());
      this.handleEvent("send_message", (payload) => this.sendMessage(payload));

      console.log("[MessageChannel] Hook initialized", {
        conversationType: this.conversationType,
        conversationId: this.conversationId,
        userId: this.userId,
      });
    } catch (error) {
      console.error("[MessageChannel] Error during hook mount:", error);
    }
  },

  connect(channelToken) {
    try {
      console.log("[MessageChannel] Connecting...");

      // channelToken is a short-lived bootstrap token delivered over the
      // LiveView WebSocket. It is used exactly once to authenticate the
      // Phoenix Socket connection. The access token is never placed in the DOM.
      this.socket = new Socket("/socket", {
        params: { token: channelToken },
      });

      // Connect to the socket
      this.socket.connect();

      // Log connection status
      this.socket.onOpen(() => {
        console.log("[MessageChannel] Socket connected");
      });

      this.socket.onError((error) => {
        console.error("[MessageChannel] Socket error:", error);
        this.pushEvent("socket_error", { reason: "connection_error" });
      });

      const topic = this.topicFor(this.conversationType, this.conversationId);
      console.log("[MessageChannel] Joining topic:", topic);

      // Join the channel
      this.channel = this.socket.channel(topic, {});

      this.channel
        .join()
        .receive("ok", (response) => {
          console.log("[MessageChannel] Joined successfully", response);
          this.connected = true;

          // Request notification permission once per hook lifecycle (requires prior user gesture).
          // Placed here so the prompt only appears after authentication,
          // not on login/setup pages where a "Block" tap is permanent.
          if (
            "Notification" in window &&
            Notification.permission === "default" &&
            !this.notificationPromptRequested
          ) {
            Notification.requestPermission();
            this.notificationPromptRequested = true;
          }

          // Notify the LiveView that we've connected
          this.pushEvent("channel_joined", {
            topic: topic,
          });
        })
        .receive("error", (response) => {
          console.error("[MessageChannel] Failed to join", response);

          // Notify the LiveView about the error
          this.pushEvent("join_error", {
            reason: response.reason || "unknown_error",
          });
        });

      // Listen for new messages
      this.channel.on("new_msg", (payload) => {
        console.log("[MessageChannel] Received message", payload);

        const messageId = payload.message_id;

        if (typeof messageId !== "string" || messageId.trim() === "") {
          console.warn(
            "[MessageChannel] Dropping message without message_id",
            payload,
          );
          this.pushEvent("message_error", { reason: "invalid_message_payload" });
          return;
        }

        if (this.seenMessageIds.has(messageId)) {
          return;
        }

        this.seenMessageIds.add(messageId);

        // Send the message to the LiveView
        this.pushEvent("message_received", {
          body: payload.body || "",
          timestamp: new Date().toISOString(),
          outgoing: false,
          user_id: payload.user_id || "unknown",
          device_id: payload.device_id || null,
          encrypted: payload.encryption_flag || false,
          message_id: messageId,
          sender_name: payload.sender_name || null,
        });

        // Browser notification when tab is not focused.
        // TODO: At L3 (E2EE), replace body with generic "New message" to prevent
        // plaintext exposure in OS notifications. Currently acceptable at L1 because
        // server decrypts for LiveView anyway.
        if (document.hidden && Notification.permission === "granted") {
          try {
            const senderName = payload.sender_name || "Someone sent you a message";
            const body = payload.body || "";
            const truncated =
              body.length > 100 ? body.slice(0, 100) + "\u2026" : body;

            const notification = new Notification(senderName, {
              body: truncated,
              tag: "famichat-" + messageId,
            });

            notification.onclick = () => {
              window.focus();
              notification.close();
              const container = document.getElementById("messages-scroll-container");
              if (container) container.scrollTop = container.scrollHeight;
            };
          } catch (e) {
            console.warn("[MessageChannel] Notification failed:", e);
          }
        }

        // Send acknowledgment to the server
        // This implements the client ACK mechanism required by Story 7.5.2.3
        this.sendAcknowledgment(messageId);
      });

      this.channel.on("security_state", (payload) => {
        this.pushEvent("security_state_update", {
          reason: payload.reason || "unknown",
          action: payload.action || null,
        });
      });
    } catch (error) {
      console.error("[MessageChannel] Error during connect:", error);
      this.pushEvent("socket_error", { reason: "initialization_error" });
    }
  },

  disconnect() {
    if (this.channel) {
      this.channel.leave().receive("ok", () => {
        console.log("[MessageChannel] Left channel");
        this.connected = false;

        // Notify the LiveView that we've disconnected
        this.pushEvent("channel_left", {});
      });
    }

    if (this.socket) {
      this.socket.disconnect();
    }

    this.connected = false;
    this.channel = null;
    this.socket = null;
  },

  sendMessage(payload) {
    if (this.connected && this.channel) {
      console.log("[MessageChannel] Sending message", payload);

      // Push the new message to the channel
      this.channel
        .push("new_msg", payload)
        .receive("ok", () => {
          console.log("[MessageChannel] Message sent successfully");
        })
        .receive("error", (err) => {
          console.error("[MessageChannel] Failed to send message", err);
          this.pushEvent("message_error", { reason: err.reason });
        });
    } else {
      console.error("[MessageChannel] Cannot send message - not connected");
      this.pushEvent("message_error", { reason: "not_connected" });
    }
  },

  updated() {
    // Check if conversation parameters have changed
    const newType = this.el.dataset.conversationType || this.conversationType;
    const newId = this.el.dataset.conversationId || "";
    const newUserId = this.el.dataset.userId || "";
    const previousTopic = this.topicFor(
      this.conversationType,
      this.conversationId,
      this.userId,
    );
    const nextTopic = this.topicFor(newType, newId, newUserId);

    // Always sync latest params so a later connect() uses fresh values.
    this.conversationType = newType;
    this.conversationId = newId;
    this.userId = newUserId;

    // If conversation parameters changed and we're connected, reconnect.
    // We disconnect and request a new channel token from the server via the
    // connect-channel event — the server will push connect_channel with a
    // fresh token. We do not call connect() directly here because we no longer
    // have the token available in the hook after the initial connect.
    if (this.connected && nextTopic !== previousTopic) {
      console.log("[MessageChannel] Conversation changed, reconnecting");
      this.disconnect();
      this.seenMessageIds.clear();
      this.pushEvent("connect-channel", {});
    }
  },

  destroyed() {
    // Clean up when the element is removed
    this.disconnect();
  },

  // New method to send message acknowledgments
  sendAcknowledgment(messageId) {
    if (this.connected && this.channel) {
      console.log(
        "[MessageChannel] Sending acknowledgment for message:",
        messageId,
      );

      // Push the acknowledgment to the channel
      this.channel
        .push("message_ack", { message_id: messageId })
        .receive("ok", () => {
          console.log("[MessageChannel] Acknowledgment sent successfully");
        })
        .receive("error", (err) => {
          console.error("[MessageChannel] Failed to send acknowledgment", err);
        });
    } else {
      console.error(
        "[MessageChannel] Cannot send acknowledgment - not connected",
      );
    }
  },

  topicFor(type, id, userId = this.userId) {
    if (type === "self") {
      return userId ? `message:self:${userId}` : "message:self";
    }

    return `message:${type}:${id}`;
  },
};

export default MessageChannelHook;
