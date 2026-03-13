# Table Wrapping Test

## Small table (should NOT get overlay - fits in window)

| Name | Age |
|------|-----|
| Alice | 30 |
| Bob | 25 |

## Wide table (should get overlay with wrapping)

| Feature | Description | Status | Notes |
|---------|-------------|--------|-------|
| Table cell wrapping | When a table is wider than the window, cells should wrap text to fit within the available width instead of requiring horizontal scrolling | In Progress | This is the feature we are currently implementing and testing |
| Overlay management | The overlay should appear when the cursor is outside the table and disappear when the cursor enters the table for editing | Done | Works with crossfade transition |
| Column width distribution | Columns are sized proportionally to their content width, with minimum and maximum constraints | Done | Min 60pt, max 50% of prose width

## Very wide table (>6 columns, should fall back to h-scroll)

| Col1 | Col2 | Col3 | Col4 | Col5 | Col6 | Col7 |
|------|------|------|------|------|------|------|
| a | b | c | d | e | f | g |
| h | i | j | k | l | m | n |

## Short content table (should NOT get overlay - all cells short)

| X | Y | Z |
|---|---|---|
| 1 | 2 | 3 |
| 4 | 5 | 6 |

## Medium table with mixed content

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/users | Returns a list of all users in the system with their profile information and recent activity |
| POST | /api/users | Creates a new user account with the provided details including name, email, and password |
| DELETE | /api/users/:id | Permanently removes a user and all associated data from the system |

Some regular text after the tables to make sure prose wrapping still works correctly. This paragraph should wrap at the window edge as usual, not affected by any table overlay logic.
