DROP TABLE IF EXISTS commands;
CREATE TABLE commands (command TEXT NOT NULL UNIQUE, usage TEXT NOT NULL, level INTEGER NOT NULL, enabled INTEGER NOT NULL, hidden INTEGER NOT NULL, can_be_disabled INTEGER NOT NULL, cmd_group TEXT);
INSERT INTO commands VALUES("auth", "auth <password> -- Authenticate with the bot.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("device", "device <device name> -- Accepts a device codename, e.g. toro, and displays the actual device name.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("deviceadd", "deviceadd <device id>!<device name> -- Add a device to the database.", 40, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("devicedel", "devicedel <device id> -- Remove a device from the database. Example: devicedel toro", 40, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("devices", "devices -- Lists all devices supported by AOKP.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("disable", "disable <command> -- Disable a command.", 90, 0, 0, 0, "nogroup");
INSERT INTO commands VALUES("enable", "enable <command> -- Enable a command.", 90, 0, 0, 0, "nogroup");
INSERT INTO commands VALUES("gtfo", "gtfo <nick> -- Kick someone out.", 50, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("help", "help [command] -- Without specified command lists all available commands. If a command is given, provides help on that command. If command is issued in a channel it must be prefaced with "", if in a private message omit the .", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("link", "link <title> -- Display the URL for link <title>. Example: link gapps", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("linkadd", "linkadd <title> <url> -- Add a link to the links database.", 40, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("linkdel", "linkdel <title> -- Remove a link from the links database.", 40, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("linkmod", "linkmod <title> <new_url> -- Update the URL for an existing link.", 40, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("links", "links -- Lists all of the links in the links database.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("mom", "mom <nick>. -- Insult a user's mom.", 10, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("mute", "mute <nick> -- Mute a user.", 50, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("nick", "nick <nick> -- Change the bot's nick.", 90, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("passwd", "passwd <old_passwd> <new_passwd> -- Change your bot password.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("say", "say <nick> <text> - Instruct the bot to speak to someone in the channel.", 40, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("seen", "seen <nick> -- Display the last time the bot has seen <nick>.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("shutdown", "shutdown <password> -- Shut down the bot. Requires your user password.", 100, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("time", "time -- Displays the current time in UTC format.", 0, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("unmute", "unmute <nick> -- Unmute a user.", 50, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("unvoice", "unvoice <nick> -- Give a user -v.", 50, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("useradd", "useradd <username> <mask> <password> <level> -- Add a user to the user database.", 100, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("userdel", "userdel <username> -- Remove a user from the user database.", 100, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("users", "users -- List all users in the user database.", 100, 0, 0, 1, "nogroup");
INSERT INTO commands VALUES("voice", "voice <nick> -- Give a user +v.", 50, 0, 0, 1, "nogroup");
