# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Koha ILS plugin that adds item recall functionality. Patrons can recall items that are currently checked out by other patrons, triggering a shortened due date for the current borrower and notifications.

## Build and Release

The plugin uses Gulp for building and GitHub Actions for CI/CD.

**Build the KPZ package locally:**
```bash
npm install
gulp build
```

This creates a `.kpz` file (Koha Plugin Zip) with the version from `package.json`.

**Run tests (requires koha-testing-docker):**
Tests run via GitHub Actions using koha-testing-docker. The test suite is at `t/00-load.t` and verifies that all Perl modules load correctly.

## Architecture

### Main Plugin Module
`Koha/Plugin/Com/ByWaterSolutions/ItemRecalls.pm` - Core plugin implementing:
- `configure()` - Plugin configuration UI (YAML-based recall rules)
- `api()` - Handles recall API actions: `can_item_be_recalled`, `recall_item`, `recall_course_items`
- `can_recall()` - Rule matching logic (branchcode, categorycode, itemtype)
- `recall_item()` - Creates recall, adjusts due date, sends RECALL_PLUGIN notice
- `before_send_messages()` - Hook that runs before Koha's message queue, handles auto-recalls and pickup notices
- `cronjob_nightly()` - Processes overdue recalls (restrictions, fines), cleans up data
- `intranet_js()` / `opac_js()` - Injects JavaScript via hooks
- `install()` - Creates `plugin_recalls` table and notice templates

### Cronjobs
- `cronjob_nightly.pl` - Run daily to process overdue recalls and apply penalties
- `cronjob.pl` - Placeholder (contains only `1;`)

### Templates
- `configure.tt` - Configuration interface
- `intranetuserjs.tt` / `opacuserjs.tt` - JavaScript injected into staff/OPAC interfaces

### Database
The plugin creates a `plugin_recalls` table with columns:
- `issue_id` - Links to checkout (foreign key to `issues`)
- `reserve_id` - Links to hold (foreign key to `reserves`)
- `rule` - YAML serialized recall rule that was applied

### Notice Templates
Created on install:
- `RECALL_PLUGIN` - Sent to borrower when their item is recalled
- `RECALL_PICKUP_PLUGIN` - Sent to recaller when item is ready for pickup

## Recall Rules Configuration

Rules are configured via YAML in the plugin configuration. Each rule can specify:
- `branchcode`, `categorycode`, `itemtype` - Matching criteria
- `due_date_length` - Days until new due date
- `past_due_fine_amount` - Fine for failing to return
- `past_due_fine_amount_is_daily` - Apply fine daily
- `past_due_restrict` - Restrict patron on failure
- `pickup_date_length` - Days for recaller to pick up
- `checkout_age_minimum` - Minimum days checked out before recall allowed

Rules are matched top-to-bottom; first match wins.

## Koha Integration Points

- Requires Koha 21.05+
- Uses Koha plugin hooks: `intranet_js`, `opac_js`, `before_send_messages`
- Integrates with: `Koha::Holds`, `Koha::Checkouts`, `C4::Letters`, `Koha::Account`
- HOLD notices must include `ID: <<reserves.reserve_id>>.` for pickup notice replacement
