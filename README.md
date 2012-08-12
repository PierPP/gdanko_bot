This is a POE-based IRC bot I've written completely from scratch and is a constant work in progress.

Basic features:
* sqlite backend
* Bot owner can modify the bot's functions on the fly without the bot leaving IRC. If the new functions module has errors it will not be loaded.
* Full user support with encrypted passwords in the sqlite DB.
* User logins time out after a pre-defined period.
* Commands definitions are stored in a sqlite database.
	* Commands can be enabled and disabled on the fly.
	* Commands can be protected from being disabled, e.g., you cannot disable the disable command
* Commands deviceadd and linkadd track the user who added the item.
