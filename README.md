# SPPID Oracle / SQL Queries

A collection of SQL queries I use as a SmartPlant P&ID (SPPID) administrator to
investigate and correct data in the SPPID database (Oracle, with a few SQL Server examples).

All schema names, IDs, drawing numbers and tags are fake placeholders (`DEMO_PID`,
`DEMO-DWG-001`, `<SOME_ID>`). Replace them with your own values.

## Contents (`sppid_oracle_queries.sql`)
- **A. Bulk data corrections** - move items between units, pad tag sequence numbers,
  update pipe run and process data from Excel, rename drawings, replace title blocks.
- **B. Clean-up** - bad connectors, orphaned representations, corrupted SmartFrames, label bugs.
- **C. Understanding the data model** - how lines, connectors and instruments are stored.
- **D. Oracle admin utilities** - users, tablespaces, sessions.

## Warning
Many of these statements change SPPID data directly. Always test on a backup or a test
schema first, check the row count with a SELECT, and confirm that this kind of change is
allowed under your SPPID support agreement and your company's rules.
