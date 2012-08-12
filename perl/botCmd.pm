package botCmd;
use Config::Tiny;
use Data::Dumper;
use Date::Parse;
use DBI;
use Exporter;
use JSON::XS;
use POSIX qw(strftime);
use WWW::Curl::Easy;

@ISA = ('Exporter');
@EXPORT = (keys(%commands));
@EXPORT_OK = qw(%commands $reloadtime);

my $root = "/home/gdanko/bot";
my $ch = new WWW::Curl::Easy;
my $salt = "codenameandroid";
my $session_timeout = 3600;	# Seconds
$reloadtime = localtime;

my $cfg = _read_config();
my $db_bot = $cfg->{database}->{db};
my $db_commands = "botCmd.db";

my $table_users = $cfg->{database}->{table_users};
my $table_devices = $cfg->{database}->{table_devices};
my $table_links = $cfg->{database}->{table_links};
my $table_seen = $cfg->{database}->{table_seen};
my $table_commands = "commands";

my $dbh_bot = DBI->connect("dbi:SQLite:dbname=$root/db/$db_bot", "", "");
my $dbh_commands = DBI->connect("dbi:SQLite:dbname=$root/db/botCmd.db", "", "");
my $devices = {};
my $users = {};
my $links = {};
our %commands = _load_commands();
_load_devices();
_load_users();
_load_links();

#################
# Core commands #
#################

sub help {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $nick = (split /!/, $usermask)[0];
	my $level = 0;
	my $help_str = "";
	my @valid_commands = ();

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}
	return unless _command_enabled("help") eq "success";

	if(defined $users->{$nick}) {
		$level = $users->{$nick}->{level} if $users->{$nick}->{level};
	}

	if($commands{$args}) {
		return unless _command_enabled($args) eq "success";
		if($level >= $commands{$args}{level}) {
			$irc->yield(privmsg => $target => "Usage: $commands{$args}{usage}");
		}

	} elsif($args) {
		$irc->yield(privmsg => $target => "Sorry, $args not found in list of commands.  Try \"!help\" to see list of available commands.");

	} else {
		my $sth = _do_query($dbh_commands, "SELECT command FROM commands WHERE enabled=1 AND hidden=0 AND level<=$level");
		my $help_items = $dbh_commands->selectall_hashref($sth, "command");
		$irc->yield(privmsg => $target => "Available commands are: " . join(", ", sort keys %$help_items) . "Use \"!help <command>\" for help with a specific command.");
	}	
	return;
}

sub auth {
	my ($irc, $where, $args, $usermask, $command) = @_;
	_load_users();

	return if $where =~ m/^#/;
	my($nick, $mask) = split(/!/, $usermask);

	if(defined $users->{$nick} and defined $users->{$nick}->{mask}) {
		if(crypt($args, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
			my $now = time;
			$dbh_bot->do("UPDATE $table_users SET last_auth='$now' WHERE nick='$nick'");
			_load_users();
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
	my ($irc, $where, $args, $usermask, $command) = @_;
	_load_users();

	return if $where =~ m/^#/;
	my $nick = (split /!/, $usermask)[0];

	if(defined $users->{$nick}) {
		my @args = split(/\s+/, $args);
		if(@args != 2) {
			$irc->yield(privmsg => $where => "Syntax error.");
			help($irc, $where, $usermask, $command);
		} else {
			my ($old_passwd, $new_passwd) = @args;
			if(crypt($old_passwd, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				my $encrypted = crypt($new_passwd, $salt);
				$dbh_bot->do("UPDATE $table_users SET password='$encrypted' WHERE nick='$nick'");
				_load_users();
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
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return if $where =~ m/^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 0) eq "success") {
		_load_users();
		my $userlist = join(", ", sort(keys(%{$users})));
		$irc->yield(privmsg => $nick => "Users: $userlist");
	}
	return;
}

sub useradd {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return if $where =~ m/^#/;

	my @args = split(/\s+/, $args);
	if(_validate_cmd($irc, $where, @args, $usermask, $command, 4) eq "success") {
		_load_users();
		my ($username, $mask, $password, $level) = split(/\s+/, $args);
		if(defined $users->{$username}) {
			$irc->yield(privmsg => $nick => "Error. User $username already exists.");
		} else {
			my $encrypted = crypt($password, $salt);
			$dbh_bot->do("INSERT INTO $table_users (nick, mask, password, level) VALUES ('$username', '$mask', '$encrypted', '$level')");
			_load_users();
			$irc->yield(privmsg => $nick => "User \"$username\" successfully created.");
			$irc->yield(privmsg => $username => "Your bot account has been created with the default password \"$password\". Please use \"passwd\" to change it.");
		}
	}
}

sub userdel {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return if $where =~ m/^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		_load_users();
		if(defined $users->{$args}) {
			$dbh_bot->do("DELETE FROM $table_users WHERE nick='$args'");
			_load_users();
			$irc->yield(privmsg => $nick => "User \"$args\" successfully deleted.");
		} else {
			$irc->yield(privmsg => $nick => "Unknown username: $args");
		}
	}
}

sub shutdown {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return if $where =~ m/^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		my $password = $args;
		if(crypt($password, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
			$irc->yield(shutdown => "Shutdown requested by $nick");
		}
	}
}

sub gtfo {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		my $target = $args;
		$irc->yield(kick => $where => $target => "GTFO!");
	}
}

sub mute {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		my $target = $args;
		$irc->yield(mode => "$where +q $target");
	}
	return;
}

sub unmute {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		my $target = $args;
		$irc->yield(mode => "$where -q $target");
	}
	return;
}

sub voice {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		my $target = $args;
		$irc->yield(mode => "$where +v $target");
	}
	return;
}

sub unvoice {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		my $target = $args;
		$irc->yield(mode => "$where -v $target");
	}
	return;
}

sub say {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 2) eq "success") {
		my @nicks = $irc->nicks();
		my ($target, $text) = split(/\s+/, $args);
		if(grep(/^$target$/, @nicks)) {
			$irc->yield(privmsg => $target => $text);
			$irc->yield(privmsg => $nick => "Message sent to $target.");
		} else {
			$irc->yield(privmsg => $where => "$target is not in the channel.");
		}
	}
}

sub nick {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	my @args = split(/!/, $args);
	return unless $where =~ /^#/;

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		$irc->yield(nick => $args);
	}
	return;
}

sub seen {
	my ($irc, $where, $args, $usermask, $command) = @_;
	return unless $where =~ /^#/;
	my @nicks = $irc->nicks();
	$args =~ s/ //g;

	my $q = "SELECT COUNT(*) FROM $table_seen WHERE nick='$args' AND channel='$where'";

	my $count = $dbh_bot->selectrow_array($q);
	if($count == 0) {
		$irc->yield(privmsg => $where => "I have not seen $args.");
	} else {
		my $time = $dbh_bot->selectrow_array("SELECT time FROM $table_seen WHERE nick='$args' AND channel='$where'");
		my $last = _duration(time - $time);

		if(grep(/^$args$/, @nicks)) {
			$irc->yield(privmsg => $where => "$args is in the channel now and last spoke $last ago.");
		} else {
			$irc->yield(privmsg => $where => "I last saw $args $last ago.");
		}
	}
}

sub mom {
	my ($irc, $where, $args, $usermask, $command) = @_;
	return unless $where =~ /^#/;
	my @nicks = $irc->nicks();
	$args =~ s/ //g;

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
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my $nick = (split /!/, $usermask)[0];

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}
	$irc->yield(privmsg => $target => "It is now " . strftime "%Y-%m-%d %T", localtime(time));
	return;
}

sub devices {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my $nick = (split /!/, $usermask)[0];
	my $devices = join(", ", sort(keys(%$devices)));

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = (split /!/, $where)[0];
	}
	$irc->yield(privmsg => $target => "supported devices: $devices");
	return;
}

sub device {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my $nick = (split /!/, $usermask)[0];

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(defined $devices->{$args}) {
		$irc->yield(privmsg => $target => "$args: $devices->{$args}->{description}");
	} else {
		$irc->yield(privmsg => $target => "unknown device: $args. type ${prefix}devices for a list of supported devices.");
	}
	return;
}

sub deviceadd {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = split (/!/, $usermask);
	my @args = split(/!/, $args);

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_devices();
		my($id, $description) = @args;
		if(defined $devices->{$id}) {
			$irc->yield(privmsg => $target => "device $id already exists.");
		} else {
			$dbh_bot->do("INSERT INTO devices (id, description, usermask) VALUES ('$id', '$description', '$usermask')");
			_load_devices();
			$irc->yield(privmsg => $target => "Device $id successfully added.");
		}
	}
	return;
}

sub devicedel {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = split (/!/, $usermask);

	my $target;

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		_load_devices();
		my $id = $args;
		if(defined $devices->{$id}) {
			$dbh_bot->do("DELETE FROM $table_devices WHERE id=i'$id'");
			_load_devices();
			$irc->yield(privmsg => $target => "device $id successfully deleted.");
		} else {
			$irc->yield(privmsg => $target => "unknown device: $id. type ${prefix}devices for a list of supported devices.");
		}
	}
}

sub links {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my $nick = (split /!/, $usermask)[0];

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	my $links = join(", ", sort(keys(%$links)));
	$irc->yield(privmsg => $target => "Available links: $links");
	return;
}

sub link {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my $nick = (split /!/, $usermask)[0];

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(defined $links->{$args}) {
		$irc->yield(privmsg => $target => "$args: $links->{$args}->{url}");
	} else {
		$irc->yield(privmsg => $target => "unknown link: $args. type ${prefix}links for a list of available links.");
	}
	return;
}

sub linkadd {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = split (/!/, $usermask);
	my @args = split(/!/, $args);

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_links();
		my ($title, $url) = @args;
		if(defined $links->{$title}) {
			$irc->yield(privmsg => $target => "link $title already exists.");
		} else {
			$dbh_bot->do("INSERT INTO links (title, url, usermask) VALUES ('$title', '$url', '$usermask')");
			_load_links();
			$irc->yield(privmsg => $target => "link $title successfully added.");
		}
	}
	return;
}

sub linkdel {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = (split /!/, $usermask);

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 1) eq "success") {
		_load_links();
		my $title = $args;
		if(defined $links->{$title}) {
			$dbh_bot->do("DELETE FROM $table_links WHERE title='$title'");
			_load_links();
			$irc->yield(privmsg => $target => "Link $title successfully deleted.");
		} else {
			$irc->yield(privmsg => $target => "unknown link: $title. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub linkmod {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = (split /!/, $usermask);

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}

	if(_validate_cmd($irc, $where, $args, $usermask, $command, 2) eq "success") {
		_load_links();
		my ($title, $url) = split(/\s+/, $args);
		if(defined $links->{$title}) {
			$dbh_bot->do("UPDATE $table_links SET url='$url' WHERE descriptor='$title'");
			_load_links();
			$irc->yield(privmsg => $target => "link $args[0] successfully updated.");
		} else {
			$irc->yield(privmsg => $target => "unknown link: $args[0]. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub enable {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = (split /!/, $usermask);

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}
	my @args = ($args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $cmd = $args;
		if(defined $commands{$cmd}) {
			if(_command_enabled($cmd) eq "success") {
				$irc->yield(privmsg => $target => "command \"$cmd\" is already enabled. nothing to do.");
				return;
			}
			$dbh_commands->do("UPDATE $table_commands SET enabled=1 WHERE command='$cmd'");
			$irc->yield(privmsg => $target => "command \"$cmd\" has been enabled.");
		} else {
			$irc->yield(privmsg => $target => "command \"$cmd\" doesn't exist.");
		}
	}
	return;
}

sub disable {
	my ($irc, $where, $args, $usermask, $command) = @_;
	my $target;
	my ($nick, $mask) = (split /!/, $usermask);

	if($where =~ /^#/) {
		$target = $where;
	} else {
		$target = $nick;
	}
	my @args = ($args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $cmd = $args;
		if($commands{$cmd}) {
			if(_command_enabled($cmd) ne "success") {
				$irc->yield(privmsg => $target => "command \"$cmd\" is already disabled. nothing to do.");
				return;
			}

			if(_command_can_be_disabled($cmd) ne "success") {
				$irc->yield(privmsg => $target => "Are you kidding!?");
				return;
			} else {
				$dbh_commands->do("UPDATE $table_commands SET enabled=0 WHERE command='$cmd'");
				$irc->yield(privmsg => $target => "command \"$cmd\" has been disabled.");
			}
		} else {
			$irc->yield(privmsg => $target => "command \"$cmd\" doesn't exist.");
		}
	}
	return;
}

#####################
# Support functions #
#####################

sub _log_seen {
	my ($nick, $time, $where) = @_;

	if( $dbh_bot->selectrow_array("SELECT COUNT(*) FROM $table_seen WHERE nick='$nick' AND channel='$where'") == 0 ) {
		$dbh_bot->do("INSERT INTO $table_seen (nick, time, channel) VALUES ('$nick', '$time', '$where')");
	} else {
		$dbh_bot->do("UPDATE $table_seen SET time='$time' WHERE nick='$nick'");
	}
}

sub _load_devices {
	my $dbh = $dbh_bot;
	my $sth = _do_query($dbh, "SELECT * FROM $table_devices");
	$devices = $dbh->selectall_hashref($sth, "id");
}

sub _load_users {
	my $dbh = $dbh_bot;
	my $sth = _do_query($dbh, "SELECT * FROM $table_users");
	$users = $dbh->selectall_hashref($sth, "nick");
}

sub _load_links {
	my $dbh = $dbh_bot;
	my $sth = _do_query($dbh, "SELECT * FROM $table_links");
	$links = $dbh->selectall_hashref($sth, "title");
}

sub _load_commands {
	my $dbh = $dbh_commands;
	my %commands;
	my $sth = _do_query($dbh, "SELECT * FROM $table_commands");
	while (my $row = $sth->fetchrow_hashref()) {
		my $cmd = $row->{command};
		# Do not load a command without a supporting function
		if (my $subref = _function_exists("${cmd}$n")) {
			$commands{$cmd} = $row;
		}
	}
	return %commands;
}

sub _validate_cmd {
	my ($irc, $where, $args, $usermask, $command, $argcount) = @_;
	my ($nick, $mask) = split(/!/, $usermask);
	my @args = @$args;
	my $now = time;
	my $account_status = 1;
	my $output;

	# Validate account and permissions
	if(defined $users->{$nick} and $users->{$nick}->{mask} eq $mask) {
		# Validate level
		if($users->{$nick}->{level} < $commands{$command}{level}) {
			$account_status = 0;
			$output = "You do not have permission to execute $command.";

		# Validate session
		} elsif(($now - $users->{$nick}->{last_auth}) > $session_timeout) {
			$account_status = 0;
			$output = "Your session has expired. Please login with \"auth\".";
		}
	} else {
		$account_status = 0;
		$output = "Unknown username: $nick";
		return $output;
	}
	if($account_status == 0) {
		$irc->yield(privmsg => $nick => $output);
		return "failed";
	}

	# Validate command
	if(@args != $argcount) {
		$irc->yield(privmsg => $where => "Syntax error.");
		help($irc, $where, $command, $usermask);
		return "failed";
	} else {
		return "success";
	}
}

sub _command_enabled {
	my $cmd = shift;
	my $q = "SELECT enabled FROM $table_commands WHERE command='$cmd'";
	if($dbh_commands->selectrow_array($q) == 1) {
		return "success";
	} else {
		return "failed";
	}
}

sub _command_can_be_disabled {
	my $cmd = shift;
	my $q = "SELECT can_be_disabled FROM $table_commands WHERE command='$cmd'";
	if($dbh_commands->selectrow_array($q) == 1) {
		return "success";
	} else {
		return "failed";
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

sub _function_exists {
	no strict "refs";
	my $function = shift;
	return \&{$function} if defined &{$function};
	return;
}

sub _read_config {
	my $config_file = "$root/conf/bot.conf";
	die("Cannot open config file \"$config_file\" for reading.\n") unless -f $config_file;
	my $cfg = Config::Tiny->read($config_file);
	return $cfg;
}
1;
