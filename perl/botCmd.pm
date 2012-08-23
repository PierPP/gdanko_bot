package botCmd;

use lib "/home/gdanko/bot/perl";
use Config::Tiny;
use Data::Dumper;
use DBI;
use HTTP::Request::Common qw { POST };
use HTTP::Headers;
use JSON::XS;
use LWP::UserAgent;
use Module::Pluggable search_path => "Bot";
use POSIX qw(strftime ceil);

@EXPORT = qw($commands);

my %classes;
our $commands = {};

my $cfg = read_config();
my $prefix = $cfg->{misc}->{prefix};
my $session_timeout = $cfg->{general}->{session_timeout};
my $root = $cfg->{general}->{root};
my $salt = $cfg->{general}->{salt};
my $database = $cfg->{database}->{database};
my $table_users = $cfg->{database}->{table_users};
my $table_seen = $cfg->{database}->{table_seen};
my $table_commands = $cfg->{database}->{table_commands};
my $table_autoop = $cfg->{database}->{table_autoop};
my $ua = LWP::UserAgent->new();
my @tiny = ("tinyurl.com", "goo.gl");
my $dbh = DBI->connect("dbi:SQLite:dbname=$root/db/$database", "", "");
my $users = {};
load_users();

# Import the modules
for my $module ( plugins() ) {
	eval "use $module";
	if($@) {
		print STDERR "[Warn] Failed to load plugin $module: $@\n";
	} else {
		print "Loaded: $module\n";
		my $mod = $module->new();
		my $module_name = $mod->{name};
		$classes{$module_name} = $mod;
	}
}
load_commands();
#print STDERR Dumper(\$commands);


$reloadtime = localtime;

# Set up the new
sub new {
	my $class = shift;
	my $self = {};
	$self->{cfg} = $cfg;
	$self->{dbh} = $dbh;
	bless($self, $class);
	return $self;
}

################
# IRC Handlers #
################

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

	# Auto voice
	#$irc->yield(mode => "$channel +v $nick");
}

sub _whois_handler {
	my ($irc, $whois) = @_;
	$irc->yield(whois => "gdanko");
	$irc->yield(privmsg => "gdanko" => "whois");
}

sub _pub_msg_handler {
	my ($irc, $kernel, $usermask, $channels, $message) = @_;
	my ($command, $args);
	my $channel = $channels->[0];
	my $nick = (split /!/, $usermask)[0];

	# Log to the "seen" table
	log_seen($nick, time, $where);

	# Interpret commands
	if($message =~ /^$prefix/) {
		$message =~ s/^$prefix//;
		if ($message =~ m/(.*?) +(.*)/) {
			($command, $args) = ($1, $2);
		} else {
			$command = $message;
		}

		if($commands->{$command}) {
			my $module = $commands->{$command}->{module};
			my $method = $commands->{$command}->{method};
			eval { $classes{$module}->$method($irc, $channel, $args, $usermask, $command, "public") };
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

	if($commands->{$command}) {
		my $module = $commands->{$command}->{module};
		my $method = $commands->{$command}->{method};
		eval { $classes{$module}->$method($irc, $nick, $args, $usermask, $command, "private") };
		$irc->yield(privmsg => $nick => "Got the following error: $@") if $@;
	} else {
		$irc->yield(privmsg => $nick => "Invalid command: $command. Type \"help\" for a list of valid commands.");
	}
	return;
}

#####################
# Support Functions #
#####################

sub log_seen {
	my ($nick, $time, $where) = @_;

	if( $dbh->selectrow_array("SELECT COUNT(*) FROM $table_seen WHERE nick='$nick' AND channel='$where'") == 0 ) {
		$dbh->do("INSERT INTO $table_seen (nick, time, channel) VALUES ('$nick', '$time', '$where')");
	} else {
		$dbh->do("UPDATE $table_seen SET time='$time' WHERE nick='$nick'");
	}
}

sub load_users {
	my $sth = $dbh->prepare("SELECT * FROM $table_users");
	$sth->execute;
	$users = $dbh->selectall_hashref($sth, "nick");
}

###########
# Helpers #
###########

sub validate_cmd {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $argcount) = @_;
	my ($nick, $mask) = split(/!/, $usermask);
	my @args = @$args;
	my $now = time;
	my $account_status = 1;
	my $output;

	if($commands->{$command}->{level} > 0) {
		# Validate account and permissions
		if(defined $users->{$nick} and $users->{$nick}->{mask} eq $mask) {
			# Validate level
			if($users->{$nick}->{level} < $commands->{$command}->{level}) {
				$account_status = 0;
				$output = "You do not have permission to execute $command.";

			# Validate session
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
		#help($irc, $where, $command, $usermask);
		return "failed";
	} else {
		return "success";
	}
}

sub log_error {
	my $self = shift;
	my $text = shift;
	print STDERR "$text\n";
}

sub command_enabled {
	my $self = shift;
	my $cmd = shift;
	my $q = "SELECT enabled FROM $table_commands WHERE command='$cmd'";
	if($dbh->selectrow_array($q) == 1) {
		return "success";
	} else {
		return "failed";
	}
}

sub command_visible {
	my $self = shift;
	my $cmd = shift;
	my $q = "SELECT hidden FROM $table_commands WHERE command='$cmd'";
	if($dbh->selectrow_array($q) == 0) {
		return "success";
	} else {
		return "failed";
	}
}

sub command_can_be_disabled {
	my $self = shift;
	my $cmd = shift;
	my $q = "SELECT can_be_disabled FROM $table_commands WHERE command='$cmd'";
	if($dbh->selectrow_array($q) == 1) {
		return "success";
	} else {
		return "failed";
	}
}

sub fetch_url {
	my $self = shift;
	my ($url, $headers, $method, $data) = @_;
	my $req = HTTP::Request->new($method, $url, $headers, $data);
	my $resp = $ua->request($req);
	return $resp->content;
}

sub duration {
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

sub function_exists {
	my $self = shift;
	no strict "refs";
	my $function = shift;
	return \&{$function} if defined &{$function};
	return;
}

sub update_commands {
	my $self = shift;
	my ($module, $methods) = @_;
	foreach my $key (keys %$methods) {
		my $method;
		my $command = $methods->{$key};
		if($command->{method}) {
			$method = $command->{method};
		} else {
			$method = $key;
		}
		my $usage = $command->{usage};
		my $level = $command->{level};
		my $cbd = $command->{can_be_disabled};

		my $count = $dbh->selectrow_array("SELECT COUNT(*) FROM $table_commands WHERE command='$key'");
		if($count > 0) {
			$dbh->do(
				"UPDATE $table_commands SET module='$module', method='$method', usage=\"$usage\", level='$level', can_be_disabled='$cbd' WHERE command='$key'"
			);
		} else {
			$dbh->do(
				"INSERT INTO $table_commands (command, usage, level, can_be_disabled, module, method, channels) VALUES ('$key', \"$usage\", $level, $cbd, '$module', '$method', '#teamkang,#AOKP-dev,#AOKP-support')"
			);
		}
	}
}

sub load_commands {
	my $self = shift;
	my $sth = $dbh->prepare("SELECT * FROM $table_commands");
	$sth->execute;
	$commands = $dbh->selectall_hashref($sth, "command");
	foreach my $key (keys %$commands) {
		$commands->{$key}->{channels} = [ split(",", $commands->{$key}->{channels}) ];
	}
}

sub read_config {
	my $config_file = "/home/gdanko/bot/bot.conf";
	die("Cannot open config file \"$config_file\" for reading.\n") unless -f $config_file;
	my $cfg = Config::Tiny->read($config_file);
	return $cfg;
}
1;
