[
  # Ignoring CSP header file due to static environment check that triggers Dialyzer.
  # The compile-time check for dev environment causes a false positive in pattern matching.
  {"lib/famichat_web/plugs/csp_header.ex"},

  # Ignoring specific contract errors in conversation_service.ex
  ~r/lib\/famichat\/chat\/conversation_service.ex:182.*call/,
  ~r/lib\/famichat\/chat\/conversation_service.ex:203.*no_return/,
  ~r/lib\/famichat\/chat\/conversation_service.ex:204.*call/
]
