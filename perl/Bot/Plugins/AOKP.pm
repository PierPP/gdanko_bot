package Bot::Plugins::AOKP;

use botCmd qw($commands);
use Data::Dumper;
use JSON::XS;

my $module = "aokp";
my $bot = botCmd->new();
my $root = $bot->{cfg}->{general}->{root};
my $table_devices = $bot->{cfg}->{database}->{table_devices};
my $dbh = $bot->{dbh};
my $devices = {};
my $commands = ${botCmd::commands};

load_devices();
load_commands();

sub new {
	my $class = shift;
	my $self = {};
	$self->{name} = $module;
	bless($self, $class);
	return $self;
}

sub devices {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		load_devices();
		my $devices = join(", ", sort(keys(%$devices)));
		$irc->yield(privmsg => $where => "supported devices: $devices");
		return;
	}
}

sub device {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
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
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args;
	@args = ($1, $2) if $args =~ m/(.*?) +(.*)/;

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		load_devices();
		my($id, $description) = @args;
		if(defined $devices->{$id}) {
			$irc->yield(privmsg => $where => "device $id already exists.");
		} else {
			$dbh->do("INSERT INTO devices (id, description, usermask) VALUES ('$id', '$description', '$usermask')");
			load_devices();
			$irc->yield(privmsg => $where => "Device $id successfully added.");
		}
	}
	return;
}

sub devicedel {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		load_devices();
		my $id = $args;
		if(defined $devices->{$id}) {
			$dbh->do("DELETE FROM $table_devices WHERE id=i'$id'");
			load_devices();
			$irc->yield(privmsg => $where => "device $id successfully deleted.");
		} else {
			$irc->yield(privmsg => $where => "unknown device: $id. type ${prefix}devices for a list of supported devices.");
		}
	}
}

sub devicemod {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args;
	@args = ($1, $2) if $args =~ m/(.*?) +(.*)/;

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		load_devices();
		my($id, $description) = @args;
		if(defined $devices->{$id}) {
			$dbh->do("UPDATE devices SET description='$description', usermask='$usermask' WHERE id='$id'");
			load_devices();
			$irc->yield(privmsg => $where => "Device $id successfully modified.");
		} else {
			$irc->yield(privmsg => $where => "Device $id does not exist.");
		}
	}
	return;
}

sub gerrit {
	my $self = shift;
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
	my $output = $bot->fetch_url($url, $h, "POST", $payload);
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

sub load_devices {
	my $sth = $dbh->prepare("SELECT * FROM $table_devices");
	$sth->execute;
	$devices = $dbh->selectall_hashref($sth, "id");
}

sub load_commands {
	my $methods = {
		devices => {
			usage => "devices -- Lists all devices supported by AOKP.",
			level => 0,
			can_be_disabled => 1
		},
		device => {
			usage => "device <device name> -- Accepts a device codename, e.g. toro, and displays the actual device name.",
			level => 0,
			can_be_disabled => 1
		},
		deviceadd => {
			usage => "deviceadd <device id> <device name> -- Add a device to the database.",
			level => 40,
			can_be_disabled => 1
		},
		devicedel => {
			usage => "devicedel <device id> -- Remove a device from the database. Example: devicedel toro",
			level => 40,
			can_be_disabled => 1
		},
		gerrit => {
			usage => "gerrit <query> -- Perform a Gerrit search for <query>. All Gerrit search criteria such as \"status:abandond\" can be used.",
			level => 0,
			can_be_disabled => 1
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
