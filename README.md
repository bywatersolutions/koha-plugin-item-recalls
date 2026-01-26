# Koha Item Recalls Plugin

This Koha plugin adds item recall functionality, allowing patrons to recall items that are currently checked out by other patrons. When a recall is placed, the current borrower's due date is shortened and they receive a notification.

## Requirements

- Koha 21.05 or later
- Plugin system enabled

## Downloading

From the [release page](https://github.com/bywatersolutions/koha-plugin-item-recalls/releases) you can download the relevant `*.kpz` file.

## Installing

1. Enable plugins in your Koha installation:
   - Change `<enable_plugins>0</enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your `koha-conf.xml` file
   - Confirm that the path to `<pluginsdir>` exists and is writable by the web server
   - Restart your webserver
   - Restart memcached if you are using it

2. Enable the `UseKohaPlugins` system preference

3. Upload the `.kpz` file via the Koha plugin manager (Tools → Plugins)

## Setup

After installing the plugin:

1. **Configure HOLD notices**: Ensure each HOLD notice template ends with the following code (the plugin will attempt to add this automatically on install):

   ```
   --
   ID: <<reserves.reserve_id>>.
   --
   ```

   This is required for the plugin to identify and replace hold pickup notices with recall pickup notices.

2. **Set up cronjobs**:
   - Run the nightly cronjob daily to process overdue recalls and apply penalties:
     ```bash
     /path/to/koha/misc/cronjobs/plugins-nightly.pl
     ```
   - Ensure `process_message_queue.pl` runs after the plugin's `before_send_messages` hook processes notices

3. **Configure recall rules** in the plugin configuration (see below)

## What the Plugin Does on Install

- Creates a `plugin_recalls` table to track recalls
- Creates two notice templates:
  - `RECALL_PLUGIN` - Sent to the borrower when their item is recalled
  - `RECALL_PICKUP_PLUGIN` - Sent to the recaller when the item is ready for pickup
- Updates existing HOLD notices to include the reserve ID

## Configuration

### Recall Rules

Rules are configured via YAML in the plugin configuration page. Rules are evaluated top to bottom, and the **first matching rule wins**. Order your rules from most specific to least specific.

#### YAML Configuration Example

```yaml
# Specific rule for DVDs at the Main branch for Faculty
- branchcode: MAIN
  categorycode: FACULTY
  itemtype: DVD
  due_date_length: 3
  pickup_date_length: 7
  past_due_fine_amount: 5.00
  past_due_restrict: 1
  checkout_age_minimum: 7

# Rule for all items at the Main branch
- branchcode: MAIN
  due_date_length: 7
  pickup_date_length: 10
  past_due_fine_amount: 2.00
  past_due_restrict: 0

# Default catch-all rule (no criteria = matches everything)
- due_date_length: 14
  pickup_date_length: 14
  past_due_restrict: 0
```

#### Rule Fields

| Field | Description | Required |
|-------|-------------|----------|
| `branchcode` | Library branch code (pickup location). Leave empty to match all branches. | No |
| `categorycode` | Patron category code. Leave empty to match all categories. | No |
| `itemtype` | Item type code. Leave empty to match all item types. | No |
| `due_date_length` | Number of days from today for the new due date. | Yes |
| `pickup_date_length` | Number of days the recaller has to pick up the item once it's available. | Yes |
| `past_due_fine_amount` | Fine amount charged if the borrower fails to return the recalled item by the new due date. | No |
| `past_due_fine_amount_is_daily` | If set to `1`, the fine is charged daily instead of once. | No |
| `past_due_restrict` | If set to `1`, the borrower will be restricted if they fail to return the item by the new due date. | No |
| `checkout_age_minimum` | Minimum number of days the item must have been checked out before a recall can be placed. | No |

### Auto-Recall

The plugin configuration includes an option to enable auto-recall. When enabled, the plugin will automatically recall eligible items during the `before_send_messages` hook.

## How Recalls Work

### Requirements for a Recall

For an item to be recalled:
- The item must be currently checked out
- A hold must exist on the item
- The hold must be an **item-level hold** (not title-level)
- The recalling patron must be **first in the hold queue** (priority 1)
- A matching recall rule must exist

### Recall Process

1. A patron places an item-level hold on a checked-out item
2. A recall button appears next to the hold (in both staff client and OPAC)
3. When clicked, the recall:
   - Shortens the current borrower's due date according to the rule
   - Sends a `RECALL_PLUGIN` notice to the current borrower
   - Records the recall in the `plugin_recalls` table
4. When the item is returned:
   - The plugin replaces the standard hold pickup notice with `RECALL_PICKUP_PLUGIN`
   - Sets the hold expiration date based on `pickup_date_length`
5. The nightly cronjob processes overdue recalls:
   - Applies fines if configured
   - Adds restrictions if configured
   - Removes restrictions once items are returned

## Notice Templates

You can customize the notice templates in Tools → Notices & Slips:

- **RECALL_PLUGIN**: Notifies the current borrower that their item has been recalled
- **RECALL_PICKUP_PLUGIN**: Notifies the recaller that their recalled item is ready for pickup

## Video Tutorial

See the plugin in action: https://youtu.be/Vb6eoKKnPnc
