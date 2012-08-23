package Bot::Plugins::Support;

use botCmd qw($commands);
use Data::Dumper;
use DBI;

my $module = "support";
my $bot = botCmd->new();
my $dbh = $bot->{dbh};
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
	$bot->update_commands($module, $methods);
}
1;
