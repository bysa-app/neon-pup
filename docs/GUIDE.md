# Neon Pup

## What Neon Pup does

Neon Pup sends all of your Mac's internet through your own servers outside China, so blocked sites like Google, Instagram, WhatsApp and Claude work. While it is connected, Claude only sees your server's location.

It lives in the menu bar as a butterfly next to the clock. Click the butterfly to open it.

Neon Pup works together with a free app called SFM, made by the people behind the engine Neon Pup uses. SFM carries your internet in the background. You only use Neon Pup, but keep SFM installed.

You need a Mac with macOS 13 or newer and at least one server link. Neon Pup comes without servers. The person or company that runs your servers gives you the links.

## Install (before you travel)

1. Download Neon-Pup.zip from neonpup.bysa.app, open it and drag Neon Pup into Applications.

2. Open Neon Pup from Applications. A setup window opens and walks you through every step, one at a time. It takes about 5 minutes and asks for your Mac password once or twice.

3. Follow the steps until the window says All set.

If you close the setup window early, click the butterfly and press Continue setup.

## Add your servers

A server link starts with vless://, hy2:// or hysteria2://. You get it from whoever runs your server, as text or as a file. Apps like Shadowrocket and Clash Verge can also export these links.

1. Open the gear menu and choose Your servers.

2. Paste your links into the box, one per line, and press Add these. If you got a file, press Import from file and pick it.

3. If a line doesn't work, the window shows its line number and the problem. The other lines are still added.

4. Rename the servers if you like, and use the arrows to put them in order. You can add up to 8.

5. Press Save my servers. Your Mac's Keychain keeps them, and SFM keeps its own copy to run them.

After you change your servers, Neon Pup asks you to open SFM and press its refresh button once. Until then it keeps using your old servers.

A server marked "skips the safety check" can't prove it is really your server. Use it only when nothing else works.

## What server links look like

Each link is one line. These examples use made-up values.

Everyday server (VLESS Reality):

```
vless://11111111-2222-4333-8444-555555555555@203.0.113.10:443?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=fUP2s8T4LqCEhMDd7z8KNoqAYv3QBJ2rW0vmxyG8Zks&sid=ab12&type=tcp&flow=xtls-rprx-vision#Singapore
```

Turbo server (Hysteria2):

```
hy2://your-password@203.0.113.10:443?obfs=salamander&obfs-password=second-password&sni=www.bing.com#Singapore%20turbo
```

Backup tunnel (VLESS over WebSocket):

```
vless://11111111-2222-4333-8444-555555555555@proxy.example.com:443?encryption=none&security=tls&sni=proxy.example.com&type=ws&host=proxy.example.com&path=%2Fyour-path#Backup
```

The part after # is the name Neon Pup shows. A servers file is a plain text file (.txt) with one link on each line.

## Turn it on and off

Wake me up connects. While it connects it says Sniffing for a server. Wait for Connected before you open anything.

Let me nap disconnects, and your Mac goes back to its normal internet.

Start when my Mac starts (gear menu) opens Neon Pup when you log in. It still waits for you to press Wake me up.

## Check that it works

Don't test with a Claude page. If Neon Pup isn't working, that page would see your China connection.

1. With Neon Pup connected, open this page in your browser:

```
https://www.cloudflare.com/cdn-cgi/trace
```

2. Find the line that starts with loc=. It shows the country your internet comes from, as a two-letter code: loc=SG is Singapore, loc=US is America.

3. If it shows loc=CN, Neon Pup isn't protecting you. Press Go offline (or Let me nap), don't open Claude, and see Get help from Claude below.

Or in Terminal:

```
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep loc
```

## Secure, Fast and Manual

Claude uses the top server in your list that works, in every mode. That covers claude.ai, the Claude desktop app and Claude Code. If that server stops working, Claude moves to the next one down.

Secure (the default): the rest of your internet follows the same order. Use it for accounts that check where you log in from, like Google, banks and Instagram.

Fast: everything except Claude uses whichever server answers fastest right now. Good for video.

Manual: everything except Claude uses the server you pick. Hearts show how fast each server is, and more hearts means faster. If your pick stops working, Neon Pup falls back to your list order and tells you.

Put the server you want Claude on at the top of the list. A server near China, such as Singapore, is usually fastest.

## Chinese sites

Sites in China, like WeChat, Alipay and Baidu, normally go straight out. They are faster that way and don't need your servers.

To send them through your servers too, open the gear menu and turn on Send Chinese sites through my servers. Chinese sites then see your server's location instead of yours, and they may be slower.

## If the connection drops

While Neon Pup is connected, SFM keeps every app on your Mac inside the tunnel. If the connection drops, Neon Pup says "The connection dropped".

Neon Pup reconnects by itself, up to three times in a row. If it still can't, press Wake me up to try again. Until then your Mac uses its normal internet (in China mode, Wi-Fi stays off).

## China mode

Turn China mode on (gear menu) before you join any Wi-Fi in China. Turn it off when you leave.

With China mode on, Neon Pup keeps the connection up and reconnects by itself if it drops. The big button says Go offline instead of Let me nap: it turns Wi-Fi off, so nothing goes online. Wake me up turns Wi-Fi back on and connects.

Quitting Neon Pup in China mode leaves the connection running, so you stay protected. To stop it completely, turn China mode off first.

In China, also turn on Start when my Mac starts in the gear menu.

## Time zone

If your Mac is set to China, Hong Kong or Macau time, Neon Pup switches it to Singapore while connected. The clock shows the same time. Apps like Claude can read your time zone, and this keeps it in line with your server. Neon Pup switches it back when you disconnect. Other time zones stay as they are.

## Wi-Fi with a login page (hotels, airports, cafes)

Some networks make you log in on a web page first. Normally your Mac shows that page by itself when you join. While Neon Pup is on, the page can't load, because your servers are unreachable until you log in.

1. Join the Wi-Fi from the Wi-Fi menu.

2. If Neon Pup shows Securely open public Wi-Fi login, press it. A browser tab opens and the network shows its login page there.

3. Log in. Neon Pup closes the login window by itself as soon as your servers answer, and after 5 minutes at the latest. You can also press Done.

While the login window is open, your browser uses the local connection so the login page can load. Claude stays on your servers the whole time. Don't open other sites until it says Connected again.

In China mode the Mac's own login pop-up can't load. Close it and use the button instead.

## Other VPN apps

Neon Pup won't connect while another VPN app is on, such as Clash Verge or a work VPN. Quit that app, then press Wake me up. SFM is part of Neon Pup and doesn't count.

## What the messages mean

"Finish setting up first": press Continue setup and follow the steps.

"I need a one-time OK in System Settings": press Open System Settings, switch Neon Pup on under Login Items & Extensions, then press Wake me up.

"Add your servers first": open the gear menu, choose Your servers and add at least one.

"Your server list changed. Press refresh in SFM": press Open SFM, then the round arrow next to Neon Pup. You stay protected meanwhile, on your old servers.

"Another app is changing your internet": quit your other VPN app.

"All servers are sleepy, I'll keep trying": none of your servers answers. On Wi-Fi with a login page, use the login button. Otherwise try another network, or ask whoever runs your servers whether they are up.

"No internet at all, check the Wi-Fi": the Wi-Fi itself isn't working.

"This server is blocked here, trying another" (Manual): pick a different server.

"The connection dropped": press Wake me up. In China mode Neon Pup does this by itself.

"I couldn't block the internet": the safety block failed. Turn Wi-Fi off so nothing leaks, then copy a report (below) and send it to whoever runs your servers.

## Stuck offline?

1. In China mode, Go offline turns Wi-Fi off. Press Wake me up to turn it back on and connect.

2. Go offline only turns off Wi-Fi. If your Mac is on a network cable, unplug it too.

3. Still offline? Turn China mode off in the gear menu, then press Let me nap.

4. Can't see the butterfly? Open Neon Pup from Applications. On a MacBook with a notch, menu bar icons can hide behind it, so quit a few other menu bar apps.

5. Still blocked? Use Emergency below.

## Emergency: get your internet back

Use this if nothing else works and your Mac stays offline.

1. Open System Settings, then VPN, and turn off SFM.

2. Turn Wi-Fi on from the Wi-Fi menu at the top of the screen.

3. Still offline? Open Terminal (in Applications, then Utilities).

4. Paste this line and press Return. Type your Mac password when asked. It doesn't show as you type.

```
pkill -x NeonPup; scutil --nc stop SFM; sudo rm -f /private/var/db/co.holinic.neonpup/killswitch-wanted /private/var/db/co.holinic.neonpup/killswitch-china; sudo pkill -x sing-box; sleep 2; sudo pfctl -a com.apple/co.holinic.neonpup -F all; defaults write co.holinic.neonpup chinaMode -bool false
```

5. This quits Neon Pup, stops SFM, lifts any block Neon Pup set and turns China mode off. Your internet works again.

6. Still offline? Restart your Mac.

If your clock shows the wrong time zone afterwards, set it in System Settings, General, Date & Time.

## Remove Neon Pup

1. Turn China mode off and press Let me nap.

2. Choose Quit in the gear menu, then drag Neon Pup from Applications to the Trash.

3. To remove SFM too: open System Settings, then VPN, and remove SFM. Then drag SFM from Applications to the Trash.

## Good to know

If you change your servers, Neon Pup asks you to open SFM and press its refresh button once. Until then it keeps using your old servers.

If SFM offers an update, say no. Neon Pup is tested with the version it installed.

Hotel or airport Wi-Fi with a login page: use Securely open public Wi-Fi login in Neon Pup.

In China mode, Go offline turns Wi-Fi off. Wake me up turns it back on.

Your phone needs its own app. Neon Pup is for this Mac only.

## Get help from Claude

Press Copy a report below. It copies a short description of Neon Pup for Claude, what Neon Pup is doing and how fast each server answers. Server addresses, passwords and keys are hidden. SFM shows more detail in its own window, under Logs.

Paste it into a chat with Claude or another assistant and ask what's wrong. Only do that while Neon Pup says Connected, or from a device with its own safe connection, such as your phone. You can also send it to whoever runs your servers.
