# powershell-email-scripts

A mail archive with no database. Each account is a folder, each mailbox is a subfolder, each message is an
`.eml` file, and **the file name carries the state**.

An `.eml` file is the complete message in its native form (headers, body, attachments). Mail servers speak IMAP,
but what they hand you is exactly that. These scripts just copy it faithfully into ordinary files, and use the
file name for the small amount of state you need: is it read, and which server message is it.

## How the pieces map

| A mail client's database would have... | Here it is... |
|---|---|
| the message store | a folder of `.eml` files |
| mailboxes / labels | subfolders named after the server folders |
| a message list with date and subject | the file name, so `ls` is the message list |
| the read / unread flag | `[UNREAD]` in the file name; renaming the file changes the flag |
| the link back to the server message | the uid at the end of the name |
| search | your file manager, `grep`, or any tool that reads `.eml` |
| backup | copy the folder |

Open any file in a mail client to read it, or grep the folder without a client at all.

## Layout and file name

    <account>/<mailbox>/YYYY-MM-DD [UNREAD] Subject-<uid>.eml
    <account>/<mailbox>/YYYY-MM-DD Subject-<uid>.eml              (already read)
    <account>/Trash/<uid>.eml                                     (Trash, Deleted, Notes: uid only)
    <account>/<mailbox>/.uidvalidity                              (bookkeeping, see below)

- The date is the message's `Date` header, so listings sort chronologically.
- `[UNREAD]` is present when the message was unread on the server when it was downloaded. On each run, a message
  that has since been read on the server loses the tag (the file is renamed).
- The subject is shortened to 100 characters, and characters not allowed in file names are replaced with `-`.
- The trailing number is the IMAP uid: the identity of the message on the server. It is how the next run knows
  what is already on disk. It is matched exactly (uid 5 is never confused with 15).
- To mark something read yourself, delete ` [UNREAD]` from its name.

## How a sync works

For each server mailbox, `getMail.ps1`:

1. Lists what is on disk by parsing the trailing uid of each file name.
2. Asks the server for the uid and flags of every message.
3. For messages already on disk: renames the file if it has been read since; nothing else.
4. For new messages: downloads, writes the `.eml`, checks the file exists and is not empty.
5. Only when `-DeleteFromServer` is set, and only after step 4 succeeded for that message, marks it deleted on the
   server; the mailbox is expunged at the end. A message that failed to download is never deleted.

There is no local database to get out of step. Delete a file and it is downloaded again next time (unless it was
already removed from the server); add files by hand and they are simply extra.

### UIDVALIDITY

A server can renumber a mailbox (rare, but the IMAP standard allows it) and announces this with a new
UIDVALIDITY value. Each mailbox folder remembers the last value in `.uidvalidity`. If it changes, the old uids
mean nothing, so the existing files are moved into `_stale-uidvalidity-<old value>/` (kept, not deleted) and the
mailbox is downloaded again.

## Setup

1. `./installMailKit.ps1` downloads MailKit, MimeKit and BouncyCastle (the IMAP and message libraries) from
   nuget.org into `lib/`. The libraries that used to be committed were .NET Framework builds that PowerShell 7
   cannot load.
2. Copy `accounts.example.json` to `accounts.json` and edit it:

       [
         { "user": "someone@gmail.com", "passwordEnv": "MAIL_GMAIL_PASSWORD", "deleteFromServer": true }
       ]

   - `passwordEnv` names an environment variable that holds the password (use an app password). If it is unset
     you are prompted. Passwords are never stored in the scripts.
   - `server` is guessed for Outlook/Hotmail/Live, Gmail and Yahoo; set it for anything else.
   - `deleteFromServer: false` keeps the mail on the server (safe default for a first run).
3. `./getMailAllAccounts.ps1` syncs every account and shows the unread total (`-Console` prints instead of a
   notification). For one account: `./getMail.ps1 -UserName you@example.org -Password (Read-Host -AsSecureString)`,
   which returns the number of new messages.

`accounts.json`, `lib/` and the downloaded mail are gitignored.

## Unread counts

The unread total is the number of files with `[UNREAD]` in their name, ignoring Junk, Spam, Bulk, Trash, Deleted
and Notes. It is a directory listing, not a query against a server.

## Trade-offs

- Search is as good as your tools (`grep -r`, Spotlight, Windows Search); there is no built-in index.
- Read state flows one way, from the server to the file names. Renaming a file marks it read locally; it does not
  tell the server.
- With `deleteFromServer`, the local folder becomes the only copy, so back it up.
- Nested server folders and Gmail's `[Gmail]` subfolders (All Mail, Sent, ...) are not downloaded.

## Requirements

PowerShell 7. On Windows, unread notifications need the [BurntToast](https://github.com/Windos/BurntToast) module;
elsewhere the summary is printed.
