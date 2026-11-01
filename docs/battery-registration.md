# Battery registration

Stasis helps riders register their own battery serial numbers in Sunshine's
shared battery tracker. The feature is available from Battery, Settings and
initial scooter setup. It does not require a connected scooter or an account to
read a pack using phone NFC.

## User flow

1. Read a battery directly with NFC, or use a connected Librescoot scooter that
   advertises `hash=1`.
2. Choose a battery if more than one was read, then explicitly confirm that its
   serial matches the physical label. Scooter readings can be cached.
3. Review what will be shared and choose "Share and continue". Only then does
   the app send the selected serial and reading method to Sunshine and prepare
   a browser handoff.
4. Finish on the website using a Sunshine account or email verification, and
   separately consent to registration there. Opening the browser is not shown
   as successful registration.

The screens use Stasis themes, original vector artwork, scrollable layouts and
one primary action per step. Secondary explanations are expandable. Serial
readings exist only in memory while the screen is open: there is no phone-side
battery inventory, history, automatic upload or offline upload queue.

The once-only introduction waits for a scooter connection, startup notifications,
completed app authentication and a foreground home screen. Deferral does not
mark it seen. Manual NFC entry remains independent of scooter setup.

## Sunshine contract

The client follows the challenge/claim handoff contract supported by Sunshine
`a22ffc7e3`, including its browser-side choice of Sunshine login or email-only
access. The app does not implement authentication or decide whether an observation
can be linked to existing parts. Account authorization, optional part linkage,
registration consent and claim handling remain server-side.

Fixed HTTPS endpoints on `sunshine.rescoot.org`:

- `POST /api/v1/battery_tracker/challenges` with `{}` returns HTTP 201 and
  `challenge`, `expires_at`.
- `POST /api/v1/battery_tracker/claims` with exactly `challenge`, `serial_number`
  and `source` (`ble` or `nfc`) returns HTTP 201, or HTTP 200 for an identical
  deliberate retry, with `code`, `expires_at`.
- The browser opens `/battery_tracker/handoff#code=...`. The opaque code is in
  the fragment; serials and reading methods never appear in browser URLs.
- Management opens `/battery_tracker/registrations` without any battery data.

Challenge and handoff tokens are 43 base64url characters and expire after ten
minutes. The client has a 30-second total deadline, rejects redirects and limits
JSON responses to 4 KiB. It sends no account credentials, cookies, scooter ID,
location or reading history. An ambiguous claim request is retained only in memory
for an explicit identical retry. Cancellation discards it and prevents late
completions from opening the browser. Browser-launch failure can reuse an
unexpired handoff. There are no automatic retries or serial-bearing fallback URLs.

A claim records an assertion, not hardware attestation, ownership or a theft
report. The server controls its explicit consent and account-linking workflows.

## Release gate

`SUNSHINE_BATTERY_REGISTRATION_ENABLED` defaults to false. Builds without the
flag permit local reading and label checks, but do not advertise automatic
registration invitations or enable sharing/management links. Enable it for an
explicitly authorized build only after the corresponding Sunshine backend has
passed release acceptance:

```sh
flutter build apk --dart-define=SUNSHINE_BATTERY_REGISTRATION_ENABLED=true
```

## Identity readers

Bluetooth captures one session and discovers `hash=1` before reading
`battery:0` and `battery:1` with the ordered fields `present,serial-number`.
Each reply is an atomic array of raw strings or nulls, transferred with the
generic hash protocol. Presence must be exactly `true` or `false`; an absent
pack's retained serial is ignored. Missing or invalid present-pack identity
rejects the entire read. Disconnects and session replacement discard results.
No minimum stable firmware version is assumed.

NFC sends only Type 2 READ commands at pages `0xc4` and `0xc8`. Serial bytes
are `status1[4:16]` followed by `status2[0:4]`. Both blocks must be complete,
printable, and produce the same serial on a second read. The NFC tag UID is
never used as battery identity. No writes, battery commands or authentication
attempts are sent. Cancellation and disposal invalidate pending results.

Serial normalization preserves leading zeroes and battery prefixes. A
16-character hexadecimal serial is uppercased; board serial conversions do not
apply to batteries. Placeholder and malformed identities are rejected.

Before distributing a build, verify NFC reading and cancellation on physical
Android and iPhone devices, both tags on actual packs, label agreement and
Bluetooth/NFC identity agreement. Automated protocol and widget tests do not
replace this hardware acceptance.
