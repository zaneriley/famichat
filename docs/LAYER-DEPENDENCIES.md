# Famichat - Layer Dependencies & Decision Tree

**Last Updated**: 2025-10-05

---

## Visual Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 0: FOUNDATION (Solo Parent)                              │
│ Goal: Prove tech stack works                                   │
│ Users: 1 (you)                                                  │
│ Duration: 2 weeks                                               │
│                                                                 │
│ Deliverables:                                                   │
│ ✓ Self-hosted Phoenix + Signal Protocol encryption             │
│ ✓ Send/receive encrypted messages to self via LiveView         │
│ ✓ Performance <200ms                                            │
└─────────────────────────────────────────────────────────────────┘
                            ↓
                    [VALIDATE OR KILL]
                            ↓
                    ┌───────────────┐
                    │ Tech works?   │
                    └───────────────┘
                      ↙           ↘
                 YES ↙             ↘ NO
                    ↙               ↘
                   ↓                 ↓
┌─────────────────────────────┐   ┌──────────────────────────┐
│ LAYER 1: DYAD               │   │ KILL/PIVOT:              │
│ (Parent + Spouse)           │   │ - Signal too complex?    │
│                             │   │ - Self-hosting broken?   │
│ Goal: Prove family          │   │ - Performance bad?       │
│       messaging core        │   │ - LiveView UX clunky?    │
│ Users: 2 (you + wife)       │   │                          │
│ Duration: 3 weeks           │   │ → Simplify encryption    │
│                             │   │ → Use managed hosting    │
│                             │   │ → Consider native app    │
│                             │   └──────────────────────────┘
│ Deliverables:               │
│ ✓ 1:1 encrypted messaging   │
│ ✓ Photo sharing             │
│ ✓ Real-time updates         │
│ ✓ Replaces SMS/WhatsApp     │
│                             │
│ JTBD Validation:            │
│ → #2 Emotional bonding      │
└─────────────────────────────┘
            ↓
    [VALIDATE OR KILL]
            ↓
      ┌─────────────┐
      │ Daily use?  │
      │ Replaces    │
      │ SMS?        │
      └─────────────┘
        ↙         ↘
    YES ↙           ↘ NO
       ↓             ↓
┌─────────────────────────────┐   ┌──────────────────────────┐
│ LAYER 2: TRIAD              │   │ KILL/PIVOT:              │
│ (Parent + Spouse + Kid)     │   │ - Not used daily?        │
│                             │   │ - Still using WhatsApp?  │
│ Goal: Prove family group    │   │ - Not "cozy" feeling?    │
│       + logistics           │   │                          │
│ Users: 3 (+ 8-12yo kid)     │   │ → Re-examine hypothesis  │
│ Duration: 4 weeks           │   │ → Maybe WhatsApp is fine │
│                             │   └──────────────────────────┘
│ Deliverables:               │
│ ✓ Family group chat         │
│ ✓ Shared lists/calendar     │
│ ✓ Voice messages (kid UX)   │
│ ✓ Age-appropriate UI        │
│                             │
│ JTBD Validation:            │
│ → #1 Logistics coordination │
│ → #2 Multi-gen bonding      │
└─────────────────────────────┘
            ↓
    [VALIDATE OR KILL]
            ↓
      ┌─────────────┐
      │ Kid         │
      │ engages?    │
      │ Logistics   │
      │ used?       │
      └─────────────┘
        ↙         ↘
    YES ↙           ↘ NO
       ↓             ↓
┌─────────────────────────────┐   ┌──────────────────────────┐
│ LAYER 3: EXTENDED FAMILY    │   │ KILL/PIVOT:              │
│ (+ Grandparent)             │   │ - Kid doesn't use?       │
│                             │   │ - Too complex for kid?   │
│ Goal: Prove multi-gen       │   │ - Logistics unused?      │
│       accessibility         │   │                          │
│ Users: 4 (+ grandparent)    │   │ → Simplify drastically   │
│ Duration: 5 weeks           │   │ → Rethink UX for kids    │
│                             │   └──────────────────────────┘
│ Deliverables:               │
│ ✓ Grandparent onboarding    │
│ ✓ Voice-first UI            │
│ ✓ Large text mode           │
│ ✓ PWA install option        │
│                             │
│ JTBD Validation:            │
│ → #5 Multi-gen accessibility│
│ → #2 Extended bonding       │
└─────────────────────────────┘
            ↓
    [VALIDATE OR KILL]
            ↓
      ┌─────────────┐
      │ Grandparent │
      │ onboards    │
      │ without     │
      │ help?       │
      └─────────────┘
        ↙         ↘
    YES ↙           ↘ NO
       ↓             ↓
       ↓        ┌──────────────────────────┐
       ↓        │ KILL/PIVOT:              │
       ↓        │ - Can't onboard alone?   │
       ↓        │ - Needs constant help?   │
       ↓        │ - Prefers phone calls?   │
       ↓        │                          │
       ↓        │ → Voice-first redesign   │
       ↓        │ → Question if achievable │
       ↓        └──────────────────────────┘
       ↓
       ↓ [SPLIT INTO PARALLEL PATHS]
       ↓
       ├─────────────────────────────┬─────────────────────────────┐
       ↓                             ↓                             ↓
┌──────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│ LAYER 4:         │   │ LAYER 5:             │   │ LAYER 6:             │
│ AUTONOMY & SAFETY│   │ TRUSTED NETWORK      │   │ COZY FEATURES        │
│                  │   │                      │   │                      │
│ (+ Teen)         │   │ (+ 2-3 families)     │   │ (Differentiation)    │
│                  │   │                      │   │                      │
│ Goal: Prove      │   │ Goal: Prove          │   │ Goal: Prove "cozy"   │
│   parent/teen    │   │   family-to-family   │   │   creates unique     │
│   trust model    │   │   coordination       │   │   experience         │
│                  │   │                      │   │                      │
│ Users: Replace   │   │ Users: +6-12 people  │   │ Users: All layers    │
│   kid with teen  │   │   (2-3 families)     │   │   validated          │
│                  │   │                      │   │                      │
│ Duration: 6 weeks│   │ Duration: 7 weeks    │   │ Duration: Ongoing    │
│                  │   │                      │   │                      │
│ Deliverables:    │   │ Deliverables:        │   │ Deliverables:        │
│ ✓ Age-based      │   │ ✓ Family invites     │   │ ✓ Slow messaging     │
│   autonomy       │   │ ✓ Shared channels    │   │ ✓ Custom themes      │
│ ✓ Check-ins      │   │ ✓ Carpool coord      │   │ ✓ Family "space"     │
│ ✓ Safe zones     │   │ ✓ Bounded network    │   │ ✓ No read receipts   │
│ ✓ Share ETA      │   │   (3-5 families max) │   │ ✓ Weekly digests     │
│ ✓ Emergency SOS  │   │                      │   │                      │
│ ✓ Transparency   │   │ JTBD Validation:     │   │ JTBD Validation:     │
│   dashboard      │   │ → #1 Extended        │   │ → "Cozy" = anti-     │
│                  │   │      logistics       │   │   capitalist space   │
│ JTBD Validation: │   │                      │   │ → Lower anxiety      │
│ → #3 Safety      │   │ [VALIDATE OR KILL]   │   │ → Family identity    │
│ → #4 Autonomy    │   │                      │   │                      │
│                  │   │ ┌──────────────────┐ │   │ [CONTINUOUS          │
│ [VALIDATE/KILL]  │   │ │ Families         │ │   │  EXPERIMENTATION]    │
│                  │   │ │ coordinate?      │ │   │                      │
│ ┌──────────────┐ │   │ │ Network small?   │ │   │ ┌──────────────────┐ │
│ │ Teen uses?   │ │   │ └──────────────────┘ │   │ │ Features used?   │ │
│ │ Feels        │ │   │   ↙            ↘     │   │ │ Lower anxiety?   │ │
│ │ trusted?     │ │   │YES ↙              ↘NO│   │ │ Unique identity? │ │
│ │ Parent peace?│ │   │  ↓                ↓  │   │ └──────────────────┘ │
│ └──────────────┘ │   │ ✓ Success    ✗ Kill │   │   ↙            ↘     │
│   ↙          ↘   │   │              or      │   │YES ↙              ↘NO│
│YES ↙            ↘NO  │              Pivot   │   │  ↓                ↓  │
│  ↓              ↓│   │                      │   │ ✓ Success    ✗ Remove│
│ ✓ Success  ✗ Kill│   └──────────────────────┘   │              features│
│            or    │                               └──────────────────────┘
│            Pivot │
└──────────────────┘

[L4 AND L5 CAN RUN IN PARALLEL AFTER L3]
[L6 CAN EXPERIMENT THROUGHOUT, BUT VALIDATES AFTER L3-5]
```

---

## Decision Tree: Technology Choices

```
┌─────────────────────────────────────────────────────────────┐
│ START: What's the right tech stack?                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────────────────┐
                    │ L0-L3: Foundation │
                    │ through Extended  │
                    │ Family            │
                    └───────────────────┘
                            ↓
              ┌─────────────────────────────────┐
              │ Phoenix LiveView +              │
              │ Signal Protocol                 │
              │ (Web UI for dogfooding Layers   │
              │  0-3, backend encryption)       │
              └─────────────────────────────────┘
                            ↓
                    [VALIDATE L3]
                            ↓
              ┌─────────────────────────────┐
              │ Did LiveView UX work?       │
              │ - Cozy feeling achieved?    │
              │ - Grandparent accessible?   │
              │ - Daily usage confirmed?    │
              └─────────────────────────────┘
                ↙                         ↘
            YES ↙                           ↘ NO
               ↓                             ↓
    ┌──────────────────────┐   ┌─────────────────────────────┐
    │ L4: Need native      │   │ PIVOT: LiveView failed      │
    │ location features?   │   │                             │
    └──────────────────────┘   │ Options:                    │
               ↓                │ A) Redesign LiveView UX     │
               │                │ B) Build native app         │
               │                │    (Flutter/iOS/Android)    │
               │                │                             │
               │                │ Timeline: +4-6 months       │
               │                └─────────────────────────────┘
               ↓
    ┌──────────────────────┐
    │ Can browser          │
    │ geolocation work?    │
    │                      │
    │ - Geofencing?        │
    │ - Background?        │
    │ - Battery OK?        │
    └──────────────────────┘
        ↙              ↘
    YES ↙                ↘ NO
       ↓                  ↓
┌──────────────┐   ┌──────────────────────┐
│ Continue     │   │ ADD: Capacitor       │
│ LiveView     │   │ (Native wrapper)     │
│              │   │                      │
│ - Faster     │   │ - Native location    │
│ - Simpler    │   │ - App install needed │
│              │   │ - Deploy to stores   │
│ Tradeoff:    │   │                      │
│ - Clunky     │   │ Tradeoff:            │
│   permissions│   │ - Grandma installs   │
│ - Battery    │   │   app (friction)     │
│   drain      │   │                      │
└──────────────┘   └──────────────────────┘
       ↓                  ↓
       └────────┬─────────┘
                ↓
    ┌──────────────────────┐
    │ L5-L6: Continue      │
    │ with proven stack    │
    │                      │
    │ Only pivot to native │
    │ app if:              │
    │ - UX fundamentally   │
    │   broken             │
    │ - Performance issues │
    │ - User rejection     │
    │ - L4 location needs  │
    │   require native     │
    └──────────────────────┘
```

---

## Parallel vs Sequential Work

### Sequential (Must validate in order)

```
L0 → L1 → L2 → L3
└──────────────┘
    CRITICAL PATH
    (~16 weeks)
```

**Why sequential?**
- L0: Foundation must work before anything else
- L1: Dyad proves messaging core before adding complexity
- L2: Triad proves group dynamics before multi-gen
- L3: Extended family proves accessibility before advanced features

**Each layer gates the next:**
- Can't test kid engagement (L2) until spouse engagement proven (L1)
- Can't test grandparent accessibility (L3) until kid UX proven (L2)
- Can't add teen autonomy (L4) until multi-gen works (L3)

### Parallel (After L3 validation)

```
L3 validates
    ↓
    ├─→ L4: Autonomy & Safety (6 weeks)
    │
    ├─→ L5: Trusted Network (7 weeks)
    │
    └─→ L6: Cozy Features (ongoing)
```

**Why parallel?**
- L4 and L5 solve different JTBDs (safety vs coordination)
- Different user segments (teens vs multi-family)
- Independent feature sets (location vs invites)
- Can explore simultaneously without blocking

**L6 is continuous:**
- Experiment with "cozy" features throughout
- Layer 1-2: Test no read receipts, slow mode
- Layer 3: Test customization, themes
- Layer 4-5: Validate if "cozy" drives retention

---

## Risk Mitigation by Layer

### Layer 0 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Signal Protocol too complex | Time-box to 5 weeks (Sprint 10) | Defer E2EE to Layer 2, use TLS only |
| Self-hosting broken | Use DigitalOcean for testing | Managed hosting (abandon self-host) |
| Performance bad | Profile + optimize | Adjust budget to 300ms |
| LiveView UX inadequate | Iterate on design, add PWA features | Pivot to native app (+4-6 months) |

### Layer 1 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Not used daily | Daily check-in prompts | Kill project (not compelling) |
| Still use WhatsApp | Understand why (UX? Features?) | Redesign or pivot |
| Not "cozy" | Iterate on design (colors, spacing) | Re-examine hypothesis |

### Layer 2 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Kid doesn't engage | Simplify UI, add games/stickers | Adult-only product |
| Logistics unused | Integrate with existing workflows | Messaging-only (drop logistics) |
| Voice messages fail | Ensure easy recording/playback | Text-only |

### Layer 3 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Grandparent can't onboard | Video tutorial, phone support | Pre-setup for them |
| Needs tech support | Improve onboarding UX | Accept support burden |
| Prefers phone calls | Understand why (too complex?) | Simplify or kill multi-gen |

### Layer 4 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Teen refuses (surveillance) | Emphasize transparency, teen input | Messaging-only |
| Parent wants more control | Explain trust model, iterate | Tiered autonomy levels |
| Geofencing unreliable | Test extensively, improve accuracy | Check-ins only |
| Battery drain | Optimize location polling | Manual check-ins only |

### Layer 5 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Families don't coordinate | Start with real need (carpool) | Family-only product |
| Network grows too large | Hard limit (5 families max) | Remove feature |
| Boundary creep | Reject feature requests firmly | Family-only scope |

### Layer 6 Risks

| Risk | Mitigation | Fallback |
|------|------------|----------|
| Slow features ignored | Make optional, not default | Remove slow features |
| Customization unused | Provide templates, examples | Standard theme only |
| Not differentiated | Focus on core value (trust, privacy) | Accept niche product |

---

## Timeline & Resource Allocation

### Estimated Timeline (Best Case)

```
Layer 0: 2 weeks  (Weeks 1-2)
Layer 1: 3 weeks  (Weeks 3-5)
Layer 2: 4 weeks  (Weeks 6-9)
Layer 3: 5 weeks  (Weeks 10-14)
───────────────────────────────
Critical Path: 14 weeks (~3.5 months)

[After L3 validation, parallel work]

Layer 4: 6 weeks  (Weeks 15-20)
Layer 5: 7 weeks  (Weeks 15-21)  } Parallel
Layer 6: Ongoing  (Weeks 15+)    }
───────────────────────────────
Total to full feature set: ~21 weeks (~5 months)
```

### Estimated Timeline (Realistic, with pivots)

```
Layer 0: 3 weeks  (1 week buffer for MLS issues)
Layer 1: 4 weeks  (1 week UX iteration)
Layer 2: 6 weeks  (2 weeks kid UX iteration)
Layer 3: 7 weeks  (2 weeks grandparent accessibility)
───────────────────────────────
Critical Path: 20 weeks (~5 months)

[After L3 validation, parallel work]

Layer 4: 8 weeks  (2 weeks native wrapper issues)
Layer 5: 9 weeks  (2 weeks social dynamics iteration)
Layer 6: Ongoing
───────────────────────────────
Total to full feature set: ~29 weeks (~7 months)
```

### Resource Requirements per Layer

| Layer | Dev Time | User Testing Time | Total |
|-------|----------|-------------------|-------|
| L0 | 2 weeks | 0 (solo testing) | 2 weeks |
| L1 | 2 weeks | 2 weeks (you + wife) | 3 weeks |
| L2 | 3 weeks | 3 weeks (+ kid) | 4 weeks |
| L3 | 3 weeks | 4 weeks (+ grandparent) | 5 weeks |
| L4 | 4 weeks | 4 weeks (teen testing) | 6 weeks |
| L5 | 3 weeks | 6 weeks (multi-family) | 7 weeks |
| L6 | Ongoing | Continuous feedback | N/A |

**Key insight:** User testing time exceeds dev time in later layers
- L1: 2 weeks dev, 2 weeks validation
- L3: 3 weeks dev, 4 weeks validation
- L5: 3 weeks dev, 6 weeks validation (multi-family coordination slower)

---

## JTBD Mapping to Layers

```
┌────────────────────────────────────────────────────────────┐
│ JTBD #1: Logistics Coordination                           │
│ "When I need to coordinate family activities"             │
└────────────────────────────────────────────────────────────┘
                            ↓
    ┌───────────────┬──────────────┬──────────────────┐
    │ L2: Triad     │ L5: Network  │ L6: Slow (async) │
    │ - Lists       │ - Carpool    │ - Weekly digest  │
    │ - Calendar    │ - Playdates  │ - Planning mode  │
    │ - Polls       │ - Emergencies│                  │
    └───────────────┴──────────────┴──────────────────┘

┌────────────────────────────────────────────────────────────┐
│ JTBD #2: Emotional Bonding                                │
│ "When I want to stay connected with family"               │
└────────────────────────────────────────────────────────────┘
                            ↓
    ┌───────────────┬──────────────┬──────────────────┐
    │ L1: Dyad      │ L3: Extended │ L6: Cozy features│
    │ - 1:1 messages│ - Grandparent│ - Slow messages  │
    │ - Photo share │   voice msgs │ - Family space   │
    │ - Check-ins   │ - Video msgs │ - Memories       │
    └───────────────┴──────────────┴──────────────────┘

┌────────────────────────────────────────────────────────────┐
│ JTBD #3: Safety & Peace of Mind                           │
│ "When I need to know family is safe"                      │
└────────────────────────────────────────────────────────────┘
                            ↓
    ┌───────────────┬──────────────┬──────────────────┐
    │ L4: Autonomy  │ L5: Network  │                  │
    │ - Check-ins   │ - Emergency  │                  │
    │ - Safe zones  │   contacts   │                  │
    │ - Share ETA   │ - Neighbor   │                  │
    │ - SOS         │   awareness  │                  │
    └───────────────┴──────────────┴──────────────────┘

┌────────────────────────────────────────────────────────────┐
│ JTBD #4: Teen Autonomy                                     │
│ "When I want privacy while being responsible"             │
└────────────────────────────────────────────────────────────┘
                            ↓
    ┌───────────────────────────────────────────────────┐
    │ L4: Autonomy & Safety                             │
    │ - Private 1:1 (parent can't read)                 │
    │ - Age-based autonomy levels                       │
    │ - Transparency dashboard (teen sees what parent   │
    │   sees)                                           │
    │ - Reciprocal location sharing                     │
    └───────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ JTBD #5: Multi-Generational Accessibility                │
│ "When family tech literacy varies widely"                 │
└────────────────────────────────────────────────────────────┘
                            ↓
    ┌───────────────┬──────────────┬──────────────────┐
    │ L2: Kid UX    │ L3: Grandpa  │ L6: Cozy (simple)│
    │ - Voice msgs  │ - Large text │ - No complexity  │
    │ - Simple UI   │ - Voice-first│ - Clear UI       │
    │ - Emojis      │ - Onboarding │ - No jargon      │
    └───────────────┴──────────────┴──────────────────┘
```

---

## Summary: The Incremental Path

**Foundation (L0-L3): Prove Core Value**
- 14-20 weeks (3.5-5 months realistic)
- Sequential validation (each layer gates next)
- Kill criteria at each gate (don't build on shaky foundation)
- Outcome: Family messaging + accessibility proven

**Extension (L4-L5): Prove Differentiation**
- 6-9 weeks each, can run parallel
- Advanced features (safety, coordination)
- Kill criteria if core hypotheses fail
- Outcome: Full JTBD coverage validated

**Refinement (L6): Prove "Cozy"**
- Ongoing experimentation
- Continuous feedback loop
- Iterate on feel, not features
- Outcome: Unique experience that builds loyalty

**Critical Decisions:**
1. **After L1**: Is messaging core compelling? (If no, kill)
2. **After L3**: Is LiveView sufficient? (If no, pivot to native app - Flutter/iOS/Android)
3. **After L4**: Do location features require native app? (If yes, evaluate Capacitor vs full native)
4. **After L4/L5**: Is differentiation working? (If no, simplify to core)

---

**Last Updated**: 2025-10-05
**Version**: 1.0
**Status**: Strategic roadmap - guides all technical decisions
