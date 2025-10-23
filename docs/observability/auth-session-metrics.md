# Auth Session Metrics & Dashboards

The sessions refactor introduced dedicated telemetry events under
`[:famichat, :auth, :session, ...]`. To surface these in the existing Elixir
Grafana dashboards, add the following panels (or equivalent Prometheus rules)
so rotation anomalies are visible at a glance.

## Metrics

| Metric | Description |
| ------ | ----------- |
| `famichat.auth.session.start.count` | Incremented whenever a session starts. |
| `famichat.auth.session.refresh.count` | Successful refresh operations. |
| `famichat.auth.session.refresh.reuse_detected` | Refresh attempts rejected because a previous token was reused. |
| `famichat.auth.session.revoke.count` | Device revokes triggered either manually or by rotation policy. |

## Grafana panel recipe

```
sum(rate(famichat_auth_session_start_count[$__rate_interval]))
```

Repeat for the refresh metrics. Use a stacked bar or single-stat panel to spot
reuse spikes quickly (alert threshold: > 0 for 5 minutes).

## Alert suggestion

```
sum(increase(famichat_auth_session_refresh_reuse_detected[10m])) > 0
```

Ship the dashboard change alongside code deploys so ops can confirm rotation
health after the cutover.
