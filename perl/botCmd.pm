package botCmd;

use lib "/home/gdanko/bot/perl";
use Config::Tiny;
use Data::Dumper;
use DBI;
use Encode;
use Exporter;
use HTTP::Request::Common qw { POST };
use HTTP::Headers;
use JSON::XS;
use LWP::UserAgent;
use POSIX qw(strftime ceil);

@ISA = ('Exporter');
@EXPORT = ();
@EXPORT_OK = qw($reloadtime &_pub_msg_handler &_priv_message_handler &_ctcp_handler &_join_handler &_whois_handler);

$reloadtime = localtime;

my $cfg = _read_config();
my $prefix = $cfg->{misc}->{prefix};
my $session_timeout = $cfg->{general}->{session_timeout};
my $root = $cfg->{general}->{root};
my $salt = $cfg->{general}->{salt};
my $database = $cfg->{database}->{database};
my $table_users = $cfg->{database}->{table_users};
my $table_devices = $cfg->{database}->{table_devices};
my $table_links = $cfg->{database}->{table_links};
my $table_seen = $cfg->{database}->{table_seen};
my $table_commands = $cfg->{database}->{table_commands};
my $table_autoop = $cfg->{database}->{table_autoop};
my $ua = LWP::UserAgent->new();
my @tiny = ("tinyurl.com", "goo.gl");

my $dbh = DBI->connect("dbi:SQLite:dbname=$root/db/$database", "", "");
my $devices = {};
my $users = {};
my $links = {};
my %commands = _load_commands();
_load_devices();
_load_users();
_load_links();

#################
# Core commands #
#################

sub help {
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

	if($cmd ne undef and $commands{$cmd}) {
		return unless _command_enabled($cmd) eq "success" and _command_visible($cmd) eq "success";
		if($level >= $commands{$args}{level}) {
			$irc->yield(privmsg => $target => "Usage: $commands{$args}{usage}");
		}

	} elsif($args) {
		$irc->yield(privmsg => $target => "Sorry, \"$args\" not found in list of commands.  Try \"${cmd_prefix}help\" to see list of available commands.");

	} else {
		my $sth = _do_query($dbh, "SELECT command FROM commands WHERE enabled=1 AND hidden=0 AND level<=$level");
		my $help_items = $dbh->selectall_hashref($sth, "command");
		$irc->yield(privmsg => $target => "Available commands are: " . join(", ", sort keys %$help_items));
		$irc->yield(privmsg => $target => "Use \"${cmd_prefix}help <command>\" for help with a specific command.");
	}	
	return;
}

sub auth {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		_load_users();
		my($nick, $mask) = split(/!/, $usermask);
		my $passwd = $args;

		if(defined $users->{$nick} and defined $users->{$nick}->{mask}) {
			if(crypt($passwd, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				my $now = time;
				$dbh->do("UPDATE $table_users SET last_auth='$now' WHERE nick='$nick'");
				_load_users();
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
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		_load_users();
		my($nick, $mask) = split(/!/, $usermask);
		$dbh->do("UPDATE $table_users SET last_auth=0 WHERE nick='$nick'");
		_load_users();
		$irc->yield(privmsg => $nick => "Session data removed.");
	}
}
	
sub passwd {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_users();
		my($nick, $mask) = split(/!/, $usermask);
		
		if(defined $users->{$nick}) {
			my ($old_passwd, $new_passwd) = split(/\s+/, $args);
			if(crypt($old_passwd, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
				my $encrypted = crypt($new_passwd, $salt);
				$dbh->do("UPDATE $table_users SET password='$encrypted' WHERE nick='$nick'");
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
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		_load_users();
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
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 4) eq "success") {
		_load_users();
		my ($nick, $mask) = split (/!/, $usermask);
		my ($username, $mask, $password, $level) = split(/\s+/, $args);

		if($level !~ /^\d+$/) {
			$irc->yield(privmsg => $nick => "Error. Level must be an integer.");
			help($irc, $where, $command, $usermask);
			return;
		}

		if(defined $users->{$username}) {
			$irc->yield(privmsg => $nick => "Error. User $username already exists.");
		} else {
			my $encrypted = crypt($password, $salt);
			$dbh->do("INSERT INTO $table_users (nick, mask, password, level) VALUES ('$username', '$mask', '$encrypted', '$level')");
			_load_users();
			$irc->yield(privmsg => $nick => "User \"$username\" successfully created.");
			$irc->yield(privmsg => $username => "Your bot account has been created with the default password \"$password\". Please use \"passwd\" to change it.");
		}
	}
}

sub userdel {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		_load_users();
		my ($nick, $mask) = split (/!/, $usermask);

		if(defined $users->{$args}) {
			$dbh->do("DELETE FROM $table_users WHERE nick='$args'");
			_load_users();
			$irc->yield(privmsg => $nick => "User \"$args\" successfully deleted.");
		} else {
			$irc->yield(privmsg => $nick => "Unknown username: $args");
		}
	}
}

sub shutdown {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $password = $args;
		if(crypt($password, $users->{$nick}->{password}) eq $users->{$nick}->{password}) {
			$irc->yield(shutdown => "Shutdown requested by $nick");
		}
	}
}

sub gtfo {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "private";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(kick => $where => $target => "GTFO!");
	}
}

sub mute {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where +q $target");
	}
	return;
}

sub unmute {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where -q $target");
	}
	return;
}

sub voice {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my ($channel, $target) = @args;
		$irc->yield(mode => "$channel +v $target");
	}
	return;
}

sub unvoice {
	# if in channel use channel, otherwise one is required.
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where -v $target");
	}
	return;
}

sub join {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $channel = $args;
		$channel = "#$channel" unless $channel =~ /^#/;
		$irc->yield(join => $channel);
	}
}

sub part {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $channel = $args;
		$channel = "#$channel" unless $channel =~ /^#/;
		$irc->yield(part => $channel);
	}
}

sub say {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args;
	@args = ($1, $2) if $args =~ m/(.*?) +(.*)/;

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my @nicks = $irc->nicks();
		my ($target, $text) = @args;
		if(grep(/^$target$/, @nicks)) {
			$irc->yield(privmsg => $target => $text);
			$irc->yield(privmsg => $nick => "Message sent to $target.");
		} else {
			$irc->yield(privmsg => $where => "$target is not in the channel.");
		}
	}
}

sub nick {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		$irc->yield(nick => $args);
	}
	return;
}

sub seen {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my @nicks = $irc->nicks();
		$args =~ s/ //g;

		my $q = "SELECT COUNT(*) FROM $table_seen WHERE nick='$args' AND channel='$where'";

		my $count = $dbh->selectrow_array($q);
		if($count == 0) {
			$irc->yield(privmsg => $where => "I have not seen $args.");
		} else {
			my $time = $dbh->selectrow_array("SELECT time FROM $table_seen WHERE nick='$args' AND channel='$where'");
			my $last = _duration(time - $time);

			if(grep(/^$args$/, @nicks)) {
				$irc->yield(privmsg => $where => "$args is in the channel now and last spoke $last ago.");
			} else {
				$irc->yield(privmsg => $where => "I last saw $args $last ago.");
			}
		}
	}	
}

sub ball {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = ($args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		return unless defined $args;
		my @answers = ("It is certain", "It is decidedly so", "Without a doubt", "Yes – definitely", "You may rely on it", "As I see it, yes", "Most likely", "Outlook good", "Yes", "Signs point to yes", "Reply hazy,  try again", "Ask again later", "Better not tell you now", "Cannot predict now", "Concentrate and ask again", "Don't count on it", "My reply is no", "My sources say no", "Outlook not so good", "Very doubtful", "ProTekk!");
		$irc->yield(privmsg => $where => $answers[ int(rand(@answers)) ]);
	}
}

sub mom {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = ($args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my @nicks = $irc->nicks();
		$args =~ s/ //g;

		if(grep(/^$args$/, @nicks)) {
			$irc->yield(privmsg => $where => "$args: I heard your mom uses an iPhone.");
		}
	}
}

sub goog {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = ($args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $q = $args;
		my $json = get("http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=$q");
		my $utf8 = encode ('utf8', $json);
		my $hashref = decode_json $utf8;
		my $url = $hashref->{responseData}->{results}[0]->{url};
		$irc->yield(privmsg => $where => $url);
	}
}

sub gerrit {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	my ($count, @changes, $url, $plref, $payload, $max_results, $h, $output);
	$max_results = 10;
	$url = "http://gerrit.sudoservers.com/gerrit/rpc/ChangeListService";
	$plref = {
		"jsonrpc" => "2.0",
		"method" => "allQueryNext",
		"params" => [ $args, "z", $max_results ],
		"id" => 1
	};
	$payload = JSON::XS->new->utf8->encode($plref);
	$h = HTTP::Headers->new(
    	Accept => "application/json",
    	Content_Type => "application/json; charset=UTF-8"
	);
	my $output = _fetch_url($url, $h, "POST", $payload);
	my $data = decode_json $output;

	if(defined $data->{error}) {
		$irc->yield(privmsg => $nick => "No results found.");
	} else {
		$irc->yield(privmsg => $nick => "Top results for the query \"$args\"");
		my @changes = @{$data->{result}->{changes}};
		foreach my $change (@changes) {
			my $c_id = $change->{id}->{id};
			my $c_subj = $change->{subject};
			$irc->yield(privmsg => $nick => "http://gerrit.sudoservers.com/$c_id - $c_subj");
		}
	}
}

sub test {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	my $text = sprintf("%15s%15s%15s", "1", "2", "3");
	$irc->yield(privmsg => $nick => $text);
}

sub _ctcp_handler {
	my ($irc, $kernel, $usermask, $channels, $message) = @_;
	return;
}

sub _join_handler {
	my ($irc, $kernel, $usermask, $channel) = @_;
	my ($nick, $mask) = split (/!/, $usermask);
	my $q = "SELECT COUNT(*) FROM $table_autoop WHERE usermask='$usermask'";
	my $count = $dbh->selectrow_array($q);
	$irc->yield(mode => "$channel +o $nick") if $count == 1;
}

sub _whois_handler {
	my ($irc, $whois) = @_;
	$irc->yield(whois => "gdanko");
	$irc->yield(privmsg => "gdanko" => "whois");
}

##################
# Other commands #
##################

sub time {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		$irc->yield(privmsg => $where => "It is now " . strftime "%Y-%m-%d %T", localtime(time));
	}
	return;
}

sub devices {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		_load_devices();
		my $devices = join(", ", sort(keys(%$devices)));
		$irc->yield(privmsg => $where => "supported devices: $devices");
		return;
	}
}

sub device {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $device = $args;
		if(defined $devices->{$device}) {
			$irc->yield(privmsg => $where => "$device: $devices->{$args}->{description}");
		} else {
			$irc->yield(privmsg => $where => "unknown device: $device. type ${prefix}devices for a list of supported devices.");
		}
	}
	return;
}

sub deviceadd {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args;
	@args = ($1, $2) if $args =~ m/(.*?) +(.*)/;

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_devices();
		my($id, $description) = @args;
		if(defined $devices->{$id}) {
			$irc->yield(privmsg => $where => "device $id already exists.");
		} else {
			$dbh->do("INSERT INTO devices (id, description, usermask) VALUES ('$id', '$description', '$usermask')");
			_load_devices();
			$irc->yield(privmsg => $where => "Device $id successfully added.");
		}
	}
	return;
}

sub devicedel {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		_load_devices();
		my $id = $args;
		if(defined $devices->{$id}) {
			$dbh->do("DELETE FROM $table_devices WHERE id=i'$id'");
			_load_devices();
			$irc->yield(privmsg => $where => "device $id successfully deleted.");
		} else {
			$irc->yield(privmsg => $where => "unknown device: $id. type ${prefix}devices for a list of supported devices.");
		}
	}
}

sub devicemod {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args;
	@args = ($1, $2) if $args =~ m/(.*?) +(.*)/;

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_devices();
		my($id, $description) = @args;
		if(defined $devices->{$id}) {
			$dbh->do("UPDATE devices SET description='$description', usermask='$usermask' WHERE id='$id'");
			_load_devices();
			$irc->yield(privmsg => $where => "Device $id successfully modified.");
		} else {
			$irc->yield(privmsg => $where => "Device $id does not exist.");
		}
	}
	return;
}

sub links {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		my $links = join(", ", sort(keys(%$links)));
		$irc->yield(privmsg => $where => "Available links: $links");
		$irc->yield(privmsg => $where => "Type ${prefix}link <link> to display the URL.");
	}
	return;
}

sub link {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		if(defined $links->{$args}) {
			$irc->yield(privmsg => $where => "$args: $links->{$args}->{url}.");
		} else {
			$irc->yield(privmsg => $where => "unknown link: $args. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub linkadd {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_links();
		my ($title, $url) = @args;
		if(defined $links->{$title}) {
			$irc->yield(privmsg => $where => "link $title already exists.");
		} else {
			$dbh->do("INSERT INTO links (title, url, usermask) VALUES ('$title', '$url', '$usermask')");
			_load_links();
			$irc->yield(privmsg => $where => "link $title successfully added.");
		}
	}
	return;
}

sub linkdel {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		_load_links();
		my $title = $args;
		if(defined $links->{$title}) {
			$dbh->do("DELETE FROM $table_links WHERE title='$title'");
			_load_links();
			$irc->yield(privmsg => $where => "Link $title successfully deleted.");
		} else {
			$irc->yield(privmsg => $where => "unknown link: $title. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub linkmod {
	my ($irc, $where, $args, $usermask, $commandi, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		_load_links();
		my ($title, $url) = @args;
		if(defined $links->{$title}) {
			$dbh->do("UPDATE $table_links SET url='$url' WHERE title='$title'");
			_load_links();
			$irc->yield(privmsg => $where => "link $args[0] successfully updated.");
		} else {
			$irc->yield(privmsg => $where => "unknown link: $args[0]. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub enable {
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $cmd = $args;
		if(defined $commands{$cmd}) {
			if(_command_enabled($cmd) eq "success") {
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
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if(_validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $cmd = $args;
		if($commands{$cmd}) {
			if(_command_enabled($cmd) ne "success") {
				$irc->yield(privmsg => $where => "command \"$cmd\" is already disabled. nothing to do.");
				return;
			}

			if(_command_can_be_disabled($cmd) ne "success") {
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

#####################
# Support functions #
#####################

sub _pub_msg_handler {
	my ($irc, $kernel, $usermask, $channels, $message) = @_;
	my ($command, $args);
	my $channel = $channels->[0];
	my $nick = (split /!/, $usermask)[0];

	# Log to the "seen" table
	_log_seen($nick, time, $where);

	# Interpret commands
	if($message =~ /^$prefix/) {
		$message =~ s/^$prefix//;
		if ($message =~ m/(.*?) +(.*)/) {
			($command, $args) = ($1, $2);
		} else {
			$command = $message;
		}

		if($commands{$command}) {
			eval { &{$commands{$command}{function}}($irc, $channel, $args, $usermask, $command, "public") };
			$irc->yield(privmsg => $channel => "Got the following error: $@") if $@;
		} else {
			$irc->yield(privmsg => $channel => "Invalid command: $command. Type \"${prefix}help\" for a list of valid commands.");
		}
		return;

	# Tiny-fy URLs
	} elsif($message =~ m/^https?:\/\/([^\/]+)/) {
		# Do not process already shortened URLs
		return if grep(/^$1e$/, @tiny) or length($message) < 20;
		#my $tiny = get("http://tinyurl.com/api-create.php?url=$message");
		$irc->yield(privmsg => $where => $tiny);
		return;

	} else {
		return;
	}
}

sub _priv_msg_handler {
	my ($irc, $kernel, $usermask, $recipients, $message) = @_;
	my ($command, $args);
	my $nick = (split /!/, $usermask)[0];

	if ($message =~ m/(.*?) +(.*)/) {
		($command, $args) = ($1, $2);
	} else {
		$command = $message;
	}

	if($commands{$command}) {
		eval { &{$commands{$command}{function}}($irc, $nick, $args, $usermask, $command, "private") };
		$irc->yield(privmsg => $nick => "Got the following error: $@") if $@;
	} else {
		$irc->yield(privmsg => $nick => "Invalid command: $command. Type \"help\" for a list of valid commands.");
	}
	return;
}

sub _log_seen {
	my ($nick, $time, $where) = @_;

	if( $dbh->selectrow_array("SELECT COUNT(*) FROM $table_seen WHERE nick='$nick' AND channel='$where'") == 0 ) {
		$dbh->do("INSERT INTO $table_seen (nick, time, channel) VALUES ('$nick', '$time', '$where')");
	} else {
		$dbh->do("UPDATE $table_seen SET time='$time' WHERE nick='$nick'");
	}
}

sub _load_devices {
	my $dbh = $dbh;
	my $sth = _do_query($dbh, "SELECT * FROM $table_devices");
	$devices = $dbh->selectall_hashref($sth, "id");
}

sub _load_users {
	my $dbh = $dbh;
	my $sth = _do_query($dbh, "SELECT * FROM $table_users");
	$users = $dbh->selectall_hashref($sth, "nick");
}

sub _load_links {
	my $dbh = $dbh;
	my $sth = _do_query($dbh, "SELECT * FROM $table_links");
	$links = $dbh->selectall_hashref($sth, "title");
}

sub _load_commands {
	my $dbh = $dbh;
	my %commands;
	my $sth = _do_query($dbh, "SELECT * FROM $table_commands");
	while (my $row = $sth->fetchrow_hashref()) {
		my $cmd = $row->{command};
		my $function = $row->{function};
		# Do not load a command without a supporting function
		if (my $subref = _function_exists("${function}$n")) {
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

	if($commands{$command}{level} > 0) {
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
		}

		if($account_status == 0) {
			$irc->yield(privmsg => $nick => $output);
			return "failed";
		}
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
	if($dbh->selectrow_array($q) == 1) {
		return "success";
	} else {
		return "failed";
	}
}

sub _command_visible {
	my $cmd = shift;
	my $q = "SELECT hidden FROM $table_commands WHERE command='$cmd'";
	if($dbh->selectrow_array($q) == 0) {
		return "success";
	} else {
		return "failed";
	}
}

sub _command_can_be_disabled {
	my $cmd = shift;
	my $q = "SELECT can_be_disabled FROM $table_commands WHERE command='$cmd'";
	if($dbh->selectrow_array($q) == 1) {
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

sub _fetch_url {
	my ($url, $headers, $method, $data) = @_;
	my $req = HTTP::Request->new($method, $url, $headers, $data);
	my $resp = $ua->request($req);
	return $resp->content;
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
	my $config_file = "/home/gdanko/bot/bot.conf";
	die("Cannot open config file \"$config_file\" for reading.\n") unless -f $config_file;
	my $cfg = Config::Tiny->read($config_file);
	return $cfg;
}
1;
