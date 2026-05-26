---
status: accepted
---

# Name the IMAP seam between BaseAdapter and provider-specific connectors

Both email connectors (Gmail, Yahoo Mail) use IMAP-like protocols but re-implement search criteria, pagination, and message parsing independently. `BaseAdapter` defines seven `NotImplementedError` methods but captures no shared IMAP behaviour. The real seam — between "IMAP protocol" and "provider-specific auth and label names" — is unnamed despite two concrete adapters existing (which makes it a real seam, not a hypothetical one).

Extract an intermediate IMAP adapter between `BaseAdapter` and the two concrete connectors, pushing shared search, pagination, and body-parsing logic there. Each concrete connector implements only auth, label names, and provider-specific quirks. Shared logic is tested once against the IMAP adapter with a mock IMAP client; adding a third IMAP connector requires only auth and labels.
