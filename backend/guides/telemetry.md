# Telemetry in Famichat

Telemetry is a key tool for monitoring the performance and behavior of the Famichat application. We use Telemetry to track critical metrics and function execution times, ensuring we meet our performance targets. These metrics are also used to help us determine product market fit by comparing user performance data over time.

## Guidelines and Best Practices

- **Instrumentation on Critical Functions:**
  - Use the `FamichatWeb.Telemetry` module's helper functions to wrap operations:
    - For simple event emissions: `FamichatWeb.Telemetry.emit_event/4`
    - For wrapping function calls: `FamichatWeb.Telemetry.with_telemetry/4`
  - Each function automatically handles tracking execution time, error handling, and performance budgets.

- **Event Naming Conventions:**
  - Use event names following the pattern `[:famichat, <module>, <function>]`. For example, for message retrieval, use:
    - `[:famichat, :message_service, :get_conversation_messages]`
  - Include relevant measurements and metadata (such as counts or error types).

- **Performance Budgets:**
  - **Definition:** Performance budgets establish thresholds for critical operations to ensure our app remains responsive.  
  - **Example Budget:** Our target for messaging operations (e.g., sending or retrieving messages) is an end-to-end execution time below 200ms.
  - **Implementation:**  
    - Set the `:performance_budget_ms` option when calling the telemetry functions.
    - Example: `FamichatWeb.Telemetry.emit_event(..., performance_budget_ms: 200)`
    - For most operations, the default of 200ms is used unless explicitly overridden.
  - **Production Monitoring:**  
    - Use Telemetry Metrics to collect, aggregate, and export these values to external monitoring tools (e.g., Prometheus, Grafana).
    - Alerts can be set if a function's 95th percentile execution time exceeds our performance budget.

- **Sensitive Data Handling:**
  - For operations dealing with sensitive information (like encrypted message data), set the `:filter_sensitive_metadata` option to true.
  - This ensures encryption metadata and sensitive fields are not included in telemetry events.

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
  - Use the centralized telemetry module rather than implementing your own telemetry logic.
  - In our code reviews, we will verify that performance-critical paths are appropriately instrumented.

- **Guidelines:**  
  - By default, all operations should target a performance budget of 200ms or less.
  - For time-critical operations such as authentication, budgets as low as 50ms are recommended.
  - Overrides that set budgets above 200ms are discouraged at this time.

## Architectural Considerations

Telemetry in Famichat is not only about tracking metrics but also about building a robust observability system. Our design philosophy includes:

- **System Observability:** Instrumentation provides real-time insights into system performance and user experience.
- **Performance Budget Strategy:** The default performance budget is set to 200ms to ensure high responsiveness. We discourage overriding this value unless absolutely necessary, as every operation should aim to complete within 200ms.
- **Monitoring and Alerting:** Telemetry data is used to trigger alerts and guide performance optimizations, ensuring prompt response to any deviations from expected performance.

*Last Updated: March 11, 2025* 