package Bot::Plugins::Core;

use botCmd qw($commands);
use Data::Dumper;
use DBI;
use POSIX qw(strftime ceil);

my $module = "core";
my $bot = botCmd->new();
my $root = $bot->{cfg}->{general}->{root};
my $table_commands = $bot->{cfg}->{database}->{table_commands};
my $table_users = $bot->{cfg}->{database}->{table_users};
my $dbh = $bot->{dbh};
my $users = {};
my $commands = ${botCmd::commands};

load_users();
load_commands();

sub new {
	my $class = shift;
	my $self = {};
	$self->{name} = $module;
	bless($self, $class);
	return $self;
}

sub help {
	my $self = shift;
	my ($irc, $target, $args, $usermask, $command, $type) = @_;
	my $nick = (split /!/, $usermask)[0];
	my $level = 0;
	my $cmd_prefix = "";
	my @valid_commands = ();

	if($type eq "public") {
		$cmd_prefix = $prefix;
	}

	if(defined $users->{$nick}) {
		$level = $users->{$nick}->{level} if $users->{$nick}->{level};
	}
	$cmd = $args;

	if($cmd ne undef and $commands->{$cmd}) {
		return unless $bot->command_enabled($cmd) eq "success" and $bot->command_visible($cmd) eq "success";
		if($level >= $commands->{$args}->{level}) {
			$irc->yield(privmsg => $target => "Usage: $commands->{$args}->{usage}");
		}

	} elsif($args) {
		$irc->yield(privmsg => $target => "Sorry, \"$args\" not found in list of commands.  Try \"${cmd_prefix}help\" to see list of available commands.");

	} else {
		my $sth = $dbh->prepare("SELECT command FROM $table_commands WHERE enabled=1 AND hidden=0 AND level<=$level");
		$sth->execute;
		my $help_items = $dbh->selectall_hashref($sth, "command");
		$irc->yield(privmsg => $target => "Available commands are: " . join(", ", sort keys %$help_items));
		$irc->yield(privmsg => $target => "Use \"${cmd_prefix}help <command>\" for help with a specific command.");
	}	
	return;
}

sub auth {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my $session_timeout = $bot->{cfg}->{general}->{session_timeout};
	return if $type eq "public";
print STDERR "entering auth\n";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		load_users();
		my($nick, $mask) = split(/!/, $usermask);
		my $passwd = $args;

		if(defined $users->{$nick} and defined $users->{$nick}->{mask}) {
			if(crypt($passwd, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				my $now = time;
				$dbh->do("UPDATE $table_users SET last_auth='$now' WHERE nick='$nick'");
				load_users();
				$irc->yield(privmsg => $nick => "Login successful. Your session will expire in " . ceil($session_timeout / 60) . " minutes.");
			} else {
				$irc->yield(privmsg => $nick => "Incorrect password");
			}
		} else {
			$irc->yield(privmsg => $nick => "Unknown username: $nick");
		}
	}
	return;
}

sub deauth {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		load_users();
		my($nick, $mask) = split(/!/, $usermask);
		$dbh->do("UPDATE $table_users SET last_auth=0 WHERE nick='$nick'");
		load_users();
		$irc->yield(privmsg => $nick => "Session data removed.");
	}
}
	
sub passwd {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		load_users();
		my($nick, $mask) = split(/!/, $usermask);
		
		if(defined $users->{$nick}) {
			my ($old_passwd, $new_passwd) = split(/\s+/, $args);
			if(crypt($old_passwd, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				my $encrypted = crypt($new_passwd, $salt);
				$dbh->do("UPDATE $table_users SET password='$encrypted' WHERE nick='$nick'");
				load_users();
				$irc->yield(privmsg => $nick => "Password successfully changed");
			} else {
				$irc->yield(privmsg => $nick => "Incorrect old password");
			}
		}
	} else {
		$irc->yield(privmsg => $nick => "Unknown username: $nick");
	}
}

sub users {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		load_users();
		my ($nick, $mask) = split (/!/, $usermask);
		$irc->yield(privmsg => $nick => sprintf("%-20s%-55s%-7s", "Nick", "Mask", "Level"));
		foreach my $key (sort keys %$users) {
			my $user = $users->{$key};
			my $line = sprintf("%-20s%-55s%-7d", $user->{nick}, $user->{mask}, $user->{level});
			$irc->yield(privmsg => $nick => $line);
		}
	}
	return;
}

sub useradd {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 4) eq "success") {
		load_users();
		my ($nick, $mask) = split (/!/, $usermask);
		my ($username, $mask, $password, $level) = split(/\s+/, $args);

		if($level !~ /^\d+$/) {
			$irc->yield(privmsg => $nick => "Error. Level must be an integer.");
			return;
		}

		if(defined $users->{$username}) {
			$irc->yield(privmsg => $nick => "Error. User $username already exists.");
		} else {
			my $encrypted = crypt($password, $salt);
			$dbh->do("INSERT INTO $table_users (nick, mask, password, level) VALUES ('$username', '$mask', '$encrypted', '$level')");
			load_users();
			$irc->yield(privmsg => $nick => "User \"$username\" successfully created.");
			$irc->yield(privmsg => $username => "Your bot account has been created with the default password \"$password\". Please use \"passwd\" to change it.");
		}
	}
}

sub userdel {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		load_users();
		my ($nick, $mask) = split (/!/, $usermask);

		if(defined $users->{$args}) {
			$dbh->do("DELETE FROM $table_users WHERE nick='$args'");
			load_users();
			$irc->yield(privmsg => $nick => "User \"$args\" successfully deleted.");
		} else {
			$irc->yield(privmsg => $nick => "Unknown username: $args");
		}
	}
}

sub shutdown {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $password = $args;
		if(crypt($password, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
			$irc->yield(shutdown => "Shutdown requested by $nick");
		}
	}
}

sub join {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $channel = $args;
		$channel = "#$channel" unless $channel =~ /^#/;
		$irc->yield(join => $channel);
	}
}

sub part {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $channel = $args;
		$channel = "#$channel" unless $channel =~ /^#/;
		$irc->yield(part => $channel);
	}
}

sub enable {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $cmd = $args;
		if(defined $commands->{$cmd}) {
			if($bot->command_enabled($cmd) eq "success") {
				$irc->yield(privmsg => $where => "command \"$cmd\" is already enabled. nothing to do.");
				return;
			}
			$dbh->do("UPDATE $table_commands SET enabled=1 WHERE command='$cmd'");
			$irc->yield(privmsg => $where => "command \"$cmd\" has been enabled.");
		} else {
			$irc->yield(privmsg => $where => "command \"$cmd\" doesn't exist.");
		}
	}
	return;
}

sub disable {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $cmd = $args;
		if($commands->{$cmd}) {
			if($bot->command_enabled($cmd) ne "success") {
				$irc->yield(privmsg => $where => "command \"$cmd\" is already disabled. nothing to do.");
				return;
			}

			if($commands->{$cmd}->{can_be_disabled} == 0) {
				$irc->yield(privmsg => $where => "Are you kidding!?");
				return;
			} else {
				$dbh->do("UPDATE $table_commands SET enabled=0 WHERE command='$cmd'");
				$irc->yield(privmsg => $where => "command \"$cmd\" has been disabled.");
			}
		} else {
			$irc->yield(privmsg => $where => "command \"$cmd\" doesn't exist.");
		}
	}
	return;
}

sub test {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
}

sub load_users {
	my $sth = $dbh->prepare("SELECT * FROM $table_users");
	$sth->execute;
	$users = $dbh->selectall_hashref($sth, "nick");
}

sub load_commands {
	my $methods = {
		help => {
			usage => "help [<command>]",
			level => 0,
			can_be_disabled => 0
		},
		auth => {
			usage => "auth <password> -- Authenticate with the bot.",
			level => 1,
			can_be_disabled => 0
		},
		deauth => {
			usage => "deauth -- Clear session data from the users database.",
			level => 1,
			can_be_disabled => 0
		},
		passwd => {
			usage => "passwd <old_passwd> <new_passwd> -- Change your bot password.",
			level => 1,
			can_be_disabled => 0
		},
		users => {
			usage => "users -- List all users in the user database.",
			level => 90,
			can_be_disabled => 0
		},
		useradd => {
			usage => "useradd <username> <mask> <password> <level> -- Add a user to the user database.",
			level => 90,
			can_be_disabled => 1
		},
		userdel => {
			usage => "userdel <username> -- Remove a user from the user database.",
			level => 90,
			can_be_disabled => 1
		},
		shutdown => {
			usage => "shutdown <password> -- Shut down the bot. Requires you enter your user password.",
			level => 100,
			can_be_disabled => 0
		},
		enable => {
			usage => "enable <command> -- Enable a command.",
			level => 90,
			can_be_disabled => 0
		},
		disable => {
			usage => "disable <command> -- Disable a command.",
			level => 90,
			can_be_disabled => 0
		},
		test => {
			usage => "",
			level => 90,
			can_be_disabled => 0
		}
	};

	foreach my $key (keys %$methods) {
		my $method = $methods->{$key};
		$method->{module} = $module;
		$method->{method} = $key;
		$commands->{$key} = $method;

		$dbh->do("UPDATE commands SET level='$method->{level}' WHERE command='$key'");
	}
}

1;
