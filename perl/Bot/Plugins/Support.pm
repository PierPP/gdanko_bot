package Bot::Plugins::Support;

use botCmd qw($commands);
use Data::Dumper;
use DBI;

my $module = "support";
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

sub faq {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		$irc->yield(privmsg => $where => "faq coming soon!");
	}
	return;
}

sub rules {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		$irc->yield(privmsg => $where => "rules coming soon!");
	}
	return;
}

sub load_commands {
	my $methods = {
		faq => {
			usage => "faq -- Display the support channel FAQ.",
			level => 0,
			can_be_disabled => 0
		},
		rules => {
			usage => "rules == Display the support channel rules.",
			level => 0,
			can_be_disabled => 0
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
