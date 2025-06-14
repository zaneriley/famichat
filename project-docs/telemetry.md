# Telemetry in Famichat

Telemetry is a key tool for monitoring the performance and behavior of the Famichat application. We use Telemetry to track critical metrics and function execution times, ensuring we meet our performance targets. These metrics are also used to help us determine product market fit by comparing user performance data over time.

## Guidelines and Best Practices

- **Instrumentation on Critical Functions:**
  - Use `:telemetry.span/3` to wrap key functions such as message retrieval, conversation creation, and other performance-critical endpoints.
  - Wrap function calls so that both the result and measurements (e.g., execution time, message counts) are emitted in telemetry events.

- **Event Naming Conventions:**
  - Use event names following the pattern `[:famichat, <module>, <function>]`. For example, for message retrieval, use:
    - `[:famichat, :message_service, :get_conversation_messages]`
  - Include relevant measurements and metadata (such as counts or error types).

- **Performance Budgets:**
  - **Definition:** Performance budgets establish thresholds for critical operations to ensure our app remains responsive.  
  - **Example Budget:** Our target for messaging operations (e.g., sending or retrieving messages) is an end-to-end execution time below 200ms.
  - **Implementation:**  
    - Instrument key functions using telemetry so that execution times are measured in both development and production environments.
    - Write tests (like our unit test that asserts `MessageService.get_conversation_messages/1` completes in under 200ms) to catch regressions early.
  - **Production Monitoring:**  
    - Use Telemetry Metrics to collect, aggregate, and export these values to external monitoring tools (e.g., Prometheus, Grafana).
    - Alerts can be set if a function's 95th percentile execution time exceeds our performance budget.

- **Integration with Monitoring Tools:**
  - Metrics will be pushed to a monitoring backend (such as Prometheus/Grafana) for visualization and alerting.
  - Developers must ensure telemetry instrumentation is non-blocking so that even if external handlers are not set up, the app continues running normally.

- **Using Telemetry Data for Product Insights:**
  - **User Experience:**  
    Analyze the performance metrics (response times, throughput) to ensure users enjoy near-instant messaging.
  - **Feature Usage & Engagement:**  
    Track the volume of messages, send failures, and conversation growth as signals for product market fit.
  - **Continuous Improvement:**  
    Use telemetry data to identify bottlenecks and adjust both performance budgets and architectural decisions over time.

- **Consistency:**
  - Every new or modified function should incorporate telemetry spans as part of its design.
  - In our code reviews, we will verify that performance-critical paths are appropriately instrumented.

*Last Updated: June 14, 2025*