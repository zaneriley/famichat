1. Information Architecture (IA)

We will structure the IA around the bottom tab navigation we previously discussed, expanding on the content and functionality within each tab.

Bottom Tab Navigation:

1.  Letters (Primary Tab - Default Overview Screen)
    *   Letters Inbox
        *   List of Letters (grouped by sender, date - visually distinct 'letter' style)
        *   Unread Letter Indicators
        *   Letter Previews (snippet of content, sender avatar)
        *   "Write a Letter" Button (prominent action button)
    *   Sent Letters (Optional - could be in profile or a sub-section)
    *   Drafts (If implemented in MVP)

2.  Calls
    *   Call History (recent calls list)
    *   Start a Call Button
    *   List of Family Members (Online/Recently Online Status - for quick call initiation)

3.  Family Space (Cozy Features Hub)
    *   Shared Family Calendar
        *   Monthly View (primary)
        *   Event Listings (upcoming events)
        *   Add Event Button (permissions-based)
    *   Photo Albums
        *   List of Albums (visual thumbnails)
        *   "Create Album" Button (permissions-based)
        *   Within Album: Photo Grid View, Add Photos Button
    *   (Future - Potential additions for V1: Shared Lists, Location/Weather, "Memory Lane" - but not in MVP IA for simplicity)

4.  Search
    *   Search Bar (prominent at top)
    *   Search Filters (optional for MVP, but plan for future: by sender, date, content type)
    *   Search Results Display (visually clear, relevant snippets, thumbnails)

5.  Profile (User & Family Settings)
    *   User Profile
        *   User Avatar & Name
        *   "Thinking of You" Status (editable)
        *   Notification Settings (granular control)
        *   Personal Aesthetic Customization (theme selection, limited for MVP)
        *   Language Selection
    *   Family Settings (Admin Access Only - indicated by a visual cue like a lock icon next to "Family Settings")
        *   Admin Panel Button (prominent for Admin users, hidden or greyed out for others) - Leads to:
            *   User Management (Invite, Remove, Role Assignment)
            *   Family Aesthetic Customization (themes, colors, family icon - basic for MVP)
            *   Feature Toggles (if implementing feature on/off for families in later versions - placeholder for now)
            *   Parent Chat Button (prominent for Parent/Admin roles) - Leads to:
                *   Parent Chat Screen (real-time messaging for Admins)
    *   Help & Support (Basic FAQs or link to documentation - for MVP)
    *   About & Version Info

Key IA Considerations:

    Letters as Central Hub: "Letters" tab is first and default, emphasizing its core role.
    Cozy Features Grouped: "Family Space" is a dedicated area for features beyond direct messaging, keeping the 'cozy' elements together.
    Search Accessibility: "Search" is readily available for finding past content across the app.
    Profile & Settings Unified: "Profile" tab encompasses both user-specific settings and family-level settings (with admin access control).
    Parent/Admin Features Segregation: Admin features are accessible via the "Profile" tab within "Family Settings," clearly marked as Admin-only and separate from the general user experience. Parent Chat is also within this Admin area. This keeps the core family UX clean and focused.
    MVP Simplicity: IA is streamlined to focus on MVP features. Future features (Shared Lists, etc.) can be easily integrated into "Family Space" or "Profile" in later iterations.

2. Overview Screen Design (Letters Inbox)

The "Letters" tab will be the default Overview Screen upon opening the app.  Let's design the layout and key elements:

Screen Name: Letters Inbox

Elements & Layout (Top to Bottom):

    App Header (Top Bar):
        Left Side: Family Icon/Crest (Customizable by Admin - visual branding). If no custom icon set, use a default family icon.
        Center: "[Family Name] Home" - App title, reinforcing personalization.
        Right Side: "Write a Letter" Button (prominent action button, likely an icon of a pen and paper or a stylized envelope + icon) - Floating Action Button style, visually distinct and always accessible on this screen.

    Letters List (Main Content Area - Below Header):
        List of Letters: Displayed in reverse chronological order (newest first).
        Visual "Letter" Style for Each Item:
            Sender Avatar (Left): Circular user avatar, indicates sender.
            Sender Name (Top Left, Bold): Clear sender identification.
            Subject Line (Below Sender Name, optional, slightly smaller font): If the letter has a subject, display it here. If no subject, show a short preview of the message content instead.
            Letter Preview Snippet (Below Subject/Sender Name, smaller font, truncated if long): A short excerpt of the letter's content to give context (e.g., "Thinking of you today! Just wanted to…").
            Timestamp (Top Right, smaller, muted font): Relative timestamp (e.g., "5 mins ago," "Yesterday," "3 days ago").
            Unread Indicator (Visual Cue - Bold Text, Unread Dot/Badge): Clearly show unread letters.
            Optional: Media Indicator Icon (Small icon to show if letter contains photo, video, voice note - near timestamp): Provides quick context of letter content.
            Visual "Letter" Background (Subtle styling to reinforce 'letter' metaphor - very slight texture, rounded corners, or a faint border - keep it clean and not distracting): Enhance the 'letter' feel visually.
        "No Letters Yet" State (If Inbox is Empty): Friendly placeholder message and guidance: "Your mailbox is empty. Write a letter to your family!" with a prominent "Write a Letter" button.

    Bottom Tab Navigation (Fixed at Bottom):
        Letters (Active/Highlighted tab visually)
        Calls
        Family Space
        Search
        Profile