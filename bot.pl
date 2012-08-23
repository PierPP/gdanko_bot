#!/usr/bin/perl

# http://www.networksorcery.com/enp/protocol/irc.htm

use strict;
use warnings;
use lib "/home/gdanko/bot/perl";
use Config::Tiny;
use File::Path;
use Data::Dumper;
use Module::Reload::Selective;
use POSIX qw(setsid strftime ceil);

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

&reload();
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
		irc_error		=>	\&bot_reconnect,
		irc_socketerr		=>	\&bot_reconnect,
		_start			=>	\&bot_start,
		autoping		=>	\&bot_do_autoping,
		_stop			=>	\&bot_stop,
		irc_001			=>	\&on_connect,
		irc_public		=>	\&on_public,
		irc_ctcp_action		=>	\&on_ctcp,
		irc_msg			=>	\&on_msg,
		irc_join		=>	\&on_join,
		irc_whois		=>	\&on_whois,
#		_default		=>	\&default
	},
);

$poe_kernel->run();
exit 0;

sub read_config {
	my $config_file = "$root/bot.conf";
	die("Cannot open config file \"$config_file\" for reading.\n") unless -f $config_file;
	my $cfg = Config::Tiny->read($config_file);
	return $cfg;
}

sub daemonize {
	chdir '/'					or die "Can't chdir to /: $!";
	open STDIN, '/dev/null'		or die "Can't read /dev/null: $!";
	open STDOUT, ">>", "/home/gdanko/bot2/out.txt" or die "Can't write to /dev/null: $!";
	open STDERR, ">>", "/home/gdanko/bot2/err.txt" or die "Can't write to /dev/null: $!";
	defined(my $pid = fork)		or die "Can't fork: $!";
	exit if $pid;
	setsid						or die "Can't start a new session: $!";
	umask 0;
}

sub default {
	my ($event, $args) = @_[ARG0 .. $#_];
	my @output = ( "$event: " );
 
	for my $arg (@$args) {
		if ( ref $arg eq 'ARRAY' ) {
			push( @output, '[' . join(', ', @$arg ) . ']' );
		} elsif ( ref $arg eq 'HASH' ) {
			while (my ($key, $value) = each (%$arg) ) {
				push ( @output, '[' . $key . '==' . $value . ']' );
			}
		} else {
			push ( @output, "'$arg'" );
		}
	}
	print join ' ', @output, "\n";
	return 0;
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
	botCmd::_pub_msg_handler($irc, $kernel, $usermask, $channels, $message);
}

sub on_msg {
	my ($kernel, $usermask, $recipients, $message) = @_[KERNEL, ARG0, ARG1, ARG2];
	my ($nick, $mask) = split(/!/, $usermask);

	# Reload must be handled here
	if($message eq "reload") {
		eval { &reload() };
		if ($@) {
			$irc->yield(privmsg => $nick => "Got error trying to reload: $@");
		} else {
			$irc->yield(privmsg => $nick => "Successfully reloaded botCmd.pm. Reload time: $reloadtime");
		}
	} else {
		botCmd::_priv_msg_handler($irc, $kernel, $usermask, $recipients, $message);
	}
}

sub on_ctcp {
	my ($kernel, $usermask, $channels, $message) = @_[KERNEL, ARG0, ARG1, ARG2];
	botCmd::_ctcp_handler($irc, $kernel, $usermask, $channels, $message);
}

sub on_join {
	my ($kernel, $usermask, $channel) = @_[KERNEL, ARG0, ARG1];
	botCmd::_join_handler($irc, $kernel, $usermask, $channel);
}

sub on_whois {
	my ($kernel, $whois) = @_[KERNEL, ARG0];
	botCmd::_whois_handler($irc, $kernel, $whois);
}

sub reload {
	$reloadtime = "";
	print STDOUT "[Info] Reloading botCmd.pm\n";
	Module::Reload::Selective->reload(qw(botCmd));
	import botCmd qw($reloadtime);
	#use botCmd qw($reloadtime);
	$reloadtime = ${botCmd::reloadtime};
}
