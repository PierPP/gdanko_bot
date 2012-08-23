package Bot::Plugins::Extras;

use botCmd qw($commands);
use Encode;
use JSON::XS;
use POSIX qw(strftime);

my $module = "extras";
my $bot = botCmd->new();
my $table_links = $bot->{cfg}->{database}->{table_links};
my $dbh = $bot->{dbh};
my $links = {};
my $commands = ${botCmd::commands};

load_links();
load_commands();

sub new {
	my $class = shift;
	my $self = {};
	$self->{name} = $module;
	bless($self, $class);
	return $self;
}

sub ball {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = ($args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		return unless defined $args;
		my @answers = ("It is certain", "It is decidedly so", "Without a doubt", "Yes – definitely", "You may rely on it", "As I see it, yes", "Most likely", "Outlook good", "Yes", "Signs point to yes", "Reply hazy, try again", "Ask again later", "Better not tell you now", "Cannot predict now", "Concentrate and ask again", "Don't count on it", "My reply is no", "My sources say no", "Outlook not so good", "Very doubtful", "ProTekk!");
		$irc->yield(privmsg => $where => $answers[ int(rand(@answers)) ]);
	}
}

sub goog {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = ($args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my $q = $args;
		my $url = "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=$q";
		my $output = $bot->fetch_url($url, undef, "GET", undef);
		my $utf8 = encode ('utf8', $output);
		my $hashref = decode_json $utf8;
		my $url = $hashref->{responseData}->{results}[0]->{url};
		$irc->yield(privmsg => $where => $url);
	}
}

sub gtfo {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return if $type eq "private";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my $target = $args;
		$irc->yield(kick => $where => $target => "GTFO!");
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

sub links {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		my $links = join(", ", sort(keys(%$links)));
		$irc->yield(privmsg => $where => "Available links: $links");
		$irc->yield(privmsg => $where => "Type ${prefix}link <link> to display the URL.");
	}
	return;
}

sub link {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		if(defined $links->{$args}) {
			$irc->yield(privmsg => $where => "$args: $links->{$args}->{url}.");
		} else {
			$irc->yield(privmsg => $where => "unknown link: $args. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub linkadd {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		load_links();
		my ($title, $url) = @args;
		if(defined $links->{$title}) {
			$irc->yield(privmsg => $where => "link $title already exists.");
		} else {
			$dbh->do("INSERT INTO links (title, url, usermask) VALUES ('$title', '$url', '$usermask')");
			load_links();
			$irc->yield(privmsg => $where => "link $title successfully added.");
		}
	}
	return;
}

sub linkdel {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		load_links();
		my $title = $args;
		if(defined $links->{$title}) {
			$dbh->do("DELETE FROM $table_links WHERE title='$title'");
			load_links();
			$irc->yield(privmsg => $where => "Link $title successfully deleted.");
		} else {
			$irc->yield(privmsg => $where => "unknown link: $title. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub linkmod {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $commandi, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
		load_links();
		my ($title, $url) = @args;
		if(defined $links->{$title}) {
			$dbh->do("UPDATE $table_links SET url='$url' WHERE title='$title'");
			load_links();
			$irc->yield(privmsg => $where => "link $args[0] successfully updated.");
		} else {
			$irc->yield(privmsg => $where => "unknown link: $args[0]. type ${prefix}links for a list of available links.");
		}
	}
	return;
}

sub mom {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = ($args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my @nicks = $irc->nicks();
		$args =~ s/ //g;

		if(grep(/^$args$/, @nicks)) {
			$irc->yield(privmsg => $where => "$args: I heard your mom uses an iPhone.");
		}
	}
}

sub nick {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		$irc->yield(nick => $args);
	}
	return;
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

sub say {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args;
	@args = ($1, $2) if $args =~ m/(.*?) +(.*)/;

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 2) eq "success") {
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

sub seen {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	return unless $type eq "public";
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 1) eq "success") {
		my ($nick, $mask) = split (/!/, $usermask);
		my @nicks = $irc->nicks();
		$args =~ s/ //g;

		my $q = "SELECT COUNT(*) FROM $table_seen WHERE nick='$args' AND channel='$where'";

		my $count = $dbh->selectrow_array($q);
		if($count == 0) {
			$irc->yield(privmsg => $where => "I have not seen $args.");
		} else {
			my $time = $dbh->selectrow_array("SELECT time FROM $table_seen WHERE nick='$args' AND channel='$where'");
			my $last = $bot->duration(time - $time);

			if(grep(/^$args$/, @nicks)) {
				$irc->yield(privmsg => $where => "$args is in the channel now and last spoke $last ago.");
			} else {
				$irc->yield(privmsg => $where => "I last saw $args $last ago.");
			}
		}
	}	
}

sub time {
	my $self = shift;
	my ($irc, $where, $args, $usermask, $command, $type) = @_;
	my @args = split(/\s+/, $args);

	if($bot->validate_cmd($irc, $where, \@args, $usermask, $command, 0) eq "success") {
		$irc->yield(privmsg => $where => "It is now " . strftime("%Y-%m-%d %T", localtime(time)) . " UTC");
	}
	return;
}

sub load_links {
	my $sth = $dbh->prepare("SELECT * FROM $table_links");
	$sth->execute;
	$links = $dbh->selectall_hashref($sth, "title");
}

sub load_commands {
	my $methods = {
		"8ball" => {
			usage => "8ball <question> -- Ask the 8ball a question.",
			level => 0,
			can_be_disabled => 1,
			method => "ball"
		},
		goog => {
			usage => "goog <query> -- Perform a Google search on <query> and display the first result.",
			level => 0,
			can_be_disabled => 1
		},
		gtfo => {
			usage => "gtfo <nick> -- Kick someone out.",
			level => 50,
			can_be_disabled => 1
		},
		join => {
			usage => "join <channel> -- Join the channel <channel>.",
			level => 90,
			can_be_disabled => 1
		},
		links => {
			usage => "links -- Lists all of the links in the links database.",
			level => 0,
			can_be_disabled => 1
		},
		link => {
			usage => "link <title> -- Display the URL for link <title>. Example: link gapps",
			level => 0,
			can_be_disabled => 1
		},
		linkadd => {
			usage => "linkadd <title> <url> -- Add a link to the links database.",
			level => 40,
			can_be_disabled => 1
		},
		linkdel => {
			usage => "linkdel <title> -- Remove a link from the links database.",
			level => 40,
			can_be_disabled => 1
		},
		linkmod => {
			usage => "linkmod <title> <new_url> -- Update the URL for an existing link.",
			level => 40,
			can_be_disabled => 1
		},
		part => {
			usage => "part <channel> -- Exit the channel <channel>.",
			level => 90,
			can_be_disabled => 1
		},
		nick => {
			usage => "nick <nick> -- Change the bot's nick.",
			level => 90,
			can_be_disabled => 1
		},
		mom => {
			usage => "mom <nick>. -- Insult a user's mom.",
			level => 0,
			can_be_disabled => 1
		},
		say => {
			usage => "say <nick> <text> - Instruct the bot to speak to someone in the channel.",
			level => 50,
			can_be_disabled => 1
		},
		seen => {
			usage => "seen <nick> -- Display the last time the bot has seen <nick>.",
			level => 0,
			can_be_disabled => 1
		},
		time => {
			usage => "time -- Displays the current time in UTC format.",
			level => 0,
			can_be_disabled => 1
		}
	};
	$bot->update_commands($module, $methods);
}
	
1;
