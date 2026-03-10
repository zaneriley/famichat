# Famichat — Brand & Positioning Notes

**Status:** Working draft. Not a launch doc. Needs dogfooding to fill in the gaps.
**Last updated:** 2026-03-01

---

## What it is

- Self-hosted messaging for a small, closed group of people you trust — inner circle, family, chosen family
- You run the server; no third party has access to the data
- Currently at L0 (one developer, solo validation); no real users yet

## Who it's for

- Primary installer: technically capable person who wants to own their own instance and is also a family organizer or community anchor
- End users: their inner circle — people who need it to feel familiar; they will not read a setup guide
- The two audiences have very different tolerance for friction

## What it's against (competitors by default, not by design)

- Facebook Messenger and Discord are what people currently use for this; not because they're good fits, more because nothing better existed
- The emotional state of current users is resigned, not outraged

## What it might eventually do differently

- The "letters" mechanic (messages delayed by geographic distance) is an idea — not a built feature, not validated, could be annoying, could be the most interesting thing in the product
- Theming, a11y, i18n are first-class requirements but mostly invisible to end users after setup
- Specific product differentiator is not yet clear; needs dogfooding to discover

## Language directions (tentative)

- "Inner circle" or "loved ones" as the frame for who belongs — not nuclear family specifically
- "Neighborhood" as a possible word for the trust graph, but meaning is ambiguous (geographic vs. trust-based); needs testing in real copy
- Off-limits: platform, feed, social media, discovery, anything implying growth or broadcast

## Copy reference — golden examples

Real decisions from the codebase. "Good" vs "almost good" — the second column isn't wrong, it's just slightly off-tone.

### English

| Good | Almost good | Why |
|---|---|---|
| "Sign in with passkey" | "Log in with passkey" | "Sign in" is warmer, less sysadmin. Consistent everywhere. |
| "Your family space is ready." | "Your family has been created." | "Created" is a database verb. "Ready" implies something waiting for you. |
| "Something went wrong connecting. Try refreshing." | "Connection failed. Please retry." | Soft opener + casual action. Brand voice is resigned-not-alarmed. |
| "The person who invited you" | "Your household admin" | Relational, not role-based. Users don't know what "admin" means in this context. |
| "Set up your family space" | "Create a family" | "Set up" = preparing a place. "Create a family" is existentially weird. |
| "Family name — optional" | "Enter your family name (optional)" | "Enter your" is form-label boilerplate. |
| "Your device will ask to confirm it's you." | "Biometric authentication required." | Describes what actually happens, not the technology category. |
| "Invite links are single-use and expire after 72 hours." | "For security, each invite link can only be used once." | States the fact. Doesn't lecture about why. Users are resigned, not paranoid. |
| "Getting started? Ask the person who told you about Famichat to send you an invite link." | "You need an invitation to use Famichat. Contact your administrator." | Assumes a social relationship exists. Doesn't invoke "administrator." |

### 日本語 (Japanese)

| Good | Almost good | Why |
|---|---|---|
| ファミリー (katakana) for the product noun | 家族 everywhere | ファミリー reads as a product concept. 家族 is the literal word — fine in explanatory contexts ("家族を招待して"), wrong as a UI label. |
| "サインインして始めましょう" | "ログインしてください" | サインイン matches EN "sign in." ～しましょう is invitational, not imperative. |
| "接続中にエラーが発生しました。ページを更新してみてください。" | "接続に失敗しました。再試行してください。" | "エラーが発生しました" (an error occurred) is softer than "失敗しました" (failed). "更新してみてください" (try refreshing) vs "再試行" (retry) — casual vs technical. |
| "このデバイスは削除されました。もう一度サインインしてください。" | "デバイスが無効化されました。再認証が必要です。" | "削除されました" (was removed) is plain. "無効化" (invalidated) and "再認証" (re-authentication) are jargon. |
| "招待してくれた方に新しいリンクを送ってもらってください。" | "管理者に連絡してください。" | Same pattern as EN: relational ("the person who invited you") not role-based ("administrator"). |
| "準備中です。すぐに完了します。" | "初期化処理を実行中です。" | "準備中" (getting ready) vs "初期化処理" (initialization process). Users don't care what the system is doing internally. |
| "お使いのブラウザはパスキーに対応していません。" | "WebAuthn APIがサポートされていません。" | Names the thing the user knows (browser, passkey) not the spec. |

### Patterns to maintain

1. **Soft error openers.** "Something went wrong..." / "エラーが発生しました..." — not "Failed" / "失敗しました"
2. **Casual actions.** "Try refreshing" / "ページを更新してみてください" — not "Please retry" / "再試行してください"
3. **Relational references.** "The person who invited you" / "招待してくれた方" — not role labels
4. **Product noun = ファミリー.** Use 家族 only when describing the social relationship, not the product scope
5. **Describe what happens, not the technology.** "Your device will ask..." not "Biometric authentication..."
6. **No E2EE claims at L0/L1.** Server decrypts for LiveView. Say "private" not "only you can read"

## What we don't know yet

- The one-sentence pitch a user would give to a friend — doesn't exist; will come from dogfooding
- Whether "letters" becomes a core mechanic or a discarded idea
- What the actual differentiator is that makes someone choose this over just using Signal group chats
- Whether "neighborhood" reads as geographic or abstract to real users
