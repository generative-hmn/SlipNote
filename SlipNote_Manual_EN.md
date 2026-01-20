# SlipNote User Manual

SlipNote is a macOS menu bar app for quick note-taking and organization.

## Quick Input

Create notes quickly from anywhere using global shortcuts.

- **Cmd+Shift+N** - Open quick input window
- Type your note, then **Cmd+Number(0-9)** - Save to category
- **Esc** - Close window (content is cached)
- **Cmd+A** - Select all text
- **Cmd+V/C/X/Z** - Paste/Copy/Cut/Undo

## Browser

Open the browser window to manage your notes.

- **Cmd+Shift+B** - Toggle browser window

### Category Filter

- **Cmd+Number(0-9)** - Toggle category filter
- **Cmd+T** - Toggle Trash filter
- **Cmd+Up/Down** - Navigate between categories
- **Esc** - Clear filter and search

### Slip Navigation

- **Up/Down Arrow** - Move selection
- **Enter** - View selected slip details
- **Cmd+Enter** - Open selected slip in edit mode
- **Double-click** - View slip details

### Slip Selection

- **Click** - Single select
- **Cmd+Click** - Toggle multi-selection
- **Shift+Click** - Range selection
- **Esc** - Clear multi-selection

### Slip Actions

- **Option+Number(0-9)** - Change category of selected slip(s)
- **Cmd+Delete** - Move selected slip(s) to Trash
- **Cmd+C** - Copy selected slip(s) as markdown
- **Cmd+P** - Pin/Unpin slip (pinned slips shown at top)
- **Drag & Drop** - Move slips to categories

### Search

- **Cmd+F** - Focus search field

### Detail View

- **Cmd+Enter** - Start editing
- **Esc** - Go back (when not editing)
- **Left/Right Arrow** - Browse version history

### Other

- **Cmd+N** - Create new slip
- **Cmd+,** - Open settings

## Categories

Default categories:
- **0** Inbox - Default save location
- **1** Idea
- **2** Plan
- **3** Task
- **4** Event
- **5** Journal
- **6** Library
- **7** Reference
- **8** Archive
- **9** Temp

You can customize category names and colors in Settings.

## Pin Slips

Pin important slips to keep them at the top of the list.

- **Cmd+P** - Pin/Unpin selected slip
- **Right-click > Pin to Top / Unpin** - Pin/Unpin
- Pinned slips are displayed with a 📌 icon at the top of the list.

## Export

- Right-click category > **Export to Markdown** - Export entire category
- **Cmd+C** - Copy selected slips as markdown

## Auto Backup

Configure automatic backups in Settings > Data tab.

- **Off** - Disable auto backup
- **Daily** - Backup every day
- **Weekly** - Backup every week
- **Monthly** - Backup every month

Backup files are stored in `~/Library/Application Support/SlipNote/Backups/` and the last 10 backups are kept.

## Spotlight Search

All slips in SlipNote are searchable via macOS Spotlight.

- Press **Cmd+Space** to open Spotlight and search for slip content
- Click on a search result to open the slip in SlipNote browser.

## URL Scheme

Control SlipNote from external apps or automation tools.

```
# Create new slip
slipnote://new?content=Note%20content&category=1

# Open browser
slipnote://browse
slipnote://browse?category=3

# Search
slipnote://search?query=keyword

# Open input window
slipnote://input
```

**Use cases:**
- Create quick notes from macOS Shortcuts app
- Alfred/Raycast workflow integration
- Automated note creation via scripts

## Data

- Settings > Data tab to view data location and create backups
- All data is stored locally

---

Copyright © 2026 gamzabi@me.com. All Rights Reserved.
