package Bot::Plugins::Modes;

use botCmd qw($commands);
use Data::Dumper;
use DBI;

my $module = "modes";
my $bot = botCmd->new();
my $dbh = $bot->{dbh};
my $table_commands = $bot->{cfg}->{database}->{table_commands};
my $commands = ${botCmd::commands};
load_commands();

sub new {
	my $class = shift;
	my $self = {};
	$self->{name} = $module;
	bless($self, $class);
	return $self;
}

sub mute {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "private";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where +q $target");
	}
	return;
}

sub unmute {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "private";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where -q $target");
	}
	return;
}

sub op {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "private";
	my ($nick, $mask) = split (/!/, $usermask);
	my @args;
	if(defined $args) {
		@args = ($args);
	} else {
		@args = ($nick);
	}

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $target = $args[0];
		$irc->yield(mode => "$where +o $target");
	}
}

sub deop {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "private";
	my @args = ($args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where -o $target");
	}
}


sub voice {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		#my ($channel, $target) = @args;
		my $target = $args;
		$irc->yield(mode => "$where +v $target");
	}
	return;
}

sub unvoice {
	my $self = shift;
	# if in channel use channel, otherwise one is required.
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	#return if $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(mode => "$where -v $target");
	}
	return;
}

sub load_commands {
	my $methods = {
		mute => {
			usage => "mute <nick> -- Mute a user.",
			level => 50,
			can_be_disabled => 1
		},
		unmute => {
			usage => "unmute <nick> -- Unmute a user.",
			level => 50,
			can_be_disabled => 1
		},
		voice => {
			usage => "voice <nick> -- Give a user +v.",
			level => 50,
			can_be_disabled => 1
		},
		unvoice => {
			usage => " unvoice <nick> -- Give a user -v.",
			level => 50,
			can_be_disabled => 1
		},
		op => {
			usage => "op [<nick>] -- If executed with a nick, ops <nick>, otherwise ops the requestor.",
			level => 90,
			can_be_disabled => 1
		},
		deop => {
			usage => "deop <nick> -- De-op <nick>.",
			level => 90,
			can_be_disabled => 1
		}
	};

	foreach my $key (keys %$methods) {
		my $method = $methods->{$key};
		$method->{module} = $module;
		$method->{method} = $key;
		$commands->{$key} = $method;

		my $count = $dbh->selectrow_array("SELECT COUNT(*) FROM $table_commands WHERE command='$key'");
		if($count > 0) {
			$dbh->do("UPDATE $table_commands SET level='$method->{level}' WHERE command='$key'");
		} else {
			$dbh->do("INSERT INTO $table_commands (command, level, channels) VALUES ('$key', $method->{level}, '#teamkang,#AOKP-dev,#AOKP-support')");
		}
	}
}
	
1;
