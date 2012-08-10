#!/usr/bin/perl

# http://www.networksorcery.com/enp/protocol/irc.htm

use strict;
use warnings;
use lib "/home/gdanko/bot/perl";
use Config::Tiny;
use File::Path;
use POSIX qw(strftime);
use Data::Dumper;
use Module::Reload::Selective;
use POSIX qw(setsid);
use LWP::Simple;

# POE!
use POE qw(
	Component::IRC
	Component::IRC::State
	Component::IRC::Plugin::NickReclaim
);

$Module::Reload::Selective::Options->{ReloadOnlyIfEnvVarsSet} = 0;

my $root = "/home/gdanko/bot";
my $cfg = read_config();
my $logging = 0;
my $prefix = $cfg->{misc}->{prefix};
my $reloadtime;
my %commands = ();
my %cmdtable = ();
my @channels = split(/,/, $cfg->{misc}->{channels});

&reload(%cmdtable, %commands);
&daemonize;

my $irc = POE::Component::IRC::State->spawn(
	server		=>	$cfg->{network}->{server},
	#port		=>	$cfg->{network}->{port},
	nick		=>	$cfg->{identity}->{nick},
	#username	=>	$cfg->{identity}->{username},
	ircname		=>	$cfg->{identity}->{ircname},
	flood		=>	$cfg->{misc}->{allow_flooding},
	
);

$irc->plugin_add("NickReclaim" => POE::Component::IRC::Plugin::NickReclaim -> new(
	poll => 30)
);

POE::Session->create(
	inline_states => {
		irc_disconnected	=>	\&bot_reconnect,
		irc_error			=>	\&bot_reconnect,
		irc_socketerr		=>	\&bot_reconnect,
		_start				=>	\&bot_start,
		autoping			=>	\&bot_do_autoping,
		_stop				=>	\&bot_stop,
		irc_001				=>	\&on_connect,
		irc_public			=>	\&on_public,
		irc_ctcp_action		=>	\&on_ctcp,
		irc_msg				=>	\&on_msg,
	},
);

$poe_kernel->run();
exit 0;

sub read_config {
	my $config_file = "$root/conf/bot.conf";
	die("Cannot open config file \"$config_file\" for reading.\n") unless -f $config_file;
	my $cfg = Config::Tiny->read($config_file);
	return $cfg;
}

sub daemonize {
	chdir '/'					or die "Can't chdir to /: $!";
	#open STDIN, '/dev/null'		or die "Can't read /dev/null: $!";
	#open STDOUT, ">>", "/home/gdanko/out.txt" or die "Can't write to /dev/null: $!";
	#open STDERR, ">>", "/home/gdanko/err.txt" or die "Can't write to /dev/null: $!";
	defined(my $pid = fork)		or die "Can't fork: $!";
	exit if $pid;
	setsid						or die "Can't start a new session: $!";
	umask 0;
}

sub bot_start {
	$irc->yield(register => "all");
	$irc->yield(connect => { Flood => 0 });
}

sub bot_stop {
	my ($kernel, $session, $self, $quitmsg, $foo, $bar) = @_[KERNEL, SESSION, OBJECT, ARG0, ARG1, ARG2];

	if ($self->{connected}) {
		$kernel->call($session => quit => $quitmsg);
		$kernel->call($session => shutdown => $quitmsg);
	}
	return;
}

# Once connected, start a periodic timer to ping ourselves.  This
# ensures that the IRC connection is still alive.  Otherwise the TCP
# socket may stall, and you won't receive a disconnect notice for
# up to several hours.
sub on_connect {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	$irc->yield( join => $_ ) for @channels;
	sleep 5;
	$irc->yield(privmsg => "NickServ" => "identify $cfg->{identity}->{nickserv_pass}");
	$irc->yield(privmsg => "NickServ" => "VERIFY REGISTER CodenameBot clggntxlrxyc");

	$heap->{seen_traffic} = 1;
	$kernel->delay(autoping => 300);
}

# Ping ourselves, but only if we haven't seen any traffic since the
# last ping.  This prevents us from pinging ourselves more than
# necessary (which tends to get noticed by server operators).
sub bot_do_autoping {
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	$kernel->post(poco_irc => userhost => "my-nickname") unless $heap->{seen_traffic};
	$heap->{seen_traffic} = 0;
	$kernel->delay(autoping => 300);
}

# Reconnect in 60 seconds.  Don't ping while we're disconnected.  It's
# important to wait between connection attempts or the server may
# detect "abuse".  In that case, you may be prohibited from connecting
# at all.
sub bot_reconnect {
	my $kernel = $_[KERNEL];
	$kernel->delay(autoping => undef);
	$kernel->delay(connect  => 60);
}

sub on_public {
	my ($kernel, $usermask, $channels, $message) = @_[KERNEL, ARG0, ARG1, ARG2, ARG3];
	my ($command, $args);
	my $where = $channels->[0];
	my $nick = (split /!/, $usermask)[0];

	# Log to the "seen" table
	botCmd::_log_seen($nick, time, $where);

	# Tiny-fy URLs
	# http://search.cpan.org/~bingos/POE-Component-WWW-Shorten-1.20/lib/POE/Component/WWW/Shorten.pm
	if($message =~ m/^http(s?):\/\//) {
		return if $message =~ m/^http(s?):\/\/tinyurl\.com/;

		my $tiny = get("http://tinyurl.com/api-create.php?url=$message");
		$irc->yield(privmsg => $where => $tiny);
		return;
	}

	# Interpret commands
	if($message =~ /^$prefix/) {
		$message =~ s/^$prefix//;
		if ($message =~ m/(.*?) +(.*)/) {
			$command = $1;
			$args = $2;
		} else {
			$command = $message;
		}
	} else {
		return;
	}

	if($cmdtable{$command}) {
		eval { &{ $cmdtable{$command} }($irc, $where, $args, $usermask, $command) };
		$irc->yield(privmsg => $where => "Got the following error: $@") if $@;
	} else {
		$irc->yield(privmsg => $where => "Invalid command: $command. Type !help for a list of commands.");
	}
	return;
}

sub on_ctcp {
	my ($kernel, $usermask, $channels, $message) = @_[KERNEL, ARG0, ARG1, ARG2];
	my $where = $channels->[0];
	my $sender = (split /!/, $usermask)[0];

	eval { &botCmd::process_ctcp($irc, $where, $sender, $message) };
	$irc->yield(privmsg => $where => "Got the following error: $@") if $@;
}

sub on_msg {
	my ($kernel, $usermask, $recipients, $message) = @_[KERNEL, ARG0, ARG1, ARG2];
	my ($command, $args);
	#my $sender = (split /!/, $usermask)[0];
	#my $sender = $usermask;
	#my $where = $sender;

	my $nick = (split /!/, $usermask)[0];

	if ($message =~ m/(.*?) +(.*)/) {
		$command = $1;
		$args = $2;
	} else {
		$command = $message;
	}

	if($command eq "reload") {
		eval { &reload() };
		if ($@) {
			$irc->yield(privmsg => $nick => "Got error trying to reload: $@");
		} else {
			$irc->yield(privmsg => $nick => "Successfully reloaded botCmd.pm. Reload time: $reloadtime");
		}
	} elsif($cmdtable{$command}) {
		eval { &{ $cmdtable{$command} }($irc, $nick, $args, $usermask, $command) };
		$irc->yield(privmsg => $nick => "Got the following error: $@") if $@; 
	} else {
		$irc->yield(privmsg => $nick => "Invalid command: $command. Type help for a list of commands.");
	}
	return;
}

sub reload {
	info_text("Reloading botCmd.pm");
	my $cmdtable = shift;
	my $commands = shift;
	Module::Reload::Selective->reload(qw(botCmd));
	import botCmd;
	%cmdtable = ();
	%commands = ();
	$reloadtime = "";
	use botCmd qw(%commands);
	use botCmd qw($reloadtime);
	$reloadtime = ${botCmd::reloadtime};
	%commands = %{botCmd::commands};
	foreach (keys(%commands)) {
		my $cmd = $_;
		my $routine = "botCmd::$cmd";
		$cmdtable{$cmd} = \&{$routine};
	}
}

sub info_text {
	my $text = shift;
	print STDOUT "[Info] $text\n" if $text;
}

sub warn_text {
	my $text = shift;
	print STDOUT "[Warn] $text\n" if $text;
}

sub _fetch_url {
	my $url = shift;
	return get($url);
}
