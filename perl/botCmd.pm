package botCmd;
use Data::Dumper;
use Date::Parse;
use DBI;
use Exporter;
use JSON::XS;
use POSIX qw(strftime);
use WWW::Curl::Easy;

# sub validate_device

@ISA = ('Exporter');
@EXPORT = (keys(%commands));
@EXPORT_OK = qw(%commands $reloadtime);

my $ch = new WWW::Curl::Easy;
my $root = "/home/gdanko/bot";
my $salt = "codenameandroid";
my $session_timeout = 3600;	# Seconds
$reloadtime = localtime;

my $dbh = DBI->connect("dbi:SQLite:dbname=$root/db/SwagBot.db", "", "");
my $devices = {};
my $users = {};
my $users1 = {};
my $links = {};
_load_devices();
_load_users();
_load_users1();
_load_links();

our %commands = (
	# Core commands
	help => {
		usage => "help [command] -- Without specified command lists all available commands. If a command is given, provides help on that command. If command is issued in a channel it must be prefaced with \"$prefix\", if in a private message omit the $prefix.",
		level => 0,
	},
	auth => {
		usage => "auth <password> -- Authenticate with the bot.",
		level => 0,
	},
	passwd => {
		usage => "passwd <old_passwd> <new_passwd> -- Change your bot password.",
		level => 0,
	},
	userlist => {
		usage => "userlist -- List all users in the user database.",
		level => 100,
	},
	useradd => {
		usage => "useradd <username> <password> <level> -- Add a user to the user database.",
		level => 100,
	},
	adduser => {
		usage => "adduser <nick> <mask> <password> <level> -- Add a user to the user database.",
		level => 100,
	},
	userdel => {
		usage => "userdel <username> -- Remove a user from the user database.",
		level => 100,
	},
	shutdown => {
		usage => "shutdown <password> -- Shut down the bot. Requires your user password.",
		level => 100,
	},
	gtfo => {
		usage => "gtfo <nick> -- Kick someone out.",
		level => 50,
	},
	say => {
		usage => "say <nick> <text> - Instruct the bot to speak to someone in the channel.",
		level => 50,
	},
	seen => {
		usage => "seen <nick> -- Display the last time the bot has seen <nick>.",
		level => 0,
	},
	mom => {
		usage => "mom <nick>.",
		level => 10,
	},
	# Other commands
	time => {
		usage => "time -- Displays the current time in UTC format.",
		level => 0,
	},
	devices => {
		usage => "devices -- Lists all devices supported by AOKP.",
		level => 0,
	},
	device => {
		usage => "device <device name> -- Accepts a device codename, e.g. toro, and displays the actual device name.",
		level => 0,
	},
	deviceadd => {
		usage => "deviceadd <device id>!<device name> -- Add a device to the database. Example: deviceadd toro!\"Samsung Galaxy Nexus CDMA\"",
		level => 90,
	},
	devicedel => {
		usage => "devicedel <device id> -- Remove a device from the database. Example: devicedel toro",
		level => 90,
	},
	links => {
		usage => "links -- Lists all of the links in the links database.",
		level => 0,
	},
	"link" => {
		usage => "link <title> -- Display the URL for link <title>. Example: link gapps",
		level => 0,
	},
	linkadd => {
		usage => "linkadd <title>!<url> -- Add a link to the links database.",
		level => 90,
	},
	linkdel => {
		usage => "linkdel <title> -- Remove a link from the links database.",
		level => 90,
	},
	linkmod => {
		usage => "linkmod <title> <new_url> -- Update the URL for an existing link.",
		level => 90,
	}
);


#################
# Core commands #
#################

sub help {
	my ($irc, $where, $args, $sender, $command) = @_;
	my $level = 0;
	my $help_str = "";
	my @valid_commands = ();

	if(defined $users->{$sender}) {
		$level = $users->{$sender}->{level} if $users->{$sender}->{level};
	}

	if($commands{$args}) {
		if($level >= $commands{$args}{level}) {
			$irc->yield(privmsg => $where => "Usage: $commands{$args}{usage}");
		}		
	} elsif($args) {
		$irc->yield(privmsg => $where => "Sorry, $args not found in list of commands.  Try \"!help\" to see list of available commands.");
	} else {
		foreach my $cmd (sort keys %commands) {
			push(@valid_commands, $cmd) if $level >= $commands{$cmd}{level};
		}
		my $available = join(", ", sort(@valid_commands));
		$irc->yield(privmsg => $where => "Available commands are: $available. Use \"!help <command>\" for help with a specific command.");
	}	
	return;
}

sub auth {
	my ($irc, $where, $args, $sender, $command) = @_;
	_load_users();

	return if $where =~ m/^#/;

	if(defined $users->{$where}) {
		my $nick = $where;
		if(crypt($args, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
			my $now = time;
			$dbh->do("UPDATE users SET last_auth='$now' WHERE username='$nick'");
			_load_users();
			$irc->yield(privmsg => $where => "Login successful");
		} else {
			$irc->yield(privmsg => $where => "Incorrect password");
		}
	} else {
		$irc->yield(privmsg => $where => "Unknown username: $nick");
	}
}

sub auth1 {
	my ($irc, $where, $args, $usermask, $command) = @_;
	_load_users1();

	return if $where =~ m/^#/;
	my($nick, $mask) = split(/!/, $usermask);

	if(defined $users1->{$nick} and defined $users1->{$nick}->{mask}) {
		if(crypt($args, $users1->{$nick}->{password}) eq $users1->{$nick}->{password}) {
			my $now = time;
			$dbh->do("UPDATE users1 SET last_auth='$now' WHERE nick='$nick'");
			_load_users1();
			$irc->yield(privmsg => $nick => "Login successful");
		} else {
			$irc->yield(privmsg => $nick => "Incorrect password");
		}
	} else {
		$irc->yield(privmsg => $nick => "Unknown username: $nick");
	}
	return;
}

sub passwd {
	my ($irc, $where, $args, $sender, $command) = @_;
	_load_users();

	return if $where =~ m/^#/;
	my $nick = $where;

	if(defined $users->{$nick}) {
		my @args = split(/\s+/, $args);
		if(@args != 2) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "passwd");
		} else {
			my ($old_passwd, $new_passwd) = @args;
			if(crypt($old_passwd, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				my $encrypted = crypt($new_passwd, $salt);
				$dbh->do("UPDATE users SET password='$encrypted' WHERE username='$nick'");
				_load_users();
				$irc->yield(privmsg => $where => "Password successfully changed");
			} else {
				$irc->yield(privmsg => $where => "Incorrect old password");
			}
		}
	} else {
		$irc->yield(privmsg => $where => "Unknown username: $nick");
	}
}

sub useradd {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_users();

		my @args = split(/\s+/, $args);
		if(@args != 3) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "useradd");
		} else {
			my ($username, $password, $level) = ($args[0], $args[1], $args[2]);
			if(defined $users->{$username}) {
				$irc->yield(privmsg => $where => "Error. Username $username already exists.");
			} else {
				my $encrypted = crypt($password, $salt);
				$dbh->do("INSERT INTO users (username, password, level) VALUES ('$username', '$encrypted', '$level')");
				_load_users();
				$irc->yield(privmsg => $where => "User \"$username\" successfully created.");
				$irc->yield(privmsg => $username => "Your bot account has been created with the default password \"$password\". Please use \"passwd\" to change it.");
			}
		}
	}
}

sub adduser {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_users();

		my @args = split(/\s+/, $args);
		if(@args != 4) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "adduser");
		} else {
			my ($nick, $mask, $password, $level) = ($args[0], $args[1], $args[2], $args[3]);
			if(defined $users1->{$nick}) {
				$irc->yield(privmsg => $where => "Error. User $nick already exists.");
			} else {
				my $encrypted = crypt($password, $salt);
				$dbh->do("INSERT INTO users1 (nick, mask, password, level) VALUES ('$nick', '$mask', '$encrypted', '$level')");
				_load_users();
				$irc->yield(privmsg => $where => "User \"$nick\" successfully created.");
				$irc->yield(privmsg => $nick => "Your bot account has been created with the default password \"$password\". Please use \"passwd\" to change it.");
			}
		}
	}
}

sub userdel {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_users();

		if($args =~ /s\+/) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "userdel");
		} else {
			if(defined $users->{$args}) {
				$dbh->do("DELETE FROM users WHERE username='$args'");
				_load_users();
				$irc->yield(privmsg => $where => "User \"$args\" successfully deleted.");
			} else {
				$irc->yield(privmsg => $where => "Unknown username: $args");
			}
		}
	}
}

sub shutdown {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		my @args = split(/\s+/, $args);
		if(@args != 1) {
			$irc->yield(privmsg => $nick =>"Syntax error.");
			help($irc, $nick, "shutdown");
		} else {
            my $password = $args[0];
			if(crypt($password, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				$irc->yield(shutdown => "Shutdown requested by $nick");
			}
		}
	}
}

sub gtfo {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		if($validate->{message} =~ /^You do not have permission/ or $validate->{message} =~ /^Unknown username/) {
			$irc->yield(kick => "#teamkang" => $sender => "Denied! GTFO!");
		} else {
			$irc->yield(privmsg => $sender => $validate->{message});
		}
	} else {
		my @args = split(/\s+/, $args);
		if(@args != 1) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "gtfo");
		} else {
			my $target = $args[0];
			$irc->yield(kick => "#teamkang" => $target => "GTFO!");
		}
	}
}

sub say {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		my @nicks = $irc->nicks();

		if($args =~ m/^([^\s]+)\s+(.*)$/) {
			my ($target, $text) = ($1, $2);
			if(grep(/^$target$/, @nicks)) {
				$irc->yield(privmsg => $target => $text);
				$irc->yield(privmsg => $sender => "Message sent to $target.");
			} else {
				$irc->yield(privmsg => $sender => "$target is not in the channel.");
			}
		}
	}
}

sub seen {
	my ($irc, $where, $args, $sender, $command) = @_;
	my @nicks = $irc->nicks();

	#if(grep(/^$args$/, @nicks)) {
	#	$irc->yield(privmsg => $where => "$args is in the channel now!");
	#	return;
	#}

	my $q = "SELECT COUNT(*) FROM seen WHERE nick='$args' AND channel='$where'";

	my $count = $dbh->selectrow_array($q);
	if($count == 0) {
		$irc->yield(privmsg => $where => "I have not seen $args.");
	} else {
		my $time = $dbh->selectrow_array("SELECT time FROM seen WHERE nick='$args' AND channel='$where'");
		my $last = _duration(time - $time);

		if(grep(/^$args$/, @nicks)) {
			$irc->yield(privmsg => $where => "$args is in the channel now and last spoke $last ago.");
		} else {
			$irc->yield(privmsg => $where => "I last saw $args $last ago.");
		}
	}
}

sub mom {
	my ($irc, $where, $args, $sender, $command) = @_;
	my @nicks = $irc->nicks();

	if(grep(/^$args$/, @nicks)) {
		$irc->yield(privmsg => $where => "$args: I heard your mom uses an iPhone.");
	}
}

sub process_ctcp {
	my ($irc, $where, $sender, $message) = @_;
	my @good_stuff = qw(cake steak cheese soup carrots pizza corn);
	my @bad_stuff = qw(mushrooms tofu sushi);

	foreach my $food (@good_stuff) {
		$irc->yield(privmsg => $where => "Mmmmm " . lc($1) . "!") if $message =~ m/($food)/i;
	}

	foreach my $food (@bad_stuff) {
		$irc->yield(privmsg => $where => lc($food) . "?! Gross!") if $Message =~ m/($food)/i;
	}
}

##################
# Other commands #
##################

sub time {
	my ($irc, $where, $args, $sender, $command) = @_;
	$irc->yield(privmsg => $where => "It is now " . strftime "%Y-%m-%d %T", localtime(time));
	return;
}

sub devices {
	my ($irc, $where, $args, $sender, $command) = @_;
	my $devices = join(", ", sort(keys(%$devices)));
	$irc->yield(privmsg => $where => "Supported devices: $devices");
	return;
}

sub device {
	my ($irc, $where, $args, $sender, $command) = @_;

	if(defined $devices->{$args}) {
		$irc->yield(privmsg => $where => "device $args: $devices->{$args}->{description}");
	} else {
		$irc->yield(privmsg => $where => "Unknown device: $args. Type ${prefix}devices for a list of supported devices.");
	}
	return;
}

sub deviceadd {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_devices();

		my @args = split(/!/, $args);
		if(@args != 2) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "deviceadd");
		} else {
			if(defined $devices->{$device_id}) {
				$irc->yield(privmsg => $where => "Device $device_id already exists.");
			} else {
				my ($device_id, $device_name) = @args;
				$dbh->do("INSERT INTO devices (id, description) VALUES ('$device_id', '$device_name')");
				_load_devices();
				$irc->yield(privmsg => $where => "Device $device_id successfully added.");
			}
		}
	}
	return;
}

sub devicedel {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_devices();

		my @args = split(/\s+/, $args);
		if(@args != 1) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "devicedel");
		} else {
			if(defined $devices->{$args[0]}) {
				$dbh->do("DELETE FROM devices WHERE id=\"$args[0]\"");
				_load_devices();
				$irc->yield(privmsg => $where => "Device $args[0] successfully deleted.");
			} else {
				$irc->yield(privmsg => $where => "Unknown device: $args[0]. Type ${prefix}devices for a list of supported devices.");
			}
		}
	}
}

sub links {
	my ($irc, $where, $args, $sender, $command) = @_;
	my $links = join(", ", sort(keys(%$links)));
	$irc->yield(privmsg => $where => "Available links: $links");
	return;
}

sub link {
	my ($irc, $where, $args, $sender, $command) = @_;

	if(defined $links->{$args}) {
		$irc->yield(privmsg => $where => "$args: $links->{$args}->{url}");
	} else {
		$irc->yield(privmsg => $where => "Unknown link: $args. Type ${prefix}links for a list of available links.");
	}
	return;
}

sub linkadd {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_links();

		my @args = split(/!/, $args);
		if(@args != 2) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "linkadd");
		} else {
			if(defined $links->{$link_title}) {
				$irc->yield(privmsg => $where => "Link $link_title already exists.");
			} else {
				my ($link_title, $link_url) = @args;
				$dbh->do("INSERT INTO links (descriptor, url) VALUES ('$link_title', '$link_url')");
				_load_links();
				$irc->yield(privmsg => $where => "Link $link_title successfully added.");
			}
		}
	}
	return;
}

sub linkdel {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_links();

		my @args = split(/\s+/, $args);
		if(@args != 1) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "linkdel");
		} else {
			if(defined $links->{$args[0]}) {
				$dbh->do("DELETE FROM links WHERE descriptor=\"$args[0]\"");
				_load_links();
				$irc->yield(privmsg => $where => "Link $args[0] successfully deleted.");
			} else {
				$irc->yield(privmsg => $where => "Unknown link: $args[0]. Type ${prefix}links for a list of available links.");
			}
		}
	}
	return;
}

sub linkmod {
	my ($irc, $where, $args, $sender, $command) = @_;

	my $validate = _validate_user($irc, $where, $sender, $command);
	if($validate->{status} eq "Error") {
		$irc->yield(privmsg => $sender => $validate->{message});
	} else {
		_load_links();

		my @args = split(/!/, $args);
		if(@args != 2) {
			$irc->yield(privmsg => $where =>"Syntax error.");
			help($irc, $where, "linkmod");
		} else {
			if(defined $links->{$args[0]}) {
				$dbh->do("UPDATE links SET url=\"$args[1]\" WHERE descriptor=\"$args[0]\"");
				_load_links();
				$irc->yield(privmsg => $where => "Link $args[0] successfully updated.");
			} else {
				$irc->yield(privmsg => $where => "Unknown link: $args[0]. Type ${prefix}links for a list of available links.");
			}
		}
	}
	return;
}

#####################
# Support functions #
#####################

sub _log_seen {
	my ($nick, $time, $where) = @_;

	if( $dbh->selectrow_array("SELECT COUNT(*) FROM seen WHERE nick='$nick' AND channel='$where'") == 0 ) {
		$dbh->do("INSERT INTO seen (nick, time, channel) VALUES ('$nick', '$time', '$where')");
	} else {
		$dbh->do("UPDATE seen SET time='$time' WHERE nick='$nick'");
	}
}

sub _load_devices {
	my $sth = _do_query($dbh, "SELECT * FROM devices");
	$devices = $dbh->selectall_hashref($sth, "id");
}

sub _load_users {
	my $sth = _do_query($dbh, "SELECT * FROM users");
	$users = $dbh->selectall_hashref($sth, "username");
}

sub _load_users1 {
	my $sth = _do_query($dbh, "SELECT * FROM users1");
	$users1 = $dbh->selectall_hashref($sth, "nick");
}

sub _load_links {
	my $sth = _do_query($dbh, "SELECT * FROM links");
	$links = $dbh->selectall_hashref($sth, "descriptor");
}

sub _validate_user {
	my ($irc, $where, $sender, $command) = @_;
	my $now = time;
	my $output;


	if(defined $users->{$sender}) {
		# Validate level
		if($users->{$sender}->{level} < $commands{$command}{level}) {
			$output = { status => "Error", message => "You do not have permission to execute $command." };
			return $output;
		}

		# Validate session
		if(($now - $users->{$sender}->{last_auth}) > $session_timeout) {
			$output = { status => "Error", message => "Your session has expired. Please login with \"auth\"." };
			return $output;
		}
	} else {
		$output = { status => "Error", message => "Unknown username: $sender" };
		return $output;
	}
}

sub _do_query {
	my ($dbh, $query) = @_;
	my $sth = $dbh->prepare($query);
	$sth->execute;
	return $sth;
}

sub _duration {
	my $string = "";
	my $sec = shift;
	my $days = int(($sec / 86400));
	my $hours = int((($sec - ($days * 86400)) / 3600));
	my $mins = int((($sec - $days * 86400 - $hours * 3600) / 60));
	my $seconds = int(($sec - ($days * 86400) - ($hours * 3600) - ($mins * 60)));

	$string .= sprintf("%02dd ", $days) if $days > 0;
	$string .= sprintf("%02dh ", $hours) if $hours > 0;
	$string .= sprintf("%02dm ", $mins) if $mins > 0;
	$string .= sprintf("%02ds", $seconds);

	return $string;	
}
1;
